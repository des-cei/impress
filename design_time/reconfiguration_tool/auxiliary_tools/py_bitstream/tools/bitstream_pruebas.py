"""
The Bitstream class
"""

import struct
import ipdb

class Bitstream (object):
    """
    ``orig``
        Info about originary file, and sometimes extra synth info.
        Example:  ``["system.ncd", "HW_TIMEOUT=FALSE", "UserID=0xFFFFFFFF"]``
    ``model``
        Model of the FPGA (family number, series name, model, packaging).
        Example:  ``"5vlx110tff1136"`` for a Virtex-5 LX110T-FF1136
    ``date``
        Tuple with creation date and time.
        Example:  ``("2012/06/28", "11:34:18")``
    ``content``
        Configuration stream, containing the following sections:

        - Configuration setup instructions
        - FPGA interconnect and block configuration data (Block Type 0)
        - FPGA BRAM content data, interconnect and block special frames,
          and BRAM non-config frames
        - Configuration closing instructions

    ``config_offset``
        Offset of FPGA configuration data within ``content``
    ``config_length``
        Size of FPGA configuration data (all of it,
        not only interconnection/block configuration)

    ``fpga``
        Module imported from ``fpgas/`` with info about this specific FPGA.

        ``fpga.frame``
            Frame size in words
        ``fpga.word``
            Word size in bytes
        ``fpga.dump()``
            Function to be called when the ``dump()`` method is called

        ``fpga.model_name``
            A string describing the FPGA model, such as
            ``"Virtex-5 LX110T-FF1136"``
        ``fpga.table``
            Array with info of sizes (in frames) and types for each column
            within the interconnect/block config data.
            The type is a string identifier that could be useful for future
            GUI features such as a colored FPGA map.
        ``fpga.bitstream_order``
            How the FPGA rows are ordered in the bitstream.  As an example,
            Virtex-5 contains first the rows on the upper half of the FPGA,
            ordered from bottom to top, and then the lower half, ordered from
            top to bottom.

            Notice that this vector is not necessarily *involutive*, this is,
            for getting the order you have to put to the rows to get a valid
            bitstream, you should do something like
            ``[ bitstr.fpga.bitstream_order.index(i)
            for i in xrange(len(bitstr.fpga.bitstream_order)) ]``

        ``fpga.frame_offset``
            Byte offset in interconnect/block config data for each row/column,
            as a list of lists.  This attribute won't be created
            until the module for this FPGA model is loaded for the first time.
        ``fpga.reconfig_size``
            Size of interconnect and block config data.  This attribute won't
            be created until the module for this FPGA model is loaded
            for the first time.
    """
    def __init__(self, name=None):
        self.orig = ["???"]
        self.model = "???"
        self.date = ("???", "???")
        self.content = None
        self.config_offset = None
        self.config_length = None

        if name is not None:
            self.load(name)
        else:
            self.set_fpga("unknown")

    def load(self, name):
        """Load a .bit file"""

        bit = open(name, 'rb')

        # Magic number - 00 09 0f f0 0f f0 0f f0 0f f0 00 00 01  (13 bytes)
        
        magic = bit.read(13)  # skip 11 bytes (magic number), or read and check them
        if magic != '\x00\x09\x0f\xf0\x0f\xf0\x0f\xf0\x0f\xf0\x00\x00\x01':
            #~ print "Warning: magic number differs:", repr(magic)
            raise ValueError("Not a bitstream file (magic number mismatches)")

        # Field 'a':  originary file and extra info  (e.g. "system.ncd;HW_TIMEOUT=FALSE;UserID=0xFFFFFFFF")
        self.orig = _get_field(bit, idx='a')[:-1].split(';')
        # Field 'b':  FPGA model  (e.g. "5vlx110tff1136")
        self.model = _get_field(bit, idx='b')[:-1]
        # Field 'c':  synth date  (e.g. "2012/06/28")
        date = _get_field(bit, idx='c')[:-1]
        # Field 'd':  synth time  (e.g. "11:34:18")
        time = _get_field(bit, idx='d')[:-1]
        self.date = (date, time)
        # Field 'e':  content (configuration stream)
        self.content2 = _get_field(bit, fmt='>I', idx='e')
        self.content = bytearray(self.content2)
        # self.content = bytearray(_get_field(bit, fmt='>I', idx='e'))
        

        # The rest of the file should be empty...  let's check
        rest = bit.read(1)
        if len(rest) > 0: print "Warning: file was not empty at the end"

        bit.close()
        # ipdb.set_trace()
        # Set FPGA model and find config data
        self.set_fpga()

    def set_fpga(self, model=None):
        """
        Import the required .py file as ``self.fpga``.

        Create ``self.fpga.frame_offset`` and ``self.fpga.reconfig_size``
        if not yet created.

        Additionally, find where the configuration data starts.
        """
        # ipdb.set_trace()
        # Load FPGA info
        if not model:  model = self.model
        try:
            self.fpga = __import__('fpgas.'+model, fromlist=[model])
        except ImportError, e:
            print "Warning: FPGA model '%s' not known" % model
            print e
            self.fpga = __import__('fpgas.unknown', fromlist=['unknown'])

        # Get configuration data offset within content
        try:
            if not self.fpga.sequence:
                raise ValueError("FPGA start-of-config sequence unknown")

            self.config_offset = self.content.index(self.fpga.sequence) + self.fpga.sequence_offset
            self.config_length = struct.unpack(">I", bytes(self.content[self.config_offset-4 : self.config_offset]))[0]

        except ValueError:  # substring not found
            self.config_offset = None
            self.config_length = None
            print "Warning: could not find configuration data in bitstream."

        # Create the frame_offset list if it doesn't exist.
        # This list contains the byte offset for each column.
        #Basicamente contiene la info de todos lo bytes que componen cada
        #columna de la FPGA. Es un array de arrays con cada valor del array    
        #formamdo una fila de region de reloj en la que se detallan todas las
        #columnas de la region de reloj 
        if self.fpga.frame_offset is None and self.fpga.table != []:
            offsets = []  # in bitstream order
            total = 0
            frm   = self.fpga.frame * self.fpga.word

            for i in self.fpga.bitstream_order:  # in bitstream order
                new = [total]
                for col in self.fpga.table[i]:
                    total += col[0] * frm
                    new.append(total)

                offsets.append(new)

            self.fpga.frame_offset = [ offsets[self.fpga.bitstream_order.index(i)]
                                  for i in xrange(len(self.fpga.bitstream_order)) ]
                                  # in upwards order
            self.fpga.reconfig_size = total

    def dump(self, print_offset=True, as_string=False):
        """
        Interpret the whole content string and print it,
        or return it as a string if called with ``as_string=True``
        """
        if self.fpga.dump is None:
            raise NotImplementedError(
                "FPGA model '%s' not known or dump() method not found"
                % self.model )

        res = self.fpga.dump(bytes(self.content), print_offset)

        if as_string:
            return res
        else:
            print res

    def info(self, as_string=False):
        """
        Print info about the bitstream, or return it as a string
        if called with ``as_string=True``
        """
        res = ["FPGA model: %s (%s)" % (self.fpga.model_name, self.model)]
        if len(self.orig) <= 1:
            res.append("Original file: %s" % self.orig[0])
        else:
            res.append("Original file: %s (%s)"
                    % (self.orig[0], ";".join(self.orig[1:])))
        res.append("Creation date: %s %s" % self.date)

        res = "\n".join(res)
        if as_string:
            return res
        else:
            print res

    def __repr__(self):
        """Return a short info string of this object (shorter than ``info()``)"""
        return "<Bitstream for %s (origin: %s)>" % (self.fpga.model_name, self.orig[0])

    def __getitem__(self, coords):
        """
        Returns a bytearray containing the data from the specified coordinates,
        sequentially (left to right and bottom to top, not in bitstream-order).

        ``bitstr[0]``
            Get bottom row (whole clock region)
        ``bitstr[-1]``
            Get top row
        ``bitstr[1:4]``
            Get rows 1 to 3  (notice that 4 *IS NOT included*)
        ``bitstr[:3]``
            Get rows below 3  (0 to 2)
        ``bitstr[3:]``
            Get rows 3 and above
        ``bitstr[1, 5]``
            Get row 1, column 5
        ``bitstr[1:3, 5:13]``
            Get rectangular selection:  rows 1 to 2, columns 5 to 12
            (row 3 and column 13 are *NOT included*)

        ``bitstr[1, 5:13, 0:10]``
            Word range.
            Don't get whole frames but just words 0 to 9 of each frame.
            Result is saved compactly (which is useless for the 2012 HWICAP
            but may be useful on newer versions such as the 2014 one
            where merging sub-region partial bitstreams is implemented)
        ``bitstr[1, 5, :, 26:36]``
            Frame range.
            Get only frames 26 to 35 of the given column range.
            Doing something like ``bitstr[1, 0:10, :, 26:36]`` will only
            get frames 26 to 35 of the first column; not of each column.
            Frame range can also be combined with word range, like
            ``bitstr[1, 5, 0:10, 26:36]``.

        TODO:  replace the word slice notation with something like
        ``bitstr[row:firstword:lastword]`` (if we are getting a subclock
        slice we won't be iterating over multiple rows anyway).
        Similarly, implement sub-column frame ranges as
        ``bitstr[row, col:firstframe:lastframe]``.  Alternatively,
        ``row/col:first:length`` could be used.
        """
        # ipdb.set_trace()
        if type(coords) != tuple:  coords = (coords,)

        result = bytearray()

        #get row range
        coord0 = coords[0] if type(coords[0]) is slice  \
               else slice(coords[0], coords[0]+1)
        #slice(None) is the same as ::
        #get column range
        coord1 = slice(None) if len(coords) < 2  \
               else coords[1] if type(coords[1]) is slice  \
               else slice(coords[1], coords[1]+1)
        #get word range
        coord2 = None if len(coords) < 3  \
               else coords[2] if type(coords[2]) is slice  \
               else slice(coords[2], coords[2]+1)
        #get frame range
        coord3 = None if len(coords) < 4  \
               else coords[3] if type(coords[3]) is slice  \
               else slice(coords[3], coords[3]+1)

        start, stop, _ = coord0.indices(len(self.fpga.frame_offset))

        for i in xrange(start, stop):
            start, stop, _ = coord1.indices(len(self.fpga.frame_offset[i]) - 1)
            # The ``- 1`` there is to remove the extra elem each row has
            # for holding the last offset.
            # E.g. a 64 columns FPGA + 1 column padding has 66 offsets
            # (offsets 0..64 surrounding reconfig parts; 64 and 65
            # surrounding the padding frame) and we'd get 66 - 1 = 65.

            start = self.fpga.frame_offset[i][start] + self.config_offset
            stop  = self.fpga.frame_offset[i][stop]  + self.config_offset

            if coord3 is not None:
                # start/stop offsets are in bytes; coord3 is in frames
                fbytes = self.fpga.word * self.fpga.frame
                start2, stop2, _ = coord3.indices((stop-start)//fbytes)
                start, stop = start + start2*fbytes, start + stop2*fbytes

            if coord2 is None:
                result += self.content[start : stop]
            else:
                fstart, fstop, _ = coord2.indices(self.fpga.frame)
                fstart *= self.fpga.word
                fstop  *= self.fpga.word

                for j in xrange(start, stop, self.fpga.word * self.fpga.frame):
                    result += self.content[j+fstart : j+fstop]

        return result

    def __setitem__(self, coords, string):
        """
        DO NOT USE - not implemented yet

        Rewrite part of a bitstream with a string such as those returned
        by ``__getitem__()``.  Same syntax as that of ``__getitem__()``.

        Example::

            chunk = bitstr1[3, 2:4]
            bitstr1[3, 4:6] = chunk

        It should print a warning message or raise an exception
        if sizes mismatch.  (TODO)
        """
        raise NotImplementedError("Bitstream edition is not yet implemented")

    def __delitem__(self, coords):
        """
        Rewrite part of a bitstream with zeros.  Same as
        ``bitstr[coords] = '\0' * len(bitstr[coords])``.

        Example::

            del bitstr1[3, 4:6]
        """
        if type(coords) != tuple:  coords = (coords,)

        coord0 = coords[0] if type(coords[0]) is slice  \
               else slice(coords[0], coords[0]+1)
        coord1 = slice(None) if len(coords) < 2  \
               else coords[1] if type(coords[1]) is slice  \
               else slice(coords[1], coords[1]+1)
        coord2 = None if len(coords) < 3  \
               else coords[2] if type(coords[2]) is slice  \
               else slice(coords[2], coords[2]+1)

        start, stop, _ = coord0.indices(len(self.fpga.frame_offset))

        for i in xrange(start, stop):
            start, stop, _ = coord1.indices(len(self.fpga.frame_offset[i]) - 1)
            # The ``- 1`` there is to remove the extra elem each row has
            # for holding the last offset.

            start = self.fpga.frame_offset[i][start] + self.config_offset
            stop  = self.fpga.frame_offset[i][stop]  + self.config_offset

            if coord2 is None:
                self.content[start : stop] = bytearray(stop - start)
            else:
                fstart, fstop, _ = coord2.indices(self.fpga.frame)
                fstart *= self.fpga.word
                fstop  *= self.fpga.word

                for j in xrange(start, stop, self.fpga.word * self.fpga.frame):
                    self.content[j+fstart : j+fstop] = bytearray(fstop - fstart)


#bit file to read
#idx valor del campo
#fmt = format?
#This function reads a field value (a,b,c ...) then redas its length and finally reads and returns its content 
def _get_field(bit, fmt='>H', idx=None):
    x = bit.read(1)
    if idx and x != idx: print "Warning: should be 'a' but got", repr(x)
    size = struct.unpack( fmt, bit.read(struct.calcsize(fmt)) )[0]
    data = bit.read(size)
    if len(data) != size: print "Warning: got", len(data), "bytes, expected", size
    return data




# number_of_files = 3
# file_inicial1 = "/home/rafa/Desktop/prueba2/dehabilitados/deshabilitados.bit"
# file_inicial2 = "/home/rafa/Desktop/prueba2/12down/prueba.bit"
# file_inicial3 = "/home/rafa/Desktop/prueba2/11up/prueba.bit"
# file_inicial4 = "/home/rafa/Desktop/prueba2/12_5_down/prueba.bit"
# file_final = "/home/rafa/Desktop/prueba2/comp_frame_14_mmm"
# 
# 
# bitstream_1 = Bitstream(file_inicial1)
# bitstream_2 = Bitstream(file_inicial2)
# bitstream_3 = Bitstream(file_inicial3)
# bitstream_4 = Bitstream(file_inicial4)
# 
# frame = 15
# 
# bitstream_1_mod = bitstream_1[0, frame]
# bitstream_2_mod = bitstream_2[0, frame]
# bitstream_3_mod = bitstream_3[0, frame]
# bitstream_4_mod = bitstream_4[0, frame]
# 
# fmt_string = '>' + 'L'*(len(bitstream_1_mod)/4)
# 
# bitstream_unpacked_1 = struct.unpack(fmt_string, bitstream_1_mod)
# bitstream_unpacked_2 = struct.unpack(fmt_string, bitstream_2_mod)
# bitstream_unpacked_3 = struct.unpack(fmt_string, bitstream_3_mod)
# bitstream_unpacked_4 = struct.unpack(fmt_string, bitstream_4_mod)
# 
# for frame in range(0,36):
#     for word in range(0,101):
#         if bitstream_unpacked_4[(frame * 101) + word] == bitstream_unpacked_1[(frame * 101) + word] == bitstream_unpacked_2[(frame * 101) + word] == bitstream_unpacked_3[(frame * 101) + word]:
#             pass
#         else:
#             with open(file_final, 'a') as file:
#                 file.write("frame number: " + str(frame) + " word number " + str(word) + "\n")
#                 file.write("   deshab = " + ''.join('{:0>8X}'.format(bitstream_unpacked_1[(frame * 101) + word])) +"\n")
#                 file.write("    hab12 = " + ''.join('{:0>8X}'.format(bitstream_unpacked_2[(frame * 101) + word])) +"\n")
#                 file.write("  hab11up = " + ''.join('{:0>8X}'.format(bitstream_unpacked_3[(frame * 101) + word])) +"\n")
#                 file.write("hab12_5do = " + ''.join('{:0>8X}'.format(bitstream_unpacked_4[(frame * 101) + word])) +"\n")



# #nota para que esto funcione hay que ejecutar el script dentro de la carpeta pu_bitstreams y no dentro de la carpeta tools
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/HIERARCHICAL/prueba.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/HIERARCHICAL/static_conjunto_MORA"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)




# #nota para que esto funcione hay que ejecutar el script dentro de la carpeta pu_bitstreams y no dentro de la carpeta tools
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_pass.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/pass.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 46:63]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_erode.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/erode.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 46:63]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_dilate.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/dilate.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 46:63]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)

