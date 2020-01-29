#ifndef IMPRESS_RECONFIGURATION 
#define IMPRESS_RECONFIGURATION

#include <stdint.h> 
#include "IMPRESS_reconfiguration_parameters.h"

#define MAX_WORDS_PER_CONSTANT          (((MAX_BITS_PER_CONSTANT - 1) / 32) + 1)
#define PREDEFINED_NUM_COLUMNS          0
#define PREDEFINED_OFFSET_COLUMN        0
#define MAX_CHARS_PER_PBS               50

#if FINE_GRAIN
	#if MAX_COLUMNS_CONSTANTS > 1
		#define MAX_COLUMNS_CONSTANT_PER_ELEMENT 2
	#else
		#define MAX_COLUMNS_CONSTANT_PER_ELEMENT 1
	#endif

	#if MAX_COLUMNS_FU > 1
		#define MAX_COLUMNS_MUX_PER_ELEMENT 2
	#else
		#define MAX_COLUMNS_MUX_PER_ELEMENT 1
	#endif

	#if MAX_COLUMNS_FU > 1
		#define MAX_COLUMNS_FU_PER_ELEMENT 2
	#else
		#define MAX_COLUMNS_FU_PER_ELEMENT 1
	#endif
#endif

/**
 * The FU component can be reconfigured to accomplish the following functions
 *
 * [add] Add both operands
 * [add_sat] Add saturated (it it overflows the operation is saturated to the maximum value that can be represented with the number of bits) [addsat]
 * [subtract] Subtract both operands
 * [subtract_sat] Subtract saturated
 * [and] AND logic operation
 * [or] OR logic operation between
 * [xor] XOR logic operation between
 * [nand] NAND logic operation between
 * [nor] NOR logic operation between
 * [xnor] XNOR logic operation between
 * [not] NOT logic operation between
 * [shift1r] shift right one position
 * [shift1l] shift right one position
 * [max] Select the maximum operand
 * [min] Select the minimum operand
 * [average] adds both operands and divides by two
 * [smaller_or_eq] compares that the first operand is smaller than the second
 * [eq_or_bigger] compares that the first operand is equal or smaller than the second
 * */

// NOTE: more functions can be implemented however they are not important for mapping LLVM IR onto an overlay, therefore they are not included.
// TODO: ver si poner mas funciones como mux por ejemplo o operaciones lógicas de 3 valores o de 2 con uno de sus operandos negados o smaller o bigger sin equal añadiendole el Cin
typedef enum  {	    add,
					add_sat,
					subtract,
					subtract_sat,
					and,
					or,
					xor,
					nand,
					nor,
					xnor,
					not,
					shift1r,
					shift1l,
					max,
					min,
					average,
					eq_or_bigger,
					smaller_or_eq} FU_functions_t;

#if FINE_GRAIN
  typedef struct {
    int initialized;
    // Constains the constant value. If the user wants to store the constant 0x86AF then
    // value[0] = 0x86 and value[1] = 0xAF
    uint32_t value[MAX_WORDS_PER_CONSTANT];
  } constant_t;

  typedef struct {
	int initialized;
	// mux_definition has a range from 0 to 3. With this variable we can define the entire
	// mux.
	int mux_definition;
  } mux_t;

  typedef struct {
	int initialized;
	FU_functions_t value;
  } FU_t;
#endif

typedef struct {
  #if FINE_GRAIN
    int num_constants; 
    int num_bits_in_constant[MAX_CONSTANTS];
    int constant_column_offset[MAX_CONSTANTS];
    int num_constant_columns[MAX_CONSTANTS];
    int num_muxes;
    int mux_data_width[MAX_MUXES];
    int mux_num_inputs[MAX_MUXES];
    int mux_column_offset[MAX_MUXES];
    int num_mux_columns[MAX_MUXES];
    int num_FU;
    int FU_4_bit_blocks[MAX_FU];
    int FU_column_offset[MAX_FU];
    int num_FU_columns[MAX_FU];
    int num_blocks;
    int offset_blocks[MAX_COLUMN_OFFSETS];
  #endif 
  char PBS_name[MAX_CHARS_PER_PBS]; // Contains the name of the PBS wich represents the element 
  int size[2]; //Width, Height
} element_info_t;

