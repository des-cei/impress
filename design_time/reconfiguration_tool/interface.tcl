##########################################################################################
# This library provides functions dealing with the interface of the reconfigurable 
# partitions. 
# 
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################


package require struct::set

namespace eval ::reconfiguration_tool::interface {
  namespace import ::reconfiguration_tool::utils
  
  # Procs that can be used in other namespaces
  namespace export obtain_interface_info
  namespace export create_interface
  namespace export place_partition_pins
  namespace export delete_duplicated_partition_pins
  
  variable groups_of_nets_info_list
  
  ########################################################################################
  # Generates the interface for a group of relocatable partitions. In order to do so it 
  # analyzes the netlist and the virtual architecture (i.e., the floorplanning of the FPGA) 
  # The function divides the reconfigurable partition pins in groups by where they are 
  # connected and assigns them a group of tiles that can be used. 
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of partitions from which the interface will be 
  # obtained
  #
  # Return Value:
  ########################################################################################
  proc create_interface {reconfigurable_partition_group} {  
    variable ::reconfiguration_tool::project_variables
    set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
    set reconfigurable_partition_reference [lindex $reconfigurable_partition_list 0]
    set reconfigurable_cell_reference [get_cells -hierarchical [dict get $reconfigurable_partition_reference partition_name]]
    
    set interface_pins [get_pins -of_objects $reconfigurable_cell_reference]
    set pin_interfaces_dict [dict create]
    set pin_globals_dict [dict create]
    
    # First we check for free clock positions 
    # TODO make the number of global clocks a parameter that depends on the target FPGA 
    set free_clock_positions {}
    for {set i 0} {$i <= 11} {incr i} {
      set free_clock_positions [concat $free_clock_positions $i]
    }
    if {[dict exists global_nets_info all_global_nets]} {
      set global_nets [dict keys [dict get $global_nets_info all_global_nets]]
      foreach net $global_nets {
        set position [dict get $global_nets_info all_global_nets $net_name position
        set free_clock_positions [::struct::set difference $free_clock_positions $position]
      }
    }
    
    foreach pin $interface_pins {
      # We need to check how the pin is connected in each reconfigurable partition. We 
      # have to see if the net is connected to another reconfigurable partition or to the 
      # static system. It is also necessary to check if it is a global clock.
      set net_type [get_property TYPE [lindex [get_nets -of_objects $pin] 0]]
      if {$net_type == "GLOBAL_CLOCK"} {
        dict set pin_globals_dict $pin [lindex $free_clock_positions 0]
        # We remove the first element 
        set free_clock_positions [lreplace $free_clock_positions 0 0]
        continue 
      }
      
      # We iterate for each reconfigurable partition that forms part of the relocatable 
      # partition group. 
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set hierarchical_partition_list [dict get $reconfigurable_partition hierarchical_partition_list]
        if {[llength $hierarchical_partition_list] > 0} {
          break
        }
        set partition_name [dict get $reconfigurable_partition partition_name]
        set reconfigurable_cell [get_cells -hierarchical ${partition_name}]
        set ref_pin_name [get_property REF_PIN_NAME $pin]
        set net [get_nets -of_objects [get_pins ${reconfigurable_cell}/${ref_pin_name}]]
        set connected_cells [get_cells -of_objects $net -filter "NAME != $reconfigurable_cell"]
        set connected_cells_number [llength $connected_cells]
        if {($connected_cells_number == 1) && ([get_property RECONFIGURABLE_PARTITION $connected_cells] == 1)} {
          # It is possible that even if it seems as a reconfigurable-to-reconfigurable 
          # connection the pblock are not close to each other and the connection needs to 
          # be done through the static system.
          set source_pblock [dict get $reconfigurable_partition xilinx_format_pblock_list]
          set destination_pbock [string map {, ""} [get_property GRID_RANGES [get_pblocks -of_objects $connected_cells]]]
          if {[catch {set direction_info [obtain_direction_info_from_pblocks_connection $source_pblock $destination_pbock]} errmsg] == 0} {
            set parsed_direction_info {}
            foreach direction $direction_info {
              set cardinal_direction [dict get $direction cardinal_direction]
              set first_tile [dict get $direction first_tile]
              set last_tile [dict get $direction last_tile]
              set directions_expanded $cardinal_direction
              for {set i $first_tile} {$i <= $last_tile} {incr i} {
                set directions_expanded [concat $directions_expanded $i]
              }
              lappend parsed_direction_info $directions_expanded 
            }
            dict append pin_interfaces_dict $pin $parsed_direction_info
          }
        }
      }
    }

    # We compare the info of each pin for the different reconfigurable partitions to 
    # extract the common interfaces. Those common interface are the ones that can only be 
    # used.   
    foreach key [dict keys $pin_interfaces_dict] {
      set pin_interface_list [dict get $pin_interfaces_dict $key]
      for {set i 0} {$i < [expr [llength $pin_interface_list] - 1]} {incr i} {
        if {$i == 0} {
          set actual_location_string [lindex $pin_interface_list 0]
        }
        set next_location_string [lindex $pin_interface_list [expr $i +1]]
        #There can be multiple strings so we have to compare all of them
        set actual_string_directions {}
        foreach single_string $actual_location_string {
          set actual_string_directions [concat $set actual_string_directions [lindex single_string 0]]
        }
        set next_string_directions {}
        foreach single_string $next_location_string {
          set next_string_directions [concat $set next_string_directions [lindex single_string 0]]
        }
        set common_direction [::struct::set intersect $next_string_directions $actual_string_directions]
        
        if {$common_direction == {}} {
          # The direction of different reconfigurable partitions do not match --> There is 
          # an error in the floorplanning
          error "pin $key has incompatible locations from the different reconfigurable partitions"
        } else {
          set common_pin_location {}
          foreach direction $common_direction {
            set actual_direction_tiles {}
            foreach single_string $actual_location_string {
              if {[lindex $single_string 0] == $direction} {
                set actual_direction_tiles [concat $actual_direction_tiles [lrange $single_string 1 end]]
              }
            }
            set next_direction_tiles {}
            foreach single_string $next_location_string {
              if {[lindex $single_string 0] == $direction} {
                set next_direction_tiles [concat $next_direction_tiles [lrange $single_string 1 end]]
              }
            }
            set common_tile_numbers [::struct::set intersect $actual_direction_tiles $next_direction_tiles]
            if {$common_tile_numbers != {}} {
              set common_pin_location [concat $direction $common_tile_numbers]
            }
          }
          if {$common_pin_location != {}} {
            dict set pin_interfaces_dict $key $common_pin_location
          } else {
            error "pin $key has incompatible locations from the different reconfigurable partitions"
          }
        }
      }
    }
    
    set pins_not_connected_to_static [::struct::set union [dict keys $pin_interfaces_dict] [dict keys $pin_globals_dict]]
    set pins_connected_to_static [::struct::set difference $interface_pins $pins_not_connected_to_static]
    
    
    #We get the pblocks properties
    set first_X_list {}
    set last_X_list {}
    set first_Y_list {}
    set last_Y_list {}
    set first_TILE_X_list {}
    set last_TILE_X_list {}
    set first_TILE_Y_list {}
    set last_TILE_Y_list {}
    
    foreach reconfigurable_partition $reconfigurable_partition_list {
      set partition_name [dict get $reconfigurable_partition partition_name]
      set pblock [get_pblocks pblock_${partition_name}]
      set sites_pblock [get_sites -of_objects $pblock]
      set tiles_pblock [get_tiles -of_objects $sites_pblock]
      set INT_tiles_pblock [get_tiles -of_objects $tiles_pblock -filter {TYPE =~ INT_?}]
      set Y_property [lsort -unique -integer [get_property INT_TILE_Y $INT_tiles_pblock]]
      set first_Y_list [concat [lindex $Y_property 0] $first_Y_list]
      set last_Y_list [concat [lindex $Y_property end] $last_Y_list]
      set X_property [lsort -unique -integer [get_property INT_TILE_X $INT_tiles_pblock]]
      # We need to check that the first X INT_tile and the last X INT_tile really belong 
      # to the pblock because due to back-to-back issues it is possible that the pblock is 
      # placed outside the pblock. Another way to see it is that the pblocks only contain 
      # logic. We comment this function because if not late it thinks that the tiles are 
      # connected to another pblock....
      # set left_down_INT_tile [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == [lindex $Y_property end] && INT_TILE_X == [lindex $X_property 0]"]
      # if {[get_property TYPE $left_down_INT_tile] == "INT_R"} {
      #   #The INT tile is not contained in the pblock 
      #   set X_property [lreplace $X_property 0 0]
      # }
      set first_X_list [concat [lindex $X_property 0] $first_X_list]
      # set top_up_INT_tile [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == [lindex $first_Y_list $i] && INT_TILE_X == [lindex $X_property end]"]
      # if {[get_property TYPE $top_up_INT_tile] == "INT_L"} {
      #   #The INT tile is not contained in the pblock 
      #   set X_property [lreplace $X_property end end]
      # } 
      set last_X_list [concat [lindex $X_property end] $last_X_list]
      #The tile X properties are coordinate which have its origin on the center of the fpga so they
      #are useful to localizate the cuadrant of the FPGA 
      set TILE_X_property [lsort -unique -integer [get_property TILE_X $INT_tiles_pblock]] 
      set first_TILE_X_list [concat [lindex $TILE_X_property 0] $first_TILE_X_list]
      set last_TILE_X_list [concat [lindex $TILE_X_property end] $last_TILE_X_list]
      set TILE_Y_property [lsort -unique -integer [get_property TILE_Y $INT_tiles_pblock]] 
      set first_TILE_Y_list [concat [lindex $TILE_Y_property 0] $first_TILE_Y_list]
      set last_TILE_Y_list [concat [lindex $TILE_Y_property end] $last_TILE_Y_list]
    }

    #We get the valid positions for the pins connected to the static system 
    set first_X [lindex $first_X_list 0]
    set last_X [lindex $last_X_list 0]
    set NORTH {}
    for {set i $first_X} {$i <= $last_X} {incr i} {
      set NORTH [concat $NORTH [expr $i - $first_X]]
    }
    set SOUTH $NORTH
    set first_Y [lindex $first_Y_list 0]
    set last_Y [lindex $last_Y_list 0]
    set EAST {}
    for {set i $first_Y} {$i <= $last_Y} {incr i} {
      set EAST [concat $EAST [expr $i - $first_Y]]
    }
    set WEST $EAST
    
    foreach value_list [dict values $pin_interfaces_dict] {
      foreach value $value_list {
        switch -exact -- [string toupper [lindex $value 0]] {
          NORTH {
            set NORTH [::struct::set difference $NORTH [lrange $value 1 end]]
          }
          SOUTH {
            set SOUTH [::struct::set difference $SOUTH [lrange $value 1 end]]
          }
          EAST {
            set EAST [::struct::set difference $EAST [lrange $value 1 end]]
          }
          WEST {
            set WEST [::struct::set difference $WEST [lrange $value 1 end]]
          }
          default {}
        }
      }
    }
    
    
    #We get all then INT_tiles of all the pblocks 
    set all_pblocks [get_pblocks *]
    set all_sites_pblock [get_sites -of_objects $all_pblocks]
    set all_tiles_pblock [get_tiles -of_objects $all_sites_pblock]
    set all_INT_tiles_pblock [get_tiles -of_objects $all_tiles_pblock -filter {TYPE =~ INT_?}]
    
    
    set prohibited_tiles {}
    foreach tile_position $NORTH {
      for {set i 0} {$i < [llength $reconfigurable_partition_list]} {incr i} {
        set first_X [lindex $first_X_list $i]
        set last_X [lindex $last_X_list $i]
        set first_Y [lindex $first_Y_list $i]
        set last_Y [lindex $last_Y_list $i]
        set expanded_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == [expr $tile_position + $first_X] && INT_TILE_Y <= [expr $first_Y - 1] && INT_TILE_Y >= [expr $first_Y - 2]"]
        if {[llength $expanded_INT_tiles] != 2 || [::struct::set intersect $expanded_INT_tiles $all_INT_tiles_pblock] != {}} {
          set prohibited_tiles [concat $prohibited_tiles $tile_position]
        }
      }
    }
    set NORTH [::struct::set difference $NORTH $prohibited_tiles]
    
    set prohibited_tiles {}
    foreach tile_position $SOUTH {
      for {set i 0} {$i < [llength $reconfigurable_partition_list]} {incr i} {
        set first_X [lindex $first_X_list $i]
        set last_X [lindex $last_X_list $i]
        set first_Y [lindex $first_Y_list $i]
        set last_Y [lindex $last_Y_list $i]
        set expanded_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == [expr $tile_position + $first_X] && INT_TILE_Y >= [expr $last_Y + 1] && INT_TILE_Y <= [expr $last_Y + 2]"]
        if {[llength $expanded_INT_tiles] != 2 || [::struct::set intersect $expanded_INT_tiles $all_INT_tiles_pblock] != {}} {
          set prohibited_tiles [concat $prohibited_tiles $tile_position]
        }
      }
    }
    set SOUTH [::struct::set difference $SOUTH $prohibited_tiles]
    
    set prohibited_tiles {}
    foreach tile_position $EAST {
      for {set i 0} {$i < [llength $reconfigurable_partition_list]} {incr i} {
        set first_X [lindex $first_X_list $i]
        set last_X [lindex $last_X_list $i]
        set first_Y [lindex $first_Y_list $i]
        set last_Y [lindex $last_Y_list $i]
        set expanded_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X <= [expr $last_X + 2] && INT_TILE_X >= [expr $last_X + 1] && INT_TILE_Y == [expr $tile_position + $first_Y]"]
        if {[llength $expanded_INT_tiles] != 2 || [::struct::set intersect $expanded_INT_tiles $all_INT_tiles_pblock] != {}} {
          set prohibited_tiles [concat $prohibited_tiles $tile_position]
        }
      }
    }
    set EAST [::struct::set difference $EAST $prohibited_tiles]
    
    set prohibited_tiles {}
    foreach tile_position $WEST {
      for {set i 0} {$i < [llength $reconfigurable_partition_list]} {incr i} {
        set first_X [lindex $first_X_list $i]
        set last_X [lindex $last_X_list $i]
        set first_Y [lindex $first_Y_list $i]
        set last_Y [lindex $last_Y_list $i]
        set expanded_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X <= [expr $first_X - 1] && INT_TILE_X >= [expr $first_X - 2] && INT_TILE_Y == [expr $tile_position + $first_Y]"]
        if {[llength $expanded_INT_tiles] != 2 || [::struct::set intersect $expanded_INT_tiles $all_INT_tiles_pblock] != {}} {
          set prohibited_tiles [concat $prohibited_tiles $tile_position]
        }
      }
    }
    set WEST [::struct::set difference $WEST $prohibited_tiles]
    

    # We calculate the average center of the pblock and we situate in a quadrant. From 
    # this quadrant we assignate priorities to the directions
    set sum_center_X_pblock 0 
    set sum_center_Y_pblock 0
    for {set i 0} {$i < [llength $reconfigurable_partition_list]} {incr i} {
      set sum_center_X_pblock [expr $sum_center_X_pblock + ([lindex $last_TILE_X_list $i] + [lindex $first_TILE_X_list $i])/2]
      set sum_center_Y_pblock [expr $sum_center_Y_pblock + ([lindex $last_TILE_Y_list $i] + [lindex $first_TILE_Y_list $i])/2]
    }
    set average_X_center_pblock [expr $sum_center_X_pblock/[llength $reconfigurable_partition_list]]
    set average_Y_center_pblock [expr $sum_center_Y_pblock/[llength $reconfigurable_partition_list]]
    
    # Now we create a list with the direction with the priorities. The last 2 direction 
    # could be changed.
    if {$average_X_center_pblock < 0 && $average_Y_center_pblock < 0} {
      set direction_priorities {EAST NORTH SOUTH WEST}
    } elseif {$average_X_center_pblock < 0 && $average_Y_center_pblock > 0} {
      set direction_priorities {EAST SOUTH NORTH WEST}
    } elseif {$average_X_center_pblock > 0 && $average_Y_center_pblock < 0} {
      set direction_priorities {WEST NORTH SOUTH EAST}
    } else {
      set direction_priorities {WEST SOUTH NORTH EAST}
    }
    
    # Now we create a string containg all the possible interfaces that will be allowed to 
    # the static system. 
    
    set valid_connection_to_static {}
    
    foreach direction $direction_priorities {
      if {[llength [set $direction]] != 0} {
        set first_tile [lindex [set $direction] 0]
        set last_tile [lindex [set $direction] end]  
        set direction_info [string tolower ${direction}]_${first_tile}:${last_tile}
        set valid_connection_to_static [concat $valid_connection_to_static $direction_info]
      }
    }
    
    # We create a dict with the info of all the pins connected to the static system 
    set pin_connected_to_static_interface_dict_formatted {}
    foreach pin $pins_connected_to_static {
        set ref_pin_name [get_property REF_PIN_NAME [get_pins $pin]]
        dict set pin_connected_to_static_interface_dict_formatted $ref_pin_name $valid_connection_to_static
    }
    
    
    # Now we convert the pin_interfaces_dict to a variable with string with the interface
    # file format
    set pin_interfaces_dict_formatted [dict create]
    foreach key [dict keys $pin_interfaces_dict] {
      set pin_interfaces_dict_value [dict get $pin_interfaces_dict $key]  
      set formated_string_direction {}
      foreach direction_info $pin_interfaces_dict_value {
        set direction [lindex $direction_info 0]
        set first_tile [lindex $direction_info 1]
        set last_tile [lindex $direction_info end]
        set formated_string_direction [concat $formated_string_direction ${direction}_${first_tile}:${last_tile}]
      }
      set ref_pin_name [get_property REF_PIN_NAME [get_pins $key]]
      dict set pin_interfaces_dict_formatted $ref_pin_name $formated_string_direction
    }
    
    set pin_globals_dict_formatted {}
    foreach key [dict keys $pin_globals_dict] {
      set ref_pin_name [get_property REF_PIN_NAME [get_pins $key]]
      dict set pin_globals_dict_formatted $ref_pin_name [dict get $pin_globals_dict $key]
    }
    
    # We write the interface file 
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    file mkdir ${directory}/${project_name}/INTERFACE
    set interface_file_name "${directory}/${project_name}/INTERFACE/${partition_group_name}_interface"
    set interface_file [open $interface_file_name w]
    puts $interface_file local_nets
    # We write the interface of nets connected to other reconfigurable partitions
    foreach key [dict keys $pin_interfaces_dict_formatted] {
      puts $interface_file "  $key [dict get $pin_interfaces_dict_formatted $key]"
    }
    # We write the interface for pins connected to the static system 
    foreach key [dict keys $pin_connected_to_static_interface_dict_formatted] {
      puts $interface_file "  $key [dict get $pin_connected_to_static_interface_dict_formatted $key]"
    }
    puts $interface_file end_local_nets
    puts $interface_file global_nets
    foreach key [dict keys $pin_globals_dict_formatted] {
      puts $interface_file "  $key [dict get $pin_globals_dict_formatted $key]"
    }
    puts $interface_file end_global_nets
    close $interface_file
    
    # We read the interface file
    variable ::reconfiguration_tool::interface::groups_of_nets_info_list
    dict set groups_of_nets_info_list $partition_group_name [read_interface_file $interface_file_name $reconfigurable_partition_group]
  }

