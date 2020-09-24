#include <stdint.h> 
#include "IMPRESS_reconfiguration.h"
#include "series7.h"
#include "xc7z020.h"
#include "reconfig_pcap.h"
#include "xparameters.h"
#include <xstatus.h>
#include "xtime_l.h"
#include <stdio.h>

#if FINE_GRAIN
#define SEARCH_IF_FINE_GRAIN_VALUE_HAS_CHANGED		0
/*Constant declaration*/
#define ICAP_CTRL_BASEADDR  XPAR_FINE_GRAIN_RE_0_S_CTRL_BASEADDR
#define ICAP_MEM_BASEADDR   XPAR_FINE_GRAIN_RE_0_S_MEM_BASEADDR
#define ICAP_MEM_HIGHADDR   XPAR_FINE_GRAIN_RE_0_S_MEM_HIGHADDR
#if ICAP_CTRL_BASEADDR==0xFFFFFFFF || ICAP_CTRL_BASEADDR==0xFFFFFFFFFFFFFFFF
#error XPAR_FAST_ICAP_SYSARR_0_S_CTRL_BASEADDR not set; \
please set ICAP_CTRL_BASEADDR manually
#endif

#define ICAP ((volatile unsigned int *) ICAP_CTRL_BASEADDR)
#endif

#define PCAP_ID 						                XPAR_XDCFG_0_DEVICE_ID

#define BITS_PER_LUT                        2
#define MINOR_COLUMN_SLICE_L_1              32
#define MINOR_COLUMN_SLICE_L_2              26
#define MINOR_COLUMN_SLICE_M_1              34
#define MINOR_COLUMN_SLICE_M_2              26
#define X_POS                               0
#define Y_POS                               1
#define WIDTH_POS                           0
#define HEIGHT_POS                          1
#define RECONFIGURE_FRAME                   1
#define DO_NOT_RECONFIGURE_FRAME            0
#define CONST_TYPE                          0 
#define MUX_TYPE                            1
#define FU_TYPE                             2
#define WORDS_PER_CONSTANTS                 13
#define WORDS_PER_MUX                       13
#define WORDS_PER_FU                        5
#define LUTS_PER_CLB						4

typedef struct {
  uint32_t frame_address;
  // Each frame is defined with 400 bits and therefore has 13 words
  uint32_t value[WORDS_PER_CONSTANTS];
} frame_constant_t;

typedef struct {
  uint32_t frame_address;
  // Each frame has 50 four-bit blocks. For each block we need to define it with 2 bit
  // therefore we need 4 words to send to the fine grain RE.
  uint32_t value[WORDS_PER_MUX];
} frame_mux_t;

typedef struct {
  uint32_t frame_address;
  uint32_t value[WORDS_PER_FU];
} frame_FU_t;


/* Function declarations*/
static void update_partition_location_info(virtual_architecture_t *virtual_architecture, int x, int y);
static int init_PCAP();
#if FINE_GRAIN
static void init_num_constant_columns_elements();
static void init_num_mux_columns_elements();
static void init_num_FU_columns_elements();
static void init_constant_frames();
static void init_mux_frames();
static void init_FU_frames();
static uint32_t obtain_frame_address_of_CLB_column(virtual_architecture_t *virtual_architecture, int x, int y, int clock_row_number, int column_number);
static void change_constant_frame_address(uint32_t frame_address_position, int first_bit, int last_bit, int previous_bits_sent, uint32_t *value);
static void change_mux_frame_address(uint32_t frame_address_position, int first_LUT, int last_LUT, int value, int LUT_position, int num_inputs);
static void change_FU_frame_address(uint32_t frame_address_position, int first_block, int last_block, int value);
static int obtain_CLB_minor_column(int row, int column, int num_slice);
static int is_column_CLB_type(int row, int column);
static void reset_fine_grain_elements(virtual_architecture_t *virtual_architecture, int x, int y);
static void find_number_of_fine_grain_blocks();
static int calculate_constant_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset);
static int calculate_mux_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset);
static int calculate_FU_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset);
static uint16_t get_PBS_2_bits(int bits);
static void load_constant_PBS();
static void load_mux_PBS();
static void load_FU();
static void load_fine_grain_PBS();
static uint32_t obtain_XFAR(uint32_t element_type, uint32_t num_frames, uint32_t frame_address);
static int LUTs_in_mux(int data_width, int num_inputs);
static void enable_ICAP();
static int update_partition_fine_grain_info(virtual_architecture_t *virtual_architecture, int x, int y);
static void reconfigure_constants();
static void reconfigure_muxes();
static void reconfigure_FU();
#endif

/*Global variables*/
static XDcfg xCAP_component;
#if FINE_GRAIN
static frame_constant_t constant_t_frames[MAX_COLUMNS_CONSTANTS]; //__attribute__((section(".OCM.data")));
static int8_t constant_frames_flags[MAX_COLUMNS_CONSTANTS];
static frame_mux_t mux_t_frames[MAX_COLUMNS_MUX];
static int8_t mux_frames_flags[MAX_COLUMNS_MUX];
static frame_FU_t  FU_t_frames[MAX_COLUMNS_FU];
static int8_t FU_frames_flags[MAX_COLUMNS_FU];
#endif
/* Function definitions*/
void init_virtual_architecture() {
  init_PCAP();
  #if FINE_GRAIN
  find_number_of_fine_grain_blocks();
  init_constant_frames();
  init_mux_frames();
  init_FU_frames();
  init_num_constant_columns_elements();
  init_num_mux_columns_elements();
  init_num_FU_columns_elements();
  load_fine_grain_PBS();
  #endif
}

static int init_PCAP() {
  int status;
  
  status = PCAP_Initialize(&xCAP_component, PCAP_ID);
  if (status != XST_SUCCESS) {
    return XST_FAILURE;
  }
  
  return XST_SUCCESS;
}



static void enable_PCAP() {
  XDcfg_SelectPcapInterface(&xCAP_component);
}

/*
* NOTE en la definicion de la funcion explicar que de momento no se elimina la info de las columnas y constantes pero que podría ser interesante para un futuro.
*/
int change_partition_element(virtual_architecture_t *virtual_architecture, int x, int y, int element_info) {
  int status;
  pblock pblock_1;
  
  if (virtual_architecture->partition[x][y].element.element_info == &elements[element_info]) {
    return XST_SUCCESS;
  } else if (element_info == -1) {
    //We can use this command to invalidate a partition. This can be used for example when other partition overwrite in the location of this partition
    virtual_architecture->partition[x][y].element.element_info = NULL;
    return XST_SUCCESS;
  }
  
  virtual_architecture->partition[x][y].element.element_info = &elements[element_info];
  
  char *filename = virtual_architecture->partition[x][y].element.element_info->PBS_name;
  
  update_partition_location_info(virtual_architecture, x, y);
  
  #if FINE_GRAIN
    update_partition_fine_grain_info(virtual_architecture, x, y);
    reset_fine_grain_elements(virtual_architecture, x, y);
  #endif
  
  pblock_1.X0 = virtual_architecture->partition[x][y].position[X_POS];
  pblock_1.Y0 = virtual_architecture->partition[x][y].position[Y_POS];
  pblock_1.Xf = virtual_architecture->partition[x][y].position[X_POS] + virtual_architecture->partition[x][y].element.element_info->size[WIDTH_POS] - 1;
  pblock_1.Yf = virtual_architecture->partition[x][y].position[Y_POS] + virtual_architecture->partition[x][y].element.element_info->size[HEIGHT_POS] - 1;
  
  enable_PCAP();
  status = write_subclock_region_PBS(&xCAP_component, (u32*) INITIAL_ADDR_RAM, filename, &pblock_1, 1, 0, 0);
  
  return status;
}


