##########################################################################################
# This library provides functions dealing with design reconstruction. That is to compone 
# the reconfigurable modules into the static design. 
# 
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################

package require struct::set

namespace eval ::reconfiguration_tool::design_reconstruction  {
  # namespace import ::reconfiguration_tool::interface::* 
  # namespace import ::reconfiguration_tool::place_and_route::* 
  # Procs that can be used in other namespaces
  namespace export extract_hierarchical_cell_info
  namespace export save_static_dcp_for_hierarchical_reconstructions
  namespace export insert_reconfigurable_module
  
  ########################################################################################
  # This function takes an implemented reconfigurable module and extracts all the info 
  # to be able to compose the module into the static system. It generates three files into 
  # the design reconstruction folder
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of relocatable reconfigurable partitions
  # module_name: name of the module to be extracted
  #
  # Return Value:
  ########################################################################################
  proc extract_hierarchical_cell_info {reconfigurable_partition_group module_name} {
    variable ::reconfiguration_tool::project_variables
    
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]

    # We get the initial coordinates of each site type of the pblock 
    set pblock [get_pblocks pblock_[get_cells -filter "RECONFIGURABLE_PARTITION == 1"]]
    set hierarchical_pblocks [::struct::set difference [get_pblocks] $pblock]
    set pblock_definition [string map {, ""} [get_property GRID_RANGES $pblock]]
    foreach site_type $pblock_definition {
      if {[string first RAMB18 $site_type] != -1} {
        regexp {RAMB18_X([0-9]+)Y([0-9]+).*} $site_type -> RAMB18_X RAMB18_Y
      } elseif {[string first RAMB36 $site_type] != -1} {
        regexp {RAMB36_X([0-9]+)Y([0-9]+).*} $site_type -> RAMB36_X RAMB36_Y
      } elseif {[string first SLICE $site_type] != -1} {
        regexp {SLICE_X([0-9]+)Y([0-9]+).*} $site_type -> SLICE_X SLICE_Y
      } elseif {[string first DSP48 $site_type] != -1} {
        regexp {DSP48_X([0-9]+)Y([0-9]+).*} $site_type -> DSP48_X DSP48_Y
      }
    }
    
    set pins_interface [get_pins -filter "HD.PARTPIN_LOCS != {}"]
    # We assign partition pins to the dummy logic.
    foreach pin $pins_interface {
      set ref_pin_name [get_property REF_PIN_NAME $pin]
      set partition_pin [get_property HD.PARTPIN_LOCS $pin]
      set dummy_pin [get_pins -filter "REF_PIN_NAME == $ref_pin_name && HD.PARTPIN_LOCS == {}"]
      if {$dummy_pin != {}} {
        set_property HD.PARTPIN_LOCS $partition_pin $dummy_pin
      }
    }
    
    set internal_reconfigurable_cells [get_cells -hierarchical -filter "PRIMITIVE_LEVEL == LEAF && REF_NAME !~ *BUF* && PARENT != dummy"]
    set reconfigurable_load_pins [get_pins -of_objects $internal_reconfigurable_cells -filter "IS_LEAF == 1 && DIRECTION == IN"]

