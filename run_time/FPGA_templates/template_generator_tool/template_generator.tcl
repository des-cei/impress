package require struct::list

proc generate_template {file_path {device ""}} {
  # We assume that all the rows have the same resources unless there are GTX 
  # tranceivers.
  if {$device != ""} {
    set_part $device 
    link_design
  }
  
  set highest_column [lindex [lsort -integer -increasing [get_property COLUMN [get_tiles]]] end]
  set middle_column [expr ($highest_column + 1)/2]
  set highest_row [lindex [lsort -integer -increasing [get_property ROW_INDEX [get_clock_regions]]] end]
  
  # We search for GTX transceivers.
  set gtx_position_left [lsort -integer -increasing -unique [get_property COLUMN [get_tiles -filter "TILE_TYPE =~ *GTX* && COLUMN < $middle_column"] -quiet]]
  if {[llength $gtx_position_left] == 0} {
    set common_row_left_column_index 0
  } else {
    set common_row_left_column_index [expr [lindex $gtx_position_left end] + 1]
  }
  set gtx_position_right [lsort -integer -increasing -unique [get_property COLUMN [get_tiles -filter "TILE_TYPE =~ *GTX* && COLUMN > $middle_column"] -quiet]]
  if {[llength $gtx_position_right] == 0} {
    set common_row_right_column_index $highest_column
  } else {
    set common_row_right_column_index [expr [lindex $gtx_position_right 0] - 1]
  }
  # We get the common row resources 
  set common_row_resources [list]
  for {set i $common_row_left_column_index} {$i <= $common_row_right_column_index} {incr i} {
    set tiles [get_tiles -filter "COLUMN == $i"] 
    set tile_type [lsort -unique [get_property TILE_TYPE $tiles]]
    set common_row_resources [concat $common_row_resources [find_resource_type $tile_type]]
  }

  set FPGA_resources_expanded [list]
  set FPGA_resources [list]
  for {set i 0} {$i <= $highest_row} {incr i} { 
    set row_resources_expanded [list]
    set row_resources [list]
    # We go through all the left side of the row until the common row
    for {set j 0} {$j < $common_row_left_column_index} {incr j} {
      set clock_regions [get_clock_regions -filter "ROW_INDEX == $i"]
      set tiles [get_tiles -of_objects $clock_regions -filter "COLUMN == $j"]
      if {[llength $tiles] != 0} {
        set tile_type [lsort -unique [get_property TILE_TYPE $tiles]]
        set row_resources_expanded [concat $row_resources_expanded [find_resource_type $tile_type]]
      }
    }
    set row_resources [concat $row_resources_expanded common_row_resources]
    set row_resources_expanded [concat $row_resources_expanded $common_row_resources]
    # We go through all the left side of the row from the common row
    for {set j [expr $common_row_right_column_index + 1]} {$j <= $highest_column} {incr j} {
      set clock_regions [get_clock_regions -filter "ROW_INDEX == $i"]
      set tiles [get_tiles -of_objects $clock_regions -filter "COLUMN == $j"]
      if {[llength $tiles] != 0} {
        set tile_type [lsort -unique [get_property TILE_TYPE $tiles]]
        set resource_type [find_resource_type $tile_type]
        set row_resources_expanded [concat $row_resources_expanded $resource_type]
        set row_resources [concat $row_resources $resource_type]
      }
    }
    lappend FPGA_resources_expanded $row_resources_expanded
    lappend FPGA_resources $row_resources
  }

  # We obtain the middle row that divides the bottom and top part of the FPGA.
  # Check series 7 configuration guide for more details. Experimentally I have 
  # observed that in zynq devices the last row is the top part and the rest are 
  # are part of the bottom. In regular series 7 devices the middle is placed in 
  # the middle row 
  if {[string first xc7z  [get_parts -of_objects [get_projects]]] != -1} {
    set zynq 1
    set first_top_row $highest_row
  } else {
    set zynq 0
    set first_top_row [expr $highest_row/2]
  }
  
  set row_order_list [list]
  
  set row_number [expr $highest_row - 1]
  for {set i 0} {$i < $first_top_row} {incr i} {
    set row_order_list [concat $row_order_list $row_number]
    set row_number [expr $row_number - 1]
  }
  
  set row_number 0
  for {set i $first_top_row} {$i <= $highest_row} {incr i} {
    set row_order_list [concat $row_order_list $row_number] 
    incr row_number
  }
  
  write_run_time_description $file_path $FPGA_resources_expanded $row_order_list $first_top_row $highest_column
  
  set bitstream_order [list]
  if {$zynq == 1} {
    for {set i $highest_row} {$i >= 0} {incr i -1} {
      set bitstream_order [concat $bitstream_order $i]
    }
  } else {
    # TODO I have to check with more FPGAs if the bitstream order is computed 
    # this way because it does not make sense...
    set middle_bitstream_row [expr ($highest_row + 1) / 2] 
    set position [expr $highest_row - $middle_bitstream_row]
    for {set i 0} {$i < $highest_row} {incr i} {
      set bitstream_order [concat $bitstream_order $position]
      if {[expr $i + 1] < $middle_bitstream_row} {
        incr position 
      } elseif {[expr $i + 1] == $middle_bitstream_row} {
        set position [expr $highest_row - $middle_bitstream_row -1]
      } else {
        incr position -1
      }
    }  
  }
  
  write_py_bitstream_description $file_path $FPGA_resources $common_row_resources $bitstream_order
}