#nota para que esto funcione hay que ejecutar el script dentro de la carpeta pu_bitstreams y no dentro de la carpeta tools
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_pass.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/pass.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32, 10:50]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_erode.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/erode.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32, 10:50]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/project_build_image_filter_dilate.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/reconfiguracion_proyecto_alberto2/project_build/BITSTREAMS_TEMP/dilate.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32, 10:50]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)


# #nota para que esto funcione hay que ejecutar el script dentro de la carpeta pu_bitstreams y no dentro de la carpeta tools
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/Reconfiguration_tool_test/Ejemplo3/cascade_filter_build_este/BITSTREAMS_TEMP/cascade_filter_build_este_image_filter_dilate.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/Reconfiguration_tool_test/Ejemplo3/cascade_filter_build_este/BITSTREAMS_TEMP/dilate.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32, 51:91]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 
# file_inicial = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/Reconfiguration_tool_test/Ejemplo3/cascade_filter_build_este/BITSTREAMS_TEMP/cascade_filter_build_este_image_filter_erode.bit"
# file_final = "/home/rafa/Work/Vivado/Proyectos/mis_proyectos/Reconfiguration_tool_test/Ejemplo3/cascade_filter_build_este/BITSTREAMS_TEMP/erode.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[0, 14:32, 51:91]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)
# 


