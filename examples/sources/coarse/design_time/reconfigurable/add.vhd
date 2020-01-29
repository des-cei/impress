library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity add is
  Port (
    clk : in std_logic;
    reset : in std_logic;
    input1 : in unsigned(7 downto 0);
    input2 : in unsigned(7 downto 0);
    output1 : out unsigned(7 downto 0)
  );
end add;

architecture Behavioral of add is

begin

    process(clk, reset) 
    begin 
        if (reset = '1') then
            output1 <= (others => '0');
        elsif (clk'event and clk ='1') then
            output1 <= input1 + input2;
        end if;
    end process; 
    

end Behavioral;