    # The first thing we need to do is lock the LUT pins assignation, so the PAR tool
    # won't swap pin positions when it places the dessign. 
    array unset lut_array 
    foreach loadpin $reconfigurable_load_pins {  
      
      set pin [lindex [split $loadpin /] end]
      set belpin [lindex [split [get_bel_pins -of $loadpin] /] end]
      set beltype [get_bel_pins -of $loadpin] 
      set route_through_pin [lindex $beltype 0]
      # Create hash table of LUT names and pin assignments, appending when needed
      if {[regexp (LUT) $beltype]} {
        
        if {[llength $beltype] > 1} {
            
            #If there is more than one beltype this means that there is a route through LUT, to fix the 
            #pin assignation it is necessary to insert a dummy lut to have a logical elementey that 
            #maps the physical LUT. If this is not done is not possible to place a LOCK_PINS constraint            
            set net [get_nets -of_objects $loadpin]
            set route_net [get_property ROUTE $net]
            set net_segments [get_nets -segments -of_objects $loadpin]
            set_property DONT_TOUCH 0 $net_segments
            set parent_cell [get_cells -of_objects $loadpin]
            
            # We search all the cells that are connected through the same LUT           
            set LUT_through_pins [list]
            set all_connected_pins [get_pins -of_objects $net_segments -filter "IS_LEAF == 1 && DIRECTION == IN"] 
            foreach individual_pin $all_connected_pins {
              set route_through_individual_pin [lindex [get_bel_pins -of $individual_pin]  0]
              if {$route_through_individual_pin == $route_through_pin} {
                set LUT_through_pins [concat $LUT_through_pins $individual_pin]
              }
            }
            
            set cell_name "${parent_cell}_${belpin}_route_through_LUT_inserted"
            create_cell -reference LUT1 $cell_name
            set_property INIT 2'h2 [get_cells $cell_name] ;#equation for LUT1 buffer
            set net_inserted "${parent_cell}_${belpin}_route_through_net_inserted"
            create_net $net_inserted
            disconnect_net -net $net_segments -objects $LUT_through_pins
            connect_net -hierarchical -net $net_inserted -objects [concat $LUT_through_pins $cell_name/O]
            connect_net -net $net -objects $cell_name/I0
            
            foreach beltype_pin $beltype {
              if {[regexp (LUT) $beltype]} {
                set LUT_pin $beltype_pin 
                break
              }
            }
            
            set_property BEL [lindex [split $LUT_pin /] 1] [get_cells $cell_name]
            set_property LOC [lindex [split $LUT_pin /] 0] [get_cells $cell_name]
            
            set belpin [lindex [split $LUT_pin /] end]
            set lut $cell_name
            set pin I0
            
            #We reconstruct pin association 
            set_property LOCK_PINS "$pin:$belpin" [get_cells $lut]
            set_property ROUTE $route_net $net
            #select belpin y poner un LOC y BEL constraint a la LUT creada  
        } else {
          # set index [expr [string length $loadpin] - 4]
          # set lut [string range $loadpin 0 $index]
          set lut [get_cells -of_objects $loadpin]
        }
        #We add the LUT info into the array 
        if { [info exists lut_array($lut)] } {
          #If the variable already exists we add the info of the new pins 
          set lut_array($lut) "$lut_array($lut) $pin:$belpin"
        } else {
          set lut_array($lut) "$pin:$belpin"
        }
      }
    }
    
    set parent_cell {${parent_cell}/}
    set internal_constraints_file_name "${directory}/${project_name}/DESIGN_RECONSTRUCTION/${partition_group_name}_${module_name}_internal_constraints"
    set fileID [open $internal_constraints_file_name w]
    foreach lut_name [array names lut_array] {
      set child_cell [join [lrange [split $lut_name /] 1 end] /]
      set cell_name ${parent_cell}${child_cell}
      puts $fileID "set_property LOCK_PINS \"$lut_array($lut_name)\" \[get_cells $cell_name\]"
    }
    # close $internal_constraints_file_name
    
    #We save the LOC and BEL properties of the cells. The LOC property needs to be relative to the 
    #pblock location. To do this there are several options, the one that is used here involves setting 
    #the LOCS with different variables (one for each type of site i.e. SLICE, DSP RAMB18, RAMB36). 
    #Other options involve the use of a macro to create RLOC properties, the problem is that cells 
    #have the same relative location among them but not with the pblock where they are contained, so 
    #it would be necessary select the placement of one cell or create another smaller pblock to 
    #constraint the placement in such a way that only one placement is possible. 
    #NOTE as explained in the paper "T. Townsend and B. Nelson, "Vivado design interface: An export/import capability for Vivado FPGA designs," 2017 27th International Conference on Field Programmable Logic and Applications (FPL), Ghent, 2017, pp. 1-7. doi: 10.23919/FPL.2017.8056809"
    #section 3.A it is important to place the different bels in a site in an specific order so the 
    #internal routes are routed correctly 
    set internal_reconfigurable_cells [get_cells -hierarchical -filter "(PRIMITIVE_LEVEL == LEAF || PRIMITIVE_LEVEL == MACRO)  && REF_NAME !~ *BUF* && PARENT != dummy"]
    set slice_type SLICE\[LM\]+\.
    # We change a little the order from the paper (experimentally I have found error 
    # in their order). As this is done experimentally it is possible that some minor 
    # changes are needed to route all the designs.
    # set bel_type_list  {D.LUT A.LUT B.LUT C.LUT \[A-D\]+FF CARRY. \[A-D\]+5FF} #funciona con el diseño de ARTICO
    set bel_type_list  {D.LUT \[A-D\]+FF A.LUT B.LUT C.LUT CARRY. \[A-D\]+5FF} ;#funciona con el diseño de ARTICO
    set grouped_cells_by_BEL ""
    foreach bel_type $bel_type_list {
      set bel ${slice_type}${bel_type}
      set cells [get_cells -hierarchical -regexp -filter "BEL =~ ${bel} && ((PRIMITIVE_LEVEL == LEAF || PRIMITIVE_LEVEL == MACRO) && PARENT != dummy && REF_NAME !~ .*BUF.*)"]
      set internal_reconfigurable_cells [::struct::set difference $internal_reconfigurable_cells $cells]
      lappend grouped_cells_by_BEL $cells 
    }
    lappend grouped_cells_by_BEL $internal_reconfigurable_cells
    