typedef struct {
  #if FINE_GRAIN
    constant_t constants_definition[MAX_CONSTANTS]; // Fill the number of constants
    mux_t mux_definition[MAX_MUXES]; // Fill the number of muxes
	  FU_t FU_definition[MAX_FU];
    int constant_frame_address_position[MAX_CONSTANTS][MAX_COLUMNS_CONSTANT_PER_ELEMENT];
  	int first_bit_in_frame[MAX_CONSTANTS][MAX_COLUMNS_CONSTANT_PER_ELEMENT];
  	int last_bit_in_frame[MAX_CONSTANTS][MAX_COLUMNS_CONSTANT_PER_ELEMENT];
  	int mux_frame_address_position[MAX_MUXES][MAX_COLUMNS_MUX_PER_ELEMENT];
  	int first_LUT_in_frame[MAX_MUXES][MAX_COLUMNS_MUX_PER_ELEMENT];
  	int last_LUT_in_frame[MAX_MUXES][MAX_COLUMNS_MUX_PER_ELEMENT];
  	int LUT_position_in_frame[MAX_MUXES][MAX_COLUMNS_MUX_PER_ELEMENT];
  	int total_LUTs_in_mux[MAX_MUXES];
  	int FU_frame_address_position[MAX_FU][MAX_COLUMNS_FU_PER_ELEMENT];
  	int first_FU_block_in_frame[MAX_FU][MAX_COLUMNS_FU_PER_ELEMENT];
  	int last_FU_block_in_frame[MAX_FU][MAX_COLUMNS_FU_PER_ELEMENT];
  #endif 
  element_info_t *element_info;
} element_t;

typedef struct {
  int first_column;
  int last_column;
  int first_row;
  int last_row;
} location_info_t;

typedef struct {
  element_t element;
  // Position of the element (down-left corner) contains X and Y position respectively 
  int position[2]; //X, Y   
  location_info_t location_info;
} partition_t;

typedef struct {
  partition_t partition[MAX_WIDTH_VIRTUAL_ARCHITECTURE][MAX_HEIGHT_VIRTUAL_ARCHITECTURE]; 
  // Position of the overlay (down-left corner)
  int position[2];
} virtual_architecture_t;

// This array need to be initializated by the user with the different elements that can be
// allocated in the virtual architecture. An example is provided.
extern element_info_t elements[NUM_ELEMENTS];

/* Function declarations*/

