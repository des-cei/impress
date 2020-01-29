# Definition file for Zynq 7020-CLG484  (the one on the Zedboard)

# FPGA family
from .series7 import *

# model name
model_name = "Kintex 7 325T-FFG900"


# table: list of lists.
# 
# Each of those lists represents an FPGA row, with table[0] representing 
# the bottommost row.
# You can create these lists by concatenating (adding) the BRAM, CLB, etc 
# one-tuple lists defined in the FPGA family module.
# 
# If you created several identical rows by multiplying a single one, 
# like ``table = 8 * [BRAM + CLB]``, and want to change an element afterwards, 
# don't just modify table[i][j] since this will affect the other rows as well. 
# If you're going to do this, better do 
# ``table = [BRAM + CLB for i in xrange(8)]``
# 
# Also notice that if the first row is the bottom one, and you declare 
# this list explicitly, the first element will be first in the code 
# (and thus it'll be the top one). 
# In that case you could just add ``[::-1]`` at the end.
# 
# NB: rows on this FPGA are not identical!

_row_common = (
    IOBA+IOBB+4*CLB   # 0-5
    + BRAM +  2*CLB   # 6-8
    + DSP  +  4*CLB   # 9-13
    + DSP  +  2*CLB   # 14-16
    + BRAM +  6*CLB   # 17-23
    + CFG  +  7*CLB   # 24-31
    + BRAM +  2*CLB   # 32-34
    + DSP  + 13*CLB   # 35-48
    + CLK  + 12*CLB   # 49-61
    + BRAM +  2*CLB   # 62-64
    + DSP  +  5*CLB   # 65-70
    + DSP  +  2*CLB   # 71-73
    + BRAM +  5*CLB   # 74-79
    + BRAM +  2*CLB   # 80-82
    + DSP  +  5*CLB   # 83-88
)

table = 3 * [
    _row_common       # 0-88
    + BRAM +  4*CLB   # 89-93
    + IOBB+IOBA       # 94-95
    + PAD             # 96
] + 4 * [
    _row_common       # 0-88
    + GT              # 89    !TODO! Check that there are no zero-width columns
    + PAD             # 90
]

# How rows are arranged in the bitstream.  0 = bottom row
bitstream_order = [3, 4, 5, 6,   2, 1, 0]
