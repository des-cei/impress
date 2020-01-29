#!/usr/bin/env python2
# -*- coding: utf-8 -*-

"""
Interactive Python console with Bitstream tools and some extended capabilities:
* ``!command``-style system commands
* history and auto-completion
"""

import code           # interactive console
import subprocess     # for the !-syntax

try:
    import readline       # adding this allows using up/down arrows on the interactive console
    import rlcompleter    # auto-completion for readline
    readline.parse_and_bind("tab: complete")
except ImportError:
    pass


def parsed_input(*args):
    s = raw_input(*args)
    sstrip = s.lstrip()
    while sstrip[:1] == '!':
        subprocess.call(sstrip[1:], shell=True)
        s = raw_input(*args)
        sstrip = s.lstrip()
    return s


from tools.bitstream import *

try:
    XUPV5 = Bitstream("examples/XUPV5.bit")
    ML510 = Bitstream("examples/ML510.bit")
    HIRE  = Bitstream("examples/S6LX150.bit")
    ATLYS = Bitstream("examples/ATLYS.bit")
    ATLYS.set_fpga("spartan6")
except IOError:
    pass


code.interact(readfunc=parsed_input, local=locals())    # read-eval-print loop (interactive console)


# TODO:
# * Make leading tabs write actual tabs (or better, 4-spaces) rather than 
#   trying to auto-complete
# * Auto-complete !-commands bash style (what if windows?)


