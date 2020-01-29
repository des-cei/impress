#ifndef IMPRESS_RECONFIGURATION_PARAMETERS 
#define IMPRESS_RECONFIGURATION_PARAMETERS

  #define MAX_WIDTH_VIRTUAL_ARCHITECTURE    1
  #define MAX_HEIGHT_VIRTUAL_ARCHITECTURE   1
  #define NUM_ELEMENTS                      1
  #define INITIAL_ADDR_RAM                  0x11100000 //It is necessary to free the RAM contents from this address to store the PBS 
  
  #define FINE_GRAIN                         1
  #if FINE_GRAIN
    #define MAX_CONSTANTS                    0
    #define MAX_MUXES                        0
    #define MAX_FU                           1
    #define MAX_BITS_PER_CONSTANT            0
    #define MAX_COLUMNS_CONSTANTS            0
    #define MAX_COLUMNS_MUX                  0
    #define MAX_COLUMNS_FU                   1
    #define MAX_COLUMN_OFFSETS               2
  #endif

#endif