# Definition file for Zynq 7020-CLG400  (the one on the PYNQ)

# FPGA family
from .series7 import *

# model name
model_name = "Zynq 7020-CLG400"


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

table = 3 * [
    IOBA+IOBB+4 * CLB   # 0-5
    + BRAM +  2 * CLB   # 6-8
    + DSP  +  4 * CLB   # 9-13
    + DSP  +  2 * CLB   # 14-16
    + BRAM +  4 * CLB   # 17-21
    + BRAM +  2 * CLB   # 22-24
    + DSP  +  7 * CLB   # 25-32
    + CLK  +  2 * CLB   # 33-35
    + BRAM + 13 * CLB   # 36-49
    + CFG  +  5 * CLB   # 50-55
    + BRAM +  2 * CLB   # 56-58
    + DSP  +  4 * CLB   # 59-63
    + DSP  +  2 * CLB   # 64-66
    + BRAM +  4 * CLB   # 67-71
    + IOBB+IOBA         # 72-73
    + PAD               # 74
]

# How rows are arranged in the bitstream.  0 = bottom row
bitstream_order = [2,   1, 0]
