##########################################################################################
# This library provides functions dealing with input file parsing and output file
# generation. This library does not deal with interfice files.
#
# This library uses the variables: project_variables, reconfigurable_module_list, 
# reconfigurable_partition_group_list, static_system_info, global_nets_info and 
# working_directory of the parent namespace (i.e. ::reconfiguration_tool).
##########################################################################################

namespace eval ::reconfiguration_tool::input_output_documents {
  # Procs that can be used into other namespaces
  namespace export parse_virtual_architecture_and_project_info_files
  namespace export write_reconfigurable_checkpoint
  namespace export generate_static_bitstream
  namespace export generate_reconfigurable_bitstream

  ########################################################################################
  # Parses both project info and virtual arquitecture files and saves the information in 
  # variables given by the user. 
  #
  # Argument Usage:
  # project_info_file: path containing the project info file
  #
  # Return Value:
  # none or error 
  ########################################################################################   
  proc parse_virtual_architecture_and_project_info_files {project_info_file} {

    variable ::reconfiguration_tool::project_variables 
    variable ::reconfiguration_tool::reconfigurable_module_list
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_static
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_reconfigurable
    variable ::reconfiguration_tool::static_system_info

    set local [file dirname $project_info_file]

    #We clear the variables where all the info is going to be saved 
    set project_variables [dict create]
    set non_reconfigurable_files [list]
    set reconfigurable_module_list [list]
    set reconfigurable_partition_group_list_static [list]
    set reconfigurable_partition_group_list_reconfigurable [list]
    set static_system_info [dict create]
    
    dict set static_system_info sources {}
    dict set static_system_info no_placement_pblock_list {}
  
    set fileId [open $project_info_file r]
    while {[gets $fileId line] != -1} {
      set line [string trim $line]
      switch -exact -- $line {
        project_variables {
          set ip_repositories {}
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_project_variables"} {
            regexp {(\S+)\s+=\s+(.+)} $line -> type name
            switch -exact -- $type {
              project_name {
                set name [string trimright $name "\\ /"]
                dict set project_variables project_name [subst $name]
              }
              directory {
                set name [string trimright $name "\\ /"]
                dict set project_variables directory [subst $name]
              }
              fpga_chip {
                dict set project_variables fpga_chip [subst $name]
              }
              ip_repository {
                lappend ip_repositories [subst $name]
              }
              default {}
            }
            if {[gets $fileId line] == -1} {
              error "Error parsing project info file end_project_variables not found"
            }
            set line [string trim $line]
          }
          dict set project_variables ip_repositories $ip_repositories
        }
        static_system {
          set sources {}
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_static_system"} {
            regexp {(\S+)\s+=\s+(.+)} $line -> type name
            switch -exact -- $type {
              sources {
                set sources [concat $sources [subst $name]]
              } 
              virtual_architecture {
                parse_virtual_architecture_file [subst $name] "static"
                # set sources ""
                # while {$line != "end_virtual_architecture"} {
                #   regexp {(\S+)\s+=\s+(.+)} $line -> type name
                #   switch -exact -- $type {
                #     sources {
                #       set sources [subst $name]
                #     }
                #     default {}
                #   }
                #   if {[gets $fileId line] == -1} {
                #     error "Error parsing project info file end_virtual_architecture not found"
                #   }
                #   set line [string trim $line]
                # }
                # parse_virtual_architecture_file $sources static
              }
              default {}
            }
            if {[gets $fileId line] == -1} {
              error "Error parsing project info file end_static_sources not found"
            }
            set line [string trim $line]
          }
          dict set static_system_info sources $sources
        }
        reconfigurable_modules {
          set reconfigurable_module_list [list]
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_reconfigurable_modules"} {
            if {[regexp {(\S+)\s+=\s+(.+)} $line -> type name] == 0} {
              set type [string trim $line]
            }
            switch -exact -- $type {
              reconfigurable_module {
                set sources {}
                set module_name {}
                set partition_group_name_list ""
                while {$line != "end_reconfigurable_module"} {
                  regexp {(\S+)\s+=\s+(.+)} $line -> type name
                  switch -exact -- $type {
                    module_name {
                      set module_name [subst $name]
                    }
                    sources {
                      set sources [concat $sources [subst $name]]
                    }
                    partition_group_name {
                      set partition_group_name_list [concat $partition_group_name_list [subst $name]]
                    }
                    default {}
                  }
                  if {[gets $fileId line] == -1} {
                    error "Error parsing project info file end_reconfigurable_module not found"
                  }
                  set line [string trim $line]
                }
                set dict_recofigurable_module [dict create module_name $module_name sources $sources partition_group_name_list $partition_group_name_list]
                lappend reconfigurable_module_list $dict_recofigurable_module
              }
              virtual_architecture {
                parse_virtual_architecture_file [subst $name] "reconfigurable"
                # set sources ""
                # while {$line != "end_virtual_architecture"} {
                #   regexp {(\S+)\s+=\s+(.+)} $line -> type name
                #   switch -exact -- $type {
                #     sources {
                #       set sources [subst $name]
                #     }
                #     default {}
                #   }
                #   if {[gets $fileId line] == -1} {
                #     error "Error parsing project info file end_virtual_architecture not found"
                #   }
                #   set line [string trim $line]
                # }
                # parse_virtual_architecture_file $sources reconfigurable 
              }
              default {}
            }
            if {[gets $fileId line] == -1} {
              error "Error parsing project info file end_reconfigurable_modules not found"
            }
            set line [string trim $line]
          }  
        }
        default {puts $line}
      }
    }
    close $fileId 
    modify_reconfigurable_module_list_all_partitions 
  } 
  
  ########################################################################################
  # This function checks if any module is meant to be reconfigured in all the possible 
  # partitions and changes the string all_partitions to the name of all the partitions.
  ########################################################################################
  proc modify_reconfigurable_module_list_all_partitions {} {
    variable ::reconfiguration_tool::reconfigurable_module_list
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_reconfigurable 
    
    set new_reconfigurable_module_list {}
    foreach reconfigurable_module $reconfigurable_module_list {
      set partition_group_name_list [dict get $reconfigurable_module partition_group_name_list]
      if {$partition_group_name_list == "all_partitions"} {
        set new_partition_group_name_list {}
        foreach reconfigurable_partition  $reconfigurable_partition_group_list_reconfigurable {
          set new_partition_group_name_list [concat $new_partition_group_name_list [dict get $reconfigurable_partition partition_group_name]]
        }
        set reconfigurable_module [dict replace $reconfigurable_module partition_group_name_list $new_partition_group_name_list]
      }
      lappend new_reconfigurable_module_list $reconfigurable_module 
    }
    set reconfigurable_module_list $new_reconfigurable_module_list
  }

  ########################################################################################
  # Parses virtual architecture file and saves information in variables 
  #
  # Argument Usage:
  # virtual_architecture_file: path of the file containing the virtual architecture info
  #
  # Return Value:
  # none or error 
  ########################################################################################
  proc parse_virtual_architecture_file {virtual_architecture_file system_type} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_static
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_reconfigurable
    variable ::reconfiguration_tool::static_system_info
    
    set local [file dirname $virtual_architecture_file]

    set fileId [open $virtual_architecture_file r]
    while {[gets $fileId line] != -1} {
      set line [string trim $line]
      switch -exact -- $line {
        reconfigurable_partition_group {
          set partition_group_name {}
          set interface {}
          set reconfigurable_partition_list {}
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_reconfigurable_partition_group"} {
            if {[regexp {(\S+)\s+=\s+(.+)} $line -> type name] == 0} {
              set type [string trim $line]
            }
            switch $type {
              partition_group_name {
                set partition_group_name [subst $name]
              }
              interface {
                set interface [subst $name]
              }
              reconfigurable_partition {
                set partition_name ""
                set pblock_list ""
                set hierarchical_partition_list ""
                while {$line != "end_reconfigurable_partition"} {
                  regexp {(\S+)\s+=\s+(.+)} $line -> type name
                  switch -exact -- $type {
                    partition_name {
                      set partition_name [subst $name]
                    }
                    pblock {
                      lappend pblock_list [subst $name]
                    }
                    hierarchical_partition {
                      set hierarchical_partition_list [concat $hierarchical_partition_list [subst $name]]
                    }
                    default {}
                  }
                  if {[gets $fileId line] == -1} {
                    error "Error parsing project info file end_reconfigurable_partition not found"
                  }
                  set line [string trim $line]
                }
                set dict_reconfigurable_partition [dict create pblock_list $pblock_list partition_name $partition_name hierarchical_partition_list $hierarchical_partition_list]
                lappend reconfigurable_partition_list $dict_reconfigurable_partition
              }
              default {}
            }
            if {[gets $fileId line] == -1} {
              error "Error parsing project info file end_reconfigurable_partition_group not found"
            }
            set line [string trim $line]
          }
          set dict_reconfigurable_partition [dict create partition_group_name $partition_group_name reconfigurable_partition_list $reconfigurable_partition_list interface $interface]
          if {$system_type == "static"} {
            lappend reconfigurable_partition_group_list_static $dict_reconfigurable_partition
          } else {
            lappend reconfigurable_partition_group_list_reconfigurable $dict_reconfigurable_partition
          }
        }
        static_system_no_placement_pblocks {
          set no_placement_pblock_list ""
          gets $fileId line
          set line [string trim $line]
          while {$line != "end_static_system_no_placement_pblocks"} {
            if {[regexp {(\S+)\s+=\s+(.+)} $line -> type name] == 0} {
              set type [string trim $line]
            }
            switch $type {
              no_placement_pblock {
                set no_placement_pblock_list [concat $no_placement_pblock_list [subst $name]]
              }
              default {}
            }
            if {[gets $fileId line] == -1} {
              error "Error parsing project info file end_reconfigurable_partition not found"
            }
            set line [string trim $line]
          }
          dict set static_system_info no_placement_pblock_list $no_placement_pblock_list 
        }
        default {}
      }
    }
    close $fileId 
  }

  ########################################################################################
  # Writes a checkpoint of a reconfigurable module.
  # 
  # Argument Usage:
  # partition_group_name: name of the group of the relocatable reconfigurable partitions.
  #   This variable is used in the name to the checkpoint
  # module_name: name of the implemented module. This variable is used in the 
  #   name of the checkpoint
  #   
  # Return Value:
  ########################################################################################
  proc write_reconfigurable_checkpoint {partition_group_name module_name} {
    variable ::reconfiguration_tool::project_variables
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    write_checkpoint ${directory}/${project_name}/IMPLEMENTED/${partition_group_name}_${module_name}
  }

  ########################################################################################
  # Generates the bitstream of the static system once it is implemented.
  #
  # Argument Usage: 
  # Return Value:
  # none or error 
  ########################################################################################
  proc generate_static_bitstream {} {
    variable ::reconfiguration_tool::project_variables
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    if {[catch {write_bitstream -force ${directory}/${project_name}/BITSTREAMS/static} errmsg]} {
      error "error generating bitstream"
    }
    write_debug_probes -quiet ${directory}/${project_name}/BITSTREAMS/static_probes
  }

  ########################################################################################
  # Generates the bitstream of a reconfigurable module once it is implemented.
  #
  # Argument Usage:
  # reconfigurable_partition_group: element of the variable 
  #   reconfigurable_partition_group_list that containf the info of a reconfigurable
  #   partition group 
  # module_name: name of the implemented module. This variable is used in the 
  #   name of the checkpoint
  #
  # Return Value:
  # none or error
  ########################################################################################
  proc generate_reconfigurable_bitstream {reconfigurable_partition_group module_name} {
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::working_directory
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    set reconfigurable_partition_list [dict get $reconfigurable_partition_group reconfigurable_partition_list]
    set reconfigurable_partition_reference [lindex $reconfigurable_partition_list 0]
    set pblock_list [dict get $reconfigurable_partition_reference custom_format_pblock_list]
    set partition_group_name [dict get $reconfigurable_partition_group partition_group_name]
    set pblock [lindex $pblock_list 0]
    file mkdir ${directory}/${project_name}/BITSTREAMS_TEMP
    set bitstream_file ${directory}/${project_name}/BITSTREAMS_TEMP/${partition_group_name}_${module_name}.bit
    set partial_bitstream_file ${directory}/${project_name}/BITSTREAMS/${partition_group_name}_${module_name}.pbs
    if {[catch {write_bitstream -no_partial_bitfile -force $bitstream_file} errmsg]} {
      error "error generating bitstream"
    }
    exec python [file join $working_directory "auxiliary_tools" "generate_partial_bitstream.py"] $bitstream_file $pblock $partial_bitstream_file
    file delete -force ${directory}/${project_name}/BITSTREAMS_TEMP
  }

}