int change_partition_element_stacked_modules(virtual_architecture_t *virtual_architecture, int x, int y, int element_info, u8 first_module, u8 last_module) {
  int status;
  pblock pblock_1;
  u8 stacked_modules;

  if (virtual_architecture->partition[x][y].element.element_info == &elements[element_info]) {
	  return XST_SUCCESS;
  } else if (element_info == -1) {
	  //We can use this command to invalidate a partition. This can be used for example when other partition overwrite in the location of this partition
	  virtual_architecture->partition[x][y].element.element_info = NULL;
	  return XST_SUCCESS;
  }

  virtual_architecture->partition[x][y].element.element_info = &elements[element_info];

  char *filename = virtual_architecture->partition[x][y].element.element_info->PBS_name;

  update_partition_location_info(virtual_architecture, x, y);

  #if FINE_GRAIN
    update_partition_fine_grain_info(virtual_architecture, x, y);
    reset_fine_grain_elements(virtual_architecture, x, y);
  #endif

  pblock_1.X0 = virtual_architecture->partition[x][y].position[X_POS];
  pblock_1.Y0 = virtual_architecture->partition[x][y].position[Y_POS];
  pblock_1.Xf = virtual_architecture->partition[x][y].position[X_POS] + virtual_architecture->partition[x][y].element.element_info->size[WIDTH_POS] - 1;
  pblock_1.Yf = virtual_architecture->partition[x][y].position[Y_POS] + virtual_architecture->partition[x][y].element.element_info->size[HEIGHT_POS] - 1;

  enable_PCAP();
  if (first_module == 1 && last_module == 0) {
	  stacked_modules = 1;
  } else if (first_module == 0 && last_module == 0) {
	  stacked_modules = 2;
  } else if (first_module == 0 && last_module == 1) {
	  stacked_modules = 3;
  } else {
	  stacked_modules = 0;
  }
  status = write_subclock_region_PBS(&xCAP_component, (u32*) INITIAL_ADDR_RAM, filename, &pblock_1, 1, 0, stacked_modules);

  return status;
}

void change_partition_position(virtual_architecture_t *virtual_architecture, int x, int y, int position_x, int position_y) {
  virtual_architecture->partition[x][y].element.element_info = NULL;
  virtual_architecture->partition[x][y].position[X_POS] = position_x;
  virtual_architecture->partition[x][y].position[Y_POS] = position_y;
  update_partition_location_info(virtual_architecture, x, y);
}

static void update_partition_location_info(virtual_architecture_t *virtual_architecture, int x, int y) {
  int partition_x, partition_y, partition_size_x, partition_size_y;
  
  partition_x = virtual_architecture->partition[x][y].position[X_POS];
  partition_y = virtual_architecture->partition[x][y].position[Y_POS];
  partition_size_x = virtual_architecture->partition[x][y].element.element_info->size[WIDTH_POS];
  partition_size_y = virtual_architecture->partition[x][y].element.element_info->size[HEIGHT_POS];
  
  virtual_architecture->partition[x][y].location_info.first_row = partition_y / ROWS_PER_CLOCK_REGION;
  virtual_architecture->partition[x][y].location_info.last_row = (partition_y + partition_size_y - 1) / ROWS_PER_CLOCK_REGION;
  virtual_architecture->partition[x][y].location_info.first_column = partition_x;
  virtual_architecture->partition[x][y].location_info.last_column = partition_x + partition_size_x - 1;
}


