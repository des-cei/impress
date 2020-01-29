/*
 * xc7z020.h
 *
 *  Created on: 30/05/2014
 *      Author: Alfonso
 */

#ifndef XC7Z020_H_
#define XC7Z020_H_

#include "series7.h"
#include "xil_types.h"

#define MAX_ROWS    3 //clock region rows
#define MAX_COLUMNS 74

// BRAM content definitions
#define BRAM_CONTENT   1
#define BRAM_NOCONTENT 0

// Clock region definitions
#define BOTTOM 1
#define TOP    0
#define ROW0   0
#define ROW1   1

// Block type definition
#define CLB_L_TYPE 		0
#define CLB_M_TYPE 		1
#define DSP_TYPE 		2
#define BRAM_TYPE 		3
#define IOBA_TYPE 		4
#define IOBB_TYPE 		5
#define CLK_TYPE 		6
#define CFG_TYPE		7
#define GT_TYPE 		8


// ID generation
#define block(top, row, type)  ((top<<24) | (row<<16) | (type))
#define content(yes_no, major)  ((yes_no<<16) | (major))


// FPGA matrix
extern const u32 fpga[MAX_ROWS][MAX_COLUMNS][2];

// FPGA bram matrix
extern const u32 fpga_bram[MAX_ROWS][MAX_COLUMNS];

#endif /* XC7Z020_H_ */
