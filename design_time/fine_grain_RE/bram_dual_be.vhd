-- Dual-port dual-clock symmetric BRAM with byte-wide write enable (inferred).
-- Read/write data port width and "byte" width configurable.
-- Memory size in words will be calculated from the address width.
-- Supported families: Virtex-6, Spartan-6 and newer.
-- Supported in both ISE and Vivado.

library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

ENTITY bram_dual_be IS
   generic (
      ADDR_WIDTH : positive := 10; -- word address, not byte address
      DATA_WIDTH : positive := 32; -- size of a word
      BYTE_WIDTH : positive :=  8  -- size of a byte (set to DATA_WIDTH for single WE)
   );
   port (
      AClk : in  std_logic; -- clock
      AEn  : in  std_logic; -- read/write enable
      AWE  : in  std_logic_vector (DATA_WIDTH/BYTE_WIDTH-1 downto 0) := (others => '0'); -- byte-wide write enable
      AAddr: in  std_logic_vector (ADDR_WIDTH-1 downto 0); -- word address
      ADin : in  std_logic_vector (DATA_WIDTH-1 downto 0) := (others => '0'); -- write data
      ADout: out std_logic_vector (DATA_WIDTH-1 downto 0); -- read data
      
      BClk : in  std_logic; -- clock
      BEn  : in  std_logic; -- read/write enable
      BWE  : in  std_logic_vector (DATA_WIDTH/BYTE_WIDTH-1 downto 0) := (others => '0'); -- byte-wide write enable
      BAddr: in  std_logic_vector (ADDR_WIDTH-1 downto 0); -- word address
      BDin : in  std_logic_vector (DATA_WIDTH-1 downto 0) := (others => '0'); -- write data
      BDout: out std_logic_vector (DATA_WIDTH-1 downto 0)  -- read data
   );

END ENTITY;

ARCHITECTURE write_first OF bram_dual_be IS
   type mem_t is array (2**ADDR_WIDTH-1 downto 0) of std_logic_vector (DATA_WIDTH-1 downto 0);
   shared variable mem : mem_t := (others => (others => '0'));
BEGIN

process(AClk) is
   variable aaddr_v : natural range 0 to 2**ADDR_WIDTH-1;
begin
   if rising_edge(AClk) then
      if AEn = '1' then
         aaddr_v := to_integer(unsigned(AAddr));
         -- write <- Din
         for i in AWE'range loop
            if AWE(i) = '1' then
               mem(aaddr_v)(i*BYTE_WIDTH + BYTE_WIDTH-1 downto i*BYTE_WIDTH) 
                     :=  ADin(i*BYTE_WIDTH + BYTE_WIDTH-1 downto i*BYTE_WIDTH);
            end if;
         end loop; -- AWE'range
         -- read -> Dout
         ADout <= mem(aaddr_v);
      end if; -- AEn = '1'
   end if; -- AClk
end process;

process(BClk) is
   variable baddr_v : natural range 0 to 2**ADDR_WIDTH-1;
begin
   if rising_edge(BClk) then
      if BEn = '1' then
         baddr_v := to_integer(unsigned(BAddr));
         -- write <- D
         for i in BWE'range loop
            if BWE(i) = '1' then
               mem(baddr_v)(i*BYTE_WIDTH + BYTE_WIDTH-1 downto i*BYTE_WIDTH) 
                     :=  BDin(i*BYTE_WIDTH + BYTE_WIDTH-1 downto i*BYTE_WIDTH);
            end if;
         end loop; -- BWE'range
         -- read -> Q
         BDout <= mem(baddr_v);
      end if; -- BEn = '1'
   end if; -- BClk
end process;

END ARCHITECTURE;


