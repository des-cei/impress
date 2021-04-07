##########################################################################################
# This library provides functions dealing with fine-grain LUT reconfiguration. It's   
# purpose is to place the LUTs in their correct SLICE column for fine-grain 
# reconfiguration. 
# The purpose of LUT-fine-grain reconfiguration is to reconfigure LUTs without 
# reconfiguring an entire reconfigurable module. The main objective is to reconfigure as 
# fast as possible, therefore the reconfiguration engine should not make a readback. 
# This implies that an entire frame should be reconfigured at a time without doing frame 
# composition, therefore all the contents of the frame should be known in advance. It is 
# important that SLICE columns used for LUT-fine-grain reconfiguration do not contain 
# other LUT elements of the design (i.e. LUTs that are not used for constant and mux 
# reconfiguration). To that end free LUTs are filled with dummy LUTs. 
##########################################################################################

package require struct::set

namespace eval ::reconfiguration_tool::fine_grain_luts {
  namespace import ::reconfiguration_tool::utils::*
  
  # Procs that can be used in other namespaces
  namespace export place_fine_grain_LUTs_reconfigurable_partition
  namespace export place_fine_grain_LUTs_static_system
  
  ########################################################################################
  # Adds the fine-grain reconfigurable LUTs in the static system. The LUTs are placed 
  # inside a pblock defined in the attributes of the elements.
  # 
  #
  # Argument Usage:
  #   None
  # Return Value:
  #   None or error
  ########################################################################################
  proc place_fine_grain_LUTs_static_system {} {
    set fine_grain_elements [get_cells -hierarchical -filter "CONSTANT_LUT_ELEMENT == YES || MUX_LUT_ELEMENT == YES || FU_LUT_ELEMENT== YES"] 
    if {[llength $fine_grain_elements] == 0} {
      return
    }   
    set pblocks_fine_grain [lsort -dictionary -unique [get_property PBLOCK_FINE_GRAIN $fine_grain_elements]] 
    set i 0
    foreach pblock $pblocks_fine_grain {
      set pblock_name pblock_fine_grain_${i}
      create_and_place_pblock $pblock_name [change_pblock_format_from_custom_to_xilinx $pblock]
      place_fine_grain_luts_pblock $pblock_name $pblock 
      # delete_pblocks [get_pblocks $pblock_name]
      incr i
    }
  }
  
  ########################################################################################
  # Adds the fine-grain reconfigurable LUTs in a reconfigurable partition.
  #
  # Argument Usage:
  #   reconfigurable_partition_group: 
  # Return Value:
  #   None or error
  ########################################################################################
  proc place_fine_grain_LUTs_reconfigurable_partition {reconfigurable_partition_group} {
    set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
    set partition_name [dict get [lindex $reconfigurable_partition_list 0] partition_name] 
    set pblock_partition pblock_${partition_name}     
    place_fine_grain_luts_pblock $pblock_partition "\{\}" $partition_name
  }
  
