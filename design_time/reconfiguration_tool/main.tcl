package require control
package require struct::set

namespace eval ::reconfiguration_tool {
  # Procs that can be used into other namespaces
  namespace export implement_reconfigurable_design

  ########################################################################################
  # Variables
  # project_variables: dict which contains variables regarding to the project. It has  
  #   the following fields.
  #     - project_name: Name of the project to be generated. It is used to create the  
  #       folder name where the outputs are generated and to name the ouput bitstreams. 
  #     - directory: directory where the outputs are going to be generated.
  #     - fpga_chip: contains the FPFA or SoC model 
  #     - ip_repositories: contains a list of all the user repositories that can be used  
  #       to search for IPs 
  variable project_variables
  # reconfigurable_module_list: list of dicts that contains the info of all the modules. 
  #   Each element of the list is a dict containing the following fields:
  #     - sources: list containng the path of all the sources of the module
  #     - module_name: name of the module. It is used to name the partial bitstreams  
  #     - partition_group_name: list of partitions where the module can be allocated 
  variable reconfigurable_module_list 
  # reconfigurable_partition_group_list: list of dict that contains the info of every 
  #   every reconfigurable partition type. A reconfigurable partition type is a group
  #   of equivalent partitions (i.e. partitions reallocable between them). Each 
  #   reconfigurable partition type is a dict containing the following fields: 
  #     - partition_group_name: name of the partition type. It is useful to name the 
  #       the PBS of all the modules that can be allocated in the partition type. 
  #     - interface: path of the file that describes the interface for all the partitions 
  #       that form the partition type. 
  #     - reconfigurable_partition_list: list of dicts. Each element is a dict that 
  #       contains the info of each partition that forms the partition type group. Each  
  #       element has the following fields:
  #         - partition_name: name of the partition. The cell in the static netlist that 
  #           is allocated in this partition needs to have the name of the partition. This 
  #           way the tool is able to find the cells in the static netlit that are going 
  #           to be reconfigured, convert them to black boxes if necessary and add to the 
  #           corresponding pblock. 
  #         - pblock: pblock definition of the partition in Xilinx or custom format
  #         - hierarchical_partition: indicates if the patition is inside another 
  #           partition. It contains another partition type name. A hierarchical partition
  #           contains one partition inside every partition of the parent partition type. 
  #           However it is only necessary (and mandatory for this tool) to define the 
  #           hierarchical partition that is included in the first partition defined 
  #           in the partition type.  
  #
  # NOTE: the reconfigurable_partition_group_list_static contain partition that are found 
  # in the static system while the reconfigurable_partition_group_list_reconfigurable 
  # contain the the partitions that are used by reconfigurable modules.  
  # reconfigurable_partition_group_list adopts the value of one of the other variables 
  # depending on which system is being implemented.
  variable reconfigurable_partition_group_list
  variable reconfigurable_partition_group_list_static
  variable reconfigurable_partition_group_list_reconfigurable
  # static_system_info: is a dict that contains info of the static system. It contains the 
  # following fields: 
  #   - no_placement_pblock_list: list of pblocks defined in the custom (i.e. XoYo:XfYf)
  #     or Xilinx format where the static system can NOT be placed. 
  #   - sources: list that contains all the sources of the static system
  variable static_system_info
  # global_nets_info: is a dict with the following format <partition_type> 
  #   <global_net_name> <global_resource_number>
  variable global_nets_info
  # The working directory contains the path where the script is stored. This is used to 
  # know the relative location of all the other files this script uses. 
  variable working_directory
  set working_directory [file dirname [info script]]
  ########################################################################################
  # Source files
  source [file join $working_directory input_output_documents.tcl]
  source [file join $working_directory design_reconstruction.tcl]
  source [file join $working_directory interface.tcl]
  source [file join $working_directory netlist.tcl]
  source [file join $working_directory place_and_route.tcl]
  source [file join $working_directory utils.tcl]
  source [file join $working_directory fine_grain_lut_placement.tcl]
  # Import namespaces
  namespace import ::reconfiguration_tool::input_output_documents::*
  namespace import ::reconfiguration_tool::design_reconstruction::*
  namespace import ::reconfiguration_tool::interface::*
  namespace import ::reconfiguration_tool::netlist::*
  namespace import ::reconfiguration_tool::place_and_route::*
  namespace import ::reconfiguration_tool::utils::*
  namespace import ::reconfiguration_tool::fine_grain_luts::*
  ########################################################################################
  
