/*
 * reconfig_pcap.h
 *
 *  Created on: 09/04/2014
 *      Author: Alfonso
 */

#ifndef RECONFIG_PCAP_H_
#define RECONFIG_PCAP_H_

/***************************** Include Files ********************************/
#include "xil_types.h"
#include "xdevcfg.h"


/**************************** Constant Definitions *******************************/

// Erase BRAM content flags
#define PCAP_BRAM_ERASE             1
#define PCAP_BRAM_DONOTHING         0

// Safe area around each PBS memory storage
#define SAFE_AREA 0x1000

// IDCODE's for the Zynq Devices
#define PCAP_XC7Z010                0x03722093
#define PCAP_XC7Z020                0x03727093
#define PCAP_XC7Z030                0x0372C093
#define PCAP_XC7Z045                0x03731093

// Configuration Type1/Type2 packets header masks
#define PCAP_TYPE_MASK              0x7
#define PCAP_REGISTER_MASK          0x1F
#define PCAP_OP_MASK                0x3

#define PCAP_WORD_COUNT_MASK_TYPE_1	0x7FF
#define PCAP_WORD_COUNT_MASK_TYPE_2	0x07FFFFFF

#define PCAP_TYPE_SHIFT             29
#define PCAP_REGISTER_SHIFT         13
#define PCAP_OP_SHIFT               27

#define PCAP_TYPE_1                 1
#define PCAP_TYPE_2                 2
#define PCAP_OP_WRITE               2
#define PCAP_OP_READ                1

// Addresses of the Configuration Registers
#define PCAP_CRC                    0
#define PCAP_FAR                    1
#define PCAP_FDRI                   2
#define PCAP_FDRO                   3
#define PCAP_CMD                    4
#define PCAP_CTL                    5
#define PCAP_MASK                   6
#define PCAP_STAT                   7
#define PCAP_LOUT                   8
#define PCAP_COR                    9
#define PCAP_MFWR                   10
#define PCAP_CBC                    11 // In some packets appears as 19
#define PCAP_IDCODE                 12
#define PCAP_AXSS                   13
#define PCAP_C0R_1                  14
#define PCAP_CSOB                   15
#define PCAP_WBSTAR                 16
#define PCAP_TIMER                  17
#define PCAP_BOOTSTS                22
#define PCAP_CTL_1                  24
#define PCAP_NUM_REGISTERS          25
#define PCAP_COR_1                  14

// Frame Address Register mask(s)
#define PCAP_FAR_BLOCK_MASK         0x7
#define PCAP_FAR_TOP_BOTTOM_MASK    0x1
#define PCAP_FAR_MAJOR_FRAME_MASK   0xFF
#define PCAP_FAR_ROW_ADDR_MASK      0x1F
#define PCAP_FAR_MINOR_FRAME_MASK   0xFF
#define PCAP_FAR_COLUMN_ADDR_MASK   0xFF
#define PCAP_FAR_MINOR_ADDR_MASK    0x7F
#define PCAP_FAR_BLOCK_SHIFT        23//21
#define PCAP_FAR_TOP_BOTTOM_SHIFT   22//20
//#define PCAP_FAR_MAJOR_FRAME_SHIFT  17
#define PCAP_FAR_ROW_ADDR_SHIFT     17//15
//#define PCAP_FAR_MINOR_FRAME_SHIFT  9
#define PCAP_FAR_COLUMN_ADDR_SHIFT  7
#define PCAP_FAR_MINOR_ADDR_SHIFT   0

// Address Block Types in the  Frame Address Register
#define PCAP_FAR_CLB_BLOCK          0 // CLB/IO/CLK Block
#define PCAP_FAR_BRAM_BLOCK         1 // Block RAM interconnect

// Configuration Commands
#define PCAP_CMD_NULL               0
#define PCAP_CMD_WCFG               1
#define PCAP_CMD_MFW                2
#define PCAP_CMD_DGHIGH             3
#define PCAP_CMD_RCFG               4
#define PCAP_CMD_START              5
#define PCAP_CMD_RCAP               6
#define PCAP_CMD_RCRC               7
#define PCAP_CMD_AGHIGH             8
#define PCAP_CMD_SWITCH             9
#define PCAP_CMD_GRESTORE           10
#define PCAP_CMD_SHUTDOWN           11
#define PCAP_CMD_GCAPTURE           12
#define PCAP_CMD_DESYNCH            13

