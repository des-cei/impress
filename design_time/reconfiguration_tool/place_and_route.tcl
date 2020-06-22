##########################################################################################
# This library provides functions dealing with the placement and route of the  
# reconfigurable design. 
# 
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################

package require struct::set

namespace eval ::reconfiguration_tool::place_and_route {

  # Procs that can be used in other namespaces
  namespace export place_the_design
  namespace export route_design_with_fence
  namespace export route_global_nets
  
  ########################################################################################
  # This function returns the fence nodes of a reconfigurable or static design. It 
  # computes the interface nodes of all the pblocks of the design. 
  #
  # Argument Usage:
  #
  # Return Value:
  # It returns all the nodes that form the fence of the design. 
  ########################################################################################
  proc get_external_fence_nodes {} {
    # variable ::reconfiguration_tool::reconfigurable_partition_group_list
    set fence_nodes {}
    set pblocks [get_pblocks -filter "NAME != pblock_no_placement"]
    # foreach pblock $pblocks {
    #   set fence_nodes [::struct::set union $fence_nodes [get_interface_nodes_pblock $pblock]]
    # }
    
    set fence_nodes [get_fence_nodes]
    set partition_pins [get_pins -hierarchical -filter {HD.PARTPIN_LOCS != {}}]
    set partition_pin_nodes {}
    foreach pin $partition_pins {
      set node [get_nodes [get_property HD.PARTPIN_LOCS $pin]]
      set partition_pin_nodes [concat $partition_pin_nodes $node]
    }
    set fence_nodes [::struct::set difference $fence_nodes $partition_pin_nodes]
    return $fence_nodes
  }
  
  ########################################################################################
  # This function calculates all the nodes that cross the reconfigurable regions
  # Return Value:
  #   it returns a list with the nodes that cross the reconfigurable regions
  ########################################################################################
  proc get_fence_nodes {} {
    set reconfigurable_resource_tiles [get_tiles -of_objects [get_sites -of_objects [get_pblocks -filter "NAME != pblock_no_placement"]]]
    set x_coordinate [lsort -unique -increasing -integer [get_property COLUMN $reconfigurable_resource_tiles]]
    set y_coordinate [lsort -unique -increasing -integer [get_property ROW $reconfigurable_resource_tiles]]
    set reconfigurable_INT_and_resource_tiles [get_tiles -filter "COLUMN <= [lindex $x_coordinate end] && COLUMN >= [lindex $x_coordinate 0] && ROW <= [lindex $y_coordinate end] && ROW >= [lindex $y_coordinate 0]"]
    set reconfigurable_nodes [lsort -unique [get_nodes -downhill -uphill -of_objects $reconfigurable_INT_and_resource_tiles -filter {COST_CODE_NAME != GLOBAL}]]
    # BRAM cascade nodes need to be treated in a special way. The reason for this is 
    # that these nodes are very long and can have multiple destinations (some inside the 
    # pblock and some outside). Because these nodes are mandatory to be used when Vivado 
    # cascade BRAMs it is necessary to make them available for reconfigurable designs.  
    # Therefore we allow nodes in the pblock that can go from the inside to another 
    # place of the pblock but also outside the pblock. However we dont allow nodes that 
    # nodes that go from the outside to the inside no matter what. Doing that we ensure 
    # that no route can go outside the pblock and return back inside of it. 
    set exception_BRAM_nodes [lsort -unique [get_nodes -downhill -of_objects $reconfigurable_INT_and_resource_tiles -filter {NAME =~ *BRAM_CASCOUT*}]]
    
    # set all_tiles [get_tiles *]
    #we only select part of the tiles to increase the speed in large FPGAs 
    set extended_tiles_length 80
    set max_x [expr [lindex $x_coordinate end] + $extended_tiles_length]
    set max_y [expr [lindex $y_coordinate end] + $extended_tiles_length]
    set min_x [expr [lindex $x_coordinate 0] - $extended_tiles_length]
    set min_y [expr [lindex $y_coordinate 0] - $extended_tiles_length]
    set all_tiles [get_tiles -filter "INT_TILE_X < $max_x && INT_TILE_X > $min_x && INT_TILE_Y < $max_y && INT_TILE_Y > $min_y"]
    
    set tiles_outside_pblock [::struct::set difference $all_tiles $reconfigurable_INT_and_resource_tiles] 
    set rest_of_all_nodes [lsort -unique [get_nodes -downhill -uphill -of_objects $tiles_outside_pblock -filter {COST_CODE_NAME != GLOBAL}]]

    set interface_nodes [::struct::set  difference [::struct::set intersect $reconfigurable_nodes $rest_of_all_nodes] $exception_BRAM_nodes]
    
    return $interface_nodes
  }


