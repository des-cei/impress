#include "IMPRESS_reconfiguration.h"
// This array need to be initializated by the user with the different elements that can be
// allocated in the virtual architecture. An example is provided.
element_info_t elements[NUM_ELEMENTS] = {
  {
    .num_constants = 2,
    .constant_column_offset = {0, 0},
    .num_bits_in_constant = {8, 8},
    .num_constant_columns = {0, 0},
    .num_muxes = 2,
    .mux_column_offset = {0, 0},
    .mux_data_width = {8, 8},
    .mux_num_inputs = {2, 2},
    .num_mux_columns = {0, 0},
    .num_FU = 1,
    .FU_4_bit_blocks = {2},
    .FU_column_offset = {0},
    .num_FU_columns = {0},
    .PBS_name = "group1_top_module.pbs",
    .size = {6, 16}
  },
  {
    .num_constants = 2,
    .constant_column_offset = {0, 0},
    .num_bits_in_constant = {8, 8},
    .num_constant_columns = {0, 0},
    .num_muxes = 1,
    .mux_column_offset = {0},
    .mux_data_width = {8},
    .mux_num_inputs = {2},
    .num_mux_columns = {0},
    .num_FU = 1,
    .FU_4_bit_blocks = {2},
    .FU_column_offset = {0},
    .num_FU_columns = {0},
    .PBS_name = "group2_bottom_module.pbs",
    .size = {6, 16}
  }
};



