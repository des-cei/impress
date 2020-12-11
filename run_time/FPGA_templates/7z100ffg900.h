#ifndef FPGA_NAME_H
#define FPGA_NAME_H


#include "series7.h"
#include "xil_types.h"

// BRAM content definitions
#define BRAM_CONTENT   1
#define BRAM_NOCONTENT 0

// Block type definition
#define CLB_L_TYPE 		0
#define CLB_M_TYPE 		1
#define DSP_TYPE 			2
#define BRAM_TYPE 		3
#define IOBA_TYPE 		4
#define IOBB_TYPE 		5
#define CLK_TYPE 			6
#define CFG_TYPE			7
#define GT_TYPE 			8

#define MAX_ROWS    7
#define MAX_COLUMNS 352

extern const u32 fpga[MAX_ROWS][MAX_COLUMNS][2];

extern const u32 fpga_bram[MAX_ROWS][MAX_COLUMNS];

#endif