proc find_resource_type {tile_type} {
  set resource_type [list]
  # We remove the interconnexion tiles 
  set INT_indices [list]
  for {set i 0} {$i < [llength $tile_type]} {incr i} {
    if {[string first INT [lindex $tile_type $i]] != -1} {
      set INT_indices [concat $INT_indices $i]
    }
  }
  set INT_indices [lsort -integer -decreasing $INT_indices]
  foreach index $INT_indices {
    set tile_type [lreplace $tile_type $index $index]
  }
  # We search the resources 
  if {[string first CLBLM $tile_type] != -1} {
    set resource_type [concat $resource_type CLB_M]
  } elseif {[string first CLBLL $tile_type] != -1} {
    set resource_type [concat $resource_type CLB_L]
  } elseif {[string first DSP $tile_type] != -1} {
    set resource_type [concat $resource_type DSP]
  } elseif {[string first BRAM $tile_type] != -1} {
    set resource_type [concat $resource_type BRAM]
  } elseif {[string first CLK_BUFG $tile_type] != -1} {
    set resource_type [concat $resource_type CLK]
  } elseif {[string first GTX_CHANNEL $tile_type] != -1} {
    set resource_type [concat $resource_type GT]
  } elseif {[string first IOB $tile_type] != -1} {
    set resource_type [concat $resource_type IOBA]
  } elseif {[string first IOI $tile_type] != -1} {
    set resource_type [concat $resource_type IOBB]
  } 
  # The CFG can share the column with other resources but in reality is a common 
  # resource that comes after the other resource with which it shares the column  
  if {[string first CFG $tile_type] != -1} {
    set resource_type [concat $resource_type CFG]
  }
  
  return $resource_type
}

