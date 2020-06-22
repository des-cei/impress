##########################################################################################
# This library provides miscelanea function that are needed in the reconfiguration flow. 
# 
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################


namespace eval ::reconfiguration_tool::utils {
  
  # Procs that can be used in other namespaces
  namespace export create_empty_design
  namespace export create_empty_design
  namespace export place_pblocks_reconfigurable_partition_type
  namespace export place_no_placement_static_pblocks
  namespace export create_and_place_pblock 
  namespace export obtain_xilinx_and_custom_pblocks_format
  namespace export pblock_has_xilinx_format
  namespace export change_pblock_format_from_custom_to_xilinx
  namespace export change_pblock_format_from_xilinx_to_custom
  namespace export obtain_max_DSP_and_RAM_for_reconfigurable_partitions
  namespace export get_edge_INT_tiles
  namespace export log_error
  namespace export log_success
  namespace export obtain_hierarchical_partitions
  namespace export clean_design
  namespace export compare_relocatable_regions
  
  ########################################################################################
  # Creates an empty project and the folder structure for the current design 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc create_empty_design {} {
    variable ::reconfiguration_tool::project_variables 
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    file delete -force -- "${directory}/${project_name}"
    file mkdir ${directory}/${project_name}
    file mkdir ${directory}/${project_name}/SYNTHESIS
    file mkdir ${directory}/${project_name}/IMPLEMENTED
    file mkdir ${directory}/${project_name}/BITSTREAMS
    file mkdir ${directory}/${project_name}/DESIGN_RECONSTRUCTION
    file mkdir ${directory}/${project_name}/TMP

