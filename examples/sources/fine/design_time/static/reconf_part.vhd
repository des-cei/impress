----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 12/30/2019 02:04:20 PM
-- Design Name: 
-- Module Name: reconf_part - Behavioral
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
--library UNISIM;
--use UNISIM.VComponents.all;

entity reconf_part is
    Port (
       clk: in std_logic;
       reset : in std_logic; 
       input1 : in std_logic_vector (7 downto 0);
       input2 : in std_logic_vector (7 downto 0);
       output1 : out std_logic_vector (7 downto 0)
    );
end reconf_part;

architecture Behavioral of reconf_part is

begin


end Behavioral;