  ########################################################################################
  # This function computes the common nodes between the pblock and the rest of the FPGA 
  # resources. 
  # Because TCL does not have static variables we use a variable global to the namespace
  # to save the interface nodes of a given pblock and thus not having to repeat the
  # computation muliple times (this function can be very time consuming in big FPGA).
  #
  # Argument Usage:
  # pblock_name: name of the pblock that is going to be analyzed. 
  #
  # Return Value:
  # it return a list with the common nodes
  ########################################################################################
  variable interface_nodes_pblocks [dict create]
  proc get_interface_nodes_pblock {pblock_name} {
    variable interface_nodes_pblocks
    if {[dict exist $interface_nodes_pblocks $pblock_name] == 1} {
      set interface_nodes [dict get $interface_nodes_pblocks $pblock_name]
    } else {
      set resource_tiles_pblock [get_tiles -of_objects [get_sites -of_objects [get_pblocks $pblock_name]]]
      set INT_and_resource_tiles_pblock [get_tiles -of_objects $resource_tiles_pblock]
      set nodes_pblock [lsort -unique [get_nodes -downhill -uphill -of_objects $INT_and_resource_tiles_pblock -filter {COST_CODE_NAME != GLOBAL}]]
      # BRAM cascade nodes need to be treated in a special way. The reason for this is 
      # that these nodes are very long and can have multiple destinations (some inside the 
      # pblock and some outside). Because these nodes are mandatory to be used when Vivado 
      # cascade BRAMs it is necessary to make them available for reconfigurable designs.  
      # Therefore we allow nodes in the pblock that can go from the inside to another 
      # place of the pblock but also outside the pblock. However we dont allow nodes that 
      # nodes that go from the outside to the inside no matter what. Doing that we ensure 
      # that no route can go outside the pblock and return back inside of it. 
      set exception_BRAM_nodes [lsort -unique [get_nodes -downhill -of_objects $INT_and_resource_tiles_pblock -filter {NAME =~ *BRAM_CASCOUT*}]]
      
      set all_tiles [get_tiles *]
      set tiles_outside_pblock [::struct::set difference $all_tiles $INT_and_resource_tiles_pblock] 
      set rest_of_all_nodes [lsort -unique [get_nodes -downhill -uphill -of_objects $tiles_outside_pblock -filter {COST_CODE_NAME != GLOBAL}]]

      set interface_nodes [::struct::set  difference [::struct::set intersect $nodes_pblock $rest_of_all_nodes] $exception_BRAM_nodes]
      dict set interface_nodes_pblocks $pblock_name $interface_nodes 
    }
    return $interface_nodes
  }
  
  ########################################################################################
  # We include different methods to calculate the interface nodes of a given pblock that 
  # have been used in the past and may be useful to take into account for future changes 
  # in the current implementation.
  
