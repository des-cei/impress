from .unknown import *  # Dummy variables to be filled when the FPGA model is loaded

# Generic name
model_name = "Virtex-5, unknown model"

# Frame and word sizes
frame = 41
word = 4

# Tuples containing the size in frames of a column of each type and the type name.
# UG191 table 6-16
BRAM = [(30, 'BRAM')]
CLB  = [(36, 'CLB' )]
CLK  = [( 4, 'CLK' )]
DSP  = [(28, 'DSP' )]
IOB  = [(54, 'IOB' )]


# Sequence to identify that the rcfg part starts
sequence = "\x30\x00\x40\x00"
sequence_offset = 8
sequence_size_mask = 0x07FFFFFF



# Function for interpreting the config string
import struct  # used in dump()

# (UG191 table 6-6)
_commands = {
    0b00000: "NULL     (Null Command)",
    0b00001: "WCFG     (Write Configuration Data)",
    0b00010: "MFW      (Multiple Frame Write)",
    0b00011: "LFRM     (Last Frame)",
    0b00100: "RCFG     (Read Configuration Data)",
    0b00101: "START    (Begin the Startup Sequence)",
    0b00110: "RCAP     (Reset the CAPTURE signal)",
    0b00111: "RCRC     (Reset the CRC register)",
    0b01000: "AGHIGH   (Assert the GHIGH_B signal)",
    0b01001: "SWITCH   (Switch the CCLK frequency)",
    0b01010: "GRESTORE (Pulse the GRESTORE signal)",
    0b01011: "SHUTDOWN (Begin the shutdown sequence)",
    0b01100: "GCAPTURE (Pulse GCAPTURE)",
    0b01101: "DESYNCH  (Reset the DALIGN Signal)",
    0b10000: "CRCC     (Calculate CRC)",
    0b01111: "IPROG    (Internal PROG for triggering a warm boot)",
    0b10001: "LTIMER   (Reload watchdog timer)",
}

# (UG191 table 6-5)
# s/(.*) (.*) ([01]{5}) (.*)/    0b\3: "\1 (\4)",/
_regs = {
    0b00000: "CRC     (CRC Register)",
    0b00001: "FAR     (Frame Address Register)",
    0b00010: "FDRI    (Frame Data Register, Input Register (write configuration data))",
    0b00011: "FDRO    (Frame Data Register, Output Register (read configuration data))",
    0b00100: "CMD     (Command Register)",
    0b00101: "CTL0    (Control Register 0)",
    0b00110: "MASK    (Masking Register for CTL0 and CTL1)",
    0b00111: "STAT    (Status Register)",
    0b01000: "LOUT    (Legacy Output Register (DOUT for daisy chain))",
    0b01001: "COR0    (Configuration Option Register 0)",
    0b01010: "MFWR    (Multiple Frame Write Register)",
    0b01011: "CBC     (Initial CBC Value Register)",  # (according to UG191. This is incorrect; it's actually 0b10011)
    0b01100: "IDCODE  (Device ID Register)",
    0b01101: "AXSS    (User Bitstream Access Register)",
    0b01110: "COR1    (Configuration Option Register 1)",
    0b01111: "CSOB    (Used for daisy chain parallel interface, similar to LOUT)",
    0b10000: "WBSTAR  (Warm Boot Start Address Register)",
    0b10001: "TIMER   (Watchdog Timer Register)",
    0b10110: "BOOTSTS (Boot History Status Register)",
    0b11000: "CTL1    (Control Register 1)",
    
    0b10011: "CBC     (Initial CBC Value Register) (Wrongly documented; typo in UG191)",
}