proc write_run_time_description {file_path resource_list row_order_list first_top_row max_column} {
  set device [get_parts -of_objects [get_projects]]
  set fpga_name [string range $device 2 [expr [string length $device] - 3]]
  
  set file_c [open ${file_path}/${fpga_name}.c w] 
  
  # We write the configuration resources array
  puts $file_c "\#include \"${fpga_name}.h\""
  puts $file_c ""
  puts $file_c "// Clock region definitions"
  puts $file_c "#define BOTTOM 1"
  puts $file_c "#define TOP    0"
  for {set i 0} {$i < [llength $row_order_list]} {incr i} {
    puts $file_c "#define ROW${i}   ${i}"
  }
  puts $file_c "// ID generation"
  puts $file_c "#define block(top, row, type)  ((top<<24) | (row<<16) | (type))"
  puts $file_c "#define content(yes_no, major)  ((yes_no<<16) | (major))"
  puts $file_c ""
  puts $file_c ""
  puts $file_c ""
  
  puts $file_c "const u32 fpga\[MAX_ROWS\]\[MAX_COLUMNS\]\[2\] = \{"
  
  for {set i 0} {$i < [llength $resource_list]} {incr i} {
    set row_resources_expanded [lindex $resource_list $i]
    puts $file_c "  \{"
    if {$i < $first_top_row} {
      set row_half BOTTOM
    } else {
      set row_half TOP
    }
    set row_position ROW[lindex $row_order_list $i]
    for {set j 0} {$j < [llength $row_resources_expanded]} {incr j} {
      set resource [lindex $row_resources_expanded $j]
      switch -exact -- $resource {
        CLB_M {
          set resource_name CLB
          set resource_type CLB_M_TYPE
        }
        CLB_L {
          set resource_name CLB
          set resource_type CLB_L_TYPE
        }
        DSP {
          set resource_name DSP
          set resource_type DSP_TYPE
        }
        BRAM {
          set resource_name BRAM
          set resource_type BRAM_TYPE
        }
        CLK {
          set resource_name CLK
          set resource_type CLK_TYPE
        }
        GT {
          set resource_name GT
          set resource_type GT_TYPE
        }
        IOBB {
          set resource_name IOB_B 
          set resource_type IOBB_TYPE
        }
        IOBA {
          set resource_name IOB_A
          set resource_type IOBA_TYPE
        }
        CFG {
          set resource_name CFG
          set resource_type CFG_TYPE
        }
        default {
          set resource_name ERROR
          set resource_type ERROR
        }
      }
      
      puts -nonewline $file_c "    \{block(${row_half}, ${row_position}, ${resource_name}), ${resource_type}\}"
      if {$j == [expr [llength $row_resources_expanded] - 1]} {
        # We force a new line
        puts $file_c ""
      } else {
        puts $file_c ","
      }
    }
    if {[expr $i + 1] == [llength $resource_list]} {
      puts $file_c "  \}"
    } else {
      puts $file_c "  \},"
    }
  }
  puts $file_c "\};"
  
  # We write the BRAM content array
  puts $file_c "const u32 fpga_bram\[MAX_ROWS\]\[MAX_COLUMNS\] = \{"
  for {set i 0} {$i < [llength $resource_list]} {incr i} {
    set row_resources_expanded [lindex $resource_list $i]
    set BRAM_number 0
    puts $file_c "  \{"
    for {set j 0} {$j < [llength $row_resources_expanded]} {incr j} {
      set resource [lindex $row_resources_expanded $j]
      if {$resource == "BRAM"} {
        puts -nonewline $file_c "   content(BRAM_CONTENT, $BRAM_number)"
        incr BRAM_number
      } else {
        puts -nonewline $file_c "   content(BRAM_NOCONTENT, 0)"
      }
      if {$j == [expr [llength $row_resources_expanded] - 1]} {
        # We force a new line
        puts $file_c ""
      } else {
        puts $file_c ","
      }
    }
    if {[expr $i + 1] == [llength $resource_list]} {
      puts $file_c "  \}"
    } else {
      puts $file_c "  \},"
    }
  }
  puts $file_c "\};"
  
  flush $file_c
  close $file_c
  
  set file_h [open ${file_path}/${fpga_name}.h w] 
  set header_symbol [string toupper fpga_name]_H
  puts $file_h "#ifndef $header_symbol"
  puts $file_h "#define $header_symbol"
  puts $file_h ""
  puts $file_h ""
  puts $file_h "#include \"series7.h\""
  puts $file_h "#include \"xil_types.h\""
  puts $file_h ""
  puts $file_c "// BRAM content definitions"
  puts $file_c "#define BRAM_CONTENT   1"
  puts $file_c "#define BRAM_NOCONTENT 0"
  puts $file_h ""
  puts $file_c "// Block type definition"
  puts $file_c "#define CLB_L_TYPE 		0"
  puts $file_c "#define CLB_M_TYPE 		1"
  puts $file_c "#define DSP_TYPE 			2"
  puts $file_c "#define BRAM_TYPE 		3"
  puts $file_c "#define IOBA_TYPE 		4"
  puts $file_c "#define IOBB_TYPE 		5"
  puts $file_c "#define CLK_TYPE 			6"
  puts $file_c "#define CFG_TYPE			7"
  puts $file_c "#define GT_TYPE 			8"
  puts $file_h ""
  puts $file_h "#define MAX_ROWS    [llength $row_order_list]"
  puts $file_h "#define MAX_COLUMNS $max_column"
  puts $file_h ""
  puts $file_h "#define PCAP_IDCODE_NUMBER //add the IDCODE of the FPGA here. You can find the IDCODE in the bitstream"
  puts $file_h ""
  puts $file_h "extern const u32 fpga\[MAX_ROWS\]\[MAX_COLUMNS\]\[2\];"
  puts $file_h ""
  puts $file_h "extern const u32 fpga_bram\[MAX_ROWS\]\[MAX_COLUMNS\];"
  puts $file_h ""
  puts $file_h "#endif"
  
  flush $file_h
  close $file_h
}