    foreach same_BEL_cells $grouped_cells_by_BEL {
      foreach cell $same_BEL_cells {
        set child_cell [join [lrange [split $cell /] 1 end] /]
        set cell_name ${parent_cell}${child_cell}
        #We fix the BEL property, that is the relative basic element in a site i.e. use the LUT C
        set BEL [get_property BEL $cell]
        if {$BEL != {}} {
          puts $fileID "set_property BEL [get_property BEL $cell] \[get_cells $cell_name\]"
          puts $fileID "set_property IS_BEL_FIXED 1 \[get_cells $cell_name\]"
        } else {
            continue 
        }
    
        #We fix the LOC property, that is to fix the location of the site, we use relative location 
        set initial_LOC [get_property LOC $cell]
        if {[regexp {(\S*)_X([0-9]+)Y([0-9]+)} $initial_LOC -> site_type X_coord Y_coord]} {
          if {$site_type == "RAMB18"} {
            set X_coord [expr $X_coord - $RAMB18_X]
            set Y_coord [expr $Y_coord - $RAMB18_Y]
            set site_location "${site_type}_X\[expr $X_coord + \$RAMB18_X\]Y\[expr $Y_coord + \$RAMB18_Y\]"
            puts $fileID "set_property LOC ${site_location} \[get_cells $cell_name\]"
          } elseif {$site_type == "RAMB36"} {
            set X_coord [expr $X_coord - $RAMB36_X]
            set Y_coord [expr $Y_coord - $RAMB36_Y]
            set site_location "${site_type}_X\[expr $X_coord + \$RAMB36_X\]Y\[expr $Y_coord + \$RAMB36_Y\]"
            puts $fileID "set_property LOC ${site_location} \[get_cells $cell_name\]"
          } elseif {$site_type == "SLICE"} {
            set X_coord [expr $X_coord - $SLICE_X]
            set Y_coord [expr $Y_coord - $SLICE_Y]
            set site_location "${site_type}_X\[expr $X_coord + \$SLICE_X\]Y\[expr $Y_coord + \$SLICE_Y\]"
            puts $fileID "set_property LOC ${site_location} \[get_cells $cell_name\]"
          } elseif {$site_type == "DSP48"} {
            set X_coord [expr $X_coord - $DSP48_X]
            set Y_coord [expr $Y_coord - $DSP48_Y]
            set site_location "${site_type}_X\[expr $X_coord + \$DSP48_X\]Y\[expr $Y_coord + \$DSP48_Y\]"
            puts $fileID "set_property LOC ${site_location} \[get_cells $cell_name\]"
          }
          puts $fileID "set_property IS_LOC_FIXED 1 \[get_cells $cell_name\]"
        }
      }
    }
    
    #Now we save the routes of the internal nets
    #We need to unroute the physical nets because they are combined and the same net can combine  
    #physical nets of the dummy and the reconfigurable logic 
    route_design -physical_nets -unroute 
    set interface_nets [get_nets -segments -of_objects $pins_interface]
    set internal_reconfigurable_nets [::struct::set difference [get_nets -hierarchical -filter "ROUTE_STATUS != INTRASITE"] $interface_nets]
    foreach net $internal_reconfigurable_nets {    
      set child_net [join [lrange [split $net /] 1 end] /]
      set net_name ${parent_cell}${child_net}
      set route [get_property ROUTE $net]
      if {[regexp {\w} $route]} {
        puts $fileID "set_property ROUTE $route \[get_nets $net_name\]"
      }
    }
    