  ########################################################################################
  # This function places all the fine-grain LUTs used for constants and multiplexers in  
  # SLICE columns of the specified PBLOCK. The number of SLICE columuns that are going to 
  # be used is defined in the vhdl file with the attributes num_columns_constants and 
  # num_columns_mux. The first SLICE columns of the pblock are going to be used for 
  # constants while the next columns will be used for muxes. Fine-grain elements are 
  # grouped in blocks defined by the column_offset. 
  #
  # Argument Usage:
  #     pblock_name: pblock where the constants and muxes are going to be placed.
  #     partition_name (optional): if the LUTs are being placed inside a partition the  
  #           user needs to specify which partition is being used so that dummy LUTs can  
  #           be instantiated inside the reconfigurable cell.  
  #
  # Return Value:
  #   None or error
  ########################################################################################  
  proc place_fine_grain_luts_pblock {pblock_name pblock_fine_grain_property {partition_name ""}} {
    set pblock_slices [list]
    set num_constant_columns ""
    
    set all_fine_grain_cells [get_cells -hierarchical -filter "(CONSTANT_LUT_ELEMENT == YES || MUX_LUT_ELEMENT == YES || FU_LUT_ELEMENT== YES) && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]
    if {[llength $all_fine_grain_cells] == 0} {
      return
    }
    set pblock_slices [find_CLB_slice_columns_in_pblock $pblock_name]  
    set column_offset_list [lsort -dictionary -unique [get_property PBLOCK_COLUMN_OFFSET $all_fine_grain_cells]] 
    foreach column_offset $column_offset_list {
      set constant_fine_grain_cells [get_cells -hierarchical -filter "CONSTANT_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]
      set num_constant_columns [lsort -unique -dictionary [get_property -quiet -name num_columns_constants -object $constant_fine_grain_cells]]
      set mux_fine_grain_cells [get_cells -hierarchical -filter "MUX_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]
      set num_mux_columns [lsort -unique -dictionary [get_property -quiet -name num_mux_columns -object $mux_fine_grain_cells ]] 
      set FU_fine_grain_cells [get_cells -hierarchical -filter "FU_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]
      set num_FU_columns [lsort -unique -dictionary [get_property -quiet -name num_FU_columns -object $FU_fine_grain_cells]]
    
      if {[llength $num_constant_columns] > 1 || [llength $num_mux_columns] > 1 || [llength $num_FU_columns] > 1} {
        # This indicate how many columns need to be filled with LUTs, if the value is 0,  
        # only the minimum number of columns will be filled. 
        error "Fine grain cells parameters num_columns_constants or num_mux_columns or num_FU_columns of column_offset ${column_offset} have multiple values"
      } 
      # We place the constants 
      set constant_LUTs [get_cells -hierarchical -filter "CONSTANT_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"] 
      if {[llength $constant_LUTs] > 0} {
        set constant_position_list [lsort -integer -unique [get_property constant_position $constant_LUTs]]
        set LUT_cells [get_constant_LUT_cells $constant_position_list $column_offset $pblock_fine_grain_property]
        set used_columns [place_LUTs_in_SLICE_columns $partition_name $LUT_cells $pblock_slices $column_offset $num_constant_columns] 
        if {$num_constant_columns != 0} {
          if {$used_columns > $num_constant_columns} {
            error "more columns have been used for constants than specified in num_constant_columns parameter"
          }
        } else {
          set num_constant_columns $used_columns
        }
      } else {
        set num_constant_columns 0
      }
      
      #We place the multiplexers
      set mux_LUTs [get_cells -hierarchical -filter "MUX_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]     
      if {[llength $mux_LUTs] > 0} {
        set mux_position_list [lsort -integer -unique [get_property mux_position $mux_LUTs]]        
        set LUT_cells [get_mux_LUT_cells $mux_position_list $column_offset $pblock_fine_grain_property]        
        set used_columns [place_LUTs_in_SLICE_columns $partition_name $LUT_cells $pblock_slices [expr $column_offset + $num_constant_columns] $num_mux_columns]   
        if {$num_mux_columns != 0} {
          if {$used_columns > $num_mux_columns} {
            error "more columns have been used for mux than specified in num_mux_columns parameter"
          }
        } else {
          set num_mux_columns $used_columns
        }
      } else {
        set num_mux_columns 0
      } 

      #We place the FU
      # set prohibited_sites [prohibited_FU_sites $pblock_name]
      set FU_LUTs [get_cells -hierarchical -filter "FU_LUT_ELEMENT == YES && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_fine_grain_property"]   
      if {[llength $FU_LUTs] > 0} {
        set FU_position_list [lsort -integer -unique [get_property FU_position $FU_LUTs]]
        set LUT_cells [get_FU_LUT_cells $FU_position_list $column_offset $pblock_fine_grain_property]
        set used_columns [place_LUTs_in_SLICE_columns $partition_name $LUT_cells $pblock_slices [expr $column_offset + $num_constant_columns + $num_mux_columns] $num_FU_columns]  
        if {$num_FU_columns != 0} {
          if {$used_columns > $num_FU_columns} {
            error "more columns have been used for mux than specified in num_mux_columns parameter"
          }
        }
      } else {
        set num_FU_columns 0
      }
    }
  }
  
  ########################################################################################
  # Returns a list of sites that cannot be used by fine-grain FUs. If the first row is odd  
  # then it cannot be used. If the last row is even it cannot be used. 
  #
  # Argument Usage:
  #   pblock_name: name of the pblock 
  # Return Value:
  #   list of sites that cannot be used by fine-grain FUs
  ########################################################################################
  proc prohibited_FU_sites {pblock_name} {
    set prohibited_sites [list]
    set pblock [get_pblocks ${pblock_name}]
    set sites_pblock [get_sites -of_objects $pblock]
    set RPM_Y_site_coordinates [lsort -integer -unique [get_property RPM_Y $sites_pblock]]
    set tiles_pblock [get_tiles -of_objects $sites_pblock]
    # contrary to the row number the INT_TILE_Y property  starts at the beginning of the
    # FPGA and an even row has an odd INT_TILE_Y property. 
    set Y_tiles_property [lsort -unique -integer [get_property INT_TILE_Y $tiles_pblock]]
    set last_Y_list [lindex $Y_tiles_property end] ;# first row
    if {[expr $last_Y_list % 2] == 0} {
      set first_RPM_Y [lindex $RPM_Y_site_coordinates 0]
      set prohibited_sites [get_sites -of_objects $pblock -filter "RPM_Y == $first_RPM_Y"]
    } 
    set first_Y_list [lindex $Y_tiles_property 0] ;# last row
    if {[expr $first_Y_list % 2] == 1} {
      set last_RPM_Y [lindex $RPM_Y_site_coordinates end]
      set prohibited_sites [concat $prohibited_sites [get_sites -of_objects $pblock -filter "RPM_Y == $last_RPM_Y"]]
    } 
    return $prohibited_sites
  }
  
  ########################################################################################
  # This function places all the LUT cells (defined in LUT_cells) in SLICE columns of the 
  # pblock. The function places the LUTs in the columns starting from first_column and 
  # finishes when it has placed all the LUT cells. If num_columns is bigger than the 
  # number of columns used to allocate the LUTs the following columns are filled with 
  # dummy LUTs. 
  #
  #
  # Argument Usage:
  #   LUT_cells: list with all the constant LUT cells. The LUTs should be in the order the 
  #              user wants them to be placed in the columns.
  #   pblock_slices: list with sublists containing all the SLICE elements of a column. 
  #                  i.e., {{slices of column 1} ··· {slices of column n}}
  #   first_column: first column of the block that is going to be filled.
  #   num_columns: number of columns that are going to be filled
  #
  # Return Value:
  #   return the number of columns filled with LUTs (or that has been set as probited 
  #   sites)
  ########################################################################################
  proc place_LUTs_in_SLICE_columns {partition_name LUT_cells pblock_slices first_column num_columns {prohibited_sites ""}} {
    if {$partition_name != ""} {
      set parent_cell "${partition_name}/"
    } else {
      set parent_cell ""
    }

    set i 0 
    while {[llength $LUT_cells] > 0 || [expr $num_columns - $i] > 0} {
      set column_slices [lsort -dictionary [lindex $pblock_slices [expr $i + $first_column]]]
      foreach slice $column_slices {
        for {set j 1} {$j <= 4} {incr j} { ; #There are 4 LUTs in each slice          
          if {([llength $LUT_cells] > 0) && ([lsearch $prohibited_sites $slice] == -1)} {
            set LUT_cell [get_cells [lindex $LUT_cells 0]]
            # We remove the element 
            set LUT_cells [lreplace $LUT_cells 0 0]
          } else {
            set LUT ${parent_cell}fine_dummy_LUT_${slice}_${j}
            create_cell -reference LUT6 $LUT
            set LUT_cell [get_cells $LUT]
            # We need to connect a net to the output so that the opt_design does not 
            # unplace the cell. Even if the net is not connected to something the 
            # opt_design does not consider it an unconnected cell
            set net ${parent_cell}fine_dummy_net_${slice}_${j}
            create_net $net 
            connect_net -net $net -objects [get_pins ${LUT}/O]
          }
          switch -exact -- $j {
            1 {
              set_property BEL A6LUT $LUT_cell 
            }
            2 {
              set_property BEL B6LUT $LUT_cell 
            }
            3 {
              set_property BEL C6LUT $LUT_cell 
            }
            4 {
              set_property BEL D6LUT $LUT_cell 
            }
            default {}
          }   
          set_property LOC $slice $LUT_cell      
          set_property DONT_TOUCH TRUE $LUT_cell                      
        }
      }
      incr i
    }
    return $i
  }
  
  ########################################################################################
  # Returns a list with all the cells that are used in constant LUTs. The list contains 
  # the elements in the order in which they are going to be placed.
  #
  # Argument Usage:
  #   constant_position_list: list which contains the constant_position property of all  
  #   the fine-grain constants.
  #
  # Return Value:
  #   list with all the cell that are used to form constants with LUTs
  ########################################################################################  
  proc get_constant_LUT_cells {constant_position_list column_offset pblock_location} {
    set constant_LUT_cells [list]
    foreach position $constant_position_list {
      set constant_LUT_cells [concat $constant_LUT_cells [lsort -dictionary [get_cells -hierarchical -filter "constant_position == $position && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_location"]]]
    }
    return $constant_LUT_cells
  }  
  
  ########################################################################################
  # Returns a list with all the cells that are used in mux LUTs. The list contains 
  # the elements in the order in which they are going to be placed.
  #
  # Argument Usage:
  #   mux_position_list: list which contains the mux_position property of all the 
  #   fine-grain muxes.
  #
  # Return Value:
  #   list with all the cell that are used to form muxes with LUTs
  ########################################################################################  
  proc get_mux_LUT_cells {mux_position_list column_offset pblock_location} {
    set mux_LUT_cells [list]
    foreach position $mux_position_list {
      set mux_LUT_cells [concat $mux_LUT_cells [lsort -dictionary [get_cells -hierarchical -filter "mux_position == $position && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_location"]]]
    }
    return $mux_LUT_cells
  }  
  
  ########################################################################################
  # Returns a list with all the cells that are used in mux LUTs. The list contains 
  # the elements in the order in which they are going to be placed.
  #
  # Argument Usage:
  #   mux_position_list: list which contains the mux_position property of all the 
  #   fine-grain muxes.
  #
  # Return Value:
  #   list with all the cell that are used to form muxes with LUTs
  ########################################################################################  
  proc get_FU_LUT_cells {FU_position_list column_offset pblock_location} {
    set ordered_FU_cells [list]
    set order_list_position "0 4 1 5 2 6 3 7"
    foreach position $FU_position_list {
      set unordered_FU_cells [lsort -dictionary [get_cells -hierarchical -filter "fu_position == $position && PBLOCK_COLUMN_OFFSET == $column_offset && PBLOCK_FINE_GRAIN == $pblock_location"]]
      for {set i 0} {$i < [llength $unordered_FU_cells]} {set i [expr $i + 8]} {
        foreach position $order_list_position {
          set ordered_FU_cells [concat $ordered_FU_cells [lindex $unordered_FU_cells [expr $i + $position]]]
        }
      }
    }
    return $ordered_FU_cells
  } 
  
  ########################################################################################
  # This function returns a list with sublists containing all the SLICE elements of a  
  # column. i.e., {{slices of column 1} ··· {slices of column n}}
  # 
  #
  # Argument Usage:
  #   pblock_name: name of the pblock to obtain the slice elements 
  # 
  #
  # Return Value:
  #   List with sublists containing all the SLICE elements of a column
  ########################################################################################
  proc find_CLB_slice_columns_in_pblock {pblock_name} {
    set pblock [get_pblocks $pblock_name]
    set all_slices [get_sites -of_objects $pblock -filter "SITE_TYPE =~ SLICE?"]
    set X_coordinates [lsort -integer -unique [get_property RPM_X $all_slices]]
    set Y_clock_regions [lsort -integer -unique -integer [get_property ROW_INDEX [get_clock_regions -of_objects  $all_slices]]]
    set slices_list [list]
    for {set i 0} {$i < [llength $X_coordinates]} {incr i} {
      set slices_in_pblock_column [list]
      for {set j 0} {$j < [llength $Y_clock_regions]} {incr j} {
        set slices_in_pblock_column [concat $slices_in_pblock_column [lsort -dictionary -unique [get_sites -of_objects [get_pblocks $pblock_name] -filter "CLOCK_REGION =~ X?Y[lindex $Y_clock_regions $j] && SITE_TYPE =~ SLICE? && RPM_X == [lindex $X_coordinates $i]"]]]
      }
      lappend slices_list $slices_in_pblock_column
    }
    return $slices_list
  }
  
}