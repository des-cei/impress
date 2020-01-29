# Definition file for Spartan-6 LX150-FGG484  (the one on the HiRe Cookie)

from .spartan6 import *

model_name = "Spartan-6 LX150-FGG484"

_CLBLM = CLBL + CLBM  # shortcut; same as writing (CLBL+CLBM)

table = 12 * [
    CFG + IOB + _CLBLM + BRAM + _CLBLM + DSP # DSP_1
    + 5*_CLBLM + BRAM + _CLBLM + CLBL + DSP # DSP_2
    + 2*_CLBLM + CLBL + BRAM + CLBM + 5*_CLBLM + CLBLD # CLBL+DCM
    + CLBM + 4*_CLBLM + CLBL + BRAM + 2*_CLBLM + CLBL + DSP1 # DSP_3
    + _CLBLM + CLBL + BRAM + CLBM + 3*_CLBLM + CLBL + DSP # DSP_4
    + CLBM + CLBL + BRAM + CLBM + CLBL + IOB + PAD
]

# How rows are arranged in the bitstream: 0, 1, 2 ... 11
bitstream_order = range(12)