# file_inicial = "/home/rafa/Desktop/reconstruido.bit"
# file_final = "/home/rafa/Desktop/reconstruido.pbs"
# # ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# prueba_partial = prueba[1, 52:72]
# with open(file_final, 'wb') as file:
#     file.write(prueba_partial)









# file_inicial = "/home/rafa/Work/Vivado/Proyectos/pruebas/prueba/clock_deshabilitados/des.bit"
# file_final = '/home/rafa/Work/Vivado/Proyectos/pruebas/prueba'
# ipdb.set_trace()
# prueba = Bitstream(file_inicial)
# for column in range(6,26,2):
#     bitstream_clock_hab = prueba[0, column]
#     fmt_string = '>' + 'L'*(len(bitstream_clock_hab)/4)
#     bitstream_clock_hab_unpacked = struct.unpack(fmt_string, bitstream_clock_hab)
#     frame = 5
#     bitstream_clock_hab_unpacked_frame_50 = bitstream_clock_hab_unpacked[((frame * 101) + 50) : ((frame * 101) + 51)]
#     words_frame_50 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_50)
#     with open(file_final, 'a') as file:
#         file.write("column number:" + str(column) + "\n")
#         file.write("    word 50 = " + words_frame_50 +"\n")


# file_inicial = "/home/rafa/Desktop/prueba2/12down/prueba.bit"
# file_final = '/home/rafa/Desktop/prueba2/12down/words50'
# file_inicial = "/home/rafa/Desktop/prueba2/12down/prueba.bit"
# file_final = '/home/rafa/Desktop/prueba2/12down/words50'
# prueba = Bitstream(file_inicial)
# bitstream_clock_hab = prueba[0, 15]
# fmt_string = '>' + 'L'*(len(bitstream_clock_hab)/4)
# bitstream_clock_hab_unpacked = struct.unpack(fmt_string, bitstream_clock_hab)
# for frame in range(0,36):
#     bitstream_clock_hab_unpacked_frame_0_49 = bitstream_clock_hab_unpacked[((frame * 101) + 0) : ((frame * 101) + 50)]
#     bitstream_clock_hab_unpacked_frame_50 = bitstream_clock_hab_unpacked[((frame * 101) + 50) : ((frame * 101) + 51)]
#     bitstream_clock_hab_unpacked_frame_51_100 = bitstream_clock_hab_unpacked[((frame * 101) + 51) : ((frame * 101) + 101)]
#     words_frame_0_49 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_0_49)
#     words_frame_50 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_50)
#     words_frame_51_100 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_51_100)
#     with open(file_final, 'a') as file:
#         file.write("frame number:" + str(frame) + "\n")
#         file.write("    words 0 to 49 \n")
#         file.write("    " + words_frame_0_49 +"\n")
#         file.write("    word 50 \n")
#         file.write("    " + words_frame_50 +"\n")
#         file.write("    words 51 to 100 \n")
#         file.write("    " + words_frame_51_100 +"\n")