  # First implementation
  # set nodes [lsort -unique [get_nodes -downhill -uphill -of_objects $INT_tiles_pblock -filter {COST_CODE_NAME != GLOBAL && COST_CODE_NAME != PINFEED && COST_CODE_NAME != OUTBOUND}]]
  # foreach node $nodes {
  #   set INT_tiles_of_node [get_tiles -of_objects [get_pips -of_objects $node] -filter {TILE_TYPE =~ INT_?}]
  #   if {![::struct::set subsetof $INT_tiles_of_node $INT_tiles_pblock]} {
  #     if {[lsearch $fence_nodes $node] == -1} {
  #       lappend fence_nodes $node
  #     }
  #   }
  # }
  
  # Second implementation 
  # set resource_tiles_pblock [get_tiles -of_objects [get_sites -of_objects [get_pblocks $pblock_name]]]
  # set x_coordinates [lsort -unique [get_property GRID_POINT_X $resource_tiles_pblock]]
  # set y_coordinates [lsort -unique [get_property GRID_POINT_Y $resource_tiles_pblock]]
  # #We include glue tiles which their only function is to pass nodes through them
  # set all_tiles_pblock [get_tiles -filter "GRID_POINT_X <= [lindex $x_coordinates end] && GRID_POINT_X >= [lindex $x_coordinates 0] && GRID_POINT_Y <= [lindex $y_coordinates end] && GRID_POINT_Y >= [lindex $y_coordinates 0]"]
  # set nodes_pblock [lsort -unique [get_nodes -downhill -uphill -of_objects $all_tiles_pblock -filter {COST_CODE_NAME != GLOBAL}]]
  # set up_hill_nodes [lsort -unique [get_nodes -uphill -of_objects $INT_tiles_pblock -filter {COST_CODE_NAME != GLOBAL && COST_CODE_NAME != PINFEED && COST_CODE_NAME != OUTBOUND}]]
  # foreach node $up_hill_nodes {
  #   set INT_tiles_of_node [get_tiles -of_objects [get_pips -of_objects $node] -filter {TILE_TYPE =~ INT_?}]
  #   set tiles_out_of_pblock [::struct::set difference $INT_tiles_of_node $INT_tiles_pblock]
  #   set tiles_in_pblock [::struct::set intersect $INT_tiles_of_node $INT_tiles_pblock]
  #   if {$tiles_out_of_pblock != {}} {
  #     #We dont add the node to the fence if the node doesn't have drivers outside the pblock and there is more than one INT tile inside the pblock
  #     if {[get_nodes -uphill -of_objects $tiles_out_of_pblock $node] == {} && [llength $tiles_in_pblock] > 1} {
  #         continue
  #     } else {
  #       if {[lsearch $fence_nodes $node] == -1} {
  #         lappend fence_nodes $node
  #       }
  #     }
  #   }
  # }
  # set down_hill_nodes [lsort -unique [get_nodes -downhill -of_objects $INT_tiles_pblock -filter {COST_CODE_NAME != GLOBAL && COST_CODE_NAME != PINFEED && COST_CODE_NAME != OUTBOUND}]]
  # set rest_of_nodes [::struct::set difference $down_hill_nodes $up_hill_nodes]
  # foreach node $rest_of_nodes {
  #   set INT_tiles_of_node [get_tiles -of_objects [get_pips -of_objects $node] -filter {TILE_TYPE =~ INT_?}]
  #   if {![::struct::set subsetof $INT_tiles_of_node $INT_tiles_pblock]} {
  #     if {[lsearch $fence_nodes $node] == -1} {
  #       lappend fence_nodes $node
  #     }
  #   }
  # }

  ########################################################################################

