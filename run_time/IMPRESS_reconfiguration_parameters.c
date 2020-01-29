#include "IMPRESS_reconfiguration.h"
// This array need to be initializated by the user with the different elements that can be
// allocated in the virtual architecture. An example is provided.
element_info_t elements[NUM_ELEMENTS] = {
  {
    .num_constants = 3,
    .constant_column_offset = {0, 0},
    .num_bits_in_constant = {10, 8, 5},
    .num_constant_columns = {5, 5},
    .num_muxes = 1,
    .mux_column_offset = {},
    .mux_data_width = {2},
    .mux_num_inputs = {3},
    .num_mux_columns = {2},
    .num_FU = 1,
    .FU_4_bit_blocks = {2},
    .FU_column_offset = {0},
    .num_FU_columns = {0},
    .PBS_name = "prueba.PBS",
    .size = {3,4}
  },
  {
    .num_constants = 2,
    .constant_column_offset = {0, 0},
    .num_bits_in_constant = {24, 16},
    .num_constant_columns = {0,0},
    .num_muxes = 1,
    .mux_column_offset = {},
    .mux_data_width = {3},
    .mux_num_inputs = {6},
    .num_mux_columns = {0},
    .num_FU = 1,
    .FU_4_bit_blocks = {2},
    .FU_column_offset = {0},
    .num_FU_columns = {0},
    .PBS_name = "prueba2.PBS",
    .size = {3,1}
  }
};

