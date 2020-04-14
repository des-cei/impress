from .series7 import *

# model name
model_name = "Zynq 70100-FFG900"

_row_common = (
    IOBA+IOBB+4*CLB   
    + BRAM +  2*CLB   
    + DSP  +  4*CLB   
    + DSP  +  2*CLB  
    + BRAM +  4*CLB   
    + BRAM +  2*CLB 
    + DSP  +  5*CLB
    + DSP  +  2*CLB 
    + BRAM +  2*CLB 
    + DSP  +  4*CLB 
    + DSP  +  2*CLB 
    + BRAM +  6*CLB
    + CFG  +  4*CLB 
    + DSP  +  2*CLB 
    + BRAM +  2*CLB
    + DSP  +  5*CLB
    + CLK  +  9*CLB 
    + DSP  +  2*CLB 
    + BRAM +  2*CLB
    + DSP  +  10*CLB 
    + DSP  +  2*CLB 
    + BRAM +  2*CLB
    + DSP  +  7*CLB 
    + DSP  +  2*CLB
    + BRAM +  3*CLB
    + DSP  +  2*CLB 
    + BRAM +  5*CLB
    + BRAM +  2*CLB
    + DSP  +  3*CLB 
)

table = 4 * [
    _row_common       
    + GT 
    + PAD
] + 3 * [
    _row_common       
    + BRAM +  4*CLB   
    + IOBB+IOBA       
    + PAD             
]

# How rows are arranged in the bitstream.  0 = bottom row
bitstream_order = [3, 4, 5, 6,   2, 1, 0]