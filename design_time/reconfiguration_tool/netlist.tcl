##########################################################################################
# This library provides functions dealing with netlist generation and netlist manipulation
# 
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################

package require struct::set

namespace eval ::reconfiguration_tool::netlist {
  namespace import ::reconfiguration_tool::utils
  # Procs that can be used in other namespaces
  namespace export create_static_netlist
  namespace export add_global_buffers_to_static_system
  namespace export add_reconfigurable_dummy_logic
  namespace export synthesize_reconfigurable_module
  namespace export create_reconfigurable_netlist
  namespace export add_global_buffers_to_reconfigurable_partition
  namespace export add_static_dummy_logic
  namespace export add_hierarchical_reconfigurable_dummy_logic
  
  ########################################################################################
  # Synthesize a reconfigurable module taking into account the number of DSP and RAM  
  # available in the partitions where the module can be allocated.
  #
  # Argument Usage:
  # reconfigurable_module: element of the list "reconfigurable_module_list" defined in the 
  #   top namespace (i.e. ::reconfiguration_tool).
  #
  # Return Value:
  # None or error
  ########################################################################################   
  proc synthesize_reconfigurable_module {reconfigurable_module} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::working_directory
    
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    # We look for all the partitions where the module can be allocated to know the minimum 
    # DSP and RAM resources that can be used (i.e. it synthesize the module with the less 
    # available DSPs and BRAMs)
    set DSP [list]
    set RAM [list]
    set partition_group_name_list [dict get $reconfigurable_module partition_group_name_list]
    foreach partition_group_name $partition_group_name_list {
      foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
        if {[dict get $reconfigurable_partition_group partition_group_name] == $partition_group_name} {
          set DSP [dict get $reconfigurable_partition_group DSP]
          set RAM [dict get $reconfigurable_partition_group RAM]
        }
      }
    }
    #We select the minimum values 
    set DSP [lindex [lsort -integer $DSP] 0]
    set RAM [lindex [lsort -integer $RAM] 0]
    
    close_design -quiet
    remove_files -fileset [get_filesets cons*] * -quiet
    remove_files -fileset [get_filesets sour*] * -quiet 
    set_part [dict get $project_variables fpga_chip]
    set sources [dict get $reconfigurable_module sources] 
    set need_to_synthesize [add_files_to_project $sources]
    # NOTE the no_srlextract option is enabled because previous experience at CEI has  
    # shown that in some models this could lead to problems.
    if {$need_to_synthesize == 1} {
      if {[catch {synth_design -no_srlextract -mode out_of_context -max_dsp $DSP -max_bram $RAM -top [lindex [find_top] 0]} errmsg]} {
        error "synthesis error. Module: ${module_name}"
      }
    }
    
    set_property DONT_TOUCH 1 [get_nets]
    set module_name [dict get $reconfigurable_module module_name]
    write_checkpoint [file join ${directory} ${project_name} SYNTHESIS ${module_name}_reconfigurable_module]   
    remove_files *
    close_design -quiet
    remove_files -fileset [get_filesets cons*] * -quiet
    remove_files -fileset [get_filesets sour*] * -quiet
  }

  ########################################################################################
  # Creates the netlist of the reconfigurable module. It is necessary that a  
  # synthesized DCP of the module is available in the folder "SYNTHESIS" found inside the 
  # project folder. 
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of partitions where the module can be allocated. 
  # it is used to find the hierarchical partitions that can be found in the module. 
  # module_name: It is used to find the synthesized DCP file
  #
  # Return Value:
  # none or error 
  ########################################################################################
  proc create_reconfigurable_netlist {reconfigurable_partition_group module_name} {
    variable ::reconfiguration_tool::project_variables
    
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    set reconfigurable_partition [lindex [dict get $reconfigurable_partition_group reconfigurable_partition_list] 0]
    set partition_name [dict get $reconfigurable_partition partition_name]
    # close_design -quiet 
    close_project -quiet
    remove_files -fileset [get_filesets cons*] * -quiet
    remove_files -fileset [get_filesets sour*] * -quiet
    set_part [dict get $project_variables fpga_chip]
    set_property "target_language" "VHDL" [current_project]
    link_design  
    # We create a blackbox and then substitute it 
    create_property RECONFIGURABLE_PARTITION cell -type bool -default_value 0
    create_cell -black_box -reference $partition_name $partition_name
    set_property RECONFIGURABLE_PARTITION 1 [get_cells $partition_name]
    read_checkpoint -cell [get_cells $partition_name] [file join ${directory} ${project_name} SYNTHESIS ${module_name}_reconfigurable_module.dcp]  
    # We put black boxes in the hierarchical reconfigurable cells 
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name] 
    set hierarchical_reconfigurable_partition_list [::reconfiguration_tool::utils::obtain_hierarchical_partitions $partition_group_name] 
    foreach reconfigurable_partition $hierarchical_reconfigurable_partition_list {
      set partition_name [dict get $reconfigurable_partition partition_name]
      set cell [get_cells -hierarchical $partition_name]
      if {[llength $cell] == 0} {
        # NOTE We don't give an error to support the case where there are modules that 
        # have the reconfigureble hierarchical cell and other modules that don't. In the 
        # last case this modules can not use the space occupied by the hierarchial module 
        # but no error is given. 
      } elseif {[llength $cell] > 1} {
        error "multiple hierarchical blackbox cell $partition_name found for partition $partition_group_name"
      } else {
        if {[get_property IS_BLACKBOX $cell] == 0} {
          update_design -cells $cell -black_box
        }
        set_property RECONFIGURABLE_PARTITION 1 $cell
      }
    }
  }

  ########################################################################################
  # Synthesize the static system and convert reconfigurable cells into black boxes.
  #
  # Argument Usage:
  #
  # Return Value:
  # None or error
  ########################################################################################
  proc create_static_netlist {} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    variable ::reconfiguration_tool::static_system_info
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::working_directory

    set directory [dict get $project_variables directory]
    set sources [dict get $static_system_info sources]
    remove_files -fileset [get_filesets cons*] * -quiet
    remove_files -fileset [get_filesets sour*] * -quiet
    # close_design -quiet
    close_project -quiet
    set_part [dict get $project_variables fpga_chip]
    set_property "target_language" "VHDL" [current_project]
    
    set need_to_synthesize [add_files_to_project $sources]
    # NOTE the no_srlextract option is enabled because previous experience at CEI has  
    # shown that in some models this could lead to problems.

    if {$need_to_synthesize == 1} {
      if {[catch {synth_design -no_srlextract -top [lindex [find_top] 0]} errmsg]} {
        error "synthesis error"
      }
    }
    # The static system contain cells that are allocated in the RPs. These cells can be 
    # black boxes or other reconfigurable modules that the user has already developed
    # (it may be easier for the user to add his/her own module than using a black box). 
    # If necessary the tool converts the cell into a blackbox. The cells are marked with 
    # the property RECONFIGURABLE_PARTITION to make it easier to find these cells in other 
    # parts of the design. 
    create_property RECONFIGURABLE_PARTITION cell -type bool -default_value 0 
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set partition_name [dict get $reconfigurable_partition partition_name]
        set cell [get_cells -hierarchical $partition_name]
        if {[llength $cell] == 0} {
          error "blackbox cell for partition $partition_name not found"
        } elseif {[llength $cell] > 1} {
          error "multiple blackbox cell for partition $partition_name found"
        } else {
          set ref_name_partition [get_property REF_NAME $cell]
          if {[llength [get_cells -hierarchical -filter "REF_NAME == $ref_name_partition"]] > 1} {
            # We recreate the partition cells to have each blackbox with a different 
            # reference. NOTE if we have multiple blackboxes with the same REF_NAME Vivado 
            # throws an error when trying to add the dummy logic inside one of the cells.
            set pins [get_pins -of_objects $cell]  
            set pins_nets [dict create]
            set pins_direction [dict create]
            foreach pin $pins {
              dict set pins_nets $pin [get_nets -of_objects $pin]
              dict set pins_direction $pin [get_property DIRECTION $pin]
            }
            remove_cell $cell
            create_cell -reference black_box_${i} -black_box $cell 
            incr i
            foreach pin $pins {
              set BUS_NAME [get_property BUS_NAME $pin]
              if {$BUS_NAME != ""} {
                set BUS_STOP [get_property BUS_STOP $pin] 
                set BUS_START [get_property BUS_START $pin]
                set PARENT_CELL [get_property PARENT_CELL $pin]
                create_pin -quiet -direction [dict get $pins_direction $pin] -from $BUS_START -to $BUS_STOP ${PARENT_CELL}/${BUS_NAME} 
              } else {
                create_pin -direction [dict get $pins_direction $pin] $pin 
              }            
              connect_net -net [dict get $pins_nets $pin] -objects $pin 
            }    
          } else {
            if {[get_property IS_BLACKBOX $cell] == 0} {
              update_design -cells $cell -black_box
            }
            set_property RECONFIGURABLE_PARTITION 1 $cell
          }
        }
      }
    }
  }
  
  ########################################################################################
  # Add files to the project 
  #
  # Argument Usage:
  #   sources: list of sources to be added in the project 
  #
  # Return Value:
  # None or error
  ########################################################################################
  proc add_files_to_project {sources} {
    variable ::reconfiguration_tool::project_variables 
    variable ::reconfiguration_tool::working_directory
    
    set need_to_synthesize 1
    set valid_extensions "*.vhd *.v *.xdc *.bd *.edif *.xci *.dcp *.tcl"
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    
    # If this is not selected block design may not generate correctly
    set_property source_mgmt_mode All [current_project]
    set tcl_files [list]
    foreach source $sources {
      set files ""
      if {[file isdirectory $source] == 1} {
        foreach extension $valid_extensions {
          set files [concat $files [glob -nocomplain -directory ${source} ${extension}]]
        }
        
      } else {
        set files $source 
      }
      foreach file $files {
        set file_extension [string tolower [string range $file [string last . $file] end]]
        switch -exact -- $file_extension {
          .vhd {
            read_vhdl $file
          }
          .v {
            read_verilog $file
          }
          .xdc {
            read_xdc $file
          }
          .bd {
            set bd_name [file tail $file]
            file copy $file ${directory}/${project_name}/TMP/${bd_name}
            read_bd ${directory}/${project_name}/TMP/${bd_name}
            generate_target all [get_files  ${directory}/${project_name}/TMP/${bd_name}] 
            read_vhdl [glob ${directory}/${project_name}/TMP/hdl/*.vhd]
          }
          .edf {
            read_edif $file
            link_design
            set need_to_synthesize 0
          }
          .xci {
            read_ip $file
          }
          .dcp {
            read_checkpoint $file
            link_design
            set need_to_synthesize 0
          }
          .tcl {
              set tcl_files [concat $tcl_files $file]
          }
          default {}
        }
      }
    }
    # TCL scripts are used to reconstruc a block design. They may contain IPs from previous 
    # sources. Therefore, it is necessary to execute them at the end. 
    if {[llength $tcl_files] > 0} {
      set old_top_files [find_top -return_file_paths]
      foreach tcl_file $tcl_files {
        source $tcl_file
      }
      # We don't include block designs included as .bd files 
      set top_files [::struct::set difference  [find_top -return_file_paths] $old_top_files]
      foreach top_file $top_files {
        if {[file extension $top_file] == ".bd"} {
         # set generated_outputs [list_target [get_files $file]]
         # if {[llength $generated_outputs] > 0} {
         #   generate_target all [get_files $top_file]
         # }
         generate_target all [get_files $top_file]
         make_wrapper -files [get_files $top_file] -top -import     
        }
      }
    }

    # NOTE We add constraints so the tools can't make RAM and ROM memories in a 
    # distributed fashion. This is done because previous experience at CEI has shown that 
    # in some models this could lead to problems.
    read_xdc [file join $working_directory "auxiliary_tools" "ROM_RAM_constraints.xdc"]
    return $need_to_synthesize
  }

  ########################################################################################
  # This function adds static dummy logic to a reconfigurable design that has an empty 
  # top design. It also adds dummy logic inside the reconfigurable module in all the 
  # unconnected pins.
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of RP where the module can be allocated. 
  #
  # Return Value:
  ########################################################################################
  proc add_static_dummy_logic {reconfigurable_partition_group} {
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
    set cell_name [get_cells -filter "RECONFIGURABLE_PARTITION == 1"]
    set input_pins [get_pins -of_objects $cell_name -filter {DIRECTION == IN && IS_CONNECTED == FALSE}]
    create_cell -black_box -reference dummy dummy
    # We connect dummy logic to input pins.
    foreach pin $input_pins {
      set net [get_nets -boundary_type lower -of_objects $pin]
      set leaf_cell [get_pins -of_objects [get_nets -boundary_type lower -segments -of_objects $pin] -filter {IS_LEAF==1}]
      if {[llength [get_pins -of_objects [get_nets -boundary_type lower -segments -of_objects $pin] -filter {DIRECTION == OUT}]] > 0} {
        set connected_to_output 1
      } else {
        set connected_to_output 0
      }
      # We create dummy logic inside the reconfigurable partition for all the unconnected 
      # pins, i.e. we connect a LUT inside the block so it is connected to something. 
      if {($leaf_cell == "") && ($connected_to_output == 0)} {
        set pin_ref [get_property REF_PIN_NAME $pin]
        set LUT "${cell_name}/${pin_ref}_LUT_inserted"
        create_cell -reference LUT1 $LUT
        if {$net == ""} {
          set net_inserted "${cell_name}/${pin_ref}_inserted"
          create_net $net_inserted
          set net [get_nets $net_inserted]
        } else {
          set_property DONT_TOUCH FALSE $net
        }
        connect_net -net $net -objects [list $pin $LUT/I0]
        set_property DONT_TOUCH TRUE $net
      }
      # We connect each pin to a dummy lut through the top module. The dummy logic will 
      # form the static system. 
      set net_direction [get_property INTERFACE_DIRECTION $net]
      if {[string first GLOBAL $net_direction] != -1} continue
      set pin_name [get_property REF_PIN_NAME $pin]
      set net_name dummy/${pin_name}
      set dummy_LUT_name dummy/dummy_LUT_OUT_${partition_group_name}_${pin_name}
      create_net $net_name
      create_cell -reference LUT1 $dummy_LUT_name
      set dummy_LUT_pin [get_pins -of [get_cells $dummy_LUT_name] -filter {DIRECTION == OUT}] 
      connect_net -hierarchical -net $net_name -objects [list $dummy_LUT_pin $pin]
      set_property -quiet -name DONT_TOUCH -value yes -object [get_nets $net_name]
    }
    # We repeat the process for the output pins 
    set output_pins [get_pins -of_objects $cell_name -filter {DIRECTION == OUT && IS_CONNECTED == FALSE}]
    foreach pin $output_pins {
      set net [get_nets -boundary_type lower -of_objects $pin]
      set leaf_cell [get_pins -of_objects [get_nets -boundary_type lower -segments -of_objects $pin] -filter {IS_LEAF==1}]
      if {[llength [get_pins -of_objects [get_nets -boundary_type lower -segments -of_objects $pin] -filter {DIRECTION == IN}]] > 0} {
        set connected_to_input 1
      } else {
        set connected_to_input 0
      }
      if {($leaf_cell == "") && ($connected_to_input == 0)} {
        set pin_ref [get_property REF_PIN_NAME $pin]
        set LUT "${cell_name}/${pin_ref}_LUT_inserted"
        create_cell -reference LUT1 $LUT
        if {$net == ""} {
          set net_inserted "${cell_name}/${pin_ref}_inserted"
          create_net $net_inserted
          set net [get_nets $net_inserted]
        } else {
          set_property DONT_TOUCH FALSE $net
        }
        connect_net -net $net -objects $LUT/O
        set_property DONT_TOUCH TRUE $net
      }
      set pin_name [get_property REF_PIN_NAME $pin]
      set net_name dummy/${pin_name}
      set dummy_LUT_name dummy/dummy_LUT_IN_${partition_group_name}_${pin_name}
      create_net $net_name
      create_cell -reference LUT1 $dummy_LUT_name
      set dummy_LUT_pin [get_pins -of [get_cells $dummy_LUT_name] -filter {DIRECTION == IN && NAME =~ */I0*}] 
      connect_net -hierarchical -net $net_name -objects [list $dummy_LUT_pin $pin]
      set_property -quiet -name DONT_TOUCH -value yes -object [get_nets $net_name]
    }
  }



  ########################################################################################
  # This functions takes an static system with a reconfigurable partition defined as a 
  # black box and populates it with dummy logic. It also adds dummy logic in the static   
  # system if there is any pin unconnected in the static system or the connection in a 
  # power one i.e. GND or VCC (this type of routing is only possible from one INT tile 
  # to its adyacent logic tile). It also adds dummy for each global signal in every column 
  # of the reconfigurable partition to ensure that all the columns have a the global 
  # signal to them. 
  #
  # Argument Usage:
  # reconfigurable_partition: partition where the dummy logic will be added 
  # partition_group_name: name of the group which the partition belongs. 
  #
  # Return Value:
  ########################################################################################
  proc add_reconfigurable_dummy_logic_to_partitions {reconfigurable_partition partition_group_name} {
    set partition_name [dict get $reconfigurable_partition partition_name]
    set cell [get_cells -hierarchical ${partition_name} -filter "RECONFIGURABLE_PARTITION == 1"]
    set input_pins [get_pins -of_objects $cell -filter {DIRECTION == IN}]
    set max_number_of_nets_per_LUT 6
    # We find how many dummy LUTs we need to connect all the input pins (each LUT can be 
    # connected 6 input pins)
    set number_of_LUTS [expr ([llength $input_pins] / $max_number_of_nets_per_LUT)]
    if {[expr ([llength $input_pins] % $max_number_of_nets_per_LUT)] != 0} {
      incr number_of_LUTS
    }
    for {set j 0} {$j < $number_of_LUTS} {incr j} {
      set dummy_LUT_name ${cell}/dummy_LUT_IN_${j}
      create_cell -reference LUT6 $dummy_LUT_name
    }
    set LUT_number 0
    set pin_number 0
    foreach pin $input_pins {
      set connected_net [get_nets -of_objects $pin]
      set connected_net_type [get_property TYPE $connected_net] 
      # If the static system connection is a power or GND type is neccesary to connect it 
      # through a LUT. 
      if { $connected_net_type == "POWER" || $connected_net_type == "GROUND"} {
        set_property DONT_TOUCH FALSE $connected_net
        insert_LUT_buffer $pin
        set_property DONT_TOUCH TRUE $connected_net
      }
      # We connect the input pins to the dummy LUTs created before.
      set pin_name [get_property REF_PIN_NAME $pin]
      set net_name ${cell}/dummy_net_${pin_name}
      create_net $net_name
      set dummy_LUT_pin [get_pins -of_objects [get_cells ${cell}/dummy_LUT_IN_${LUT_number}] -filter "DIRECTION == IN && NAME =~ */I${pin_number}*"] 
      connect_net -net $net_name -objects [list $dummy_LUT_pin $pin]
      set_property -quiet -name DONT_TOUCH -value yes -object [get_nets -boundary_type lower -of_objects $pin]
      set_property -quiet -name DONT_TOUCH -value yes -object [get_nets -boundary_type upper -of_objects $pin]
      incr pin_number
      if {$pin_number >= $max_number_of_nets_per_LUT} {
        set pin_number 0
        incr LUT_number
      }    
    }
    # We now connect the output dummy logic. 
    set output_pins [get_pins -of_objects $cell -filter {DIRECTION == OUT}]
    foreach pin $output_pins {
      #We look if the net of the pin is connected to a lead cell. If not we connect one 
      set input_leaf_cell [get_pins -of_objects [get_nets -segments -of_objects $pin] -filter {IS_LEAF && (DIRECTION == "IN")}]
      set input_cell [get_cells -of_objects [get_pins -of_objects [get_nets -segments -of_objects $pin] -filter {(DIRECTION == "IN")}]]
      if {$input_cell == ""} {
        set connected_to_another_reconfigurable_cell FALSE
      } else {
        if {[get_property RECONFIGURABLE_PARTITION $input_cell] == TRUE} {
          set connected_to_another_reconfigurable_cell TRUE
        } else {
          set connected_to_another_reconfigurable_cell FALSE
        }
      }
      # We connect dummy logic to all the pins unconnected in the static system. 
      if {$input_leaf_cell == "" && $connected_to_another_reconfigurable_cell == FALSE} {
        set pin_ref [get_property REF_PIN_NAME $pin]
        set net [get_nets -boundary upper -of_objects $pin]
        set LUT "${cell}_${pin_ref}_LUT_inserted"
        create_cell -reference LUT1 $LUT
        if {$net == ""} {
          set net_inserted "${cell}_${pin_ref}_inserted"
          create_net $net_inserted
          set net [get_nets $net_inserted]
          connect_net -net $net -objects [list $pin $LUT/I0]
        } else {
          set_property DONT_TOUCH FALSE $net
          connect_net -net $net -objects $LUT/I0
        }
        set_property DONT_TOUCH TRUE $net
      }
      # We connect the dummy LUTs inside the cell
      set pin_name [get_property REF_PIN_NAME $pin]
      set net_name ${cell}/dummy_net_${pin_name}
      create_net $net_name
      set dummy_LUT_name ${cell}/dummy_LUT_OUT_${pin_name}
      create_cell -reference LUT1 $dummy_LUT_name
      set dummy_LUT_pin [get_pins -of [get_cells $dummy_LUT_name] -filter {DIRECTION == OUT}] 
      connect_net -net $net_name -objects [list $dummy_LUT_pin $pin]
      # set FF_name ${cell}/dummy_FF_${pin_name}
      # create_cell -reference FDRE $FF_name
      # set dummy_FF_pin [get_pins -of [get_cells $FF_name] -filter {DIRECTION == OUT}] 
      # connect_net -net $net_name -objects [list $dummy_FF_pin $pin]
      set_property -quiet -name DONT_TOUCH -value yes -object [get_nets -boundary_type lower -of_objects $pin]
    }
    # We add the dummy logic for global 
    add_dummy_logic_to_global_nets $partition_name $partition_group_name
  }
  
  
  ########################################################################################
  # This function obtains all the hierarchical partitions of a RP group and adds dummy 
  # logic to all of them. 
  #
  # Argument Usage:
  # reconfigurable_partition_group: group of relocatable partitions. 
  #
  # Return Value:
  ########################################################################################
  proc add_hierarchical_reconfigurable_dummy_logic {reconfigurable_partition_group} {
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name] 
    set hierarchical_reconfigurable_partition_list [::reconfiguration_tool::utils::obtain_hierarchical_partitions $partition_group_name] 
    foreach reconfigurable_partition $hierarchical_reconfigurable_partition_list {
      add_reconfigurable_dummy_logic_to_partitions $reconfigurable_partition $partition_group_name
    }
  }

  ########################################################################################
  # Adds the reconfigurable dummy logic to all the partitions of the system. 
  #
  # Argument Usage:
  # Return Value:
  ########################################################################################
  proc add_reconfigurable_dummy_logic {} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
      set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
      foreach reconfigurable_partition $reconfigurable_partition_list {
        set hierarchical_partition_list [dict get $reconfigurable_partition hierarchical_partition_list]
        if {[llength $hierarchical_partition_list] > 0} {
          break
        }
        add_reconfigurable_dummy_logic_to_partitions $reconfigurable_partition $partition_group_name
      }
    }
  }

  ########################################################################################
  # Adds global buffer to all the global nets in the static system.
  #
  # Argument Usage:
  # Return Value:
  ########################################################################################
  proc add_global_buffers_to_static_system {} {
    variable ::reconfiguration_tool::global_nets_info
    if {$global_nets_info == ""} {
      return 
    }
    set global_nets [dict keys [dict get $global_nets_info all_global_nets]]
    foreach net_name $global_nets {
      #Check if there in already a BUFG
      set pin [get_pins -of_objects [get_cells -hierarchical -filter {RECONFIGURABLE_PARTITION == TRUE}] -filter "REF_PIN_NAME == $net_name"]
      set net_complete [get_nets -segments -of_objects $pin]
      if {[llength [get_cells -of_objects $net_complete -filter {REF_NAME =~ "BUFG*" || REF_NAME =~ "BUFH*"}]] == 0} {
        insert_clock_buffer_in_pin BUFG $pin 
      }
      set net [get_nets -of_objects $pin]
      set_property DONT_TOUCH TRUE $net
    }
  }

  ########################################################################################
  # Adds global buffer to the global nets that belong to a group of reconfigurable 
  # partitions. 
  #
  # Argument Usage:
  # reconfigurable_partition_group:
  #
  # Return Value:
  ########################################################################################
  proc add_global_buffers_to_reconfigurable_partition {reconfigurable_partition_group} {
    variable ::reconfiguration_tool::global_nets_info
    if {$global_nets_info == ""} {
      return 
    }
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
    
    set global_nets ""
    if {[info exists global_nets_info] == 1} {
      if {[dict exists $global_nets_info $partition_group_name] == 1} {
        set global_nets [dict keys [dict get $global_nets_info $partition_group_name]]
      }
    }

    foreach net_name $global_nets {
      set buffer_global_partition_name BUF_${net_name}
      create_cell -reference BUFG $buffer_global_partition_name
      set pin_out_buffer_global_cell [get_pins -of_objects [get_cells $buffer_global_partition_name] -filter {DIRECTION == OUT}]
      set buffer_net_name BUF_${net_name}_net
      create_net $buffer_net_name
      set pins_to_connect $pin_out_buffer_global_cell
      set cell [get_cells -hierarchical -filter "RECONFIGURABLE_PARTITION == 1"]
      set pins_to_connect [concat $pins_to_connect [get_pins -of_objects $cell -filter "NAME =~ *$net_name"]]
      connect_net -net [get_nets $buffer_net_name] -objects $pins_to_connect
    }
  }

  ########################################################################################
  # Inserts a clock buffer (BUFG, BUFHCE, BUFR, etc) on the specified net(s). 
  #
  # Argument Usage:
  # type: buffer type to insert i.e. BUFG, BUFHCE, BUFR, etc
  # nets: net where the buffer will be inserted
  #
  # Return Value:
  ########################################################################################
  proc insert_clock_buffer { type nets } {
     foreach net $nets {
        #The last requirement is required for systems with ILA
        # set driver [get_pins -quiet -of [get_nets -segments $net] -filter "DIRECTION==OUT && (REF_NAME == IBUF || PARENT_CELL =~ [get_property PARENT_CELL $net]/*)"] 
        set driver [get_pins -quiet -of $net -filter "DIRECTION==OUT && (REF_NAME == IBUF || PARENT_CELL =~ [get_property PARENT_CELL $net]/*)"]
        set net_driver [get_nets -of_objects $driver]
        if {[llength $driver]} {
           set cell "${net_driver}_${type}_inserted"
           disconnect_net -net $net_driver -objects $driver
           create_cell -reference $type $cell
           create_net ${net_driver}_inserted
           connect_net -net ${net_driver}_inserted -objects [list $driver $cell/I]
           connect_net -net ${net_driver} -objects $cell/O
        } else {
           puts "ERROR: Could not find leaf level driver for net $net. Make sure the specified net is at the same level of hierarchy as the leaf level driver."
        }
     }
  }
  
  ########################################################################################
  # Inserts a clock buffer (BUFG, BUFHCE, BUFR, etc) on the specified pin. 
  #
  # Argument Usage:
  # type: buffer type to insert i.e. BUFG, BUFHCE, BUFR, etc
  # pin: pin where the buffer will be inserted
  #
  # Return Value:
  ########################################################################################
  proc insert_clock_buffer_in_pin {type pin} {
    set net [get_nets -of_objects $pin] 
    set dont_touch_property [get_property DONT_TOUCH $net]
    set_property DONT_TOUCH	false $net 
    set cell "${net}_${type}_inserted"
    disconnect_net -net $net -objects $pin 
    create_cell -reference $type $cell
    create_net ${net}_inserted 
    connect_net -net ${net}_inserted -objects [list $pin $cell/O]
    connect_net -net ${net} -objects $cell/I
    set_property DONT_TOUCH $dont_touch_property $net
  }
  


  ########################################################################################
  # Inserts a LUT buffer in a pin. It is useful in cases where a power net (GND or VCC) 
  # of the static system is connected to a reconfigurable module. To decouple this is 
  # necessary to insert a buffer LUT (in regular designs the optimization process solves 
  # this situation). 
  #
  # Argument Usage:
  # pin where the LUT is inserted. 
  #
  # Return Value:
  ########################################################################################
  proc insert_LUT_buffer {pin} {
    set net [get_nets -of_objects $pin]
    set parent_cell [get_property PARENT_CELL $net]
    set pin_ref [get_property REF_PIN_NAME $pin]
    set driver [get_pins -quiet -of [get_nets $net] -filter "DIRECTION==OUT"]  
    set ref_name_driver [get_property REF_NAME $driver]
    if {[llength $driver]} {
      if {$parent_cell == ""} {
        set cell "${pin_ref}_LUT_inserted"
        set net_inserted "${pin_ref}_inserted"
      } else {
        set cell "${parent_cell}/${pin_ref}_LUT_inserted"
        set net_inserted "${parent_cell}/${pin_ref}_inserted"
      }
      create_cell -reference LUT1 $cell
      set_property INIT 2'h2 [get_cells $cell] ;#equation for LUT1 buffer
      
      create_net $net_inserted
      if {$ref_name_driver == "VCC" || $ref_name_driver == "GND"} {
        connect_net -hierarchical -net $net -objects $cell/I0
        disconnect_net -net $net -pinlist $pin
        connect_net -hierarchical -net $net_inserted -objects [list $pin $cell/O]
      } else {
        disconnect_net -net $net -objects $driver
        connect_net -net $net_inserted -objects [list $driver $cell/I0]
        connect_net -net $net -objects $cell/O
      }
    } else {
       puts "ERROR: Could not find driver for net $net"
    }
  }
 
  ########################################################################################
  # Adds n dummy LUTs for each global net (where n is the number of columns in the 
  # reconfigurable partition). This is done in order to activate the PIPS of the clock row 
  # that provides the clock to each tile in the column. 
  #
  # Argument Usage:
  # partition_name: this refers to the name of the partition (and the reconfigurable cell) 
  #   where the dummy logic will be added. 
  # partition_group_name: name of the partition group which the particular partition 
  #   belongs. 
  #
  # Return Value:
  ########################################################################################
  proc add_dummy_logic_to_global_nets {partition_name partition_group_name} {
    variable ::reconfiguration_tool::global_nets_info
    if {$global_nets_info == ""} {
      return 
    }
    set cell [get_cells -hierarchical ${partition_name} -filter "RECONFIGURABLE_PARTITION == 1"]
    set hierarchical_cells ${cell}/ 
    if {[dict exist $global_nets_info $partition_group_name] == 0} {
      return
    }
    set global_nets [dict keys [dict get $global_nets_info $partition_group_name]]
    set number_global_nets [llength $global_nets]
    set pblock_sites [get_sites -of_objects [get_pblocks -of_objects $cell]]
    set clock_regions [get_clock_regions -of_objects $pblock_sites]
    set pblock_tiles [get_tiles -of_objects $pblock_sites]
    foreach net_name $global_nets {
      set net [get_nets -of_objects [get_pins -of_objects [get_cells $cell] -filter "REF_PIN_NAME == $net_name"] -boundary_type lower]
      set_property DONT_TOUCH FALSE $net
    }
    
    foreach clock_region $clock_regions {
      set clock_region_tiles [get_tiles -of_objects $clock_region]
      set intersect_tiles [get_tiles -of_objects [lsort -dictionary [::struct::set intersect $clock_region_tiles $pblock_tiles]]]
      set x_coordinates [lsort -integer -unique [get_property GRID_POINT_X [get_tiles -of_objects $intersect_tiles -filter {TYPE =~ *CLB*}]]]
      set y_coordenates [lsort -integer -decreasing -unique [get_property INT_TILE_Y [get_tiles -of_objects $intersect_tiles -filter {TYPE =~ *CLB*}]]]
      set high_y_coordenate [lindex $y_coordenates end]
      set low_y_coordenate [lindex $y_coordenates 0]
      # We check that we can allocate all the global nets   
      set num_rows_in_clock_region 50
      set high_y_coordenate_relative [expr $high_y_coordenate % $num_rows_in_clock_region]
      set low_y_coordenate_relative [expr $low_y_coordenate % $num_rows_in_clock_region]
      set rows_in_upper_part [expr ($num_rows_in_clock_region / 2) - $high_y_coordenate_relative]
      set rows_in_lower_part [expr $low_y_coordenate_relative - (($num_rows_in_clock_region / 2) - 1)]
      set min_rows [expr min($rows_in_upper_part,$rows_in_lower_part)]
      
      # How many FF with differenct clock can we place by row (i.e. 2 for series 7)
      set max_FF_per_row 1 ; #Sometime Vivado throws placement errors when I have this to 2 i dont know why...
      # We see if we need to use LUTs. In some designs adding LUTs has cause problems. So
      # we only added if necessary
      if {(($number_global_nets / $max_FF_per_row) + 1) > $min_rows} {
        set max_nets_to_LUTs 2
      } else {
        set max_nets_to_LUTs 0
      }
      #How many global nets can we have per row 
      set global_nets_per_row [expr $max_FF_per_row + $max_nets_to_LUTs]
      
      set number_of_rows_needed [expr ($number_global_nets / $global_nets_per_row) + 1]
      if {$rows_in_upper_part > 0} {
        if {$number_of_rows_needed > $rows_in_upper_part} {
          error "there are more global nets that can be allocated in the upper part of $partition_name in \ 
          clock region $clock_region. There are $rows_in_upper_part that can allocate a maximum of \ 
          ($rows_in_upper_part * $global_nets_per_row) nets."
        } 

        foreach x_coordinate $x_coordinates {
          set net_position 0
          for {set i 0} {$i < $number_of_rows_needed} {incr i} {
            set row [expr $high_y_coordenate + $i]
            set CLB_sites [get_sites -of_objects [get_tiles -filter "TYPE =~ *CLB* && INT_TILE_Y == $row && GRID_POINT_X == $x_coordinate"]]
            for {set j 0} {$j < $global_nets_per_row} {incr j} {
              if {$net_position < $number_global_nets} {
                set pin_name [lindex $global_nets $net_position]
                set net [get_nets -of_objects [get_pins -of_objects [get_cells $cell] -filter "REF_PIN_NAME == $pin_name"] -boundary_type lower] 
                incr net_position          
                set dummy_cell ${hierarchical_cells}dummy_global_nets_${clock_region}_x${x_coordinate}_up_row${i}_element${j}
                connect_net_to_cell $dummy_cell $j $net $CLB_sites   
              }
            }
          }
        }
      }
      if {$rows_in_lower_part > 0} {
        if {$number_of_rows_needed > $rows_in_lower_part} {
          error "there are more global nets that can be allocated in the upper part of $partition_name in \ 
          clock region $clock_region. There are $rows_in_upper_part that can allocate a maximum of \ 
          ($rows_in_upper_part * $global_nets_per_row) nets."
        }
        foreach x_coordinate $x_coordinates {
          set net_position 0
          for {set i 0} {$i < $number_of_rows_needed} {incr i} {
            set row [expr $low_y_coordenate - $i]
            set CLB_sites [get_sites -of_objects [get_tiles -filter "TYPE =~ *CLB* && INT_TILE_Y == $row && GRID_POINT_X == $x_coordinate"]]
            for {set j 0} {$j < $global_nets_per_row} {incr j} {
              if {$net_position < $number_global_nets} {
                set pin_name [lindex $global_nets $net_position]
                set net [get_nets -of_objects [get_pins -of_objects [get_cells $cell] -filter "REF_PIN_NAME == $pin_name"] -boundary_type lower] 
                incr net_position
                set dummy_cell ${hierarchical_cells}dummy_global_nets_${clock_region}_x${x_coordinate}_down_row${i}_element${j}
                connect_net_to_cell $dummy_cell $j $net $CLB_sites                   
              }
            }
          }
        }
      }
    }
    
    foreach net_name $global_nets {
      set net [get_nets -of_objects [get_pins -of_objects [get_cells $cell] -filter "REF_PIN_NAME == $net_name"] -boundary_type lower]
      set_property DONT_TOUCH TRUE $net
    }
  }
  
  ########################################################################################
  # Helper function of add_dummy_logic_to_global_nets. Creates a cell that will be  
  # connected to the net 
  #
  # Argument Usage:
  # dummy_cell
  # 
  #
  # Return Value:
  ########################################################################################
  proc connect_net_to_cell {dummy_cell position net CLB_sites} {
    switch -exact -- $position {
      0 {
        create_cell -reference FDRE $dummy_cell
        set_property LOC [lindex $CLB_sites 0] [get_cells $dummy_cell]
        set pin [get_pins -of [get_cells $dummy_cell] -filter "DIRECTION == IN && NAME =~ */C*"]                    
      }
      1 {
        create_cell -reference FDRE $dummy_cell
        set_property LOC [lindex $CLB_sites 1] [get_cells $dummy_cell]
        set pin [get_pins -of [get_cells $dummy_cell] -filter "DIRECTION == IN && NAME =~ */C*"]
        
      }
      2 {
        create_cell -reference LUT2 $dummy_cell
        set_property LOC [lindex $CLB_sites 1] [get_cells $dummy_cell]
        set pin [get_pins -of [get_cells $dummy_cell] -filter "DIRECTION == IN && NAME =~ */I0*"]
      }
      3 {
        set pin [get_pins -of [get_cells ${hierarchical_cells}dummy_global_nets_${clock_region}_x${x_coordinate}_up_row${i}_element2] -filter "DIRECTION == IN && NAME =~ */I1*"]
      }
      default {}
    }
    connect_net -net $net -objects $pin    
  }
  
  
  
  ########################################################################################
  # Updates a netlist by changing one reconfigurable module for other. The new module 
  # needs to be synthesized in a design check point (DCP) and to be saved in the SYNTHESIS 
  # folder located inside the project structure.
  #
  # Argument Usage:
  # partition_name: this refers to the name of the partition (and the reconfigurable cell) 
  #   where the new module will be added 
  # module_name: name of the new module that will be added to the netlist.
  #
  # Return Value:
  ########################################################################################
  proc change_module_of_reconfigurable_partition {partition_name module_name} {
    variable ::reconfiguration_tool::project_variables
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    set_property IS_ROUTE_FIXED 0 [get_nets -filter "IS_ROUTE_FIXED == 1"]
    route_design -unroute
    place_design -unplace
    update_design -cell [get_cells $partition_name] -black_box
    read_checkpoint -cell [get_cells $partition_name] ${directory}/${project_name}/SYNTHESIS/${partition_name}_${module_name}_reconfigurable_module.dcp
  }

}