    #We save the location of the pblock and the partitio pins 
    foreach pblock $hierarchical_pblocks {
      set pblock_definition [string map {, ""} [get_property GRID_RANGES $pblock]]
      puts $fileID "create_pblock $pblock"
      puts $fileID "resize_pblock $pblock -add {$pblock_definition}"
      set cell [get_cells -of_objects [get_pblocks pblock_hierarchical_2_0]]
      set child_cell [join [lrange [split $cell /] 1 end] /]
      set cell_name ${parent_cell}${child_cell}
      puts $fileID "set_property PARENT ROOT $pblock"
      puts $fileID "add_cells_to_pblock $pblock $cell_name"
      set interface_pins [get_pins -of_objects $cell -filter "HD.PARTPIN_LOCS != {}"]
      foreach pin $interface_pins {
        set child_pin [join [lrange [split $pin /] 1 end] /]
        set pin_name ${parent_cell}${child_pin}
        set partition_pin [get_property HD.PARTPIN_LOCS $pin]
        puts $fileID "set_property HD.PARTPIN_LOCS $partition_pin \[get_pins $pin_name\]"
      }
      
    }
    
    close $fileID

    set dummy_cells [get_cells dummy]
    set local_interface_nets [get_nets -of_objects $dummy_cells -filter "TYPE !~ *CLOCK"]
    set_property IS_ROUTE_FIXED 1 $local_interface_nets
    set_property HD.partition 1 $dummy_cells
    update_design -cells $dummy_cells -black_box
    
    
    #We save the routes if the interface nets to the partition pins.
    set interface_file_name "${directory}/${project_name}/DESIGN_RECONSTRUCTION/${partition_group_name}_${module_name}_interface_nets"
    set fileID [open $interface_file_name w]
    foreach pin $pins_interface {
      puts $fileID "[get_property REF_PIN_NAME $pin] [get_property ROUTE [get_nets -of_objects $pin]]"
    }
    close $fileID
    
    #Now we unroute and unplace the design to export only the synthesis checkpoint 
    lock_design -unlock -level placement
    lock_design -unlock -level routing
    
    place_design -unplace 
    route_design -unroute 
    
