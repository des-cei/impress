#include "IMPRESS_reconfiguration.h"
// This array need to be initializated by the user with the different elements that can be
// allocated in the virtual architecture. An example is provided.
element_info_t elements[NUM_ELEMENTS] = {
  {
    .PBS_name = "group1_add.pbs",
    .size = {6,32}
  },
  {
    .PBS_name = "group1_substract.pbs",
    .size = {6,32}
  },
  {
    .PBS_name = "group1_multiply.pbs",
    .size = {6,32}
  }
};