#define PCAP_CMD_IPROG              15
#define PCAP_CMD_CRCC               16
#define PCAP_CMD_LTIMER             17
#define PCAP_TYPE_2_READ            ((PCAP_TYPE_2 << PCAP_TYPE_SHIFT) | (PCAP_OP_READ << PCAP_OP_SHIFT))
#define PCAP_TYPE_2_WRITE           ((PCAP_TYPE_2 << PCAP_TYPE_SHIFT) | (PCAP_OP_WRITE << PCAP_OP_SHIFT))

// Packet constants
#define PCAP_BW_SYNC                0x000000BB
#define PCAP_BW_DETECT              0x11220044
#define PCAP_SYNC_PACKET            0xAA995566
#define PCAP_DUMMY_PACKET           0xFFFFFFFF
#define PCAP_DEVICE_ID_READ         0x28018001
#define PCAP_NOOP_PACKET            (PCAP_TYPE_1 << PCAP_TYPE_SHIFT)

#define PCAP_TYPE_1_PACKET_MAX_WORDS 2047
#define PCAP_TYPE_1_HEADER_BYTES     4
#define PCAP_TYPE_2_HEADER_BYTES     8

#define PCAP_NUM_FRAME_BYTES                 404 //324  // Number of bytes in a frame
#define PCAP_NUM_FRAME_WORDS                 101 //81   // Number of Words in a frame (101 32-bit words?)
#define PCAP_NUM_WORDS_FRAME_INCL_NULL_FRAME 202 //162 // Num of Words in a frame read from the device including the NULL frame
#define BYTES_PER_WORD_OF_FRAME				 4

//// Device Resources
//#define CLB                         0
//#define DSP                         1
//#define BRAM                        2
//#define BRAM_INT                    3
//#define IOB                         4
//#define IOI                         5
//#define CLK                         6
//#define MGT                         7

// The number of words reserved for the header
#define PCAP_HEADER_BUFFER_WORDS    20
#define PCAP_HEADER_BUFFER_BYTES    (PCAP_HEADER_BUFFER_WORDS << 2)


// CLB major frames start at 3 for the first column (since we are using
// column numbers that start at 1, when the column is added to this offset,
// that first one will be 3 as required.
#define PCAP_CLB_MAJOR_FRAME_OFFSET 2

// Constant to use for CRC check when CRC has been disabled
#define PCAP_DISABLED_AUTO_CRC      0x0000DEFC
#define PCAP_DISABLED_AUTO_CRC_ONE  0x9876
#define PCAP_DISABLED_AUTO_CRC_TWO  0xDEFC

// Major Row Offset
#define PCAP_CLB_MAJOR_ROW_OFFSET   96+(32*PCAP_HEADER_BUFFER_WORDS)-1

// Number of times to poll the Status Register
#define PCAP_MAX_RETRIES            1000

// Mask for the Device ID read from the ID code Register
#define PCAP_DEVICE_ID_CODE_MASK    0x0FFFFFFF

//When we save a PBS it is divided as reconfigurable sections. One for each pblock, and for each
//pblock one for each used clock region
#define MAX_RECONFIGURABLE_CLOCK_REGIONS 15

//Struct definition 
typedef struct {
	int X0;
	int Y0;
	int Xf;
	int Yf;
} pblock;


/***************** Macros (Inline Functions) Definitions *********************/

/****************************************************************************/
/**
*
* Generates a Type 1 packet header that reads back the requested Configuration
* register.
*
* @param	Register is the address of the register to be read back.
*
* @return	Type 1 packet header to read the specified register
*
* @note		None.
*
*****************************************************************************/
#define PCAP_Type1Read(Register) \
	( (PCAP_TYPE_1 << PCAP_TYPE_SHIFT) | ((Register) << PCAP_REGISTER_SHIFT) | \
	(PCAP_OP_READ << PCAP_OP_SHIFT) )

/****************************************************************************/
/**
*
* Generates a Type 2 packet header that reads back the requested Configuration
* register.
*
* @param	Register is the address of the register to be read back.
*
* @return	Type 1 packet header to read the specified register
*
* @note		None.
*
*****************************************************************************/
#define PCAP_Type2Read(Register) \
	( PCAP_TYPE_2_READ | ((Register) << PCAP_REGISTER_SHIFT))

