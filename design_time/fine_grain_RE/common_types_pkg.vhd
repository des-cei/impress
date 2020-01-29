library ieee;
use ieee.std_logic_1164.all;

package common_types_pkg is
   type reconfiguration_t is (const, mux, FU);
   attribute ENUM_ENCODING: string; 
   attribute ENUM_ENCODING of reconfiguration_t: type is "00 01 10";
   constant MAX_BITS_CFG : integer := 400; 
   constant CFG_W_MAX : integer := 4095;
end package;