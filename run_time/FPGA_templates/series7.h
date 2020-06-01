#ifndef series7_H
#define series7_H

// FPGA sizes

#define ROWS_PER_CLOCK_REGION 50 //Number of rows per clock region
#define CLOCK_WORDS 1
#define WORDS_PER_ROW_IN_CLOCK_REGION 2 //Number of words per each row 

//#define CLBS_IN_A_CLOCK_REGION_COLUMN ROWS_PER_CLOCK_REGION
//#define DSP_IN_A_CLOCK_REGION_COLUMN 10
//#define RAM_IN_A_CLOCK_REGION_COLUMN 10

// Block type definitions
#define IOB_A  42
#define IOB_B  30
#define CLB    36
#define BRAM   28
#define DSP    28
#define CLK    30
#define CFG    30
#define GT     32

#define NUM_FRAME_BYTES                 404 
#define NUM_FRAME_WORDS                 101 
#define BYTES_PER_WORD_OF_FRAME				 	4
#define FRAMES_CLK_INTERCONNECT 		    26


#endif
