library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;
use ieee.std_logic_arith.all;
use ieee.std_logic_signed.all;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity multiply is
  Port (
    clk : in std_logic;
    reset : in std_logic;
    input1 : in std_logic_vector (7 downto 0);
    input2 : in std_logic_vector(7 downto 0);
    output1 : out std_logic_vector (7 downto 0)
  );
end multiply;

architecture Behavioral of multiply is
	signal temp : std_logic_vector (15 downto 0);
begin
    
    temp <= input1*input2;
    process(clk, reset) 
    begin 
        if (reset = '1') then
            output1 <= (others => '0');
        elsif (clk'event and clk ='1') then
            output1 <= temp(7 downto 0);  
        end if;
    end process;       

end Behavioral;
