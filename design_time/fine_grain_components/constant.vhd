----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10/08/2018 11:12:43 AM
-- Design Name: 
-- Module Name: constant - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity lut_constant is
    generic (
        NUM_BITS : positive; 
        POSITION : positive;
        CONSTANT_COLUMNS: natural := 0;
        COLUMN_OFFSET : natural := 0;
        PBLOCK : string := "";
        DEFAULT_VALUE : bit_vector (63 downto 0) := x"0000_0000_0000_0000" -- We init the LUT with output always using 0 in the two outputs
    );
    port (
        constant_output : out std_logic_vector(NUM_BITS - 1 downto 0) 
    );
end lut_constant;

architecture Behavioral of lut_constant is
--    attribute DONT_TOUCH : string;
--    attribute DONT_TOUCH of constant_output : port is "TRUE";
begin
    
    -- TODO: what happens if the constant has an odd number of bits. 
    -- We instantiate LUTs with 2 outputs and all their inputs connected to 0
    CONSTANT_GEN : for i in 0 to NUM_BITS/2 generate
      attribute DONT_TOUCH : string;
      attribute CONSTANT_LUT_ELEMENT : string;
      attribute constant_position : positive;
      attribute num_columns_constants : positive;
      attribute PBLOCK_FINE_GRAIN : string;
      attribute PBLOCK_COLUMN_OFFSET : integer;
    
        
    begin
      
      LAST_LUT_ODD: if i = (NUM_BITS/2) and (NUM_BITS mod 2) = 1 generate 
      
        attribute DONT_TOUCH of LUT_INST : label is "TRUE";
        attribute constant_position of LUT_INST: label is POSITION;
        attribute num_columns_constants of LUT_INST: label is CONSTANT_COLUMNS;
        attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;
        attribute CONSTANT_LUT_ELEMENT of LUT_INST : label is "TRUE";
        attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;
      
        begin
        LUT_INST : LUT6_2  
          generic map (
             INIT => DEFAULT_VALUE  -- LUT "equation"
          )
          port map (
             O6 => open,      --O6
             O5 => constant_output(i*2),          --O5
             I5 => '1', -- A6
             I4 => '0', -- A5
             I3 => '0', -- A4
             I2 => '0', -- A3
             I1 => '0', -- A2
             I0 => '0'  -- A1
          );
          
      end generate LAST_LUT_ODD;
      
       FIRST_LUTS: if i < (NUM_BITS/2)  generate 
         attribute DONT_TOUCH of LUT_INST : label is "TRUE";
         attribute constant_position of LUT_INST: label is POSITION;
         attribute num_columns_constants of LUT_INST: label is CONSTANT_COLUMNS;
         attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;
         attribute CONSTANT_LUT_ELEMENT of LUT_INST : label is "TRUE";
         attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;
         begin
         LUT_INST : LUT6_2  
           generic map (
              INIT => DEFAULT_VALUE  -- LUT "equation"
           )
           port map (
              O6 => constant_output(i*2 + 1),      --O6
              O5 => constant_output(i*2),          --O5
              I5 => '1', -- A6
              I4 => '0', -- A5
              I3 => '0', -- A4
              I2 => '0', -- A3
              I1 => '0', -- A2
              I0 => '0'  -- A1
           );
       end generate FIRST_LUTS; 
     end generate;

end Behavioral;
