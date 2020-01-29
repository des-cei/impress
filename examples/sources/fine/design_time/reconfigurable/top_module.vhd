library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.fine_grain_mux.ALL;  


entity module_2_inputs is
  Port (
      clk : in std_logic;
      reset : in std_logic;
      input1 : in std_logic_vector(7 downto 0);
      input2 : in std_logic_vector(7 downto 0);
      output1 : out std_logic_vector(7 downto 0)
    );
end module_2_inputs;

architecture Behavioral of module_2_inputs is
    signal cte1, cte2 : std_logic_vector(7 downto 0);
    signal input_mux_1 : mux_input_t(1 downto 0, 7 downto 0);
    signal input_mux_2 : mux_input_t(1 downto 0, 7 downto 0);
    signal mux_out1, mux_out2, output_tmp : std_logic_vector(7 downto 0);
begin
    lut_constant_1: entity work.lut_constant
        generic map (
            POSITION => 1,
            NUM_BITS => 8
        )
        port map (
            constant_output => cte1
        );
    lut_constant_2: entity work.lut_constant
        generic map (
            POSITION => 2,
            NUM_BITS => 8

        )
        port map (
            constant_output => cte2
        );
        
    vector_to_matrix_row(input_mux_1, 0, input1);
    vector_to_matrix_row(input_mux_1, 1, cte1);
    lut_mux_1: entity work.lut_multiplexor
        generic map (
            POSITION => 1,
            NUM_INPUTS => 2,
            DATA_WIDTH => 8
        )
        port map (
            mux_input => input_mux_1,
            mux_output => mux_out1
        );
        
    vector_to_matrix_row(input_mux_2, 0, input2);
    vector_to_matrix_row(input_mux_2, 1, cte2);
    lut_mux_2: entity work.lut_multiplexor
        generic map (
            POSITION => 2,
            NUM_INPUTS => 2,
            DATA_WIDTH => 8
        )
        port map (
            mux_input => input_mux_2,
            mux_output => mux_out2
        );
	
	lut_FU_1: entity work.lut_FU
        generic map (
            POSITION => 1,
            NUM_BLOCKS_4_BITS => 2
        )
        port map (
            in1 => mux_out1,
            in2 => mux_out2,
            FU_out => output_tmp
        );   
        
    process(clk, reset) 
    begin 
        if (reset = '1') then
            output1 <= (others => '0');
        elsif (clk'event and clk ='1') then
            output1 <= output_tmp;
        end if;
    end process;  

end Behavioral;
