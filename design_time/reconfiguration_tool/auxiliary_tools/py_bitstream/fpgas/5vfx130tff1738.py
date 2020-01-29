# Definition file for Virtex-5 FX130T-FF1738  (the one on the ML510 board)

from .virtex5 import *

model_name = "Virtex-5 FX130T-FF1738"


#~ PPC  = [( 0, '')]
_PAD = [(34, '')]
#~ _PAD = [( 0, '')]


#~ __row = (
       #~ IOB  + 4*CLB 
    #~ + (BRAM + 6*CLB) * 3 
    #~ +  BRAM + 2*CLB 
    #~ + (DSP  + 2*CLB) * 2 
    #~ +  BRAM + 4*CLB 
    #~ +  IOB  + CLK + 4*CLB 
    #~ +  BRAM + 2*CLB 
    #~ + (DSP  + 2*CLB) * 2 
    #~ +  BRAM + 6*CLB 
    #~ +  BRAM + 4*CLB 
    #~ +  IOB  + 4*CLB + BRAM + _PAD
#~ )
#~ 
#~ __row_PPC = (
       #~ IOB  + 4*CLB 
    #~ +  BRAM + 4*CLB 
    #~ + 14*PPC+ 2*CLB     # <-- HERE
    #~ +  BRAM + 2*CLB 
    #~ + (DSP  + 2*CLB) * 2 
    #~ +  BRAM + 4*CLB 
    #~ +  IOB  + CLK + 4*CLB 
    #~ +  BRAM + 2*CLB 
    #~ + (DSP  + 2*CLB) * 2 
    #~ +  BRAM + 6*CLB 
    #~ +  BRAM + 4*CLB 
    #~ +  IOB  + 4*CLB + BRAM + _PAD
#~ )
#~ 
#~ table = [
    #~ __row,
    #~ __row,
    #~ __row_PPC,
    #~ __row_PPC,
    #~ __row,
    #~ __row,
    #~ __row_PPC,
    #~ __row_PPC,
    #~ __row,
    #~ __row,
#~ ]

table = 10 * [
       IOB  + 4*CLB 
    + (BRAM + 6*CLB) * 3 
    +  BRAM + 2*CLB 
    + (DSP  + 2*CLB) * 2 
    +  BRAM + 4*CLB 
    +  IOB  + CLK + 4*CLB 
    +  BRAM + 2*CLB 
    + (DSP  + 2*CLB) * 2 
    +  BRAM + 6*CLB 
    +  BRAM + 4*CLB 
    +  IOB  + 4*CLB 
    +  BRAM 
    +  _PAD    # I don't know what's this pad; it's not documented anywhere
]

bitstream_order = [5, 6, 7, 8, 9,   4, 3, 2, 1, 0]


