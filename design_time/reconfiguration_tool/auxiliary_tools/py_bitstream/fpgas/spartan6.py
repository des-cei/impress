from .unknown import *  # Dummy variables to be filled when the FPGA model is loaded

# Generic name
model_name = "Spartan-6, unknown model"

# frame and word sizes
frame = 65
word = 2

# Tuples containing the size in frames of a column of each type and the type name.
CFG   = [(4,  'CFG' )]  #???
IOB   = [(30, 'IOB' )]
CLBL  = [(30, 'CLBL')]
CLBM  = [(31, 'CLBM')]
BRAM  = [(25, 'BRAM')]
DSP   = [(24, 'DSP' )]
DSP1  = [(31, 'DSP1')]
MCB   = [(30, 'MCB' )]
CLBLD = [(31, 'CLBL+DCM')]
PAD   = [(2,  'PAD' )]

# Sequence to identify that the rcfg part starts
sequence = "\x50\x60\x00"
sequence_offset = 6
sequence_size_mask = 0x0FFFFFFF



# Function for interpreting the config string
import struct  # used in dump()

# (UG380 table 5-33)
_commands = {
    0:  "NULL     (Null Command)",
    1:  "WCFG     (Write Configuration Data)",
    2:  "MFW      (Multiple Frame Write)",
    3:  "LFRM     (Last Frame)",
    4:  "RCFG     (Read Configuration Data)",
    5:  "START    (Begin the Startup Sequence)",
    7:  "RCRC     (Reset the CRC register)",
    8:  "AGHIGH   (Assert the GHIGH_B signal)",
    10: "GRESTORE (Pulse the GRESTORE signal)",
    11: "SHUTDOWN (Begin the shutdown sequence)",
    13: "DESYNC   (Reset the DALIGN Signal)",
    14: "IPROG    (Reconfigure from the address specified in the general register)",
}

# (UG380 table 5-30)
# s/(.*) (.*) 6'h(..) (.*)\./    0x\3: "\1 (\4)",/
_regs = {
    0x00: "CRC        (Cyclic Redundancy Check)",
    0x01: "FAR_MAJ    (Frame Address Register Block and Major)",
    0x02: "FAR_MIN    (Frame Address Register Minor)",
    0x03: "FDRI       (Frame Data Input)",
    0x04: "FDRO       (Frame Data Output)",
    0x05: "CMD        (Command)",
    0x06: "CTL        (Control)",
    0x07: "MASK       (Control Mask)",
    0x08: "STAT       (Status)",
    0x09: "LOUT       (Legacy output for serial daisy-chain)",
    0x0a: "COR1       (Configuration Option 1)",
    0x0b: "COR2       (Configuration Option 2)",
    0x0c: "PWRDN_REG  (Power-down Option register)",
    0x0d: "FLR        (Frame Length register)",
    0x0e: "IDCODE     (Product IDCODE)",
    0x0f: "CWDT       (Configuration Watchdog Timer)",
    0x10: "HC_OPT_REG (House Clean Option register)",
    0x12: "CSBO       (CSB output for parallel daisy-chaining)",
    0x13: "GENERAL1   (Power-up self test or loadable program address)",
    0x14: "GENERAL2   (Power-up self test or loadable program address and new SPI opcode)",
    0x15: "GENERAL3   (Golden bitstream address)",
    0x16: "GENERAL4   (Golden bitstream address and new SPI opcode)",
    0x17: "GENERAL5   (User-defined register for fail-safe scheme)",
    0x18: "MODE_REG   (Reboot mode)",
    0x19: "PU_GWE     (GWE cycle during wake-up from suspend)",
    0x1a: "PU_GTS     (GTS cycle during wake-up from suspend)",
    0x1b: "MFWR       (Multi-frame write register)",
    0x1c: "CCLK_FREQ  (CCLK frequency select for master mode)",
    0x1d: "SEU_OPT    (SEU frequency, enable and status)",
    0x1e: "EXP_SIGN   (Expected readback signature for SEU detection)",
    0x1f: "RDBK_SIGN  (Readback signature for readback command and SEU)",
    0x20: "BOOTSTS    (Boot History Register)",
    0x21: "EYE_MASK   (Mask pins for Multi-Pin Wake-Up)",
    0x22: "CBC_REG    (Initial CBC Value Register)",
}