proc write_resources_py_format {file_py common_row_resources} {
  set new_line [list]
  set consecutive_CLB 0
  set number_lines 0
  for {set i 0} {$i < [llength $common_row_resources]} {incr i} {
    set resource [lindex $common_row_resources $i] 
    if {[expr $i+ 1] == [llength $common_row_resources]} {
      set next_resource "end_list"
    } else {
      set next_resource [lindex $common_row_resources [expr $i+ 1]] 
    }
    # We don't differentiate between CLB types in the python template
    if {[string first CLB $resource] != -1} {
      set resource CLB
    }
    if {[string first CLB $next_resource] != -1} {
      set next_resource CLB
    } 
    if {$resource != "CLB"} {
      set new_line [concat $new_line $resource]
    } else {
      incr consecutive_CLB
    }
    if {($resource == "CLB" && $next_resource != "CLB") || ($next_resource == "end_list") || $resource == "common_row_resources"} {
      if {$consecutive_CLB > 0} {
        set new_line [concat $new_line "${consecutive_CLB}*CLB"] 
      }
      
      
      if {$number_lines == 0} {
        puts -nonewline $file_py "  "
      } else {
        puts -nonewline $file_py "  + "
      }
      
      set num_elements [llength $new_line]
      for {set j 0} {$j < $num_elements} {incr j} {
        set element [lindex $new_line $j]
        puts -nonewline $file_py "${element}"
        if {[expr $j + 1] != $num_elements} {
            puts -nonewline $file_py " + "
        }
      }
      set new_line [list]
      set consecutive_CLB 0
      puts $file_py ""    
      incr number_lines
    }
    
  }
}



proc write_py_bitstream_description {file_path resource_list common_row_resources bitstream_order} {
  set device [get_parts -of_objects [get_projects]]
  set fpga_name [string range $device 2 [expr [string length $device] - 3]]
  
  set file_py [open ${file_path}/${fpga_name}.py w] 
  
  puts $file_py "from .series7 import *"
  puts $file_py ""
  puts $file_py "model_name = \"$fpga_name\""
  puts $file_py ""
  puts $file_py ""
  puts $file_py "common_row_resources = ("
  
  write_resources_py_format $file_py $common_row_resources 
  
  puts $file_py ")"
  puts $file_py ""
  puts $file_py ""
  puts $file_py ""
  
  set common_rows 1 
  set number_lines 0
  puts -nonewline $file_py "table = "
  for {set i 0} {$i < [llength $resource_list]} {incr i} {
    set current_row [lindex $resource_list $i]
    if {[expr $i+ 1] == [llength $resource_list]} {
      set next_row "end_list"
    } else {
      set next_row [lindex $resource_list [expr $i+ 1]] 
    }
    
    if {[::struct::list equal $current_row $next_row]} {
      incr common_rows
    } else {
      if {$number_lines != 0} {
        puts -nonewline $file_py " + "
      } else {
        puts -nonewline $file_py " "
      }
      
      puts $file_py "${common_rows} * \["
      write_resources_py_format $file_py [concat $current_row PAD] 
      puts -nonewline $file_py "\]"
      set common_rows 1
      incr number_lines
    }
  }
  
  puts $file_py ""
  puts $file_py ""
  set number_rows [llength $bitstream_order]
  puts -nonewline $file_py "bitstream_order = \["
  for {set i 0} {$i < $number_rows} {incr i} {
    puts -nonewline $file_py "[lindex $bitstream_order $i]"
    if {[expr $i + 1] != $number_rows} {
        puts -nonewline $file_py ", "
    }
  }
  puts $file_py "\]"

  flush $file_py
  close $file_py
}








