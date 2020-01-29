# Definition file for Virtex-5 LX110T-FF1136  (the one on the XUPV5 board)

# FPGA family
from .virtex5 import *

# model name
model_name = "Virtex-5 LX110T-FF1136"


# table: list of lists of tuples.
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

_PAD = [(34, '')]

table = 8 * [
      IOB   +  4 * CLB
    + BRAM  + 10 * CLB
    + BRAM  +  2 * CLB
    + DSP   +  8 * CLB
    + IOB 
    + CLK   + 12 * CLB
    + BRAM  + 10 * CLB
    + BRAM  +  4 * CLB
    + IOB   +  4 * CLB
    + BRAM
    + _PAD
]

# How rows are arranged in the bitstream.  0 = bottom row
bitstream_order = [4, 5, 6, 7,   3, 2, 1, 0]


