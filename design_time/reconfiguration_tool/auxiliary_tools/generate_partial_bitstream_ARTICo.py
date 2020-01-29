import sys
import re 
import os
#We import the py_bitstream tool 
sys.path.append(os.path.dirname(os.path.abspath(__file__)) + '/py_bitstream')
from tools import bitstream

'''
This script calls the py_bitstream tool to extract partial bitstreams (pbs). The py_bitstream tool 
only allows to extract pbs from one clock region. This script allows to extract a pbs spanning 
multiple clock regions. 

The script should be called with 3 arguments:
    param argv[1]: bitstream source file 
    param argv[2]: defines the area where the pbs will be extracted. The format of the variable is 
                   XxYy:XxYy i.e. X3Y5:X8Y12. If the reconfigurable partition is composed with
                   several pblocks, this argument should be defined as a list.  
    param argv[3]: partial bitstream destination file name.
    
    return: returns an extracted pbs located in the destination file defined in argv[3] 
    
    Example: python generate_partial_bitstream ./static.bit X3Y5:X8Y12 ./module.pbs
    
NOTE: the pblocks definition should be rectangular. That is, they should be aligned with the height
of RAM and DSP tiles.  

NOTE2: right now it only works for series7 devices 
'''


# if __name__ == '__main__':
# ipdb.set_trace()
bitstream_obj = bitstream.Bitstream(sys.argv[1]) 
pblock_definition_list = sys.argv[2] 
destination_file = sys.argv[3]


#TODO in the future when ultrascale devices are supported these parameters should be family device 
#dependent and should be written in MORAs (py_bitstream) tool (in the families devices). 
rows_per_clock_region = 50
words_per_row_in_clock_region = 2
frame_words_num = 101
clock_word_num = 1 
words_per_half_clock_region_without_clock = (frame_words_num - clock_word_num) / words_per_row_in_clock_region

extracted_bitstream = bytearray()
extracted_BRAM_contents = bytearray()
    
for pblock_definition in pblock_definition_list.split():
    expression = re.search("X([0-9]+)Y([0-9]+):X([0-9]+)Y([0-9]+)", pblock_definition)
    x0 = int(expression.group(1))
    y0 = int(expression.group(2)) 
    xf = int(expression.group(3))
    yf = int(expression.group(4)) 

    first_clock_region_row = y0 / rows_per_clock_region
    last_clock_region_row = yf / rows_per_clock_region 

    for i in range(first_clock_region_row, last_clock_region_row + 1):
        first_words_not_used = 0
        last_words_not_used = 0
        if (i == first_clock_region_row):
            intial_rows_not_used = y0 - (first_clock_region_row * rows_per_clock_region)
            first_words_not_used = intial_rows_not_used * words_per_row_in_clock_region

        if (i == last_clock_region_row):
            last_rows_not_used = (((first_clock_region_row + 1) * rows_per_clock_region) - 1) - yf
            last_words_not_used = last_rows_not_used * words_per_row_in_clock_region
            
        if (first_words_not_used < words_per_half_clock_region_without_clock and last_words_not_used < words_per_half_clock_region_without_clock):
            # The region crosses the middle of the clock region
            # We go through each frame of each column
            for j in range(x0, xf + 1):
                for k in range(0, bitstream_obj.fpga.table[i][j][0]):
                    bitstream_block = bitstream_obj[i, j, first_words_not_used:words_per_half_clock_region_without_clock, k]
                    # print(i, j, k, k+1, first_words_not_used, words_per_half_clock_region_without_clock)
                    extracted_bitstream.extend(bitstream_block)
                    # extracted_BRAM_contents.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(first_words_not_used, words_per_half_clock_region_without_clock), k)))
                    # print(i, j, k, k+1, (words_per_half_clock_region_without_clock + 1), (frame_words_num-last_words_not_used))
                    bitstream_block = bitstream_obj[i, j, (words_per_half_clock_region_without_clock + 1):(frame_words_num-last_words_not_used), k]
                    extracted_bitstream.extend(bitstream_block)     
                    # extracted_BRAM_contents.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(words_per_half_clock_region_without_clock + 1, frame_words_num-last_words_not_used), k)))
            for j in range(x0, xf + 1):    
                if bitstream_obj.fpga.table[i][j][1] == 'BRAM':
                    for k in range(0, 128):
                        # bitstream_block = bitstream_obj[i, j, first_words_not_used:words_per_half_clock_region_without_clock, k]
                        # # print(i, j, k, k+1, first_words_not_used, words_per_half_clock_region_without_clock)
                        # extracted_bitstream.extend(bitstream_block)
                        extracted_bitstream.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(first_words_not_used, words_per_half_clock_region_without_clock), k)))
                        # extracted_BRAM_contents.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(first_words_not_used, words_per_half_clock_region_without_clock), k)))
                        # print(i, j, k, k+1, (words_per_half_clock_region_without_clock + 1), (frame_words_num-last_words_not_used))
                        # bitstream_block = bitstream_obj[i, j, (words_per_half_clock_region_without_clock + 1):(frame_words_num-last_words_not_used), k]
                        # extracted_bitstream.extend(bitstream_block)     
                        extracted_bitstream.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice((words_per_half_clock_region_without_clock + 1), (frame_words_num-last_words_not_used)), k)))
                        # extracted_BRAM_contents.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(words_per_half_clock_region_without_clock + 1, frame_words_num-last_words_not_used), k)))
                
                # if bitstream_obj.fpga.table[i][j][1] == 'BRAM':
                #     extracted_bitstream.extend(bitstream_obj.obtain_BRAM_contents((i, j, slice(first_words_not_used, (frame_words_num-last_words_not_used)))))
        elif (first_words_not_used >= words_per_half_clock_region_without_clock and last_words_not_used < words_per_half_clock_region_without_clock):
            # Region on the top half of the clock region
            first_word = first_words_not_used + clock_word_num
            bitstream_block = bitstream_obj[i, x0:(xf + 1), first_word:(frame_words_num-last_words_not_used)]
            extracted_bitstream.extend(bitstream_block)
            extracted_bitstream.extend(bitstream_obj.obtain_BRAM_contents((i, slice(x0, (xf + 1)), slice(first_word, (frame_words_num-last_words_not_used)))))
        elif (first_words_not_used < words_per_half_clock_region_without_clock and last_words_not_used >= words_per_half_clock_region_without_clock):
            # Region on the bottom half of tyhe clock region
            last_word = frame_words_num - last_words_not_used - clock_word_num
            bitstream_block = bitstream_obj[i, x0:(xf + 1), first_words_not_used:last_word]
            extracted_bitstream.extend(bitstream_block)
            extracted_bitstream.extend(bitstream_obj.obtain_BRAM_contents((i, slice(x0, (xf + 1)), slice(first_words_not_used, last_word))))
        else: 
            print "error"


#~ for i in xrange(0, len(extracted_BRAM_contents)):
    #~ if extracted_BRAM_contents[i] != 0:
        #~ extracted_bitstream.extend(extracted_BRAM_contents)
        #~ break 
        
# extracted_bitstream.extend(extracted_BRAM_contents)


# with open(sys.argv[1] + ".prueba", 'wb') as file:
#     file.write("arg1\n")
#     file.write(sys.argv[1])
#     file.write("\narg2\n")
#     file.write(sys.argv[2])
#     file.write("\narg3\n")
#     file.write(sys.argv[3])
 
with open(destination_file, 'wb') as file:
    file.write(extracted_bitstream) 