/****************************************************************************/
/**
*
* Initializes all the components and variables needed to use multi-grain 
* reconfiguration
*
* @return   none
*
*****************************************************************************/
void init_virtual_architecture();
/****************************************************************************/
/**
*
* The virtual architecture variable is a matrix where each element represents 
* a region that can allocate a reconfigurable module. This function maps a 
* matrix element with coordinates of an FPGA.  
*
* @param virtual_architecture:  
* @param x: x coordinate of the virtual architecture matrix 
* @param y: y coordinate of the virtual architecture matrix 
* @param position_x: x FPGA coordinate
* @param position_y: x FPGA coordinate
* @return   none
*
*****************************************************************************/
void change_partition_position(virtual_architecture_t *virtual_architecture, int x, int y, int position_x, int position_y);
/****************************************************************************/
/**
*
* Once the virtual architecture matrix is mapped to specific FPGA coordinates,
* it is possible to start downloading reconfigurable modules. The 
* reconfigurable modules that can be used must be described by the user in the 
* elements variable located at IMPRESS_reconfiguration_parameters.c file. The 
* module is reconfigurated placing the left down corner of the module at the 
* FPGA location stored in the virtual architecture variable   
*
* @param virtual_architecture:  
* @param x: x coordinate of the virtual architecture matrix 
* @param y: y coordinate of the virtual architecture matrix 
* @param num_element: reconfigurable module position in elements variable
*
* @return  XST_SUCCESS or XST_FAILURE if the reconfigurable module could 
*           not be reconfigured correctly
*
*****************************************************************************/
int change_partition_element(virtual_architecture_t *virtual_architecture, int x, int y, int num_element);
#if FINE_GRAIN
  /****************************************************************************/
  /**
  *
  * This function is similar to change_partition_element but it does not  
  * reconfigure an element. Its purpose is to indicate that in that region there 
  * is a static region with fine-grain components. 
  *
  * @param virtual_architecture:  
  * @param x: x coordinate of the virtual architecture matrix 
  * @param y: y coordinate of the virtual architecture matrix 
  * @param num_element: reconfigurable module position in elements variable
  *
  * @return   none
  *
  *****************************************************************************/
  void add_fine_grain_static_region(virtual_architecture_t *virtual_architecture, int x, int y, int element_info);
  /****************************************************************************/
  /**
  *
  * This function can be used to change the value of a fine-grain constant of an 
  * element of the virtual architecture.
  * IMPORTANT: this function only reconfigures the internal frames representation 
  * variables. The FPGA is not reconfigured until reconfigure_fine_grain() is 
  * called. 
  *
  * @param virtual_architecture:  
  * @param x: x coordinate of the virtual architecture matrix 
  * @param y: y coordinate of the virtual architecture matrix 
  * @param constant_number: position of the constant to change as represented in 
  * the element variable 
  * @param value[MAX_WORDS_PER_CONSTANT] pointer to a vector that contains the 
  *        new value of the constant. If the constant has 32 or less bits, this
  *        variable is a pointer to an uint32_t variable.
  * @return   none
  *
  *****************************************************************************/
  void change_partition_constant(virtual_architecture_t *virtual_architecture, int x, int y, int constant_number, uint32_t value[MAX_WORDS_PER_CONSTANT]);
  /****************************************************************************/
  /**
  *
  * This function can be used to change the value of a fine-grain multiplexor of an 
  * element of the virtual architecture.
  * IMPORTANT: this function only reconfigures the internal frames representation 
  * variables. The FPGA is not reconfigured until reconfigure_fine_grain() is 
  * called. 
  *
  * @param virtual_architecture:  
  * @param x: x coordinate of the virtual architecture matrix 
  * @param y: y coordinate of the virtual architecture matrix 
  * @param mux_number: position of the multiplexor to change as represented in 
  * the element variable 
  * @param value: input that will be selected 
  * @return   none
  *
  *****************************************************************************/
  void change_partition_mux(virtual_architecture_t *virtual_architecture, int x, int y, int mux_number, int value);
  /****************************************************************************/
  /**
  *
  * This function can be used to change the value of a fine-grain FU of an 
  * element of the virtual architecture.
  * IMPORTANT: this function only reconfigures the internal frames representation 
  * variables. The FPGA is not reconfigured until reconfigure_fine_grain() is 
  * called. 
  *
  * @param virtual_architecture:  
  * @param x: x coordinate of the virtual architecture matrix 
  * @param y: y coordinate of the virtual architecture matrix 
  * @param FU_number: position of the FU to change as represented in 
  * the element variable 
  * @param value: new functionality of the FU
  * @return   none
  *
  *****************************************************************************/
  void change_partition_FU(virtual_architecture_t *virtual_architecture, int x, int y, int FU_number, FU_functions_t value);
  /****************************************************************************/
  /**
  *
  * It starts the fine-grain reconfiguration of all the fine-grain components 
  * that have been updated.
  *
  * @return   none
  *
  *****************************************************************************/
  void reconfigure_fine_grain();
#endif

#endif