#if FINE_GRAIN

  static void enable_ICAP() {
    XDcfg_SelectIcapInterface(&xCAP_component);
  }

  /*
  * TODO in this first version the midle+fine grain support is only possible with blocks
  * completely contained in a clock region row (it can not cross vertical clock regions)
  * if a PR is bigger than a clock region it must occupy the full heigh of the lowest
  * clock region row.
  * NOTE for the next version it could be possible to use the pblock parameter even in the
  * RP and therefore have pblocks inside pblocks. Para esto lo que podemos hacer es guardar los 2 pblocks
  * el original y el de grano fino y con los 2 sacar el tamaño del pblock y la ubicacion de las constantes.
  * En la proxima version permitir cualquier combinacion.
  */

  static void init_constant_frames() {
    int i, j;
    for (i = 0; i < MAX_COLUMNS_CONSTANTS; i++) {
      constant_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
      constant_t_frames[i].frame_address = 0;
      for (j = 0; j < WORDS_PER_CONSTANTS; j++) {
        constant_t_frames[i].value[j] = 0;
      }
    }
  }

  static void init_mux_frames() {
    int i, j;
    for (i = 0; i < MAX_COLUMNS_MUX; i++) {
      mux_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
      mux_t_frames[i].frame_address = 0;
      for (j = 0; j < WORDS_PER_MUX; j++) {
        mux_t_frames[i].value[j] = 0;
      }
    }
  }

  static void init_FU_frames() {
    int i, j;
    for (i = 0; i < MAX_COLUMNS_FU; i++) {
      FU_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
      FU_t_frames[i].frame_address = 0;
      for (j = 0; j < WORDS_PER_FU; j++) {
        FU_t_frames[i].value[j] = 0;
      }
    }
  }

  static void init_num_constant_columns_elements() {
    int i, j, k, num_bits, height_fine_grain, num_blocks;
    int *offset_in_blocks;
    
    for (i = 0; i < NUM_ELEMENTS; i++) {
      num_blocks = elements[i].num_blocks;
      offset_in_blocks = elements[i].offset_blocks;
      for (j = 0; j < num_blocks; j++) {
        num_bits = 0;
        for (k = 0; k < elements[i].num_constants; k++) {
          if (elements[i].constant_column_offset[k] == offset_in_blocks[j]) {
            // If num_constant_columns is already populated we skip this block 
            if (elements[i].num_constant_columns[k] != PREDEFINED_NUM_COLUMNS) break; 
            num_bits += elements[i].num_bits_in_constant[k];
          }
        }
        if (num_bits != 0) {
          height_fine_grain = elements[i].size[HEIGHT_POS];
          for (k = 0; k < elements[i].num_constants; k++) {
            if (elements[i].constant_column_offset[k] == offset_in_blocks[j]) {
              elements[i].num_constant_columns[k] = ((num_bits - 1) / (height_fine_grain * LUTS_PER_CLB * BITS_PER_LUT) + 1);
            }
          }          
        }
      }
    }
  }


  static void init_num_mux_columns_elements() {
    int i, j, k, num_LUTs, height_fine_grain, num_blocks;
    int *offset_in_blocks;
    
    for (i = 0; i < NUM_ELEMENTS; i++) {
      num_blocks = elements[i].num_blocks;
      offset_in_blocks = elements[i].offset_blocks;
      for (j = 0; j < num_blocks; j++) {
        num_LUTs = 0;
        for (k = 0; k < elements[i].num_muxes; k++) {
          if (elements[i].mux_column_offset[k] == offset_in_blocks[j]) {
            // If num_mux_columns is already populated we skip this block 
            if (elements[i].num_mux_columns[k] != PREDEFINED_NUM_COLUMNS) break; 
            num_LUTs += LUTs_in_mux(elements[i].mux_data_width[k], elements[i].mux_num_inputs[k]);
          }
        }
        if (num_LUTs != 0) {
          height_fine_grain = elements[i].size[HEIGHT_POS];
          for (k = 0; k < elements[i].num_muxes; k++) {
            if (elements[i].mux_column_offset[k] == offset_in_blocks[j]) {
              elements[i].num_mux_columns[k] = ((num_LUTs - 1) / (height_fine_grain * LUTS_PER_CLB) + 1);
            }
          }          
        }
      }
    }
  }

  static void init_num_FU_columns_elements() {
    int i, j, k, num_LUTs, height_fine_grain, num_blocks;
    int *offset_in_blocks;
    
    for (i = 0; i < NUM_ELEMENTS; i++) {
      num_blocks = elements[i].num_blocks;
      offset_in_blocks = elements[i].offset_blocks;
      for (j = 0; j < num_blocks; j++) {
        num_LUTs = 0;
        for (k = 0; k < elements[i].num_FU; k++) {
          if (elements[i].FU_column_offset[k] == offset_in_blocks[j]) {
            // If num_FU_columns is already populated we skip this block 
            if (elements[i].num_FU_columns[k] != PREDEFINED_NUM_COLUMNS) break; 
            num_LUTs += elements[i].FU_4_bit_blocks[k]*4*2; //8 LUTs per 4-bit block
          }
        }
        if (num_LUTs != 0) {
          height_fine_grain = elements[i].size[HEIGHT_POS];
          for (k = 0; k < elements[i].num_FU; k++) {
            if (elements[i].FU_column_offset[k] == offset_in_blocks[j]) {
              elements[i].num_FU_columns[k] = ((num_LUTs - 1) / (height_fine_grain * LUTS_PER_CLB) + 1);
            }
          }          
        }
      }
    }
  }

  void add_fine_grain_static_region(virtual_architecture_t *virtual_architecture, int x, int y, int element_info) {
    
    virtual_architecture->partition[x][y].element.element_info = &elements[element_info];
    update_partition_location_info(virtual_architecture, x, y);
    update_partition_fine_grain_info(virtual_architecture, x, y);
    reset_fine_grain_elements(virtual_architecture, x, y);
  }


  static int update_partition_fine_grain_info(virtual_architecture_t *virtual_architecture, int x, int y) {
    int i;
    int height_fine_grain, first_row, last_row;
    int column_number;
    int first_clock_row, last_clock_row;
    int num_blocks;
    int *offset_in_blocks;
    int status;
    
    height_fine_grain = virtual_architecture->partition[x][y].element.element_info->size[HEIGHT_POS];
    first_clock_row = virtual_architecture->partition[x][y].position[Y_POS] / ROWS_PER_CLOCK_REGION;
    last_clock_row = (virtual_architecture->partition[x][y].position[Y_POS] + height_fine_grain - 1) / ROWS_PER_CLOCK_REGION;
    first_row = virtual_architecture->partition[x][y].position[Y_POS] % ROWS_PER_CLOCK_REGION;
    last_row = (virtual_architecture->partition[x][y].position[Y_POS] + height_fine_grain - 1) % ROWS_PER_CLOCK_REGION;
    
    num_blocks = virtual_architecture->partition[x][y].element.element_info->num_blocks;
    offset_in_blocks = virtual_architecture->partition[x][y].element.element_info->offset_blocks;
    
    for (i = 0; i < num_blocks; i++) {
      column_number = offset_in_blocks[i];
      status = calculate_constant_parameters(virtual_architecture, x, y, first_clock_row, last_clock_row, first_row, last_row, &column_number, offset_in_blocks[i]);
      if (status == -1) {
        return -1;
      }
      status = calculate_mux_parameters(virtual_architecture, x, y, first_clock_row, last_clock_row, first_row, last_row, &column_number, offset_in_blocks[i]);
      if (status == -1) {
        return -1;
      }
      status = calculate_FU_parameters(virtual_architecture, x, y, first_clock_row, last_clock_row, first_row, last_row, &column_number, offset_in_blocks[i]);
      if (status == -1) {
        return -1;
      }
    }
    return 0;
  }

  #define BITS_PER_CLB 		  8
  #define MAX_BITS_IN_CLOCK_ROW 400
  static int calculate_constant_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset) {
    int i, j, k;
    int first_bit_first_clock_row, last_bit_first_clock_row, first_bit_last_clock_row, last_bit_last_clock_row;
    int first_bit_in_column, last_bit_in_column, total_bits_to_send, bits_to_send;
    int clock_row_number, initial_column, num_constants;
    uint32_t frame_address;
    
    initial_column = *column;
    
    first_bit_first_clock_row = first_row * BITS_PER_CLB;
    last_bit_last_clock_row = ((last_row + 1) * BITS_PER_CLB) - 1;
    if (first_clock_row == last_clock_row) {
      first_bit_last_clock_row = first_bit_first_clock_row;
      last_bit_first_clock_row = last_bit_last_clock_row;
    } else {
      first_bit_last_clock_row = 0;
      last_bit_first_clock_row = MAX_BITS_IN_CLOCK_ROW - 1;
    }
    clock_row_number = first_clock_row;
    
    num_constants = virtual_architecture->partition[x][y].element.element_info->num_constants;
    first_bit_in_column = first_bit_first_clock_row;
    last_bit_in_column = last_bit_first_clock_row;
    for (i = 0; i < num_constants; i++) {
      if (virtual_architecture->partition[x][y].element.element_info->constant_column_offset[i] != offset) {
        continue;
      }
      total_bits_to_send = virtual_architecture->partition[x][y].element.element_info->num_bits_in_constant[i];
      j = 0;
      while (total_bits_to_send > 0) {
        frame_address = obtain_frame_address_of_CLB_column(virtual_architecture, x, y, clock_row_number, *column);
        if (frame_address == -1) {
          return -1;
        }
        for (k = 0; k < MAX_COLUMNS_CONSTANTS; k++) {
          // We search for an empty frame address or for a previous equal frame address.
          if (constant_t_frames[k].frame_address != frame_address && constant_t_frames[k].frame_address != 0) {
            continue;
          }
          else {
            constant_t_frames[k].frame_address = frame_address;
            break;
          }
        }
        if (k == MAX_COLUMNS_CONSTANTS) {
          return -1;
        }
        if (total_bits_to_send > (last_bit_in_column + 1 - first_bit_in_column)) {
          bits_to_send = last_bit_in_column + 1 - first_bit_in_column;
        } else {
          bits_to_send = total_bits_to_send;
        }
        virtual_architecture->partition[x][y].element.constant_frame_address_position[i][j] = k;
        virtual_architecture->partition[x][y].element.first_bit_in_frame[i][j] = first_bit_in_column;
        first_bit_in_column += bits_to_send;
        virtual_architecture->partition[x][y].element.last_bit_in_frame[i][j] = first_bit_in_column - 1;
        total_bits_to_send -= bits_to_send;
        if (total_bits_to_send == 0 && i == (num_constants - 1)) {
          //If it is the last constant we start a new column in the first row where the LUT muxes are going to be placed.
          (*column)++;
          if ((*column - initial_column) < virtual_architecture->partition[x][y].element.element_info->num_constant_columns[i]) {
            *column = initial_column + virtual_architecture->partition[x][y].element.element_info->num_constant_columns[i];
          }
        } else if (first_bit_in_column > last_bit_in_column) {
          clock_row_number++;
          if (clock_row_number > last_clock_row) {
            clock_row_number = first_clock_row;
            (*column)++;
          }
          if (clock_row_number == first_clock_row) {
            first_bit_in_column = first_bit_first_clock_row;
            last_bit_in_column = last_bit_first_clock_row;
          } else if (clock_row_number == last_clock_row) {
            first_bit_in_column = first_bit_last_clock_row;
            last_bit_in_column = last_bit_last_clock_row;
          } else {
            first_bit_in_column = 0;
            last_bit_in_column = MAX_BITS_IN_CLOCK_ROW - 1;
          }
        }
        j++;
      }
      //If the constant has an odd number of bits we have to add one because the next constant will start in a new LUT.
      if (first_bit_in_column % 2 != 0) {
        first_bit_in_column += 1;
      }
    }
    return 0;
  }

  #define MAX_LUTS_IN_CLOCK_ROW 200
  #define LUTS_PER_CLB 		  4

  static int calculate_mux_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset) {
    int i,j,k;
    int first_LUT_first_clock_row, last_LUT_first_clock_row, first_LUT_last_clock_row, last_LUT_last_clock_row;
    int LUT_position, num_inputs, total_LUTs_to_send, LUTs_to_send;
    int first_LUT_in_column, last_LUT_in_column, initial_column, num_muxes;
    int clock_row_number;
    uint32_t frame_address;
    
    initial_column = *column;
    
    first_LUT_first_clock_row = first_row * LUTS_PER_CLB;
    last_LUT_last_clock_row = ((last_row + 1) * LUTS_PER_CLB) - 1;
    if (first_clock_row == last_clock_row) {
      first_LUT_last_clock_row = first_LUT_first_clock_row;
      last_LUT_first_clock_row = last_LUT_last_clock_row;
      
    } else {
      first_LUT_last_clock_row = 0;
      last_LUT_first_clock_row = MAX_LUTS_IN_CLOCK_ROW - 1;
    }
    
    clock_row_number = first_clock_row;
    first_LUT_in_column = first_LUT_first_clock_row;
    last_LUT_in_column = last_LUT_first_clock_row;
    num_muxes = virtual_architecture->partition[x][y].element.element_info->num_muxes;
    for (i = 0; i < num_muxes; i++) {
      if (virtual_architecture->partition[x][y].element.element_info->mux_column_offset[i] != offset)  {
        continue;
      }
      num_inputs = virtual_architecture->partition[x][y].element.element_info->mux_num_inputs[i];
      total_LUTs_to_send = LUTs_in_mux(virtual_architecture->partition[x][y].element.element_info->mux_data_width[i], num_inputs);
      virtual_architecture->partition[x][y].element.total_LUTs_in_mux[i] = total_LUTs_to_send;
      j = 0;
      LUT_position = 0;
      while (total_LUTs_to_send > 0) {
        frame_address = obtain_frame_address_of_CLB_column(virtual_architecture, x, y, clock_row_number, *column);
        if (frame_address == -1) {
          return -1;
        }
        for (k = 0; k < MAX_COLUMNS_MUX; k++) {
          // We search for an empty frame address or for a previous equal frame address.
          if (mux_t_frames[k].frame_address != frame_address && mux_t_frames[k].frame_address != 0) {
            continue;
          }
          else {
            mux_t_frames[k].frame_address = frame_address;
            break;
          }
        }
        if (k == MAX_COLUMNS_MUX) {
          return -1;
        }
        if (total_LUTs_to_send > (last_LUT_in_column + 1 - first_LUT_in_column)) {
          LUTs_to_send = last_LUT_in_column + 1 - first_LUT_in_column;
        } else {
          LUTs_to_send = total_LUTs_to_send;
        }
        virtual_architecture->partition[x][y].element.mux_frame_address_position[i][j] = k;
        virtual_architecture->partition[x][y].element.first_LUT_in_frame[i][j] = first_LUT_in_column;
        first_LUT_in_column += LUTs_to_send;
        virtual_architecture->partition[x][y].element.last_LUT_in_frame[i][j] = first_LUT_in_column - 1;
        virtual_architecture->partition[x][y].element.LUT_position_in_frame[i][j] = LUT_position;
        LUT_position = (LUT_position + LUTs_to_send) % (((num_inputs - 2) / 3) + 1);
        total_LUTs_to_send -= LUTs_to_send;
        if (total_LUTs_to_send == 0 && i == (num_muxes - 1)) {
          //If it is the last mux we start a new column in the first row where the LUT FUs are going to be placed.
          (*column)++;
          if ((*column - initial_column) < virtual_architecture->partition[x][y].element.element_info->num_mux_columns[i]) {
            *column = initial_column + virtual_architecture->partition[x][y].element.element_info->num_mux_columns[i];
          }
        } else if (first_LUT_in_column > last_LUT_in_column) {
          clock_row_number++;
          if (clock_row_number > last_clock_row) {
            clock_row_number = first_clock_row;
            (*column)++;
          }
          if (clock_row_number == first_clock_row) {
            first_LUT_in_column = first_LUT_first_clock_row;
            last_LUT_in_column = last_LUT_first_clock_row;
          } else if (clock_row_number == last_clock_row) {
            first_LUT_in_column = first_LUT_last_clock_row;
            last_LUT_in_column = last_LUT_last_clock_row;
          } else {
            first_LUT_in_column = 0;
            last_LUT_in_column = MAX_LUTS_IN_CLOCK_ROW - 1;
          }
        }
        j++;
      }
    }
    return 0;
  }

  #define CLBS_IN_COLUMN	50

  static int calculate_FU_parameters(virtual_architecture_t *virtual_architecture, int x, int y, int first_clock_row, int last_clock_row, int first_row, int last_row, int *column, int offset) {
    int i,j,k;
    int first_block_first_clock_row, last_block_first_clock_row, first_block_last_clock_row, last_block_last_clock_row;
    int first_block_in_column, last_block_in_column, total_blocks_to_send;
    int clock_row_number, blocks_to_send, initial_column, num_FU;
    uint32_t frame_address;
    
    initial_column = *column;
    // If the first row is odd it does not have FU as they have to start from an even row
    if ((first_row % 2) == 1) first_row++;
    // If the last row is even it does not have FU as they have to finish in an odd row
    if ((last_row % 2) == 0) last_row--;
    first_block_first_clock_row = first_row/2;
    last_block_last_clock_row = last_row/2;
    if (first_clock_row == last_clock_row) {
      first_block_last_clock_row = first_block_first_clock_row;
      last_block_first_clock_row = last_block_last_clock_row;
    } else {
      first_block_last_clock_row = 0;
      last_block_first_clock_row = CLBS_IN_COLUMN - 1;
    }
    clock_row_number = first_clock_row;
    
    first_block_in_column = first_block_first_clock_row;
    last_block_in_column = last_block_first_clock_row;
    num_FU = virtual_architecture->partition[x][y].element.element_info->num_FU;
    for (i = 0; i < num_FU; i++) {
      if (virtual_architecture->partition[x][y].element.element_info->FU_column_offset[i] != offset) {
        continue;
      }
      total_blocks_to_send = virtual_architecture->partition[x][y].element.element_info->FU_4_bit_blocks[i];
      j = 0;
      while (total_blocks_to_send > 0) {
        frame_address = obtain_frame_address_of_CLB_column(virtual_architecture, x, y, clock_row_number, (*column));
        if (frame_address == -1) {
          return -1;
        }
        for (k = 0; k < MAX_COLUMNS_FU; k++) {
          // We search for an empty frame address or for a previous equal frame address.
          if (FU_t_frames[k].frame_address != frame_address && FU_t_frames[k].frame_address != 0) {
            continue;
          }
          else {
            FU_t_frames[k].frame_address = frame_address;
            break;
          }
        }
        if (k == MAX_COLUMNS_FU) {
          return -1;
        }
        if (total_blocks_to_send > (last_block_in_column + 1 - first_block_in_column)) {
          blocks_to_send = last_block_in_column + 1 - first_block_in_column;
        } else {
          blocks_to_send = total_blocks_to_send;
        }
        virtual_architecture->partition[x][y].element.FU_frame_address_position[i][j] = k;
        virtual_architecture->partition[x][y].element.first_FU_block_in_frame[i][j] = first_block_in_column;
        first_block_in_column += blocks_to_send;
        virtual_architecture->partition[x][y].element.last_FU_block_in_frame[i][j] = first_block_in_column - 1;
        total_blocks_to_send -= blocks_to_send;
        if (total_blocks_to_send == 0 && i == (num_FU - 1)) {
          (*column)++;
          if ((*column - initial_column) < virtual_architecture->partition[x][y].element.element_info->num_FU_columns[i]) {
            *column = initial_column + virtual_architecture->partition[x][y].element.element_info->num_FU_columns[i];
          }
        } else if (first_block_in_column > last_block_in_column) {
          clock_row_number++;
          if (clock_row_number > last_clock_row) {
            clock_row_number = first_clock_row;
            (*column)++;
          }
          if (clock_row_number == first_clock_row) {
            first_block_in_column = first_block_first_clock_row;
            last_block_in_column = last_block_first_clock_row;
          } else if (clock_row_number == last_clock_row) {
            first_block_in_column = first_block_last_clock_row;
            last_block_in_column = last_block_last_clock_row;
          } else {
            first_block_in_column = 0;
            last_block_in_column = MAX_BITS_IN_CLOCK_ROW - 1;
          }
        }
        j++;
      }
    }
    return 0;
  }

  /*
  * Fine grain LUT-based elements in a reconfigurable partition can be placed
  * a number of columns (offset) away from the first left LUT column. Each
  * element having a different offset starts a new block of fine-grain elements.
  * This function analyzes all the fine grain elements of the elment and computes
  * the total number of blocks and their corresponding offsets.
  *
  * */
  static void find_number_of_fine_grain_blocks() {
    int num_constants, num_muxes, num_FU;
    int  offset_in_array;
    int i, j, num_element;
    
    for (num_element = 0; num_element < NUM_ELEMENTS; num_element++) {
      elements[num_element].num_blocks = 0;
      for (i = 0; i < MAX_COLUMN_OFFSETS; i++) {
        elements[num_element].offset_blocks[i] = -1;
      }
      
      num_constants = elements[num_element].num_constants;
      num_muxes = elements[num_element].num_muxes;
      num_FU = elements[num_element].num_FU;
      
      for (i = 0; i < num_constants; i++) {
        offset_in_array = 0;
        for (j = 0; j < elements[num_element].num_blocks; j++) {
          if (elements[num_element].constant_column_offset[i] == elements[num_element].offset_blocks[j]) {
            offset_in_array = 1;
          }
        }
        if (offset_in_array == 0) {
          if (elements[num_element].num_blocks >= MAX_COLUMN_OFFSETS) {
            return;
          }
          elements[num_element].offset_blocks[elements[num_element].num_blocks] = elements[num_element].constant_column_offset[i];
          elements[num_element].num_blocks++;
        }
      }
      for (i = 0; i < num_muxes; i++) {
        offset_in_array = 0;
        for (j = 0; j < elements[num_element].num_blocks; j++) {
          if (elements[num_element].mux_column_offset[i] == elements[num_element].offset_blocks[j]) {
            offset_in_array = 1;
          }
        }
        if (offset_in_array == 0) {
          if (elements[num_element].num_blocks >= MAX_COLUMN_OFFSETS) {
            return;
          }
          elements[num_element].offset_blocks[elements[num_element].num_blocks] = elements[num_element].mux_column_offset[i];
          elements[num_element].num_blocks++;
        }
      }
      for (i = 0; i < num_FU; i++) {
        offset_in_array = 0;
        for (j = 0; j < elements[num_element].num_blocks; j++) {
          if (elements[num_element].FU_column_offset[i] == elements[num_element].offset_blocks[j]) {
            offset_in_array = 1;
          }
        }
        if (offset_in_array == 0) {
          if (elements[num_element].num_blocks >= MAX_COLUMN_OFFSETS) {
            return;
          }
          elements[num_element].offset_blocks[elements[num_element].num_blocks] = elements[num_element].FU_column_offset[i];
          elements[num_element].num_blocks++;
        }
      }
    }
  }


  static void reset_fine_grain_elements(virtual_architecture_t *virtual_architecture, int x, int y) {
    int i;
    for (i = 0; i < MAX_CONSTANTS; i++) {
      virtual_architecture->partition[x][y].element.constants_definition[i].initialized = 0;
    }
    for (i = 0; i < MAX_MUXES; i++) {
      virtual_architecture->partition[x][y].element.mux_definition[i].initialized = 0;
    }
    for (i = 0; i < MAX_FU; i++) {
      virtual_architecture->partition[x][y].element.mux_definition[i].initialized = 0;
    }
  }

  /*
  * 31-30 element type (00 const, 01 mux, 10 PE)
  * 29-26 number of frames to reconfigure
  * 25-0 frame address
  */
  static uint32_t obtain_XFAR(uint32_t element_type, uint32_t num_frames, uint32_t frame_address) {
    return (((element_type & 0x3) << 30) | ((num_frames & 0x7) << 26) | frame_address);
  }

  /*
  *
  * NOTE in overlays constant columns come first then mux columns and finally FUs.
  */
  void change_partition_constant(virtual_architecture_t *virtual_architecture, int x, int y, int constant_number, uint32_t value[MAX_WORDS_PER_CONSTANT]) {
      int i;
      int total_bits_to_send, bits_sent, first_bit, last_bit, bits_to_send;
      uint32_t frame_address_position;

      total_bits_to_send = virtual_architecture->partition[x][y].element.element_info->num_bits_in_constant[constant_number];

      #if SEARCH_IF_FINE_GRAIN_VALUE_HAS_CHANGED == 1
        int same_value = 1;

      for (i = 0; i <= ((total_bits_to_send-1)/32); i++) {
        if (value[i] != virtual_architecture->partition[x][y].element.constants_definition[constant_number].value[i]) {
          same_value = 0;
          virtual_architecture->partition[x][y].element.constants_definition[constant_number].value[i] = value[i];
        }
      }
      // The constant already has that value
      if (same_value == 1 && virtual_architecture->partition[x][y].element.constants_definition[constant_number].initialized == 1) {
        return;
      }

        virtual_architecture->partition[x][y].element.constants_definition[constant_number].initialized = 1;
      #endif

      bits_sent = 0;
      i = 0;
      while (total_bits_to_send > bits_sent) {
        frame_address_position = virtual_architecture->partition[x][y].element.constant_frame_address_position[constant_number][i];
        first_bit = virtual_architecture->partition[x][y].element.first_bit_in_frame[constant_number][i];
        last_bit = virtual_architecture->partition[x][y].element.last_bit_in_frame[constant_number][i];
        bits_to_send = last_bit + 1 - first_bit;
 		if ((bits_to_send == 32) && ((first_bit % 32) == 0)) {
 			constant_t_frames[frame_address_position].value[first_bit/32] = value[0];
 			constant_frames_flags[frame_address_position] = RECONFIGURE_FRAME;
 			return;
 		} else if ((bits_to_send == 16) && ((first_bit % 16) == 0)) {
 			//tmp = first_bit/32;
 			if ((first_bit%32) == 0) {
 				constant_t_frames[frame_address_position].value[first_bit/32] = (constant_t_frames[frame_address_position].value[first_bit/32]&0xFFFF0000) | (value[0]&0x0000FFFF);
 			} else {
 				constant_t_frames[frame_address_position].value[first_bit/32] = (constant_t_frames[frame_address_position].value[first_bit/32]&0x0000FFFF) | (value[0]<<16);
 			}
 			constant_frames_flags[frame_address_position] = RECONFIGURE_FRAME;
 			return;
         } else {
 			change_constant_frame_address(frame_address_position, first_bit, last_bit, bits_sent, &value[0]);
 		}
 		//change_constant_frame_address(frame_address_position, first_bit, last_bit, bits_sent, &value[0]);
        i++;
        bits_sent += bits_to_send;
      }
    }

   static void change_constant_frame_address(uint32_t frame_address_position, int first_bit, int last_bit, int previous_bits_sent, uint32_t *value) {
      uint32_t first_frame_word, first_frame_bit, last_frame_word, last_frame_bit, frame_mask;
      uint32_t aux_value;
      uint32_t j, k;

  	constant_frames_flags[frame_address_position] = RECONFIGURE_FRAME;

 	if (((last_bit + 1 - first_bit) == 32) && ((first_bit % 32) == 0)) {
 		constant_t_frames[frame_address_position].value[first_bit/32] = value[0];
 		return;
 	}

  	first_frame_word = first_bit / 32;
  	last_frame_word = last_bit / 32;


  	for (j = first_frame_word; j <= last_frame_word; j++) {
  	if (j == first_frame_word) {
  	  first_frame_bit = (first_bit % 32);
  	} else {
  	  first_frame_bit = 0;
  	}
  	if (j == last_frame_word) {
  	  last_frame_bit = (last_bit % 32);
  	} else {
  	  last_frame_bit = 31;
  	}

  	aux_value = 0;
  	frame_mask = 0;
  	for (k = first_frame_bit; k <= last_frame_bit; k++) {
  	  frame_mask |= (0x1 << k);
  	  aux_value |= ((value[previous_bits_sent/32] >> (previous_bits_sent % 32)) & 1) << k;
  	  previous_bits_sent++;
  	}

  	constant_t_frames[frame_address_position].value[j] = (constant_t_frames[frame_address_position].value[j] & (~frame_mask)) | aux_value;
  	}
    }


  void change_partition_mux(virtual_architecture_t *virtual_architecture, int x, int y, int mux_number, int value) {
    int total_LUTs_to_send, LUTs_to_send, LUT_position, num_inputs, LUTs_sent;
    int frame_address_position, first_LUT, last_LUT;
    int i;
    
    #if SEARCH_IF_FINE_GRAIN_VALUE_HAS_CHANGED == 1
      int same_value = 1;
      if (value != virtual_architecture->partition[x][y].element.mux_definition[mux_number].value) {
       same_value = 0;
       virtual_architecture->partition[x][y].element.mux_definition[mux_number].value = value;
      }

      // The constant already has that value
      if (same_value == 1 && virtual_architecture->partition[x][y].element.mux_definition[mux_number].initialized == 1) {
       return;
      }

      virtual_architecture->partition[x][y].element.mux_definition[mux_number].initialized = 1;
    #endif

    num_inputs = virtual_architecture->partition[x][y].element.element_info->mux_num_inputs[mux_number];
    total_LUTs_to_send = virtual_architecture->partition[x][y].element.total_LUTs_in_mux[mux_number];
    LUTs_sent = 0;
    i = 0;
    while (total_LUTs_to_send > LUTs_sent) {
      frame_address_position = virtual_architecture->partition[x][y].element.mux_frame_address_position[mux_number][i];
      first_LUT = virtual_architecture->partition[x][y].element.first_LUT_in_frame[mux_number][i];
      last_LUT = virtual_architecture->partition[x][y].element.last_LUT_in_frame[mux_number][i];
      LUTs_to_send = last_LUT + 1 - first_LUT;
      LUT_position = virtual_architecture->partition[x][y].element.LUT_position_in_frame[mux_number][i];
      change_mux_frame_address(frame_address_position, first_LUT, last_LUT, value, LUT_position , num_inputs);
      LUTs_sent += LUTs_to_send;
      i++;
    }
  }

  static void change_mux_frame_address(uint32_t frame_address_position, int first_LUT, int last_LUT, int value, int LUT_position, int num_inputs) {
    uint32_t first_frame_word, first_frame_LUT, last_frame_word, last_frame_LUT, frame_mask;
    uint32_t aux_value;
    uint32_t j, k;
    
    
    
    mux_frames_flags[frame_address_position] = RECONFIGURE_FRAME;
    
    first_frame_word = first_LUT / 16;
    last_frame_word = last_LUT / 16;
    
    for (j = first_frame_word; j <= last_frame_word; j++) {
      if (j == first_frame_word) {
        first_frame_LUT = first_LUT % 16;
      } else {
        first_frame_LUT = 0;
      }
      if (j == last_frame_word) {
        last_frame_LUT = last_LUT % 16;
      } else {
        last_frame_LUT = 15;
      }
      
      frame_mask = 0;
      aux_value = 0;
      for (k = first_frame_LUT; k <= last_frame_LUT; k++) {
        frame_mask |= (0x3 << k*2);
        if (((value - 1) / 3) > LUT_position) {
          //We don't care about the value of lower LUTs
        } else if (((value - 1) / 3) < LUT_position) {
          aux_value |= (0x3 << k*2);
        } else {
          if (value <= 3) {
            aux_value |= (value << k*2);
          } else {
            aux_value |= (((value - 4) % 3) << k*2);
          }
        }
        LUT_position = (LUT_position + 1) % (((num_inputs - 2) / 3) + 1);
      }
      mux_t_frames[frame_address_position].value[j] = (mux_t_frames[frame_address_position].value[j] & (~frame_mask)) | aux_value;
    }
  }

  void change_partition_FU(virtual_architecture_t *virtual_architecture, int x, int y, int FU_number, FU_functions_t value) {
    int i;
    int total_blocks_to_send, blocks_sent, first_block, last_block, blocks_to_send;
    uint32_t frame_address_position;
    
    #if SEARCH_IF_FINE_GRAIN_VALUE_HAS_CHANGED == 1
      int same_value = 1;

      if (value != virtual_architecture->partition[x][y].element.FU_definition[FU_number].value) {
       same_value = 0;
       virtual_architecture->partition[x][y].element.FU_definition[FU_number].value = value;
      }

      // The constant already has that value
      if (same_value == 1 && virtual_architecture->partition[x][y].element.FU_definition[FU_number].initialized == 1) {
       return;
      }

      virtual_architecture->partition[x][y].element.FU_definition[FU_number].initialized = 1;
    #endif
    
    total_blocks_to_send = virtual_architecture->partition[x][y].element.element_info->FU_4_bit_blocks[FU_number];
    blocks_sent = 0;
    i = 0;
    while (total_blocks_to_send > blocks_sent) {
      frame_address_position = virtual_architecture->partition[x][y].element.FU_frame_address_position[FU_number][i];
      first_block = virtual_architecture->partition[x][y].element.first_FU_block_in_frame[FU_number][i];
      last_block = virtual_architecture->partition[x][y].element.last_FU_block_in_frame[FU_number][i];
      blocks_to_send = last_block + 1 - first_block;
      change_FU_frame_address(frame_address_position, first_block, last_block, (int) value);
      i++;
      blocks_sent += blocks_to_send;
    }
  }

  #define BITS_PER_BLOCK 	5
  #define BLOCK_PER_WORD    (32 / BITS_PER_BLOCK)
  static void change_FU_frame_address(uint32_t frame_address_position, int first_block, int last_block, int value) {
    uint32_t first_frame_word, first_frame_block, last_frame_word, last_frame_block, frame_mask;
    uint32_t aux_value;
    uint32_t j, k;
    
    FU_frames_flags[frame_address_position] = RECONFIGURE_FRAME;
    
    first_frame_word = first_block / BLOCK_PER_WORD;
    last_frame_word = last_block / BLOCK_PER_WORD;
    
    for (j = first_frame_word; j <= last_frame_word; j++) {
      if (j == first_frame_word) {
        first_frame_block = (first_block % BLOCK_PER_WORD);
      } else {
        first_frame_block = 0;
      }
      if (j == last_frame_word) {
        last_frame_block = (last_block % BLOCK_PER_WORD);
      } else {
        last_frame_block = BLOCK_PER_WORD-1;
      }
      
      aux_value = 0;
      frame_mask = 0;
      // Each 32-bit word contains the info of BLOCK_PER_WORD FU blocks. The info of the first block starts at bit 0.
      // This way of storing the FU block information uses more words but is faster to update.
      for (k = first_frame_block; k <= last_frame_block; k++) {
        frame_mask |= (0x1F << k*5);
        aux_value |= value << k*5;
      }
      FU_t_frames[frame_address_position].value[j] = (FU_t_frames[frame_address_position].value[j] & (~frame_mask)) | aux_value;
    }
  }


