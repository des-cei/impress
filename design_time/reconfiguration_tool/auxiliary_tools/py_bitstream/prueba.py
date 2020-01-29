#!/usr/bin/env python2
# -*- coding: utf-8 -*-

def decode_far_address(address):
    minor_address = address & 0x7F
    column_address = ( address >> 7 ) & 0x3FF
    row_address = ( address >> 17 ) & 0x1F
    top_bottom_bit = ( address >> 22 ) & 1
    if top_bottom_bit == 0:
        top_bottom_bit = "top"
    else:
        top_bottom_bit = "bottom" 
    block_type = ( address >> 23 ) & 0x7
    if block_type == 0:
        decoded_block_type = "CLB, IO or CLK"
    elif block_type == 1:
        decoded_block_type = "RAM content"
    elif block_type == 1:
        decoded_block_type = "CFG_CLB"
    else: 
        decoded_block_type = "Error"
    print("minor_address = ", minor_address)
    print("column_address = ", column_address)
    print("row_address = ", row_address)
    print("top_bottom_bit = ", top_bottom_bit)
    print("decoded_block_type = ", decoded_block_type)
    return 
    
print("FAR address: ", 0x00420300)
decode_far_address(0x00420300)
print("****************************")
print("FAR address: ", 0x00C20000)
decode_far_address(0x00C20000)