def dump(s, print_offset=True):
    """Dump de-compiled content"""
    
    res = []
    
    i = 0
    while i < len(s):
        if print_offset:  res.append("%8d: " % i)
        
        if s[i : i+word] == "\xFF\xFF\xFF\xFF":
            n = 1
            while s[i+word*n : i+word*(n+1)] == "\xFF\xFF\xFF\xFF":
                n += 1
            if n == 1:
                res.append("FFFFFFFF    Dummy Word\n")
            else:
                res.append("FFFFFFFF{*%d}    Dummy Word\n" % n)
            i += word*n
        
        elif s[i : i+word] == "\xAA\x99\x55\x66":
            res.append("AA995566    Sync Word\n")
            i += word
        
        elif s[i : i+2*word] == "\x00\x00\x00\xBB\x11\x22\x00\x44":
            res.append("000000BB 11220044    Bus Width Detection Pattern\n")
            i += 2*word
        
        elif s[i : i+word] == "\x20\x00\x00\x00":
            n = 1
            while s[i+word*n : i+word*(n+1)] == "\x20\x00\x00\x00":
                n += 1
            if n == 1:
                res.append("20000000    NOOP\n")
            else:
                res.append("20000000{*%d}    NOOP\n" % n)
            i += word*n
        
        elif s[i : i+word] == "\x30\x00\x80\x01":
            cmd = struct.unpack(">I", s[i+word : i+2*word])[0]
            res.append("30008001 %08X    Send command %s\n" 
                    % (cmd, _commands.get(cmd, "%08X <unknown>" % cmd)))
            i += 2*word
        
        else:
            instr = struct.unpack(">I", s[i : i+word])[0]
            itype = (instr >> 29) & 0x7   # 1=Type-1  2=Type-2
            idir  = (instr >> 27) & 0x3   # 1=Read    2=Write
            ireg  = (instr >> 13) & 0x1F  # 0..31; see _regs
            isize = (instr >>  0) & 0x7FF # unused when type-2
            
            if itype == 1 and idir == 1 and isize != 0:
                res.append("%08X    Read %d words from %s\n" 
                        % (instr, isize, 
                        _regs.get(ireg, "register %08X <unknown>" % ireg)))
                i += word
            
            elif itype == 1 and idir == 1 and isize == 0:
                sizew = struct.unpack(">I", s[i+word : i+2*word])[0]
                isize = sizew & sequence_size_mask
                res.append("%08X %08X    Read %d words from %s\n" 
                        % (instr, sizew, isize, 
                        _regs.get(ireg, "register %08X <unknown>" % ireg)))
                i += 2*word
            
            elif itype == 1 and idir == 2 and isize != 0:
                cmd = ''.join(" %08X" % struct.unpack(">I", s[j:j+word])[0] 
                              for j in xrange(i+word, i+word*(1+isize), word))
                res.append("%08X%s    Write%s to %s\n" 
                        % (instr, cmd, cmd, 
                        _regs.get(ireg, "register %08X <unknown>" % ireg)))
                i += word*(1+isize)
            
            elif itype == 1 and idir == 2 and isize == 0:
                sizew = struct.unpack(">I", s[i+word : i+2*word])[0]
                isize = sizew & sequence_size_mask
                res.append("%08X %08X    Write %d words to %s\n" 
                        % (instr, sizew, isize, 
                        _regs.get(ireg, "register %08X <unknown>" % ireg)))
                if print_offset:  res.append("%8d: " % (i + 2*word))
                res.append("XXXXXXXX{*%d}    (data)\n" % isize)
                #~ ##!!DEBUG!!## vv
                #~ print "<<<DEBUG>>> %s ...%s" % (
                    #~ ''.join(" %08X" % struct.unpack(">I", s[j:j+word])[0] 
                            #~ for j in xrange(i+word*3, i+word*(3+5), word)),
                    #~ ''.join(" %08X" % struct.unpack(">I", s[j:j+word])[0] 
                            #~ for j in xrange(i+word*(3+isize-5), i+word*(3+isize), word))
                #~ )
                #~ ##!!DEBUG!!## ^^
                
                i += word*(2+isize)
                #~ crc = "%08X %08X" % struct.unpack(">2I", s[i+word*(isize+3) : i+word*(isize+5)])
                #~ res.append("%s    CRC = %s (not sure about this)\n" % (crc, crc))
                #~ i += word*(isize+5)
            
            else:
                res.append("%08X    ?\n" % struct.unpack(">I", s[i : i+word])[0])
                i += word
    
    if print_offset:  res.append("%8d: -- end --" % i)
    
    return "".join(res)



#~ def fix_crc(tail, crc=None):
    #~ """
    #~ Replace the CRC value with the provided one.
    #~ 
    #~ Alternatively, insert a "Clear CRC" command right after it 
    #~ (if None is provided instead of an actual CRC).
    #~ 
    #~ ``tail`` should be a bytearray.  Bytearrays are kinda "passed by 
    #~ reference", so modifying its content here will reflect on the variable 
    #~ passed.
    #~ """
    #~ pos = tail.index("\x30\x00\x00\x01") + word
    #~ 
    #~ if crc is None:
        #~ # Insert "reset CRC" right after CRC
        #~ tail[pos+4 : pos+4] = "\x30\xA1\x00\x07"
        #~ return
    #~ 
    #~ if type(crc) in (int, long):
        #~ crc = struct.pack(">I", crc & 0xFFFFFFFF)
    #~ 
    #~ tail[pos : pos+4] = crc