    #We save a checkpoint of the cell
    write_checkpoint -cell [get_cells -filter "RECONFIGURABLE_PARTITION == 1"] "${directory}/${project_name}/DESIGN_RECONSTRUCTION/${partition_group_name}_${module_name}"
  }

  ########################################################################################
  # Saves a design checkpoint of the static system that can be used for design 
  # reconstruction.
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc save_static_dcp_for_hierarchical_reconstructions {} {
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    
    set_property IS_ROUTE_FIXED 1 [get_nets -hierarchical]
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      if {[catch {::reconfiguration_tool::interface::place_partition_pins $reconfigurable_partition_group "static"} errmsg]} {
        file mkdir ${directory}/${project_name}/ERROR
        write_checkpoint ${directory}/${project_name}/ERROR/static_system
        set fileId [open "${directory}/${project_name}/info" "a+"]
        puts $fileId "ERROR -> module: static, type: $errmsg"
        close $fileId
        return 
      }
    }
    set_property IS_ROUTE_FIXED 0 [get_nets -hierarchical]

    write_checkpoint "${directory}/${project_name}/DESIGN_RECONSTRUCTION/static_system"
  }

  ########################################################################################
  # This function sort the bell elements of a site in ther order explained in the 
  # "T. Townsend and B. Nelson, "Vivado design interface: An export/import capability for 
  # Vivado FPGA designs," 2017 27th International Conference on Field Programmable Logic 
  # and Applications (FPL), Ghent, 2017, pp. 1-7. doi: 10.23919/FPL.2017.8056809" It is 
  # necessary to have the BEL placement constraints in a certain order for not having 
  # routing problems.
  #
  # Argument Usage:
  # site: site which elements will be analyzed
  #
  # Return Value:
  # returns a list of sorted cells 
  ########################################################################################
  proc sort_cell_by_bel_type {site} {
    set site_cells [get_cells -of_objects $site -filter "(PRIMITIVE_LEVEL == LEAF || PRIMITIVE_LEVEL == MACRO)"]
    if {[llength $site_cells] == 0} {
      return ""
    }
    
    set site_type [get_property SITE_TYPE $site]
    if {[string first "SLICE" $site_type] != -1} {
      set bel_site_types [get_property BEL $site_cells]
      # We change a little the order from the paper (experimentally I have found error 
      # in their order). As this is done experimentally it is possible that some minor 
      # changes are needed to route all the designs.
      set bel_type_list  {D.LUT \[B-C\]+.LUT \[A-D\]+FF A.LUT CARRY. \[A-D\]+5FF}
      # set bel_type_list  {D.LUT \[B-C\]+.LUT \[A-D\]+FF A.LUT CARRY. \[A-D\]+5FF}
      
      set sorted_list_cells ""
      foreach bel_type $bel_type_list {
        set bel ${site_type}.${bel_type}
        if {[regexp $bel $bel_site_types]} {
          set cells [get_cells -of_objects $site -regexp -filter "BEL =~ ${bel}"]  
          set sorted_list_cells [concat $sorted_list_cells $cells]
        }
      }
    } else {
      set sorted_list_cells $site_cells
    }
    
    return $sorted_list_cells 
  }


  ########################################################################################
  # To use this function it is necessary to open the static syatem DCP (design check point)
  # saved in the DESIGN_RECONSTRUCTION folder if the project. Then it is posible 
  # reconstruct reconfigurable modules into the design checkpoint. 
  #
  # Argument Usage:
  # pblock_name: name of the pblock where the the reconfigurable module will be
  # reconstructed.
  # dcp_file: path of the reconfigurable module DCP included in the DESIGN_RECONSTRUCTION 
  # folder.  
  #
  # Return Value:
  ########################################################################################
  proc insert_reconfigurable_module {pblock_name dcp_file} {
    regexp {(.*)\.dcp} $dcp_file -> file
    set physical_interface_file ${file}_interface_nets
    set internal_constraints_file ${file}_internal_constraints 
    
    
    set pblock [get_pblocks $pblock_name]
    set_property PARENT ROOT $pblock
    set cell [get_cells -of_objects $pblock]
    set pblock_definition [string map {, ""} [get_property GRID_RANGES $pblock]]
    #We get the initial coordinates of each site type of the pblock 
    foreach site_type $pblock_definition {
      if {[string first RAMB18 $site_type] != -1} {
        regexp {RAMB18_X([0-9]+)Y([0-9]+).*} $site_type -> RAMB18_X RAMB18_Y
      } elseif {[string first RAMB36 $site_type] != -1} {
        regexp {RAMB36_X([0-9]+)Y([0-9]+).*} $site_type -> RAMB36_X RAMB36_Y
      } elseif {[string first SLICE $site_type] != -1} {
        regexp {SLICE_X([0-9]+)Y([0-9]+).*} $site_type -> SLICE_X SLICE_Y
      } elseif {[string first DSP48 $site_type] != -1} {
        regexp {DSP48_X([0-9]+)Y([0-9]+).*} $site_type -> DSP48_X DSP48_Y
      }
    }

    set local_interface_nets [get_nets -of_objects $cell -filter "TYPE !~ *CLOCK"]
    set global_interface_nets [get_nets -of_objects $cell -filter "TYPE =~ *CLOCK"]
    set local_pins [get_pins -of_objects $local_interface_nets -filter "PARENT_CELL == $cell"]
    
    #We create a dict with the partition pins of the dict
    set all_partition_pin_dict [dict create]
    foreach pin $local_pins {
      set partition_pin [get_property HD.PARTPIN_LOCS $pin]
      dict set all_partition_pin_dict $pin $partition_pin
    }
    
    set_property IS_ROUTE_FIXED 0 [get_nets -hierarchical]
    set_property IS_ROUTE_FIXED 1 $local_interface_nets
    set_property HD.partition 1 $cell


    update_design -cells  $cell -black_box
    
    #We save the static routes in a dict 
    set static_routes_dict [dict create]
    foreach pin $local_pins {
      dict set static_routes_dict [get_property REF_PIN_NAME $pin] [get_property ROUTE [get_nets -of_objects $pin]]
    }
    
    set parent_cell $cell
    
    read_checkpoint -quiet -cell $cell $dcp_file 
    
    add_cells_to_pblock $pblock $cell
    set reconfigurable_cells [get_cells -hierarchical -filter "HD.reconfigurable == 1"]
    foreach cell $reconfigurable_cells {
      set_property HD.reconfigurable 0 $cell
    }
    
    set_property HD.partition 0 $cell
    set_property HD.reconfigurable 0 $cell
    # set_property IS_ROUTE_FIXED 1 [get_nets -hierarchical]

    read_xdc -unmanaged $internal_constraints_file
    
    
    #We read the physical interface file of the reconfigurable module and save in a dict 
    set reconfigurable_routes_dict [dict create]
    set fileId [open $physical_interface_file r]
    while {[gets $fileId line] != -1} {
      regexp {(\S+)\s+(.*)} $line -> pin route
      dict set reconfigurable_routes_dict $pin $route
    }
    close $fileId
    
    #We combine the 2 nets. There can be problem if the same net feed 2 pins with the same partition 
    #pin 
    set nets_with_problems ""
    set index ""
    set hand_routing_pins "" 
    set local_interface_nets [get_nets -of_objects $cell -filter "TYPE !~ *CLOCK"]
    foreach local_net $local_interface_nets {
      #We need to search all the segments of the nets because it can converge with other nets. 
      #So in order to find all the pins connected to the same physical net it is necessary to select 
      #all the segments of the net 
      set net [get_nets -segments $local_net]
      set pins [get_pins -of_objects $net -filter "PARENT_CELL == $cell"]

      set pin_direction [get_property DIRECTION [lindex $pins 0]]
      if {$pin_direction == "IN"} {
        set starting_route [lindex [dict get $static_routes_dict [get_property REF_PIN_NAME [lindex $pins 0]]] 0]
      } else {
        set starting_route [lindex [dict get $reconfigurable_routes_dict [get_property REF_PIN_NAME [lindex $pins 0]]] 0]
      }
      set ending_route [dict create]
      set partition_pin_nodes ""
      set partition_pin_dict [dict create]
      foreach pin $pins {
        set ref_pin_name [get_property REF_PIN_NAME $pin]
        if {$pin_direction == "IN"} {
          dict set ending_route $ref_pin_name [lindex [dict get $reconfigurable_routes_dict $ref_pin_name] 0]
        } else {
          dict set ending_route $ref_pin_name [lindex [dict get $static_routes_dict $ref_pin_name] 0]
        }
        set partition_pin [dict get $all_partition_pin_dict $pin]
        dict set partition_pin_dict $partition_pin $pin
        regexp {(.*)/(.*)} $partition_pin -> tile node
        set partition_pin_nodes [concat $partition_pin_nodes $node]
      }
      #The starting routes should be equal to each other. We select one of them and we flat the hierarchy 
      #This is done by changing the bracket for start_branch and end_branch. This allows to treat the 
      #route as a list and not as a list of lists 
      set starting_route [string map {\{ start_branch \} end_branch}  [concat "{ " $starting_route " }"]]
      set modified_starting_route $starting_route

      #We search for all the possible position in the starting_route where we have to insert a branch 
      set branch_positions ""
      foreach node $partition_pin_nodes {
        set possible_positions [lsearch -all $starting_route $node]
        foreach position $possible_positions {
          #The nodes used for partition pins can't be end nodes. Thus if we find one of these nodes 
          #in the end of a branch this means that it has been cut and is the partition pin where we 
          #need to insert the ending route
          if {[lindex $starting_route [expr $position + 1]] == "end_branch"} {
            set branch_positions [concat $branch_positions $position]
            break 
          }
        }
      }
      set branch_positions [lsort $branch_positions]
      if {[llength [lsort -unique $partition_pin_nodes]] != [llength $partition_pin_nodes]} {
        #We search for the partition pin nodes to replace them with the complete tile/node info 
        set driver [get_pins -of_objects $net -filter "IS_LEAF == 1 && DIRECTION == OUT"]
        set previous_node [get_nodes -of_objects [get_tiles -of_objects [get_sites -of_objects [get_cells -of_objects $driver]]] */[lindex $starting_route 1]]
        set init_branch_node_list ""
        for {set i 2} {$i < [llength $starting_route]} {incr i} {
          set actual_node [lindex $starting_route $i]
          if {$actual_node == "start_branch"} {
            lappend init_branch_node_list $previous_node
            continue
          } elseif {$actual_node == "end_branch"} {
            #We select the last element of the "init_branch_node_list" as the new origin node and we 
            #delete it from the list 
            set previous_node [lindex $init_branch_node_list end]
            set init_branch_node_list [lrange $init_branch_node_list 0 end-1]
            continue
          }
          
          # set destination_pips [get_pips -downhill -of_objects $previous_node]
          # regexp {(\S+)/(\S+)} $previous_node -> tile node 
          if {[string first "<" $actual_node] == -1} {
            #There is only one possible node. When there are more the name of the node starts with 
            #<num> indicating the number of the node to be selected 
            set pips [get_pips -downhill -of_objects $previous_node *$actual_node]
            #If there are 2 nodes repeated successively we will find 2 nodes the previous one and the 
            #new one --> We have to insure that we only select the new one 
            set nodes [get_nodes -downhill -of_objects $pips ]
            set previous_node [::struct::set difference $nodes $previous_node]  
          } else {
            regexp {<([0-9]+)>(.*)} $actual_node -> node_position node_definition
            #NOTE when there are multiple nodes with the same identifier, Xilinx uses a special 
            #notation to distinguish them. It uses a prefix <num> to indicate the specific node. 
            #The first tests seem to indicate that the algorithm sorts the nodes by how far they are from 
            #the center to the origin of the FPGA. Tha is measured by TILE_X and TILE_Y properties 
            #I have not test what happens when the are repeated nodes in positive and negative sides. 
            #Right now the criterion is the first nodes are the ones in the left. But it could be other 
            set destination_pips [get_pips -downhill -of_objects $previous_node *$node_definition]
            # set possible_nodes [get_nodes -downhill -of_objects $destination_pips]
            set possible_tiles [get_tiles -of_objects $destination_pips]
            #We have to detect if the nodes are in the same row or in the same column 
            set X_coordinates [lsort -dict -unique [get_property TILE_X $possible_tiles]]
            if {[llength $X_coordinates] > 1} {
              set tile [get_tiles -of_objects $destination_pips -filter "TILE_X == [lindex $X_coordinates $node_position]"] 
              set pip [get_pips -downhill -of_objects $previous_node $tile*$node_definition]
              set previous_node [get_nodes -downhill -of_objects $pip]
            }
            
            set Y_coordinates [lsort  -dict -unique [get_property TILE_Y $possible_tiles]]
            if {[llength $Y_coordinates] > 1} {
              set tile [get_tiles -of_objects $destination_pips -filter "TILE_Y == [lindex $Y_coordinates $node_position]"] 
              set pip [get_pips -downhill -of_objects $previous_node $tile*$node_definition]
              set previous_node [get_nodes -downhill -of_objects $pip]
            }
          }
          
          if {[::struct::set contains $branch_positions $i]} {
            set pin [dict get $partition_pin_dict $previous_node]
            set ref_pin_name [get_property REF_PIN_NAME $pin]
            set modified_starting_route [lreplace $modified_starting_route $i $i $ref_pin_name]
          }

        }
      } else {
        foreach position $branch_positions {
          set node [lindex $starting_route $position]
          set pin [dict values [dict filter $partition_pin_dict key */${node}]]
          set ref_pin_name [get_property REF_PIN_NAME $pin]
          set modified_starting_route [lreplace $modified_starting_route $position $position $ref_pin_name]
        }
      }
      
      #Now we change the modified_starting_route to include the destination branches 
      foreach pin $pins {
        set ref_pin_name [get_property REF_PIN_NAME $pin]
        set position [lsearch -exact $modified_starting_route $ref_pin_name] 
        set modified_starting_route [concat [lrange $modified_starting_route 0 [expr $position - 1]] [dict get $ending_route $ref_pin_name] [lrange $modified_starting_route [expr $position + 1] end]]
      }
      
      #We rebuild the list herarchy 
      set final_route [string map {start_branch \{ end_branch \}} $modified_starting_route]
      #We assign the route to the net 
      set_property ROUTE $final_route $net
    } 

    #We route the physical nets that have not been routed
    route_design -preserve -physical_nets
    #We route the global nets 
    #Check if only route the global nets that we have disabled
    ::reconfiguration_tool::place_and_route::route_global_nets
     
    

    
    #We add the partition pins 
    set_property IS_ROUTE_FIXED 1 $local_interface_nets
    foreach pin [dict keys $all_partition_pin_dict] {
      set_property HD.PARTPIN_LOCS [dict get $all_partition_pin_dict $pin] $pin 
    }
  }
}