  ########################################################################################
  # When two reconfigurable partitions are connected to each other the 2 interface pins 
  # share the same partition pin. Vidado can't route if this happens. This function deletes 
  # all the duplicated partition pins.
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc delete_duplicated_partition_pins {} {
    set input_partition_pins [get_pins -hierarchical -filter {HD.PARTPIN_LOCS != {} && DIRECTION == IN}]
    set input_partition_pin_nodes [get_property -quiet HD.PARTPIN_LOCS $input_partition_pins]
    set output_partition_pins [get_pins -hierarchical -filter {HD.PARTPIN_LOCS != {} && DIRECTION == OUT}]
    set output_partition_pin_nodes [get_property -quiet HD.PARTPIN_LOCS $output_partition_pins]
    set duplicate_partition_pins_nodes [::struct::set intersect $output_partition_pin_nodes $input_partition_pin_nodes]
    foreach partition_pin_node $duplicate_partition_pins_nodes {
      set pin [get_pins -hierarchical -filter "HD.PARTPIN_LOCS == $partition_pin_node && DIRECTION == IN"]
      reset_property HD.PARTPIN_LOCS $pin
    }
  }
  
  ########################################################################################
  # Reads the interface of all the reconfigurable partition groups and saves the info on 
  # the variable groups_of_nets_info_list
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc obtain_interface_info {} {
    variable ::reconfiguration_tool::global_nets_info
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    variable ::reconfiguration_tool::interface::groups_of_nets_info_list
    set global_nets_info {}
    set groups_of_nets_info_list [dict create]
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set interface [dict get $reconfigurable_partition_group interface]
      if {$interface != ""} {
        set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
        dict set groups_of_nets_info_list $partition_group_name [read_interface_file $interface $reconfigurable_partition_group]
      }
    }
  }
  
  ########################################################################################
  # Places the partition pins of a reconfigurable partition group (group of relocatable 
  # partitions). It is necessary to indicate if the current design is the implementation 
  # of the static system or a reconfigurable partition. 
  #
  # Argument Usage:
  # reconfigurable_partition_group: dict which contains the information of the 
  #   reconfigurable partition group. 
  # type: this can be static or reconfigurable and idicates whis design is being 
  # implemented.  
  # Return Value:
  ########################################################################################
  proc place_partition_pins {reconfigurable_partition_group type} {
    variable ::reconfiguration_tool::interface::groups_of_nets_info_list
    
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
    set groups_of_nets_info_list_reconfigurable_partition [dict get $groups_of_nets_info_list $partition_group_name]
    set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
    if {$type == "static"} {
      foreach reconfigurable_partition $reconfigurable_partition_list {
        # We check if there is a RP inside the sttaic system with the same name 
        set partition_name [dict get $reconfigurable_partition partition_name]
        if {[llength [get_cells -hierarchical ${partition_name} -filter "RECONFIGURABLE_PARTITION == 1"]] == 0} {
          continue
        }
        set hierarchical_partition_list [dict get $reconfigurable_partition hierarchical_partition_list]
        if {[llength $hierarchical_partition_list] > 0} {
          break
        }
        set partition_name [dict get $reconfigurable_partition partition_name]
        place_partition_pins_of_cell $groups_of_nets_info_list_reconfigurable_partition $partition_name
      }
    } else {
      # set reconfigurable_partition [lindex $reconfigurable_partition_list 0]
      # set partition_name [dict get $reconfigurable_partition partition_name]
      # place_partition_pins_of_cell $groups_of_nets_info_list_reconfigurable_partition $partition_name
      set partition_group_name [dict get $reconfigurable_partition_group partition_group_name] 
      set hierarchical_reconfigurable_partition_list [::reconfiguration_tool::utils::obtain_hierarchical_partitions $partition_group_name]
      lappend hierarchical_reconfigurable_partition_list [lindex $reconfigurable_partition_list 0]
      foreach reconfigurable_partition $hierarchical_reconfigurable_partition_list {
        set partition_name [dict get $reconfigurable_partition partition_name]
        place_partition_pins_of_cell $groups_of_nets_info_list_reconfigurable_partition $partition_name
      }
    }
  }
  
  ########################################################################################
  # Places the partition pins of a single cell  
  #
  # Argument Usage:
  # group_of_nets_list: list that contains group of pins that contains the same interface 
  # partition_name: name of the partition (and the cell) on which the partition pins will 
  # be placed. 
  #
  # Return Value:
  ########################################################################################
  proc place_partition_pins_of_cell {group_of_nets_list partition_name} {
    set edge_tiles [::reconfiguration_tool::utils::get_edge_INT_tiles pblock_${partition_name}]
    foreach group_of_nets $group_of_nets_list {
      if {[catch {set_partition_pins_to_direction $group_of_nets $edge_tiles ${partition_name}} errmsg]} {
        error "Error placing partitions pins of reconfigurable partition: ${partition_name}. Type: $errmsg"
      }
    }
    set cell [get_cells -hierarchical $partition_name -filter "RECONFIGURABLE_PARTITION == 1"]
    set partition_pins [get_property HD.PARTPIN_LOCS [get_pins -of_objects $cell -filter {HD.PARTPIN_LOCS != {}}]]
    if {[llength $partition_pins] != [llength [lsort -unique $partition_pins]]} {
      error "repeated partition pins"
    }
  }

  ########################################################################################
  # Parses an interface file of a reconfigurable partition type i.e group of 
  # reconfigurable partitions (RPs) where the same PBS can be used to reconfigure them and
  # therefore the RPs need to have the same resources and the same interface with the 
  # static system and other RPs.
  #
  # Argument Usage:
  # interface_file: path of the reconfigurable partition 
  # reconfigurable_partition_group: 
  #
  # Return Value:
  # 
  ########################################################################################
  proc read_interface_file {interface_file reconfigurable_partition_group} {
    variable ::reconfiguration_tool::global_nets_info
    set fileId [open $interface_file r]
    set interface_directions {}
    set local_nets [dict create]
    set neighbour_pblocks [dict create]
    set source_pblock {}
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]

    while {[gets $fileId line] != -1} {
      switch -exact -- [string trim $line] {
        pblocks_definition {
          # This section contains the definition of a set of pblocks that can be used to 
          # define how a pin is connected to the exterior. This is done in other functions 
          # by extracting the common borders of the two pblocks and thus extracting the 
          # cardinal direction and the relative tiles that can be used. 
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_pblocks_definition"} {
            regexp {(\S+)\s+(.+)} [string trim $line] -> name definition
            if {$name == "source_pblock"} {
              if {[::reconfiguration_tool::utils::pblock_has_xilinx_format $definition] == 0} {
                set source_pblock [::reconfiguration_tool::utils::change_pblock_format_from_custom_to_xilinx $definition]
              } else {
                set source_pblock $definition
              }
            } else {
              if {[::reconfiguration_tool::utils::pblock_has_xilinx_format $definition] == 0} {
                dict set neighbour_pblocks $name [::reconfiguration_tool::utils::change_pblock_format_from_custom_to_xilinx $definition]
              } else {
                dict set neighbour_pblocks $name $definition
              }
            }
            if {[gets $fileId line] == -1} {
              error "error parsing interface file: $interface_file -> end_pblocks_definition not found"
            }
            set line [string trim $line]
          }
        }
        
        local_nets {
          # This section contains all the local pins of the RP. The interface can be 
          # defined in three different ways.
          #   1) <pin_name> <source_pblock> <destination_pblock> each is one defined in 
          #      the previous section. The destination pblock can be the static system.
          #      i.e. DataIN pblock1 static
          #   2) <pin_name>_<cardinal_direction> the pins can use all the tiles of the  
          #      cardinal direction. i.e. DataIN_NORTH
          #   3) <pin_name> <cardinal_direction:initial_tile:end_tile> 
          #      i.e. DataIN_NORTH_0:5
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_local_nets"} {
            if {[regexp {(\S+)\s+(.+)} [string trim $line] -> name direction] == 1} {
              if {$direction ni $interface_directions} {
                lappend interface_directions $direction
                set ${direction}_list {}
              } 
              lappend ${direction}_list $name
            }
            if {[gets $fileId line] == -1} {
              error "error parsing interface file: $interface_file -> end_local_nets not found"
            }
            set line [string trim $line]
          }
          foreach direction $interface_directions {
            dict set local_nets $direction [set ${direction}_list]
          }  
        }
        global_nets {
          # This section contains all the global pins that are connected using global 
          # resources. They are defined indicating the number of the resource used 
          # (i.e. clk 0)
          gets $fileId line
          set line [string trim $line]
          while { $line != "end_global_nets"} {
            regexp {(\S+)\s+(.+)} [string trim $line] -> name position
            set global_nets_info_keys [list $partition_group_name all_global_nets]
            foreach key $global_nets_info_keys {
              if {[dict exists $global_nets_info $key $name]} {
                if {($position != [dict get $global_nets_info $key $name position])} {
                  error "error parsing interface file: $interface_file -> global net $key is repeated"              
                }
              } else {
                dict set global_nets_info $key $name position $position      
              }
            }
            if {[gets $fileId line] == -1} {
              error "error parsing interface file: $interface_file -> end_global_nets not found"
            }
            set line [string trim $line]
          }
        }
        default {}
      }
    }
    if {[catch {set group_of_nets_list [parse_local_nets_data $source_pblock $neighbour_pblocks $local_nets $partition_group_name]} errMsg]} {
      error $errMsg
    }
    return $group_of_nets_list
  }
  
  ########################################################################################
  # This function parses the interface description of a set a nets that share the same 
  # interface. The interface description can be the name of a destination pblock or a 
  # string with the cardinal information and the relative number of the initial and end 
  # tiles.   
  #
  # Argument Usage:
  # source_pblock: source pblock definition as written in the interface file 
  # neighbour_pblocks: the different pblocks defined in the interface file where the 
  #   source pblock can be connected. 
  # local_nets: group of nets defined in the interface file in the local_nets section 
  # partition_group_name: name of the group of reconfigurable partition that can be 
  #   reallocated among them. 
  #
  # Return Value:
  ########################################################################################
  proc parse_local_nets_data {source_pblock neighbour_pblocks local_nets partition_group_name} {
    set group_of_nets_list {}
    foreach direction [dict keys $local_nets] {
      set nets [dict get $local_nets $direction]
      # We check if the direction corresponds to a pblock or is a cardinal direction and 
      # the initial and end tile. 
      if {[lsearch [dict keys $neighbour_pblocks] $direction] != -1} {
        if {[catch {set directions [obtain_direction_info_from_pblocks_connection $source_pblock [dict get $neighbour_pblocks $direction]]} errMsg]} {
          error "Error with $partition_group_name interface. Type: ${errMsg}"
        }
        dict set group_of_nets_info directions $directions
        dict set group_of_nets_info nets $nets
        lappend group_of_nets_list $group_of_nets_info
        
        # if {[catch {lappend group_of_nets_list [obtain_direction_info_from_pblocks_connection $source_pblock [dict get $neighbour_pblocks $direction] $nets]} errMsg]} {
        #   error "Error with $partition_group_name interface. Type: ${errMsg}"
        # }
      } else {
        if {[catch {lappend group_of_nets_list [obtain_direction_info_from_cardinal_direction_connection $direction $nets]} errMsg]} {
          error "Error with $partition_group_name interface. Type: ${errMsg}"
        }
      }
    }
    return $group_of_nets_list
  }
  
  ########################################################################################
  # This function obtains the interface of the source pblock with regard to the 
  # destination pblock. The information is saved in the pblocks_connetion_info variable. 
  # It contains the cardinal direction and the position of the initial and end tile, 
  # i.e. NORTH 0 4
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  # Because TCL does not admit static variables we create the variable pblocks_connetion_info
  # to store the information of the border calculation (and thus not repeating the same 
  # operations again and again)  
  variable pblocks_connetion_info [dict create]
  proc obtain_direction_info_from_pblocks_connection {source_pblock destination_pblock} {
    variable ::reconfiguration_tool::interface::pblocks_connetion_info
    if {[dict exist $pblocks_connetion_info "${source_pblock}-${destination_pblock}"] == 1} {
      set directions [dict get $pblocks_connetion_info ${source_pblock}-${destination_pblock}]
    } else {
      ::reconfiguration_tool::utils::create_and_place_pblock source_pblock $source_pblock
      ::reconfiguration_tool::utils::create_and_place_pblock destination_pblock $destination_pblock
      set edge_tile_source_pblock [::reconfiguration_tool::utils::get_edge_INT_tiles source_pblock]
      set incremented_edge_tile_destination_pblock [::reconfiguration_tool::utils::get_edge_INT_tiles destination_pblock 1]
      set directions {}
      foreach direction [dict keys $edge_tile_source_pblock] {
        set source_tiles [dict get $edge_tile_source_pblock $direction]
        switch -exact -- [string tolower $direction] {
          north {
            set destination_tiles [dict get $incremented_edge_tile_destination_pblock south]
          }
          south {
            set destination_tiles [dict get $incremented_edge_tile_destination_pblock north]
          }
          east {
            set destination_tiles [dict get $incremented_edge_tile_destination_pblock west]
          }
          west {
            set destination_tiles [dict get $incremented_edge_tile_destination_pblock east]
          }
          default {}
        }
        set common_tiles [::struct::set intersect $source_tiles $destination_tiles]
        if {$common_tiles != {}} {
          set list_of_index {}
          foreach tile $common_tiles {
            set list_of_index [concat $list_of_index [lsearch $source_tiles $tile]]
          }
          set list_of_index [lsort -dictionary $list_of_index]
          set first_tile [lindex $list_of_index 0]
          set last_tile [lindex $list_of_index [expr [llength $list_of_index] -1]]
          dict set direction_info cardinal_direction $direction
          dict set direction_info first_tile $first_tile
          dict set direction_info last_tile $last_tile
          lappend directions $direction_info
        }
      }
      if {$directions == {}} {
        error "destination pblock ${destination_pblock} do not has common tiles with source pblock ${source_pblock}"
      }
      delete_pblocks source_pblock
      delete_pblocks destination_pblock
      
      dict set pblocks_connetion_info "${source_pblock}-${destination_pblock}" $directions
    }

    return $directions
  }
  
  ########################################################################################
  # This function parses an interface description (i.e. NORTH or NORTH_0:5) and saves the 
  # information in a variable that contains the information of the cardinal direction, 
  # the first and last that can be used.
  #
  # Argument Usage:
  # direction: interface description (i.e. NORTH or NORTH_0:5)
  # nets: group of nets which have the same interface description.
  #
  # Return Value:
  ########################################################################################
  proc obtain_direction_info_from_cardinal_direction_connection {direction nets} {
    set direction_info {}
    set directions {}
    foreach single_direction $direction {
      if {[string first _ $single_direction] == -1} {
        #The direction is just a cardinal direction, so it include all the direction
        set cardinal_direction $single_direction
        set first_tile 0
        set last_tile end
      } else {
        #The direction in the interface file includes the relative initial and final tile
        regexp {([a-zA-Z]+)_([0-9]+):([0-9]+)} $single_direction -> cardinal_direction first_tile last_tile
      }
      set valid_directions {south north east west}
      if {[lsearch $valid_directions [string tolower $cardinal_direction]] == -1} {
        error "${direction} is not a valid cardinal direction"
      }
      
      dict set direction_info cardinal_direction $cardinal_direction
      dict set direction_info first_tile $first_tile
      dict set direction_info last_tile $last_tile
      lappend directions $direction_info
    }
    dict set group_of_nets_info directions $directions
    dict set group_of_nets_info nets $nets
    return $group_of_nets_info
  }

  ########################################################################################
  # Assigns the partition pins of a group of nets belonging to a cell that share the same 
  # interface. 
  #
  # Argument Usage:
  # group_of_nets_info: dict with the following fields: nets (which contains the names of  
  #   the pins of the cell that share the same interface) and directions (which contains  
  #   the information of the nets interface)
  # edge_tiles: dict which contains all the edge tiles of each cardinal direction. 
  # cell_name: name of the cell where the pins belong. 
  #
  # Return Value:
  # none or error
  ########################################################################################
  proc set_partition_pins_to_direction {group_of_nets_info edge_tiles cell_name} {
    # The nodes are with the wildcard * because in the INT tiles in the edge of a clock 
    # region have different names. The right thing to do would be to do it with regular 
    # expressions to only accept the possible options. The problem is that Xilinx doesn't  
    # accept all regular expression metacharacters (? or | for example) 
    set output_north_nodes {*NR1*3* *NR1*2* *NR1*1* *NR1*0* *NL1*2* *NL1*1*}
    set output_south_nodes {*SR1*2* *SR1*1* *SL1*3* *SL1*2* *SL1*1* *SL1*0*}
    set output_west_nodes {WL1BEG0 WL1BEG1 WR1BEG1 WL1BEG2 WR1BEG2 WR1BEG3}
    set output_east_nodes {EL1BEG1 ER1BEG1 EL1BEG2 ER1BEG2}
    set input_north_nodes $output_south_nodes
    set input_south_nodes $output_north_nodes
    set input_west_nodes $output_east_nodes
    set input_east_nodes $output_west_nodes
    
    set valid_directions {north south west east}

    set directions_info_list [dict get $group_of_nets_info directions] 
    set input_pins {}
    set output_pins {}
    set nets [dict get $group_of_nets_info nets]
    foreach net $nets {
      set pins [lsort -dictionary [get_pins -of_objects [get_cells -hierarchical $cell_name -filter "RECONFIGURABLE_PARTITION == 1"] -filter "REF_PIN_NAME == $net || BUS_NAME == $net"]]
      
      if {$pins != {}} {
        # If only the static system interfaces are described (and not the interfaces 
        # between reconfigurable systems) then there may be nets in the interface that do 
        # not correspond to any pin (because there are part of reconfigurable to 
        # reconfigurable interfaces)
        if {[get_property DIRECTION [lindex $pins 0]] == "IN"} {
          set input_pins [concat $input_pins $pins]
        } else {
          set output_pins [concat $output_pins $pins]
        }
      }
    }
    # We implement two possible ways to place the partition pins. Spreading them the most 
    # or placing them as close as possible (filling each tile until is complete). To 
    # change the alternative change the variable spread_partition_pin
    set spread_partition_pin 1
    
    if {$spread_partition_pin == 1} {
      # Spreading the partition pins as much as possible. 
      set max_input_nodes 0 
      set max_output_nodes 0
      set max_interface_tiles 0
      set minimum_input_nodes_per_tile ""
      set maximum_input_nodes_per_tile ""
      set minimum_output_nodes_per_tile ""
      set maximum_output_nodes_per_tile ""
      foreach direction_info $directions_info_list {
        set direction [string tolower [dict get $direction_info cardinal_direction]]
        set first_tile [dict get $direction_info first_tile]
        set last_tile [dict get $direction_info last_tile]
        if {[lsearch $valid_directions $direction] == -1} {
          error "partition pins with wrong directions. Wrong direction: $direction_info"
        }
        set available_input_nodes [set input_${direction}_nodes]
        set available_output_nodes [set output_${direction}_nodes]
        set interface_tiles [lrange [dict get $edge_tiles $direction] $first_tile $last_tile]
        set max_input_nodes [expr $max_input_nodes + [llength $available_input_nodes] * [llength $interface_tiles]]
        set max_output_nodes [expr $max_output_nodes + [llength $available_output_nodes] * [llength $interface_tiles]]
        set max_interface_tiles [expr [llength $interface_tiles] + $max_interface_tiles]
        
        # Of all the direction available we calculate the maximum nodes per tile and the 
        # minimum nodes per tile. 
        
        if {([llength $available_input_nodes] > $maximum_input_nodes_per_tile) || $maximum_input_nodes_per_tile == ""} {
          set maximum_input_nodes_per_tile [llength $available_input_nodes]
        }
        if {([llength $available_input_nodes] < $minimum_input_nodes_per_tile) || $minimum_input_nodes_per_tile == ""} {
          set minimum_input_nodes_per_tile [llength $available_input_nodes]
        }
        
        if {([llength $available_output_nodes] > $maximum_output_nodes_per_tile) || $maximum_output_nodes_per_tile == ""} {
          set maximum_output_nodes_per_tile [llength $available_input_nodes]
        }
        if {([llength $available_output_nodes] < $minimum_output_nodes_per_tile) || $minimum_output_nodes_per_tile == ""} {
          set minimum_output_nodes_per_tile [llength $available_input_nodes]
        }
      }

      if {[llength $input_pins] > $max_input_nodes} {
        error "Not enough nodes to allocate input interface pins"
      }
      if {[llength $output_pins] > $max_output_nodes} {
        error "Not enough nodes to allocate output interface pins"
      }
      # We calculate the minimum number of partition pins that we need to place in every 
      # tile. 
  
      if {[llength $input_pins] > 0} {
        set number_of_in_partition_pins_per_tile [expr [llength $input_pins] / $max_interface_tiles]
        if {[expr [llength $input_pins] % $max_interface_tiles] > 0} {
          incr number_of_in_partition_pins_per_tile
        }
        # In the case that the number of nodes per tile is bigger than the available in 
        # some tiles, and smaller than the available in other tiles, we change the 
        # number_of_in_partition_pins_per_tile to the maximum value to ensure that all 
        # nodes are correctly allocated even if they are not as spreaded as maximum as
        # possible. 
        if {$number_of_in_partition_pins_per_tile > $minimum_output_nodes_per_tile} {
          set number_of_in_partition_pins_per_tile $maximum_input_nodes_per_tile
        }
        
      } 
      if {[llength $output_pins] > 0} {
        set number_of_out_partition_pins_per_tile [expr [llength $output_pins] / $max_interface_tiles]
        if {[expr [llength $output_pins] % $max_interface_tiles] > 0} {
          incr number_of_out_partition_pins_per_tile
        }
        if {$number_of_out_partition_pins_per_tile > $minimum_output_nodes_per_tile} {
          set number_of_out_partition_pins_per_tile $maximum_output_nodes_per_tile
        }
      }      
      
      set i 0
      set j 0
      # We place the partition pins 
      foreach direction_info $directions_info_list {
        set direction [string tolower [dict get $direction_info cardinal_direction]]
        set first_tile [dict get $direction_info first_tile]
        set last_tile [dict get $direction_info last_tile]
        set available_input_nodes [set input_${direction}_nodes]
        set available_output_nodes [set output_${direction}_nodes]
        set interface_tiles [lrange [dict get $edge_tiles $direction] $first_tile $last_tile]
      
        set current_wire 0
        set current_tile 0
        
        while {$i < [llength $input_pins]} {
          set_property -name HD.PARTPIN_LOCS -value [get_nodes -uphill -of_objects [lindex $interface_tiles $current_tile] -filter "NAME =~ */[lindex $available_input_nodes $current_wire]"] -object [lindex $input_pins $i]
          incr i
          incr current_wire
          if {$current_wire >= $number_of_in_partition_pins_per_tile || $current_wire >= [llength $available_input_nodes]} {
            set current_wire 0
            incr current_tile
            if {$current_tile >= [llength $interface_tiles]} {
              break
            }
          }
        }
        set current_wire 0
        set current_tile 0
        while {$j < [llength $output_pins]} {
          set_property -name HD.PARTPIN_LOCS -value [get_nodes -downhill -of_objects [lindex $interface_tiles $current_tile] -filter "NAME =~ */[lindex $available_output_nodes $current_wire]"] -object [lindex $output_pins $j]
          incr j
          incr current_wire
          if {$current_wire >= $number_of_out_partition_pins_per_tile || $current_wire >= [llength $available_output_nodes]} {
            set current_wire 0
            incr current_tile
            if {$current_tile >= [llength $interface_tiles]} {
              break
            }
          }
        }
      } 
    } else {
      #Placing the partition pins as close as possible.
      set i 0
      set j 0
      foreach direction_info $directions_info_list {
        set direction [string tolower [dict get $direction_info cardinal_direction]]
        set first_tile [dict get $direction_info first_tile]
        set last_tile [dict get $direction_info last_tile]
        if {[lsearch $valid_directions $direction] == -1} {
          error "partition pins with wrong directions. Wrong direction: $direction_info"
        }
        set available_input_nodes [set input_${direction}_nodes]
        set available_output_nodes [set output_${direction}_nodes]
        set interface_tiles [lrange [dict get $edge_tiles $direction] $first_tile $last_tile]   
      
        set current_wire 0
        set current_tile 0
        while {$i < [llength $input_pins]} {  
          set_property -name HD.PARTPIN_LOCS -value [get_nodes -uphill -of_objects [lindex $interface_tiles $current_tile] -filter "NAME =~ */[lindex $available_input_nodes $current_wire]"] -object [lindex $input_pins $i]
          incr current_wire
          incr i 
          if {$current_wire >= [llength $available_input_nodes]} {
            set current_wire 0
            incr current_tile
            if {$current_tile >= [llength $interface_tiles]} {
              break
            }
          }
        }
        set current_wire 0
        set current_tile 0
        while {$j < [llength $output_pins]} {
          set_property -name HD.PARTPIN_LOCS -value [get_nodes -downhill -of_objects [lindex $interface_tiles $current_tile] -filter "NAME =~ */[lindex $available_output_nodes $current_wire]"] -object [lindex $output_pins $j]
          incr current_wire
          incr j
          if {$current_wire >= [llength $available_output_nodes]} {
            set current_wire 0
            incr current_tile
            if {$current_tile >= [llength $interface_tiles]} {
              break
            }
          }
        }  
      }  
      if {$i < [llength $input_pins] || $j < [llength $output_pins]} {
        error "Not enough nodes to allocate interface pins."
      }
    }
    
  }
}