  ########################################################################################
  # Function that is called to implement a reconfigurable design specified in the project 
  # info file. 
  #
  # Argument Usage:
  # project_info_file: path to the project info file 
  #
  # Return Value:
  ########################################################################################
  proc implement_reconfigurable_design {project_info_file} {
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_static
    variable ::reconfiguration_tool::reconfigurable_partition_group_list_reconfigurable
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::static_system_info
    variable ::reconfiguration_tool::reconfigurable_module_list
    variable ::reconfiguration_tool::global_nets_info
    
    #We initialize the global variables 
    set project_variables ""
    set reconfigurable_module_list ""
    set reconfigurable_partition_group_list ""
    set static_system_info ""
    set global_nets_info ""
    
    
    # We parse the project info file and the virtual architecture.
    if {[catch {parse_virtual_architecture_and_project_info_files $project_info_file} errmsg]} {
      return $errmsg
    }

    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    
    create_empty_design
    
    if {$reconfigurable_partition_group_list_static ne $reconfigurable_partition_group_list_reconfigurable } {
      set different_virtual_architectures 1
    } else {
      set different_virtual_architectures 0
    }
  
    # We implement the static design
    set static_sources [dict get $static_system_info sources]
    if {[llength $static_sources] != 0} {
      set reconfigurable_partition_group_list $reconfigurable_partition_group_list_static
      analyze_virtual_architecture
      obtain_static_bitstream
    }

    # We implement the reconfigurable modules
    if {$different_virtual_architectures == 1} {
      set reconfigurable_partition_group_list $reconfigurable_partition_group_list_reconfigurable  
      analyze_virtual_architecture
    }
    foreach reconfigurable_module $reconfigurable_module_list {
      obtain_reconfigurable_bitstream $reconfigurable_module
    }
    
    clean_design
  }
  
  proc analyze_virtual_architecture {} {
    # We parse the interface file.
    if {[catch {obtain_interface_info} errmsg]} {
      log_error "ERROR -> $errmsg"
      return 
    }
    # We modify the pblocks format and analyze the resources in them. 
    obtain_xilinx_and_custom_pblocks_format
    obtain_max_DSP_and_RAM_for_reconfigurable_partitions
  }

  ########################################################################################
  # Implements the static bitstream defined in the project info file 
  #
  # Argument Usage:
  #
  # Return Value:
  ########################################################################################
  proc obtain_static_bitstream {} {
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::reconfigurable_partition_group_list

    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name]
    