file_inicial = "/home/rafa/Desktop/comparacion/LEIDO2"
file_final = '/home/rafa/Desktop/comparacion/LEIDO2_parsed'
# file_inicial = "/home/rafa/Desktop/comparacion/reconstruido2.pbs"
# file_final = '/home/rafa/Desktop/comparacion/reconstruido2_parsed'
with open(file_inicial, 'rb') as file:
    bitstream = bytearray(file.read())
fmt_string = '>' + 'L'*(len(bitstream)/4)
bitstream_unpacked = struct.unpack(fmt_string, bitstream)
for frame in range(0,688):
    bitstream_clock_hab_unpacked_frame_0_49 = bitstream_unpacked[((frame * 101) + 0) : ((frame * 101) + 50)]
    bitstream_clock_hab_unpacked_frame_50 = bitstream_unpacked[((frame * 101) + 50) : ((frame * 101) + 51)]
    bitstream_clock_hab_unpacked_frame_51_100 = bitstream_unpacked[((frame * 101) + 51) : ((frame * 101) + 101)]
    words_frame_0_49 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_0_49)
    words_frame_50 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_50)
    words_frame_51_100 = " ".join(format(x,'0>8X') for x in bitstream_clock_hab_unpacked_frame_51_100)
    with open(file_final, 'a') as file:
        file.write("frame number:" + str(frame) + "\n")
        file.write("    words 0 to 49 \n")
        file.write("    " + words_frame_0_49 +"\n")
        file.write("    word 50 \n")
        file.write("    " + words_frame_50[:-4] +"\n")
        file.write("    words 51 to 100 \n")
        file.write("    " + words_frame_51_100 +"\n")





