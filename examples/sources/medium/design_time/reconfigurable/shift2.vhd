

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity shift2 is
  Port (
      clk : in std_logic;
      reset : in std_logic;
      input1 : in std_logic_vector(7 downto 0);
      output1 : out std_logic_vector(7 downto 0)
    );
end shift2;

architecture Behavioral of shift2 is

begin
    process(clk, reset) 
    begin 
        if (reset = '1') then
            output1 <= (others => '0');
        elsif (clk'event and clk ='1') then
            output1 <= "00" & input1(7 downto 2);
        end if;
    end process; 

end Behavioral;