    close_project -quiet
    set_part [dict get $project_variables fpga_chip]
    link_design
    set ip_repositories [dict get $project_variables ip_repositories]
    set_property IP_REPO_PATHS $ip_repositories [current_project]
    # Rebuild user ip_repo's index before adding any source files
    update_ip_catalog -rebuild
    set_param general.maxThreads 8
    set_property "target_language" "VHDL" [current_project]
  }
  
  ########################################################################################
  # Cleans temporal folders and files 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc clean_design {} {
    variable ::reconfiguration_tool::project_variables 
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    file delete -force -- "${directory}/${project_name}/TMP"
  }
  
  ########################################################################################
  # This function is responsible for placing the pblocks of a set of relocatable 
  # reconfigurable paratitions group. It is necessary to indicate if the design that is 
  # being implemented is the static part or the reconfigurable one. In the case of 
  # implementing the reconfigutable part only the first pblock needs to be placed, however
  # it is also necessary to place hierarchical pblocks.
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of partitions of which the pblocks are going to 
  #   be placed. 
  # type: design being implemented (i.e., static or reconfigurable)
  #
  # Return Value:
  ########################################################################################
  proc place_pblocks_reconfigurable_partition_type {reconfigurable_partition_group type} {
    variable ::reconfiguration_tool::static_system_info
    set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
    if {$type == "static"} {
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set partition_name [dict get $reconfigurable_partition partition_name]
        set hierarchical_partition_list [dict get $reconfigurable_partition hierarchical_partition_list]
        if {[llength $hierarchical_partition_list] > 0} {
          break
        }
        set pblock_list [dict get $reconfigurable_partition xilinx_format_pblock_list]
        set pblock_name pblock_${partition_name}
        create_and_place_pblock $pblock_name $pblock_list
        set_property CONTAIN_ROUTING TRUE [get_pblocks $pblock_name]
        set_property EXCLUDE_PLACEMENT TRUE [get_pblocks $pblock_name]
        add_cells_to_pblock [get_pblocks pblock_${partition_name}] [get_cells -hierarchical ${partition_name} -filter "RECONFIGURABLE_PARTITION == 1"]
      }
    } else {    
      set partition_group_name [dict get $reconfigurable_partition_group partition_group_name] 
      set hierarchical_reconfigurable_partition_list [obtain_hierarchical_partitions $partition_group_name]
      
      set partition_name [dict get [lindex $reconfigurable_partition_list 0] partition_name]
      set pblock_list [dict get [lindex $reconfigurable_partition_list 0] xilinx_format_pblock_list]
      set pblock_name pblock_${partition_name}
      set cell [get_cells $partition_name -filter "RECONFIGURABLE_PARTITION == 1"]
      set child_cells [get_cells -hierarchical -filter "PARENT == $cell && IS_BLACKBOX == 0"]
      #If there are no leaf cells and there are hierarchical cells inside we need to insert a dummy 
      #element that will be deleted in the opt_design command. If we don't do this there are problems 
      #in the pblock assignation 
      if {([llength $child_cells] == 0) && ([llength $hierarchical_reconfigurable_partition_list] > 0) } {
        create_cell -reference LUT1 ${cell}/dummy
      }
      set_property HD.RECONFIGURABLE 1 $cell
      create_and_place_pblock $pblock_name $pblock_list
      add_cells_to_pblock [get_pblocks pblock_${partition_name}] $cell
      foreach reconfigurable_partition $hierarchical_reconfigurable_partition_list {
        set partition_name [dict get $reconfigurable_partition partition_name] 
        set pblock_list [dict get $reconfigurable_partition xilinx_format_pblock_list]
        set pblock_name pblock_${partition_name} 
        set cell [get_cells -hierarchical ${partition_name} -filter "RECONFIGURABLE_PARTITION == 1"]
        create_and_place_pblock $pblock_name $pblock_list
        set_property CONTAIN_ROUTING TRUE [get_pblocks $pblock_name]
        set_property EXCLUDE_PLACEMENT TRUE [get_pblocks $pblock_name]
        add_cells_to_pblock [get_pblocks pblock_${partition_name}] $cell
      }
    }
  }
  
  ########################################################################################
  # Adds the pblocks where the static system can not place any logic.
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc place_no_placement_static_pblocks {} {
    variable ::reconfiguration_tool::static_system_info
    set no_placement_pblock_list [dict get $static_system_info xilinx_format_no_placement_pblock_list]
    if {[llength $no_placement_pblock_list] > 0} {
      create_and_place_pblock "pblock_no_placement" $no_placement_pblock_list
      set_property EXCLUDE_PLACEMENT TRUE [get_pblocks "pblock_no_placement"]
    }
  }
  
  ########################################################################################
  # Place an individual pblock (which can consist of a union of pblocks)
  #
  # Argument Usage:
  # pblock_name: name that the pblock will have. 
  # pblock_definition_list: list which contains the set of pblock definitions that form 
  #   the pblock. 
  #
  # Return Value:
  ########################################################################################
  proc create_and_place_pblock {pblock_name pblock_definition_list} {
    create_pblock $pblock_name
    foreach pblock_definition $pblock_definition_list {
      resize_pblock $pblock_name -add $pblock_definition
    }
  }

  ########################################################################################
  # This function takes the pblocks defined by the user in either the xilinx format or 
  # custom format (XoYo:XfYf) and creates variable with the pblock defined in the 2 
  # formats (both of them are needed in the tool i.e. the xilinx format is needed in 
  # vivado and the custom format in the MORA PBS extractor tool).
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc obtain_xilinx_and_custom_pblocks_format {} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    variable ::reconfiguration_tool::static_system_info
    set modified_reconfigurable_partitions_type_list ""
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
      set custom_format_pblock_list ""
      set xilinx_format_pblock_list ""
      set modified_reconfigurable_partition_list [list]
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set pblock_list [dict get $reconfigurable_partition pblock_list]
        if {[pblock_has_xilinx_format $pblock_list] == 1} {
          set custom_format_pblock_list [change_pblock_format_from_xilinx_to_custom $pblock_list]
          set xilinx_format_pblock_list $pblock_list
        } else {
          set custom_format_pblock_list $pblock_list
          set xilinx_format_pblock_list [change_pblock_format_from_custom_to_xilinx $pblock_list]
        } 
        set reconfigurable_partition [dict remove $reconfigurable_partition pblock_list]
        dict set reconfigurable_partition custom_format_pblock_list $custom_format_pblock_list
        dict set reconfigurable_partition xilinx_format_pblock_list $xilinx_format_pblock_list
        lappend modified_reconfigurable_partition_list $reconfigurable_partition
      }
      dict set reconfigurable_partition_group reconfigurable_partition_list  $modified_reconfigurable_partition_list
      lappend modified_reconfigurable_partitions_type_list $reconfigurable_partition_group
    } 
    set reconfigurable_partition_group_list $modified_reconfigurable_partitions_type_list
    #We calculate the xilinx_format pblocks of the static system 
    set xilinx_format_no_placement_pblock_list ""  
    set pblock_list [dict get $static_system_info no_placement_pblock_list]
    if {[pblock_has_xilinx_format $pblock_list] == 1} {
      set xilinx_format_no_placement_pblock_list $pblock_list
    } else {
      set xilinx_format_no_placement_pblock_list [change_pblock_format_from_custom_to_xilinx $pblock_list]
    }
    dict set static_system_info xilinx_format_no_placement_pblock_list $xilinx_format_no_placement_pblock_list
  }

  ########################################################################################
  # Indicates if a pblock definition (which can be a list with several pblocks) has the 
  # the Xilinx format (or on the contrary contains the custom format). 
  #
  # Argument Usage:
  # pblock_list: pblock list that will be analyzed.
  #
  # Return Value:
  # returns 1 if the pblock has the Xilinx format, else returns 0
  ########################################################################################
  proc pblock_has_xilinx_format {pblock_list} {
    if {([string first SLICE $pblock_list] != -1) || ([string first DSP $pblock_list] != -1) || ([string first RAM $pblock_list] != -1) || ([string first CLOCKREGION $pblock_list] != -1)} {
      return 1
    } else {
      return 0
    }
  }

  ########################################################################################
  # Changes a pblock definition from custom format (e.g. XoYo:XfYf) to Xilinx format 
  #
  # Argument Usage:
  # pblock_list: pblock list that will be changed. 
  #
  # Return Value:
  # New pblock list with Xilinx format. 
  ########################################################################################
  proc change_pblock_format_from_custom_to_xilinx {pblock_list} {
    set new_pblock_format_list ""
    foreach pblock $pblock_list {
      if {[regexp {X([0-9]+)Y([0-9]+):X([0-9]+)Y([0-9]+)} $pblock -> X0_X X0_Y Xf_X Xf_Y] == 0} {
        error "pblock $pblock has a incorrect format"
      }
      set initial_INT_tile [get_tiles -filter "NAME =~ *_X${X0_X}Y${X0_Y} && TYPE =~ INT_?"]
      set initial_tile [get_tiles -of_objects $initial_INT_tile -filter {TYPE =~ CLBL* || TYPE =~ BRAM_? || TYPE =~ DSP_? || TYPE =~ LIOI3*}]
      set initial_GRID_POINT_X [get_property GRID_POINT_X $initial_tile]
      set initial_GRID_POINT_Y [get_property GRID_POINT_Y $initial_INT_tile]
      set final_INT_tile [get_tiles -filter "NAME =~ *_X${Xf_X}Y${Xf_Y} && TYPE =~ INT_?"] 
      set final_tile [get_tiles -of_objects $final_INT_tile -filter {TYPE =~ CLB* || TYPE =~ BRAM_? || TYPE =~ DSP_?}]
      set final_GRID_POINT_X [get_property GRID_POINT_X $final_tile]
      set final_GRID_POINT_Y [get_property GRID_POINT_Y $final_INT_tile]

      set pblock_tiles [get_tiles -filter "GRID_POINT_X >= $initial_GRID_POINT_X && GRID_POINT_X <= $final_GRID_POINT_X && GRID_POINT_Y <= $initial_GRID_POINT_Y && GRID_POINT_Y >= $final_GRID_POINT_Y && (TYPE =~ CLB* || TYPE =~ BRAM_? || TYPE =~ DSP_?)"]

      set SLICES [lsort -unique -dictionary [get_sites -filter {NAME =~ *SLICE*} -of_objects $pblock_tiles]]
      set RAMB18 [lsort -unique -dictionary [get_sites -filter {NAME =~ *RAMB18*} -of_objects $pblock_tiles]]
      set RAMB36 [lsort -unique -dictionary [get_sites -filter {NAME =~ *RAMB36*} -of_objects $pblock_tiles]]
      set DSP [lsort -unique -dictionary [get_sites -filter {NAME =~ *DSP*} -of_objects $pblock_tiles]]

      set new_pblock_format ""
      if {$SLICES != {}} {
        set new_pblock_format [concat $new_pblock_format "[lindex $SLICES 0]:[lindex $SLICES [expr [llength $SLICES] -1]] "]
      }
      if {$DSP != {}} {
            set new_pblock_format [concat $new_pblock_format "[lindex $DSP 0]:[lindex $DSP [expr [llength $DSP] -1]] "]
      }
      if {$RAMB18 != {}} {
            set new_pblock_format [concat $new_pblock_format "[lindex $RAMB18 0]:[lindex $RAMB18 [expr [llength $RAMB18] -1]] "]
      }
      if {$RAMB36 != {}} {
            set new_pblock_format [concat $new_pblock_format "[lindex $RAMB36 0]:[lindex $RAMB36 [expr [llength $RAMB36] -1]] "]
      }
      lappend new_pblock_format_list $new_pblock_format
    }  
    return $new_pblock_format_list
  }
  
  ########################################################################################
  # Changes a pblock definition from Xilinx format to custom format (e.g. XoYo:XfYf) 
  #
  # Argument Usage:
  # pblock_list: pblock list that will be changed. 
  #
  # Return Value:
  # New pblock list with custom format. 
  ########################################################################################
  proc change_pblock_format_from_xilinx_to_custom {pblock_list} {
    set new_pblock_format_list ""
    foreach pblock $pblock_list {
      #We create a list with all the elements of the pblock definition
      set pblock_site_list [regexp -all -inline {[^:\s]+} $pblock] 
      set X_coord_list {}
      set Y_coord_list {}
      foreach site $pblock_site_list {
        set tile [get_tiles -of_objects [get_sites $site]]
        regexp {_X([0-9]+)Y([0-9]+)} $tile -> X Y
        lappend X_coord_list $X 
        lappend Y_coord_list $Y
      }
      set X_coord_list [lsort -dictionary $X_coord_list]
      set Y_coord_list [lsort -dictionary $Y_coord_list]
      set min_X [lindex $X_coord_list 0]
      set min_Y [lindex $Y_coord_list 0]
      set max_X [lindex $X_coord_list end]
      set max_Y [lindex $Y_coord_list end]
      set new_pblock_format "X${min_X}Y${min_Y}:X${max_X}Y${max_Y}"
      lappend new_pblock_format_list $new_pblock_format
    }
    return $new_pblock_format
  }

  ########################################################################################
  # Obtains the maximum DSP and RAM coponents for each reconfigurable partition group.
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc obtain_max_DSP_and_RAM_for_reconfigurable_partitions {} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    set modified_reconfigurable_partition_list [list]
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
      #We only get one reconfigurable partition
      set reconfigurable_partition [lindex $reconfigurable_partition_list 0]
      set partition_name [dict get $reconfigurable_partition partition_name]
      set pblock_list [dict get $reconfigurable_partition xilinx_format_pblock_list]
      obtain_max_DSP_and_RAM_for_pblock $partition_name $pblock_list DSP RAM
      dict set reconfigurable_partition_group DSP $DSP 
      dict set reconfigurable_partition_group RAM $RAM
      lappend modified_reconfigurable_partition_list $reconfigurable_partition_group
    }
    set reconfigurable_partition_group_list $modified_reconfigurable_partition_list
  }

  ########################################################################################
  # Obtains the maximum DSP and RAM coponents for a given pblock
  #
  # Argument Usage:
  # partition_name: name of the reconfiurable partition to analyze. 
  # pblock_list:  pblock definition 
  # DSP: given by reference it will contain the number of DSP of the given pblock
  # RAM: given by reference it will contain the mumber of BRAM of the givenn pblock.  
  #
  # Return Value:
  ########################################################################################
  proc obtain_max_DSP_and_RAM_for_pblock {partition_name pblock_list DSP RAM} {
    upvar $DSP local_DSP
    upvar $RAM local_RAM
    if {[get_pblocks *$partition_name*] == {}} {
      set pblock_name pblock_${partition_name}
      create_and_place_pblock $pblock_name $pblock_list
      set sites_pblock [get_sites -of_objects [get_pblocks *$partition_name*]]
      delete_pblocks $pblock_name
    } else {
      set sites_pblock [get_sites -of_objects [lindex [get_pblocks *$partition_name*] 0]]
    }
    
    set local_DSP [llength [get_tiles -of_objects $sites_pblock -filter {TYPE =~ *DSP*}]]
    set local_RAM [llength [get_tiles -of_objects $sites_pblock -filter {TYPE =~ *RAM*}]]
  }

  ########################################################################################
  # It returns a dict with 4 fields (that correspond to cardinal the directions) and each 
  # direction contains all the edge interconnexion tiles. It is possible to use the 
  # expansion variable to find the edge tiles in a pblock expanded in each direction x 
  # number of tiles. 
  #
  # Argument Usage:
  # pblock_name: name of the pblock to find the edge tiles 
  # expansion: optional defaul value 0. Indicates if the function analyzes the raw pblock 
  # or expands it in each direction x number of tiles.
  #
  # Return Value:
  # dict with 4 fields (that correspond to cardinal the directions) and each 
  # direction contains all the edge interconnexion tiles.
  ########################################################################################
  #TODO this function can be optimized by reducing the calls to Vivado functions spceially
  # in pblocks with more tha one rectangle.
  proc get_edge_INT_tiles {pblock_name {expansion 0}} {
    set pblock [get_pblocks $pblock_name]
    set tiles_pblock [get_tiles -of_objects [get_sites -of_objects $pblock]]
    set INT_tiles_pblock [get_tiles -filter {TYPE =~ INT_?} -of_objects $tiles_pblock]
    set X_properties [lsort -integer -unique [get_property INT_TILE_X $INT_tiles_pblock]]
    set Y_properties [lsort -integer -unique -decreasing [get_property INT_TILE_Y $INT_tiles_pblock]]
    set NORTH_INT_tiles {}
    set SOUTH_INT_tiles {}
    set EAST_INT_tiles {}
    set WEST_INT_tiles {}
    set rectangle_count [get_property RECTANGLE_COUNT $pblock]
    if {$rectangle_count == 1 && $expansion == 0} {
      set NORTH_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == [lindex $Y_properties end]" -of_objects $tiles_pblock]
      set SOUTH_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == [lindex $Y_properties 0]" -of_objects $tiles_pblock]
      set EAST_INT_tiles [lsort -dictionary -increasing [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == [lindex $X_properties end]" -of_objects $tiles_pblock]]
      set WEST_INT_tiles [lsort -dictionary -increasing [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == [lindex $X_properties 0]" -of_objects $tiles_pblock]]
    } else {
      foreach X_property $X_properties {
        set column_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == $X_property" -of_objects $INT_tiles_pblock]
        set Y_property_of_column_tiles [lsort -integer -unique -decreasing [get_property INT_TILE_Y $column_tiles]]
        lappend SOUTH_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == $X_property && INT_TILE_Y == [expr [lindex $Y_property_of_column_tiles 0] + $expansion]"]
        lappend NORTH_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_X == $X_property && INT_TILE_Y == [expr [lindex $Y_property_of_column_tiles end] - $expansion]"]
      }
      foreach Y_property $Y_properties {
        set row_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == $Y_property" -of_objects $INT_tiles_pblock]
        set X_property_of_column_tiles [lsort -integer -unique [get_property INT_TILE_X $row_tiles]]
        lappend WEST_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == $Y_property && INT_TILE_X == [expr [lindex $X_property_of_column_tiles 0] - $expansion]"]
        lappend EAST_INT_tiles [get_tiles -filter "TYPE =~ INT_? && INT_TILE_Y == $Y_property && INT_TILE_X == [expr [lindex $X_property_of_column_tiles [expr [llength $X_property_of_column_tiles] -1]] + $expansion]"]
      }
    }
    dict set edge_tiles south $SOUTH_INT_tiles
    dict set edge_tiles north $NORTH_INT_tiles
    dict set edge_tiles east $EAST_INT_tiles
    dict set edge_tiles west $WEST_INT_tiles
    
    return $edge_tiles
  }
  
  ########################################################################################
  # This function logs an error in the info file and if necessary writes a design check 
  # point (DCP) of the current design 
  #
  # Argument Usage:
  # error_message: message to be written in the info file 
  # checkpoint_name: name of the design chekpoint to be written. If not filled the DCP 
  #   will not be generated. 
  #
  # Return Value:
  ########################################################################################
  proc log_error {error_message {checkpoint_name 0}} {
    variable ::reconfiguration_tool::project_variables 
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    file mkdir ${directory}/${project_name}/ERROR
    set fileId [open "${directory}/${project_name}/info" "a+"]
    puts $fileId "$error_message"
    close $fileId
    if {$checkpoint_name != 0} {
      write_checkpoint ${directory}/${project_name}/ERROR/$checkpoint_name
    }
  }
  
  ########################################################################################
  # This function logs the succesful implementation of a reconfigurable module or static
  # design. 
  #
  # Argument Usage:
  # success_message: message to be written in the info file 
  #
  # Return Value:
  ########################################################################################
  proc log_success {success_message} {
    variable ::reconfiguration_tool::project_variables 
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    set fileId [open "${directory}/${project_name}/info" "a+"]
    puts $fileId $success_message
    close $fileId
  }
  
  ########################################################################################
  # This function search for all the reconfigurable partition that are contained inside 
  # another reconfigurable partition, i.e. all the hierarchical RPs 
  #
  # Argument Usage:
  # partition_group_name: group of relocatable partition that will be searched to find if 
  # it has hierarchical modules. 
  #
  # Return Value:
  ########################################################################################
  proc obtain_hierarchical_partitions {partition_group_name} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    set hierarchical_reconfigurable_partition_list ""
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set hierarchical_partition_list [dict get $reconfigurable_partition hierarchical_partition_list]
        foreach hierarchical_partition $hierarchical_partition_list {
          if {$hierarchical_partition == $partition_group_name} {
              lappend hierarchical_reconfigurable_partition_list $reconfigurable_partition
              break
          }
        }
      }
    }
    return $hierarchical_reconfigurable_partition_list
  }
  
  proc find_reconfigurable_resource_type {tile_type} {
     
    if {[string first CLBLM $tile_type] != -1} {
      set resource_type CLB_M
    } elseif {[string first CLBLL $tile_type] != -1} {
      set resource_type CLB_L
    } elseif {[string first DSP $tile_type] != -1} {
      set resource_type DSP
    } elseif {[string first BRAM $tile_type] != -1} {
      set resource_type BRAM
    } else {
      set resource_type IRRELEVANT
    }
    
    return $resource_type
  }
  
  ########################################################################################
  # This function compares 2 regions and return 1 if they are relocatable or 0 if they are 
  # not
  #
  # Argument Usage:
  # pblock1, pblock2: definitions of pblocks to compare
  #
  # Return Value: 1 if they are relocatable or 0 if the are not
  ########################################################################################
  proc compare_relocatable_regions {pblock1 pblock2} {
    set pblock1_xilinx [change_pblock_format_from_custom_to_xilinx $pblock1] 
    set pblock2_xilinx [change_pblock_format_from_custom_to_xilinx $pblock2]
    
    create_and_place_pblock compare_pblock_1 $pblock1_xilinx
    create_and_place_pblock compare_pblock_2 $pblock2_xilinx
    
    set pblock1_resource_tiles [get_tiles -of_objects [get_sites -of_objects [get_pblocks -filter "NAME == compare_pblock_1"]]]
    set y_coordinate_1 [lsort -unique -increasing [get_property ROW $pblock1_resource_tiles]]
    set max_y_1 [lindex $y_coordinate_1 end]
    set min_y_1 [lindex $y_coordinate_1 0]
    set x_coordinate_1 [lsort -unique -increasing [get_property COLUMN $pblock1_resource_tiles]]
    set max_x_1 [lindex $x_coordinate_1 end]
    set min_x_1 [lindex $x_coordinate_1 0]
    
    
    set pblock2_resource_tiles [get_tiles -of_objects [get_sites -of_objects [get_pblocks -filter "NAME == compare_pblock_2"]]]
    set y_coordinate_2 [lsort -unique -increasing [get_property ROW $pblock2_resource_tiles]]
    set max_y_2 [lindex $y_coordinate_2 end]
    set min_y_2 [lindex $y_coordinate_2 0]
    set x_coordinate_2 [lsort -unique -increasing [get_property COLUMN $pblock2_resource_tiles]]
    set max_x_2 [lindex $x_coordinate_2 end]
    set min_x_2 [lindex $x_coordinate_2 0]
    
    set resource_list_pblock_1 [list] 
    for {set i $min_x_1} {$i <= $max_x_1} {incr i} {
      for {set j $min_y_1} {$j <= $max_y_1} {incr j} {
        set tile_type [get_property TILE_TYPE [get_tiles -filter "COLUMN == $i && ROW == $j"]]
        set reconfigurable_tile_type [find_reconfigurable_resource_type $tile_type] 
        if {$reconfigurable_tile_type != "IRRELEVANT"} {
          puts "type $reconfigurable_tile_type"
          set resource_list_pblock_1 [concat $resource_list_pblock_1 $reconfigurable_tile_type]
        }
      }
    }
    
    set resource_list_pblock_2 [list] 
    for {set i $min_x_2} {$i <= $max_x_2} {incr i} {
      for {set j $min_y_2} {$j <= $max_y_2} {incr j} {
        set tile_type [get_property TILE_TYPE [get_tiles -filter "COLUMN == $i && ROW == $j"]]
        set reconfigurable_tile_type [find_reconfigurable_resource_type $tile_type] 
        if {$reconfigurable_tile_type != "IRRELEVANT"} {
          set resource_list_pblock_2 [concat $resource_list_pblock_2 $reconfigurable_tile_type]
        }
      }
    }
    
    delete_pblocks compare_pblock_1
    delete_pblocks compare_pblock_2
    
    if {[::struct::list equal $resource_list_pblock_1 $resource_list_pblock_2]} {
      # pblcoks are relocatable
      return 1
    } else {
      #pblocks are not relocatable 
      return 0
    }
    
  
  }
  
}