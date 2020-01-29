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
library ieee;
use ieee.std_logic_1164.all;

package fine_grain_mux is
    type mux_input_t is array (integer range <>, integer range <>) of std_logic; -- number of inputs, width of each input.
    
    function matrix_row_to_vector(signal matrix : mux_input_t; constant row : natural) return std_logic_vector;
    procedure vector_to_matrix_row(signal matrix : out mux_input_t; constant row : natural; signal vector : in std_logic_vector);
end package;

package body fine_grain_mux is 
    procedure vector_to_matrix_row(signal matrix : out mux_input_t; constant row : natural; signal vector : in std_logic_vector) is
        variable matrix_i, vector_i: integer;
    begin
        matrix_i := matrix'LOW(2);
        vector_i := vector'LOW;
        for i in 0 to vector'HIGH - vector'LOW loop
            matrix(row, i + matrix_i) <= vector(i + vector_i);
        end loop;
    end procedure;
    
    function matrix_row_to_vector(signal matrix : mux_input_t; constant row : natural) return std_logic_vector is
        variable vector : std_logic_vector(matrix'length(2) - 1 downto 0);
    begin
        for i in vector'range loop
            vector(i) := matrix(row, i);
        end loop;
        return vector;
    end function;
end package body;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.fine_grain_mux.ALL;  



entity lut_multiplexor is
    generic (
        NUM_INPUTS : positive;
        DATA_WIDTH : positive;
        POSITION : positive;
        MUX_COLUMNS: natural := 0;
        COLUMN_OFFSET : integer := 0;
        PBLOCK : string := "";
        DEFAULT_VALUE : bit_vector (63 downto 0) := x"0000_0000_0000_0000" -- We init the multiplexor to use I0 --TODO change this value
    );
    port (
        mux_input : in mux_input_t(NUM_INPUTS-1 downto 0, DATA_WIDTH - 1 downto 0);
        mux_output : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end lut_multiplexor;

architecture Behavioral of lut_multiplexor is
    type LUT_interconnexion_t is array (DATA_WIDTH - 1 downto 0) 
         of std_logic_vector ((NUM_INPUTS - 2)/3 downto 0);
    signal LUT_interconnexion : LUT_interconnexion_t;
begin
        
    MULTIPLEXOR_GEN_1 : for i in 0 to DATA_WIDTH - 1 generate
        MULTIPLEXOR_GEN_2_1: if NUM_INPUTS = 2 generate
            attribute LOCK_PINS : string;          
            attribute DONT_TOUCH : string;            
            attribute MUX_LUT_ELEMENT: string;
            attribute mux_position : positive;
            attribute num_mux_columns : positive;         
            attribute PBLOCK_FINE_GRAIN : string;
            attribute PBLOCK_COLUMN_OFFSET : integer;
            attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
            attribute DONT_TOUCH of LUT_INST : label is "TRUE";
            attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
            attribute mux_position of LUT_INST: label is POSITION;
            attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
            attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;
            attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;
        begin
            LUT_INST : LUT6_2  
                generic map (
                    INIT => DEFAULT_VALUE  -- LUT "equation"
                )
                port map (
                     O6 => mux_output(i),    
                     O5 => open,                     
                     I5 => '0', 
                     I4 => '0', 
                     I3 => '0',        
                     I2 => mux_input(1, i), 
                     I1 => mux_input(0, i), 
                     I0 => '0'         
              );
        end generate;      
        MULTIPLEXOR_GEN_2_2 : if NUM_INPUTS = 3 generate 
            attribute LOCK_PINS : string;          
            attribute DONT_TOUCH : string;            
            attribute MUX_LUT_ELEMENT: string;
            attribute mux_position : positive;
            attribute num_mux_columns : positive;         
            attribute PBLOCK_FINE_GRAIN : string;
            attribute PBLOCK_COLUMN_OFFSET : integer;
            attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
            attribute DONT_TOUCH of LUT_INST : label is "TRUE";
            attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
            attribute mux_position of LUT_INST: label is POSITION;
            attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
            attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;    
            attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;                    
        begin
            LUT_INST : LUT6_2  
            generic map (
                INIT => DEFAULT_VALUE  -- LUT "equation"
            )
            port map (
                 O6 => mux_output(i),    
                 O5 => open,                     
                 I5 => '0', 
                 I4 => mux_input(2, i), 
                 I3 => '0',        
                 I2 => mux_input(1, i), 
                 I1 => mux_input(0, i), 
                 I0 => '0'         
            );      
        end generate; 
        MULTIPLEXOR_GEN_2_3 : if NUM_INPUTS = 4 generate 
            attribute LOCK_PINS : string;          
            attribute DONT_TOUCH : string;            
            attribute MUX_LUT_ELEMENT: string;
            attribute mux_position : positive;
            attribute num_mux_columns : positive;         
            attribute PBLOCK_FINE_GRAIN : string;
            attribute PBLOCK_COLUMN_OFFSET : integer;
            attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
            attribute DONT_TOUCH of LUT_INST : label is "TRUE";
            attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
            attribute mux_position of LUT_INST: label is POSITION;
            attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
            attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;    
            attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;        
            begin
                LUT_INST : LUT6_2  
                generic map (
                  INIT => DEFAULT_VALUE  -- LUT "equation"
                )
                port map (
                   O6 => mux_output(i),    
                   O5 => open,                     
                   I5 => mux_input(3, i), 
                   I4 => mux_input(2, i), 
                   I3 => '0',        
                   I2 => mux_input(1, i), 
                   I1 => mux_input(0, i), 
                   I0 => '0'         
                );    
            end generate;       
        MULTIPLEXOR_GEN_2_4 : if NUM_INPUTS > 4 generate
            MULTIPLEXOR_GEN_3 : for j in 0 to (NUM_INPUTS - 2)/3 generate 
                MULTIPLEXOR_GEN_4_1: if j = 0 generate --First LUT
                    attribute LOCK_PINS : string;          
                    attribute DONT_TOUCH : string;            
                    attribute MUX_LUT_ELEMENT: string;
                    attribute mux_position : positive;
                    attribute num_mux_columns : positive;         
                    attribute PBLOCK_FINE_GRAIN : string;
                    attribute PBLOCK_COLUMN_OFFSET : integer;
                    attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
                    attribute DONT_TOUCH of LUT_INST : label is "TRUE";
                    attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
                    attribute mux_position of LUT_INST: label is POSITION;
                    attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
                    attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;   
                    attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;                 
                    begin
                        LUT_INST : LUT6_2  
                        generic map (
                            INIT => DEFAULT_VALUE  -- LUT "equation"
                        )
                        port map (
                             O6 => LUT_interconnexion(i)(j),    
                             O5 => open,                     
                             I5 => mux_input(3, i), 
                             I4 => mux_input(2, i), 
                             I3 => '0',        
                             I2 => mux_input(1, i), 
                             I1 => mux_input(0, i), 
                             I0 => '0'         
                        );  
                   end generate;
                MULTIPLEXOR_GEN_4_2 : if j/= 0 and j < (NUM_INPUTS - 2)/3 generate --Middle LUT
                    attribute LOCK_PINS : string;          
                    attribute DONT_TOUCH : string;            
                    attribute MUX_LUT_ELEMENT: string;
                    attribute mux_position : positive;
                    attribute num_mux_columns : positive;         
                    attribute PBLOCK_FINE_GRAIN : string;
                    attribute PBLOCK_COLUMN_OFFSET : integer;
                    attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
                    attribute DONT_TOUCH of LUT_INST : label is "TRUE";
                    attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
                    attribute mux_position of LUT_INST: label is POSITION;
                    attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
                    attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;      
                    attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;               
                begin
                    LUT_INST : LUT6_2  
                    generic map (
                        INIT => DEFAULT_VALUE  -- LUT "equation"
                    )
                    port map (
                         O6 => LUT_interconnexion(i)(j),    
                         O5 => open,      
                         I5 => LUT_interconnexion(i)(j-1), 
                         I4 => mux_input(6 + (j-1)*3, i), 
                         I3 => '0',        
                         I2 => mux_input(5 + (j-1)*3, i), 
                         I1 => mux_input(4 + (j-1)*3, i),                
                         I0 => '0'         
                    );  
                end generate;
                MULTIPLEXOR_GEN_4_3 : if j /= 0 and j >= (NUM_INPUTS - 2)/3 generate --Last LUTs
                    MULTIPLEXOR_GEN_5_1: if (NUM_INPUTS-4) mod 3 =  1 generate
                        attribute LOCK_PINS : string;          
                        attribute DONT_TOUCH : string;            
                        attribute MUX_LUT_ELEMENT: string;
                        attribute mux_position : positive;
                        attribute num_mux_columns : positive;         
                        attribute PBLOCK_FINE_GRAIN : string;
                        attribute PBLOCK_COLUMN_OFFSET : integer;
                        attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
                        attribute DONT_TOUCH of LUT_INST : label is "TRUE";
                        attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
                        attribute mux_position of LUT_INST: label is POSITION;
                        attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
                        attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;    
                        attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;                    
                    begin
                        LUT_INST : LUT6_2  
                        generic map (
                            INIT => DEFAULT_VALUE  -- LUT "equation"
                        )
                        port map (
                             O6 => mux_output(i),    
                             O5 => open,                     
                             I5 => LUT_interconnexion(i)(j-1), 
                             I4 => '0', 
                             I3 => '0',        
                             I2 => '0', 
                             I1 => mux_input(4 + (j-1)*3, i), 
                             I0 => '0'         
                        );    
                    end generate;
                    MULTIPLEXOR_GEN_5_2 : if (NUM_INPUTS-4) mod 3 =  2 generate
                        attribute LOCK_PINS : string;          
                        attribute DONT_TOUCH : string;            
                        attribute MUX_LUT_ELEMENT: string;
                        attribute mux_position : positive;
                        attribute num_mux_columns : positive;         
                        attribute PBLOCK_FINE_GRAIN : string;
                        attribute PBLOCK_COLUMN_OFFSET : integer;
                        attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
                        attribute DONT_TOUCH of LUT_INST : label is "TRUE";
                        attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
                        attribute mux_position of LUT_INST: label is POSITION;
                        attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
                        attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;       
                        attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;             
                    begin
                        LUT_INST : LUT6_2  
                        generic map (
                            INIT => DEFAULT_VALUE  -- LUT "equation"
                        )
                        port map (
                             O6 => mux_output(i),    
                             O5 => open,                     
                             I5 => LUT_interconnexion(i)(j-1), 
                             I4 => '0', 
                             I3 => '0',        
                             I2 => mux_input(5 + (j-1)*3, i), 
                             I1 => mux_input(4 + (j-1)*3, i), 
                             I0 => '0'         
                        );       
                    end generate;
                    MULTIPLEXOR_GEN_5_3 : if (NUM_INPUTS-4) mod 3 =  0 generate
                        attribute LOCK_PINS : string;          
                        attribute DONT_TOUCH : string;            
                        attribute MUX_LUT_ELEMENT: string;
                        attribute mux_position : positive;
                        attribute num_mux_columns : positive;         
                        attribute PBLOCK_FINE_GRAIN : string;
                        attribute PBLOCK_COLUMN_OFFSET : integer;
                        attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
                        attribute DONT_TOUCH of LUT_INST : label is "TRUE";
                        attribute MUX_LUT_ELEMENT of LUT_INST: label is "TRUE";
                        attribute mux_position of LUT_INST: label is POSITION;
                        attribute num_mux_columns of LUT_INST: label is MUX_COLUMNS;
                        attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;   
                        attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;             
                    begin
                        LUT_INST : LUT6_2  
                        generic map (
                            INIT => DEFAULT_VALUE  -- LUT "equation"
                        )
                        port map (
                             O6 => mux_output(i),    
                             O5 => open,                     
                             I5 => LUT_interconnexion(i)(j-1), 
                             I4 => mux_input(6 + (j-1)*3, i), 
                             I3 => '0',        
                             I2 => mux_input(5 + (j-1)*3, i), 
                             I1 => mux_input(4 + (j-1)*3, i), 
                             I0 => '0'         
                        );                    
                    end generate;               
                end generate;
            end generate;
        end generate; 
    end generate;

end Behavioral;