# prueba = Bitstream("/home/rafa/Desktop/prueba/prueba.bit")
# ipdb.set_trace()
# bitstream = prueba[0, 6:25, 20:40]
# fmt_string = '>' + 'L'*(len(bitstream)/4)
# bitstream_32bits = struct.unpack(fmt_string, bitstream)
# bitstream_32bits_hex = " ".join(format(x,'0>8X') for x in bitstream_32bits) 
# with open('/home/rafa/Desktop/prueba/bitstream_parcial_herramienta_mora_hex', 'w') as file:
#     file.write(bitstream_32bits_hex)
# bitstream_whole_frame = prueba[0, 6:25]
# fmt_string = '>' + 'L'*(len(bitstream_whole_frame)/4)
# bitstream_whole_frame_32bits = struct.unpack(fmt_string, bitstream_whole_frame)
# bitstream_whole_frame_32bits_hex = " ".join(format(x,'0>8X') for x in bitstream_whole_frame_32bits) 
# with open('/home/rafa/Desktop/prueba/bitstream_parcial_whole_frame_herramienta_mora_hex', 'w') as file:
#     file.write(bitstream_whole_frame_32bits_hex)

# prueba = Bitstream("/home/rafa/Desktop/prueba/prueba_multiplier_0_multiplicador_32_bits_partial_bitstream")
# 
# #We divide the content of the bitstreams (without commands and extra info) in its different sections
# #Bytes have been selected from Moras tool
# content_FAR_00420300_1 = prueba.content[152:272044]
# content_FAR_00420300_2 = prueba.content[427648:699540]
# content_FAR_00C20000_1 = prueba.content[272076:427616]
# content_FAR_00C20000_2 = prueba.content[699572:855112]
# #We convert the bitstreams into 32 bit words
# fmt_string = '>' + 'L'*(len(content_FAR_00420300_1)/4)
# bitstream_content_FAR_00420300_1 = struct.unpack(fmt_string, content_FAR_00420300_1)
# fmt_string = '>' + 'L'*(len(content_FAR_00420300_2)/4)
# bitstream_content_FAR_00420300_2 = struct.unpack(fmt_string, content_FAR_00420300_2)
# fmt_string = '>' + 'L'*(len(content_FAR_00C20000_1)/4)
# bitstream_content_FAR_00C20000_1 = struct.unpack(fmt_string, content_FAR_00C20000_1)
# fmt_string = '>' + 'L'*(len(content_FAR_00C20000_2)/4)
# bitstream_content_FAR_00C20000_2 = struct.unpack(fmt_string, content_FAR_00C20000_2)
# #We convert the tuples into strings with hexadecimal numbers
# bitstream_content_FAR_00420300_1_hex = " ".join(format(x,'0>8X') for x in bitstream_content_FAR_00420300_1) 
# bitstream_content_FAR_00420300_2_hex = " ".join(format(x,'0>8X') for x in bitstream_content_FAR_00420300_2) 
# bitstream_content_FAR_00C20000_1_hex = " ".join(format(x,'0>8X') for x in bitstream_content_FAR_00C20000_1) 
# bitstream_content_FAR_00C20000_2_hex = " ".join(format(x,'0>8X') for x in bitstream_content_FAR_00C20000_2) 
# #We write the content in files
# with open('/home/rafa/Desktop/prueba/bitstream_content_FAR_00420300_1_hex', 'w') as file:
#     file.write(bitstream_content_FAR_00420300_1_hex)
# with open('/home/rafa/Desktop/prueba/bitstream_content_FAR_00420300_2_hex', 'w') as file:
#     file.write(bitstream_content_FAR_00420300_2_hex)
# with open('/home/rafa/Desktop/prueba/bitstream_content_FAR_00C20000_1_hex', 'w') as file:
#     file.write(bitstream_content_FAR_00C20000_1_hex)
# with open('/home/rafa/Desktop/prueba/bitstream_content_FAR_00C20000_2_hex', 'w') as file:
#     file.write(bitstream_content_FAR_00C20000_2_hex)