/****************************************************************************/
/**
*
* Generates a Type 1 packet header that writes to the requested Configuration
* register.
*
* @param	Register is the address of the register to be written to.
*
* @return	Type 1 packet header to write the specified register
*
* @note		None.
*
*****************************************************************************/
#define PCAP_Type1Write(Register) \
	( (PCAP_TYPE_1 << PCAP_TYPE_SHIFT) | ((Register) << PCAP_REGISTER_SHIFT) | \
	(PCAP_OP_WRITE << PCAP_OP_SHIFT) )

/****************************************************************************/
/**
*
* Generates a Type 2 packet header that writes to the requested Configuration
* register.
*
* @param	Register is the address of the register to be written to.
*
* @return	Type 1 packet header to write the specified register
*
* @note		None.
*
*****************************************************************************/
#define PCAP_Type2Write(Register) \
	( (PCAP_TYPE_2 << PCAP_TYPE_SHIFT) | ((Register) << PCAP_REGISTER_SHIFT) | \
	(PCAP_OP_WRITE << PCAP_OP_SHIFT) )

/****************************************************************************/
/**
*
* Generates a Type 1 packet header that is written to the Frame Address
* Register (FAR) for a 7-Series device.
*
* @param	Block - Address Block Type (CLB or BRAM address space)
* @param	Top - top (0) or bottom (1) half of device
* @param	Row - Row Address
* @param	ColumnAddress - CLB or BRAM column
* @param	MinorAddress - Frame within a column
*
* @return	Type 1 packet header to write the FAR
*
* @note		None.
*
*****************************************************************************/
#define PCAP_SetupFar7S(Top, Block, Row, ColumnAddress, MinorAddress)  \
	((Block) << PCAP_FAR_BLOCK_SHIFT) | \
	(((Top) << PCAP_FAR_TOP_BOTTOM_SHIFT) | \
	((Row) << PCAP_FAR_ROW_ADDR_SHIFT) | \
	((ColumnAddress) << PCAP_FAR_COLUMN_ADDR_SHIFT) | \
	((MinorAddress) << PCAP_FAR_MINOR_ADDR_SHIFT))


/************************** Function Prototypes ******************************/

/****************************************************************************/
/**
*
* Loads a partial bitstream file from the external SD card to the on-board RAM
*
* @param file_name is the name of the PBS file stored in the SD card
* @param addr_start is the initial position of the PBS in the RAM
*
* @return final position of the PBS in the RAM
*
*****************************************************************************/
u32 load_bitstream_from_SD_to_RAM(const char *file_name, u32 *addr_start);

/****************************************************************************/
/**
*
* Stores a partial bitstream file from the on-board RAM to the external SD card
*
* @param file_name is the name of the PBS file to be stored in the SD card
* @param addr_start is the initial position of the PBS in the RAM
* @param TotalWords is the amount of configuration words that the PBS contains
*
* @return final position of the PBS in the RAM
*
*****************************************************************************/
u32 load_bitstream_from_RAM_to_SD(const char *file_name, u32 *addr_start, u32 TotalWords);

/****************************************************************************/
/**
*
* Initializes PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance
*
* @return	XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_Initialize(XDcfg *InstancePtr, u16 DeviceId);

/****************************************************************************/
/**
*
* Writes PBS file using PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance.
* @param addr_ini is a pointer to the frame that is to be written to the device
* @param addr_end is the value of the last memory position of the PBS
* @param x0, y0, xf, yf are the coordinates of the region to be reconfigured
* @param erase_bram is a control parameter used to erase BRAM contents through the configuration port
*
* @return	XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_RAM_write(XDcfg *InstancePtr, u32 *addr_start, u32 addr_end, u32 x0, u32 y0, u32 xf, u32 yf, u32 erase_bram);

/****************************************************************************/
/**
*
* Reads PBS file using PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance.
* @param addr_ini is a pointer to the memory addres that will store data read from the device
* @param TotalWords is total amount of words that the PCAP has to read
* @param x0, y0, xf, yf are the coordinates of the region to be reconfigured
*
* @return	XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_RAM_read(XDcfg *InstancePtr, u32 **addr_start, u32 x0, u32 y0, u32 xf, u32 yf);

int write_subclock_region_PBS(XDcfg *InstancePtr, u32 *addr_start, const char *file_name, pblock pblock_list[], u32 num_pblocks, u32 erase_bram);

#endif /* RECONFIG_PCAP_H_ */
