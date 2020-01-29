#ifndef IMPRESS_RECONFIGURATION_PARAMETERS 
#define IMPRESS_RECONFIGURATION_PARAMETERS

  #define INITIAL_ADDR_RAM                  0x11100000 //It is necessary to free the RAM contents from this address to store the PBS 
  #define MAX_WIDTH_VIRTUAL_ARCHITECTURE    1
  #define MAX_HEIGHT_VIRTUAL_ARCHITECTURE   2
  #define NUM_ELEMENTS                      2

  #define FINE_GRAIN                        1
  #if FINE_GRAIN
    #define MAX_CONSTANTS                   2
    #define MAX_MUXES                       2
    #define MAX_FU                          1
    #define MAX_BITS_PER_CONSTANT           8
    #define MAX_COLUMNS_CONSTANTS           1
    #define MAX_COLUMNS_MUX                 1
    #define MAX_COLUMNS_FU                  1
    #define MAX_COLUMN_OFFSETS              1
  #endif

#define MODULE_TOP			0
#define MODULE_BOTTOM		1

#endif