def dump(s, print_offset=True):
    """Dump de-compiled content"""
    
    res = []
    
    i = 0
    while i < len(s):
        if print_offset:  res.append("%8d: " % i)
        
        if s[i : i+word] == "\xFF\xFF":
            n = 1
            while s[i+word*n : i+word*(n+1)] == "\xFF\xFF":
                n += 1
            if n == 1:
                res.append("FFFF    Dummy Word\n")
            else:
                res.append("FFFF{*%d}    Dummy Word\n" % n)
            i += word*n
        
        elif s[i : i+2*word] == "\xAA\x99\x55\x66":
            res.append("AA99 5566    Sync Word\n")
            i += 2*word
        
        elif s[i : i+word] == "\x20\x00":
            n = 1
            while s[i+word*n : i+word*(n+1)] == "\x20\x00":
                n += 1
            if n == 1:
                res.append("2000    NOOP\n")
            else:
                res.append("2000{*%d}    NOOP\n" % n)
            i += word*n
        
        elif s[i : i+word] == "\x30\xA1":
            cmd = struct.unpack(">H", s[i+word : i+2*word])[0]
            res.append("30A1 %04X    Send command %s\n" 
                    % (cmd, _commands.get(cmd, "%04X <unknown>" % cmd)))
            i += 2*word
        
        #~ elif s[i : i+word] == "\x50\x60":
            #~ isize = struct.unpack(">I", s[i+word : i+3*word])[0]
            #~ res.append("5060 %04X %04X    Reconfigure %d words\n" % (isize>>16, isize&0xFFFF, isize))
            #~ res.append("XXXX{*%d}    (data)\n" % isize)
            #~ i += word*(3+isize)
        
        else:
            instr = struct.unpack(">H", s[i : i+word])[0]
            itype = (instr >> 13) & 0x7   # 1=Type-1  2=Type-2
            idir  = (instr >> 11) & 0x3   # 1=Read    2=Write
            ireg  = (instr >>  5) & 0x3F  # 0..63; see _regs
            isize = (instr >>  0) & 0x1F  # unused when type-2
            
            if itype == 1 and idir == 1:
                res.append("%04X    Read %d words from %s\n" 
                        % (instr, isize, 
                        _regs.get(ireg, "register %04X <unknown>" % ireg)))
                i += word
            
            elif itype == 2 and idir == 1:
                sizew = struct.unpack(">I", s[i+word : i+3*word])[0]
                isize = sizew & sequence_size_mask
                res.append("%04X %04X %04X    Read %d words from %s\n" 
                        % (instr, sizew>>16, sizew&0xFFFF, isize, 
                        _regs.get(ireg, "register %04X <unknown>" % ireg)))
                i += 3*word
            
            elif itype == 1 and idir == 2:
                cmd = ''.join(" %04X" % struct.unpack(">H", s[j:j+word])[0] 
                              for j in xrange(i+word, i+word*(1+isize), word))
                res.append("%04X%s    Write%s to %s\n" 
                        % (instr, cmd, cmd, 
                        _regs.get(ireg, "register %04X <unknown>" % ireg)))
                i += word*(1+isize)
            
            elif itype == 2 and idir == 2:
                sizew = struct.unpack(">I", s[i+word : i+3*word])[0]
                isize = sizew & sequence_size_mask
                res.append("%04X %04X %04X    Write %d words to %s\n" 
                        % (instr, sizew>>16, sizew&0xFFFF, isize, 
                        _regs.get(ireg, "register %04X <unknown>" % ireg)))
                if print_offset:  res.append("%8d: " % (i + 3*word))
                res.append("XXXX{*%d}    (data)\n" % isize)
                #~ ##!!DEBUG!!## vv
                #~ print "<<<DEBUG>>> %s ...%s" % (
                    #~ ''.join(" %04X" % struct.unpack(">H", s[j:j+word])[0] 
                            #~ for j in xrange(i+word*3, i+word*(3+5), word)),
                    #~ ''.join(" %04X" % struct.unpack(">H", s[j:j+word])[0] 
                            #~ for j in xrange(i+word*(3+isize-5), i+word*(3+isize), word))
                #~ )
                #~ ##!!DEBUG!!## ^^
                
                #~ i += word*(3+isize)
                if print_offset:  res.append("%8d: " % (i+word*(isize+3)))
                crc = "%04X %04X" % struct.unpack(">2H", s[i+word*(isize+3) : i+word*(isize+5)])
                res.append("%s    CRC = %s (not sure about this...)\n" 
                        % (crc, crc))
                i += word*(isize+5)
            
            else:
                res.append("%04X    ?\n" 
                        % struct.unpack(">H", s[i : i+word])[0])
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
    #~ pos = 0  # always @ beginning of tail
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