  ########################################################################################
  # Create a "fake" net for blocking a set of nodes, with all the input and
  # output pins needed for it to be possible, and apply the right FIXED_ROUTE
  # constraints that cause the nodes to become unusable.
  #
  # Argument Usage:
  # name: name of the fake net that will be created. 
  # nodes: set of nodes that will be used to create the fake net. 
  #
  # Return Value:
  # Returns a list containing: the in/out pins, the in/out buffers, the nets
  # between pins and buffers, and the actual net.  The actual net is at position
  # 0, and the rest of the stuff after it in deletion order
  # (nets; buffers; ports).
  ########################################################################################
  proc create_blocking_net {name nodes} {
      # Create the net and related elements
      set net [create_net ${name}]                     ;# blocking net
      set in  [create_net ${name}_in]                  ;#    input net
      set on  [create_net ${name}_on]                  ;#   output net
      set ib  [create_cell -reference IBUF ${name}_ib] ;#    input buffer
      set ob  [create_cell -reference OBUF ${name}_ob] ;#   output buffer
      set ip  [create_port -direction IN ${name}_ip]   ;#    input port
      set op  [create_port -direction OUT ${name}_op]  ;#   output port
      set fence [list $net $in $on $ib $ob $ip $op]

      # If there is an error, cleanup (delete net and related elements)
      if {[catch {

          # Connect the elements and place the ports
          connect_net -net $in -objects [list $ip [get_pins $ib/I]]
          connect_net -net $net \
                  -objects [list [get_pins $ib/O] [get_pins $ob/I]]
          connect_net -net $on -objects [list [get_pins $ob/O] $op]
          # We change the IOSTANDARD to have more I/O pins to place the ports
          set_property IOSTANDARD LVCMOS33 [get_ports $ip]
          set_property IOSTANDARD LVCMOS33 [get_ports $op]
          place_ports $ip $op

          # Add the FIXED_ROUTE constraint
          set froute [list]
          foreach node $nodes {
              lappend froute GAP $node
          }
          set_property FIXED_ROUTE [list $froute] $net

      } errMsg errOpt]} {
          # cleanup
          delete_blocking_net $fence
          return -options $errOpt $errMsg
      }

      # Return all the stuff
      return $fence
  }

  ########################################################################################
  # Delete a net created with [create_blocking_net].
  #
  # Argument Usage:
  # fence: list returned by the command [create_blocking_net].
  #
  # Return Value:
  ########################################################################################
  proc delete_blocking_net {fence} {

      set_property FIXED_ROUTE "" [lindex $fence 0]
      remove_net  [lindex $fence 1] ;#    input net
      remove_net  [lindex $fence 2] ;#   output net
      remove_cell [lindex $fence 3] ;#    input buffer
      remove_cell [lindex $fence 4] ;#   output buffer
      remove_port [lindex $fence 5] ;#    input port
      remove_port [lindex $fence 6] ;#   output port
      remove_net  [lindex $fence 0] ;# blocking net
      puts "Remove fence: [lindex $fence 0]"

  }