//#define BITS_PER_BLOCK 	5
// static void change_FU_frame_address(uint32_t frame_address_position, int first_block, int last_block, int value) {
//   uint32_t first_frame_word, first_frame_bit, last_frame_word, last_frame_bit, frame_mask, first_bit, last_bit;
//   uint32_t aux_value, index;
//   uint32_t j, k;
//
//   FU_frames_flags[frame_address_position] = RECONFIGURE_FRAME;
//
//   first_bit = first_block * BITS_PER_BLOCK;
//   last_bit = ((last_block + 1) * BITS_PER_BLOCK) - 1;
//
//   first_frame_word = first_bit / 32;
//   last_frame_word = last_bit / 32;
//
//   index = 0;
//   for (j = first_frame_word; j <= last_frame_word; j++) {
//     if (j == first_frame_word) {
//   	  first_frame_bit = first_bit % 32;
//     } else {
//   	  first_frame_bit = 0;
//     }
//     if (j == last_frame_word) {
//   	last_frame_bit = last_bit % 32;
//     } else {
//   	last_frame_bit = 31;
//     }
//
//     aux_value = 0;
//     frame_mask = 0;
//     for (k = first_frame_bit; k <= last_frame_bit; k++) {
//   	  frame_mask |= (0x1 << k);
//   	  aux_value |= ((value >> index) & 1) << k;
//		  if ( index >=  (BITS_PER_BLOCK - 1)) {
//			  index = 0;
//		  } else {
//			  index++;
//		  }
//     }
//     FU_t_frames[frame_address_position].value[j] = (FU_t_frames[frame_address_position].value[j] & (~frame_mask)) | aux_value;
//   }
// }


  /*
  *
  */
  static uint32_t obtain_frame_address_of_CLB_column(virtual_architecture_t *virtual_architecture, int x, int y, int clock_row_number, int column_number ) {
    int first_column, last_column, row, column;
    int CLB_columns, minor_column;
    uint32_t frame_address = 0;
    
    
    first_column = virtual_architecture->partition[x][y].location_info.first_column;
    last_column = virtual_architecture->partition[x][y].location_info.last_column;
    row = clock_row_number;
    column = first_column;
    CLB_columns = 0;
    
    while (column <= last_column) {
      if (is_column_CLB_type(row, column)) {
        if (CLB_columns == (column_number / 2)) {
          minor_column = obtain_CLB_minor_column(row, column, column_number % 2);
          frame_address = PCAP_SetupFar7S (((fpga[row][column][0]>>24) & 0xFF), \
          PCAP_FAR_CLB_BLOCK, ((fpga[row][column][0]>>16) & 0xFF), (column), minor_column);
          return frame_address;
        }
        CLB_columns ++;
      }
      column++;
    }
    
    return -1;
  }

  static int is_column_CLB_type(int row, int column) {
    return (fpga[row][column][1] == CLB_M_TYPE) || (fpga[row][column][1] == CLB_L_TYPE);
  }

  static int obtain_CLB_minor_column(int row, int column, int num_slice) {
    int minor_column;
    if (fpga[row][column][1] == CLB_L_TYPE) {
      if (num_slice == 0) {
        // First slice
        minor_column = MINOR_COLUMN_SLICE_L_1;
      } else {
        // Second slice
        minor_column = MINOR_COLUMN_SLICE_L_2;
      }
    } else {
      if (num_slice == 0) {
        // First slice
        minor_column = MINOR_COLUMN_SLICE_M_1;
      } else {
        // Second slice
        minor_column = MINOR_COLUMN_SLICE_M_2;
      }
    }
    return minor_column;
  }


  static int LUTs_in_mux(int data_width, int num_inputs){
    return (((num_inputs - 2)/3 + 1) * data_width);
  }


  /*
  *
  */
  void reconfigure_fine_grain() {
    reconfigure_constants();
    reconfigure_muxes();
    reconfigure_FU();
  }

  void reconfigure_constants() {
    int i, j;
    uint32_t xfar;
    enable_ICAP();
    for (i = 0; i < MAX_COLUMNS_CONSTANTS; i++) {
      if (constant_frames_flags[i] == RECONFIGURE_FRAME) {
        constant_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
        while (ICAP[0] & 0x1) { }  // wait for ack (mandatory)
        for (j = 0; j < WORDS_PER_CONSTANTS; j++) {
          ICAP[j+1] = constant_t_frames[i].value[j];
        }
        xfar = obtain_XFAR(CONST_TYPE, 1, constant_t_frames[i].frame_address);
        ICAP[0] = xfar; // send XFAR and start reconfiguration!
      }
    }
    while (ICAP[0] != 0);
  }

  void reconfigure_muxes() {
    int i, j;
    uint32_t xfar;
    enable_ICAP();
    for (i = 0; i < MAX_COLUMNS_MUX; i++) {
      if (mux_frames_flags[i] == RECONFIGURE_FRAME) {
        mux_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
        while (ICAP[0] & 0x1) { }  // wait for ack (mandatory)
        for (j = 0; j < WORDS_PER_MUX; j++) {
          ICAP[j+1] = mux_t_frames[i].value[j];
        }
        xfar = obtain_XFAR(MUX_TYPE, 1, mux_t_frames[i].frame_address);
        ICAP[0] = xfar; // send XFAR and start reconfiguration!
      }
    }
    while (ICAP[0] != 0);
  }


  void reconfigure_FU() {
    int i, j;
    uint32_t xfar;
    enable_ICAP();
    for (i = 0; i < MAX_COLUMNS_FU; i++) {
      if (FU_frames_flags[i] == RECONFIGURE_FRAME) {
        FU_frames_flags[i] = DO_NOT_RECONFIGURE_FRAME;
        while (ICAP[0] & 0x1) { }  // wait for ack (mandatory)
        for (j = 0; j < WORDS_PER_FU; j++) {
          ICAP[j+1] = FU_t_frames[i].value[j];
        }
        xfar = obtain_XFAR(FU_TYPE, 2, FU_t_frames[i].frame_address);
        ICAP[0] = xfar; // send XFAR and start reconfiguration!
      }
    }
    while (ICAP[0] != 0);
  }


  void load_fine_grain_PBS() {
    load_constant_PBS();
    load_mux_PBS();
    load_FU();
  }

  #define OFFSET_MUX_PBS    16
  #define BITS_CONSTANT_PBS   4
  static void load_constant_PBS() {
    volatile uint32_t *mem_constant_PBS = (volatile uint32_t*) ICAP_MEM_BASEADDR;
    int constant;
    uint32_t PBS_word;
    
    
    for (constant = 0; constant < OFFSET_MUX_PBS; constant++) {
      //PBS_word = (get_PBS_2_bits(constant & 0x3) << 16) | get_PBS_2_bits((constant & 0xC) >> 2);
      PBS_word = get_PBS_2_bits(constant & 0x3)  | (get_PBS_2_bits((constant & 0xC) >> 2) << 16);
      *(mem_constant_PBS+constant) = PBS_word;
    }
    
  }

  static uint16_t get_PBS_2_bits(int bits) {
    uint16_t PBS;
    switch (bits) {
      case 0:
      PBS = 0x0000;
      break;
      case 1:
      PBS = 0xFF00;
      break;
      case 2:
      PBS = 0x00FF;
      break;
      case 3:
      PBS = 0xFFFF;
      break;
      default:
      PBS = 0x0000;
      break;
    }
    return PBS;
  }

  #define A6_mux 0x00FF //Correspond to A3_mux in our 4-input LUT
  #define A5_mux 0x0F0F //Correspond to A2_mux in our 4-input LUT
  #define A3_mux 0x3333 //Correspond to A1 in our 4-input LUT
  #define A2_mux 0x5555 //Correspond to A0 in our 4-input LUT
  static void load_mux_PBS() {
    volatile uint32_t *mem_constant_PBS = (volatile uint32_t*) (ICAP_MEM_BASEADDR);
    
    *(mem_constant_PBS + OFFSET_MUX_PBS)     =  (A2_mux << 16)|A2_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 1) =  (A2_mux << 16)|A3_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 2) =  (A2_mux << 16)|A5_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 3) =  (A2_mux << 16)|A6_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 4) =  (A3_mux << 16)|A2_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 5) =  (A3_mux << 16)|A3_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 6) =  (A3_mux << 16)|A5_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 7) =  (A3_mux << 16)|A6_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 8) =  (A5_mux << 16)|A2_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 9) =  (A5_mux << 16)|A3_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 10) = (A5_mux << 16)|A5_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 11) = (A5_mux << 16)|A6_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 12) = (A6_mux << 16)|A2_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 13) = (A6_mux << 16)|A3_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 14) = (A6_mux << 16)|A5_mux;
    *(mem_constant_PBS + OFFSET_MUX_PBS + 15) = (A6_mux << 16)|A6_mux;
  }

  // Frame:    1st  2nd
  //           <--><-->
  #define A6 0x00FF00FF
  #define A5 0x0F0F0F0F
  //      A4 (unused)
  #define A3 0x33333333
  #define A2 0x55555555
  #define A1 0x0000FFFF

  #define IN1_S1  A5  // north (1st stage)
  #define IN2_S1  A3  // west  (1st stage)
  #define IN1_S2 A2  // north (2nd stage)
  #define IN2_S2 A1  // west  (2nd stage)
  #define S  A3  // sum   (mod 256)
  #define S2 A5  // sum/2 (rounded down)
  #define C  A6  // carry (overflow)
  #define FF 0xFFFFFFFF // all ones

  #define ADD(a,b) (( /* O5: */ ((a)&(b)) & ~A6 ) | ( /* O6: */ ((a)^(b)) & A6 ))
  #define SAT(noovf, ovf)  (( (noovf) & ~C ) | ( (ovf) & C ))
  #define FUNC(a,b, noovf,ovf)  { ADD((a), (b)),  SAT((noovf), (ovf)) }


  #define NUM_FU_FUNCTIONS 18

  //IN1_S1 --> first operand
  //IN2_S1 --> second operand
  static const uint32_t lut_functions[NUM_FU_FUNCTIONS][2] = {
    /** PE functions **/
    // Stage1  Stage2
    FUNC(IN1_S1,IN2_S1,   S,S),   // IN1_S1+IN2_S1 mod
    FUNC(IN1_S1,IN2_S1,   S,FF),  // IN1_S1+IN2_S1 sat
    FUNC(~IN1_S1,IN2_S1,  ~S,0),  // IN1_S1-IN2_S1
    FUNC(~IN1_S1,IN2_S1,  ~S,0),  // IN1_S1-IN2_S1     (sat<0)
    {0, IN1_S2 & IN2_S2}, // and (we don't care about the first stage)
    {0, IN1_S2 | IN2_S2}, // or
    {0, IN1_S2 ^ IN2_S2}, // xor
    {0, ~(IN1_S2 & IN2_S2)}, // nand
    {0, ~(IN1_S2 | IN2_S2)}, // nor
    {0, ~(IN1_S2 ^ IN2_S2)}, // xnor
    {0, ~IN1_S2}, // not
    FUNC(IN1_S1,0,   S2,S2), // IN1_S1/2 (shift1r)
    FUNC(IN1_S1,IN1_S1,   S,S),   // 2N  mod (shift1l)
    FUNC(IN1_S1,~IN2_S1,  IN1_S2,IN2_S2),   // max
    FUNC(IN1_S1,~IN2_S1,  IN1_S2,IN2_S2),   // min
    FUNC(IN1_S1,IN2_S1,   S2,S2),   // (IN1_S1+IN2_S1)/2
    FUNC(~IN1_S1,IN2_S1,  FF,0),    // IN1_S1>=IN2_S1 ? 255 : 0
    FUNC(~IN2_S1,IN1_S1,  FF,0),    // IN2_S1>=IN1_S1 ? 255 : 0
  };


  #define OFFSET_FU_PBS    (256*4) //2 pow 8
  #define PE_SIZE			 8
  #define FU_MEM_BASE_ADDR (ICAP_MEM_BASEADDR + OFFSET_FU_PBS)
  void load_FU() {
    volatile uint32_t (*PE_ADDR)[PE_SIZE] = (volatile uint32_t (*)[PE_SIZE]) FU_MEM_BASE_ADDR;
    int i;
    for (i=0; i<NUM_FU_FUNCTIONS; i++) {
      uint32_t f1, f2; //Estos son los frames 1 y 2.
      
      // Stage 1 (2 frames; ABOVE stage 2)
      f1 = f2 = lut_functions[i][0];
      f1 = f1 >> 16;    // frame 1
      f2 = f2 & 0xFFFF; // frame 2
      PE_ADDR[i][0] = PE_ADDR[i][1] = f1<<16 | f1;
      PE_ADDR[i][4] = PE_ADDR[i][5] = f2<<16 | f2;
      
      // Stage 2 (2 frames; BELOW stage 1)
      f1 = f2 = lut_functions[i][1];
      f1 = f1 >> 16;    // frame 1
      f2 = f2 & 0xFFFF; // frame 2
      
      PE_ADDR[i][2] = PE_ADDR[i][3] = f1<<16 | f1;
      PE_ADDR[i][6] = PE_ADDR[i][7] = f2<<16 | f2;
    }
    
  }

#endif
