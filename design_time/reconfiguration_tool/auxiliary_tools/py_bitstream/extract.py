#!/usr/bin/env python2
# -*- coding: utf-8 -*-

"""
Example implementation of the bitstream manipulation tools
"""

import sys    # sys.argv
from tools import bitstream    # Bitstream class and methods


if len(sys.argv) == 1:
    print "=== Bit Extraction tool (interactive mode) ==="
    print
    
    while True:
        fname = raw_input('> Enter .bit file name (Return to exit): ')
        if not fname: sys.exit()
        try:
            bs = bitstream.Bitstream(fname)
            break
        except IOError:
            print "*** File '%s' not found!" % fname
    print
    print "--- Bitstream from file %s ---" % fname
    bs.info()
    print
    
    while True:
        rng = raw_input('> Enter range (Return to exit, "?" for examples): ')
        if not rng: sys.exit()
        if rng != "?": break
        
        print
        print '7,43:45'
        print '    "Cut" row 7, columns 43 and 44 (45 not included)'
        print '7,43:45,0:10'
        print '    Same, but only write first (bottom) 10 words of each row (compactly; '
        print '    without the extra space before the 10 words of the next frame)'
        print
    
    print "Extracting bitstream[%s]" % rng
    chunk = eval("bs[%s]" % rng)    # Yes!  I used eval()!  Sue me!
    print "Extracted %d bytes from %s" % (len(chunk), fname)
    
    fname2 = raw_input('> Enter .pbs file name to save chunk to (Return to cancel): ')
    if not fname2: sys.exit()
    with open(fname2, 'wb') as pbs:
        pbs.write(chunk)
    print "File %s written" % fname2


elif sys.argv[1] in ["-h", "-?", "--help"]:
    print 'Usage:  %s origin.bit [range dest.pbs]' % sys.argv[0]
    print 'Examples:'
    print '    %s top.bit 7,43:45 element.pbs' % sys.argv[0]
    print '        "Cut" row 7, columns 43 and 44 (45 not included) and save them to '
    print '        element.pbs'
    print '    %s top.bit 7,43:45,0:10 element.pbs' % sys.argv[0]
    print '        Same, but only write first (bottom) 10 words of each row (compactly; '
    print '        without the extra space before the 10 words of the next frame)'

elif len(sys.argv) == 2:
    bs = bitstream.Bitstream(sys.argv[1])
    print "=== Bitstream from file %s ===" % sys.argv[1]
    bs.info()

elif len(sys.argv) == 4:
    bs = bitstream.Bitstream(sys.argv[1])
    chunk = eval("bs[%s]" % sys.argv[2])    # Yes!  I used eval()!  Sue me!
    with open(sys.argv[3], 'wb') as pbs:
        pbs.write(chunk)