  ########################################################################################
  # Places the components of the design design. 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc place_the_design {} {
    # It is necessary to lower the DRC severity of the partitition pins placement (in our 
    # design flow the input partition pins are placed outside the pblock and therefore 
    # vivado considers that there is a problem )
    set_property SEVERITY {Warning} [get_drc_checks HDPR-17]
    # The directive ExtraTimingOpt seems to improve hold violations but has worse slack 
    # (WNS).
    # if {[catch [place_design -directive ExtraTimingOpt] errMsg]} {
    #   error $errMsg
    # }
    if {[catch [place_design] errMsg]} {
      error $errMsg
    }
    set_property SEVERITY {Error} [get_drc_checks HDPR-17]
  }

  ########################################################################################
  # Routes the design taking into account the isolation needed for having relocation 
  # between relocatable reconfigurable partitions. 
  #
  # Argument Usage:
  # type: design that is being implemented i.e. static or reconfigurable. 
  #
  # Return Value:
  ########################################################################################
  proc route_design_with_fence {type} {
    
    # It is necessary to lower the DRC severity of the partitition pins placement (in our 
    # design flow the input partition pins are placed outside the pblock and therefore 
    # vivado considers that there is a problem )
    set_property SEVERITY {Warning} [get_drc_checks HDPR-17]
    # Some of the input partition pins may belong to tiles thar are not interconnection 
    # tiles (tiles that cross 2 clock regions). Therefore we need to lower the DRC 
    # severity. 
    set_property SEVERITY {Warning} [get_drc_checks HDPR-43] 
    

    set fence_nodes [get_external_fence_nodes]
    set external_fence [create_blocking_net external_fence $fence_nodes]
    

    ######################################################################################
    # We add this code just in case is necessary in the future to indicate the route to
    # try to constraint more the interface nets. In this case we tell the router to try to 
    # constraint to half the time the most restrictive clock in the design but this can be
    # changed in the future.
    
    # set min_clock [lindex [lsort -unique [get_property PERIOD [get_clocks]]] 0]
    # set max_clock [lindex [lsort -unique [get_property PERIOD [get_clocks]]] end]
    # 
    # set reconfigurable_pins_in [get_pins -of_objects [get_cells -hierarchical dummy_LUT_IN*] -filter {DIRECTION == IN}]
    # foreach pin $reconfigurable_pins_in {
    #   set_max_delay -to $pin -reset_path [expr 0.5*$min_clock]
    # }
    # 
    # set reconfigurable_pins_out [get_pins -of_objects [get_cells -hierarchical dummy_LUT_OUT*] -filter {DIRECTION == OUT}]
    # foreach pin $reconfigurable_pins_out {
    #   set_max_delay -from $pin -reset_path [expr 0.5*$min_clock]
    # }
    ######################################################################################

    # The static and reconfigurable routing have different commands because experimentally
    # it has been observed that this way Vivado can route more designs that otherwise find 
    # unroutable. 
    if {$type == "static"} {
      route_design -auto_delay -nets [get_nets -hierarchical -filter {ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}] -quiet
    } else {
      # If we dont route the physical nets first then sometimes the vivado router can't 
      # get a valid solution
      route_design -physical_nets
      route_design -auto_delay -nets [get_nets -hierarchical -filter {ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}] -quiet
      # Sometimes routing the physical route nets gives an error, if that is the case we 
      # unroute and reroute the design
      if {[llength [get_nets -hierarchical -filter {ROUTE_STATUS != NOLOADS && ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}]]} {
        route_design -unroute
        route_design -auto_delay -nets [get_nets -hierarchical -filter {ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}] -quiet
      }
    }
    
    #We try to route nets with conflicts 
    set conflict_nets [get_nets -hierarchical -filter {ROUTE_STATUS != NOLOADS && ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}]
    if {[llength $conflict_nets] > 0} {
      route_design -unroute -nets $conflict_nets
      route_design -nets $conflict_nets
    }
    
    # If we still have conflicting nets we try another strategy. First we route the global clocks. 
    # Then we route local nets. Finally we reroute the global clocks again
    set conflict_nets [get_nets -hierarchical -filter {ROUTE_STATUS != NOLOADS && ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}]
    if {[llength $conflict_nets] > 0} {
      route_design -unroute
      if {[catch configure_and_route_global_nets errMsg]} {
        error $errMsg
      }
      set_property is_route_fixed 0 [get_nets -hierarchical -filter {NAME !~ *fence*}]
      route_design -auto_delay -nets [get_nets -hierarchical -filter {ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}] -quiet
    }
    # If we route the global clocks before the rest of the design I do not 
    # know why but a lot of hold violations appear.
    if {[catch configure_and_route_global_nets errMsg]} {
      error $errMsg
    }
    
    phys_opt_design -placement_opt -routing_opt -slr_crossing_opt -rewire -insert_negative_edge_ffs -critical_cell_opt -hold_fix -retime -critical_pin_opt -clock_opt -quiet
    
    if {[llength [get_nets -hierarchical -filter {ROUTE_STATUS != NOLOADS && ROUTE_STATUS != ROUTED && ROUTE_STATUS != INTRASITE && NAME !~ *fence*}]]} {
      error "routing errors"
    }
    
    delete_blocking_net $external_fence 
    set_property SEVERITY {Error} [get_drc_checks HDPR-17]
    set_property SEVERITY {Error} [get_drc_checks HDPR-43]
    
    ######################################################################################
    # We put the maximum constraints so we dont see errors in the interface nets if we 
    # have overconstrained them.
    
    # set reconfigurable_pins_in [get_pins -of_objects [get_cells -hierarchical dummy_LUT_IN*] -filter {DIRECTION == IN}]
    # foreach pin $reconfigurable_pins_in {
    #   set_max_delay -to $pin -reset_path max_clock
    # }
    # 
    # set reconfigurable_pins_out [get_pins -of_objects [get_cells -hierarchical dummy_LUT_OUT*] -filter {DIRECTION == OUT}]
    # foreach pin $reconfigurable_pins_out {
    #   set_max_delay -from $pin -reset_path $max_clock
    # }
    ######################################################################################

  }

  ########################################################################################
  # Configures global nets and routes them using the specified resources. 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc configure_and_route_global_nets {} {
    set_global_nets_property
    route_global_nets
  }

  ########################################################################################
  # We add a property for global nets indicating its global resource position. This is 
  # done so it can be used in design reconstruction so it is possible to know all the 
  # global clocks and the resources available for them. 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc set_global_nets_property {} {
    variable ::reconfiguration_tool::global_nets_info
    
    if {$global_nets_info == ""} {
      return 
    }
    
    set global_nets [dict keys [dict get $global_nets_info all_global_nets]]
    
    create_property -type int GLOBAL_NET_POSITION net -quiet
    foreach net_name $global_nets {
      #set nets [get_nets -of_objects [get_pins -hierarchical -filter "REF_PIN_NAME == $net_name"] -filter "TYPE == GLOBAL_CLOCK"]
      set nets [get_nets -of_objects [get_pins -hierarchical -filter "REF_PIN_NAME == $net_name"] -filter "TYPE =~ *CLOCK"]
      if {$nets == {}} {
        #If we are routing a reconfigurable module it is possible that it does not contain all the global nets.
        continue
      } else {
        # route_design -unroute -nets $nets 
        set position [dict get $global_nets_info all_global_nets $net_name position]
        #We add one to not have the zero value because when searching for nets with the property set to 0 gives problems
        set_property GLOBAL_NET_POSITION [expr $position + 1] $nets
      }
    }
  }
  
  ########################################################################################
  # Routes the global nets using the specified resources. 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc route_global_nets {} {  
    set all_global_nets [get_nets -hierarchical -filter "TYPE =~ *CLOCK"]
    route_design -unroute -nets $all_global_nets
    set reconfigurable_global_nets [get_nets -hierarchical -filter "GLOBAL_NET_POSITION > 0 && ROUTE_STATUS != ROUTED"]
    if {[llength $reconfigurable_global_nets] == 0} {
      return
    }
    
    set local_nets_using_global_nets [list]
    
    set global_position [lsort -integer -unique [get_property GLOBAL_NET_POSITION $reconfigurable_global_nets]]
    set all_global_nodes [all_global_nodes]
    set used_nodes [list]
    
    # We have to disable the reconfigurabe option. If we dont vivado is not able to route 
    # the global nets in only one vertical route. 
    set reconfigurable_cells [get_cells -filter {HD.reconfigurable == TRUE}]
    if {$reconfigurable_cells != {}} {
        set partition_pins_dict [dict create]
        set partition_pins [get_pins -filter "HD.PARTPIN_LOCS != {}"]
        foreach pin $partition_pins {
          dict set partition_pins_dict $pin [get_property HD.PARTPIN_LOCS $pin]
        }
        set_property -name HD.reconfigurable -value FALSE -objects $reconfigurable_cells
    }
    set reconfigurable_global_nets [list]
    foreach position $global_position {    
      set nets [get_nets -segments [get_nets -hierarchical -filter "GLOBAL_NET_POSITION == $position && ROUTE_STATUS != ROUTED"]]
      set reconfigurable_global_nets [concat $reconfigurable_global_nets $nets]  
      set allowable_nodes [global_node_position [expr $position -1]]
      # set used_nodes [concat $used_nodes $allowable_nodes]
      set global_fence_nodes [struct::set difference $all_global_nodes [struct::set union $allowable_nodes $used_nodes]]
      set global_fence [create_blocking_net global_fence $global_fence_nodes]
      
      set conflict_nets [get_nets -hierarchical -filter {ROUTE_STATUS == CONFLICTS && NAME !~ *fence*}]
      if {[llength $conflict_nets] > 0} {
        set local_nets_using_global_nets [concat $local_nets_using_global_nets $conflict_nets]
        route_design -unroute -nets $local_nets_using_global_nets
      }
      
      # We have to reset the partition pin of the global nets. If we don't the router 
      # tries to route through the partition pin thay may not coincide withe global 
      # position 
      reset_property HD.PARTPIN_LOCS [get_pins -of_objects $nets]
      route_design -nets $nets -quiet
      foreach net $nets {
        if {[get_property ROUTE_STATUS $net] != "ROUTED"} {
          delete_blocking_net $global_fence
          error "error routing global nets"
        }
      }
      set used_nodes [concat $used_nodes [get_nodes -of_objects $net]]
      delete_blocking_net $global_fence
      set_property -name IS_ROUTE_FIXED -value 1 -object $nets  
    }

    if {$reconfigurable_cells != {}} {
        set_property -name HD.reconfigurable -value TRUE -objects $reconfigurable_cells
        foreach pin [dict keys $partition_pins_dict] {
          set_property HD.PARTPIN_LOCS [dict get $partition_pins_dict $pin] $pin
        }
    }
    # We route, without fences, the global nets that are not reconfigurable and local  
    # nets that were using reserved global resources. The reconfigurable nets are not 
    # routed as they are fixed.
    set non_reconfigurable_global_nets [struct::set difference $all_global_nets $reconfigurable_global_nets]
    set unrouted_nets [concat $local_nets_using_global_nets $non_reconfigurable_global_nets]
    if {[llength $unrouted_nets] != 0} {
      route_design -nets $unrouted_nets
    }    
  
  }
  
  ########################################################################################
  # Gets all the nodes that can be used for a specified global resource position. 
  #
  # Argument Usage:
  # node_position: global resource that can be used by the net 
  #
  # Return Value:
  # set of nodes that can be used to route the global net. 
  ########################################################################################
  proc global_node_position {node_position} {
    set tiles_clock [get_tiles -filter "TYPE =~ *CLK*"]
    if {$node_position <= 5} {
      set vertical_nodes_top [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_TOP$node_position"]
      set vertical_nodes_bottom [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_BOT$node_position"]
    } else {
      set relative_node_position [expr $node_position -6]
      set vertical_nodes_top [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_TOPL$relative_node_position"]
      set vertical_nodes_bottom [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_BOTL$relative_node_position"]
    }
    set horizontal_nodes [get_nodes -of_objects $tiles_clock -filter "NAME =~ *CLK_HROW_CK_BUFHCLK_?${node_position}"]
    set allowable_nodes [concat $vertical_nodes_top $vertical_nodes_bottom $horizontal_nodes]
    return $allowable_nodes
  }

  ########################################################################################
  # return all the global nodes. 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc all_global_nodes {} {
    set tiles_clock [get_tiles -filter "TYPE =~ *CLK*"]
    return [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_*"]
    # return [get_nodes -of_objects $tiles_clock -filter "NAME =~ *HCLK_LEAF_CLK_B_* || NAME =~ *CLK_HROW_CK_BUFHCLK_*"]
  }
}