    if {[catch create_static_netlist errmsg]} {
      log_error "ERROR -> module: static, type: $errmsg" static_system
      return 
    }
    
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      place_pblocks_reconfigurable_partition_type $reconfigurable_partition_group "static"
    }
    
    place_fine_grain_LUTs_static_system
    place_no_placement_static_pblocks
    
    foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
      set interface [dict get $reconfigurable_partition_group interface]
      if {$interface == ""} {
        create_interface $reconfigurable_partition_group
      }
      if {[catch {place_partition_pins $reconfigurable_partition_group "static"} errmsg]} {
        log_error "ERROR -> module: static, type: $errmsg" static_system
        return 
      }
    }
    if {[llength $reconfigurable_partition_group_list] > 0} {
      delete_duplicated_partition_pins
      add_global_buffers_to_static_system
      add_reconfigurable_dummy_logic
      opt_design
      if {[catch place_the_design errmsg]} {
        log_error "ERROR -> module: static, type: $errmsg" static_system
        return 
      } 
      if {[catch {route_design_with_fence static} errmsg]} {
        log_error "ERROR -> module: static, type: $errmsg" static_system
        return 
      }
    } else {
      opt_design
      place_design 
      route_design
    }
   
    
    write_checkpoint -force ${directory}/${project_name}/IMPLEMENTED/static_system
    if {[catch {generate_static_bitstream} errmsg]} {
      log_error "ERROR -> module: static, type: $errmsg" static_system
      return 
    }
    if {[llength $reconfigurable_partition_group_list] > 0} {
      save_static_dcp_for_hierarchical_reconstructions
    }
    log_success "SUCCESS: static module"
    
  }

  ########################################################################################
  # Implements a reconfigurable module 
  #
  # Argument Usage:
  # reconfigurable_module: reconfigurable module that will be implemented. 
  #
  # Return Value:
  ########################################################################################
  proc obtain_reconfigurable_bitstream {reconfigurable_module} {
    variable ::reconfiguration_tool::project_variables
    variable ::reconfiguration_tool::reconfigurable_partition_group_list
    
    set directory [dict get $project_variables directory]
    set project_name [dict get $project_variables project_name] 
    synthesize_reconfigurable_module $reconfigurable_module
    set module_name [dict get $reconfigurable_module module_name]
    set partition_group_name_list [dict get $reconfigurable_module partition_group_name_list] 
    foreach partition_group_name $partition_group_name_list {
      # We loop into all the reconfigurable partitions in order to find the 
      # reconfigurable_partition_group with the name partition_group_name
      foreach reconfigurable_partition_group $reconfigurable_partition_group_list {
        if {[dict get $reconfigurable_partition_group partition_group_name] == $partition_group_name} {
          break 
        }
      }
      create_reconfigurable_netlist $reconfigurable_partition_group $module_name
      place_pblocks_reconfigurable_partition_type $reconfigurable_partition_group "reconfigurable"
      if {[catch {place_partition_pins $reconfigurable_partition_group "reconfigurable"} errmsg]} {
        log_error "ERROR -> partition: ${partition_group_name}, module: ${module_name}, type: $errmsg" ${partition_group_name}_${module_name}
        continue 
      }

      add_global_buffers_to_reconfigurable_partition $reconfigurable_partition_group
      add_static_dummy_logic $reconfigurable_partition_group
      add_hierarchical_reconfigurable_dummy_logic $reconfigurable_partition_group
      place_fine_grain_LUTs_reconfigurable_partition $reconfigurable_partition_group
      opt_design
      if {[catch place_the_design errmsg]} {
        log_error "ERROR -> partition: ${partition_group_name}, module: ${module_name}, type: $errmsg" ${partition_group_name}_${module_name}
        continue 
      }
      
      if {[catch {route_design_with_fence reconfigurable} errmsg]} {
        log_error "ERROR -> partition: ${partition_group_name}, module: ${module_name}, type: $errmsg" ${partition_group_name}_${module_name}
        continue 
      }
      write_reconfigurable_checkpoint $partition_group_name $module_name 
      if {[catch {generate_reconfigurable_bitstream $reconfigurable_partition_group $module_name} errmsg]} {
        log_error "ERROR -> partition: ${partition_group_name}, module: ${module_name}, type: $errmsg" ${partition_group_name}_${module_name}
        continue 
      }
      # In design with encrypted IPs the design reconstruction can not be done as it is  
      # not possible modify the netlist to remove route through LUTs. Therefore, we 
      # don't consider an error if this happens but we notify the user. 
      set design_reconstruction_log ""
      if {[catch {extract_hierarchical_cell_info $reconfigurable_partition_group $module_name} errmsg]} {
        set design_reconstruction_log "NOTE: Design reconstruction information could not be obtained"
      }
      
      log_success "SUCCESS: partition: ${partition_group_name}, module: ${module_name}. $design_reconstruction_log"
    }
  }
}
