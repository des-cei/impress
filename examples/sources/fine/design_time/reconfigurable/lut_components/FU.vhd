library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

library UNISIM;
use UNISIM.VComponents.all;

entity lut_FU is
    generic (
        NUM_BLOCKS_4_BITS : positive := 1;
        POSITION : positive;
        FU_COLUMNS : natural := 0;
        COLUMN_OFFSET : integer := 0;
        PBLOCK : string := "";
        INIT1 : bit_vector (63 downto 0) := x"0000_0000_0000_0000"; 
        INIT2 : bit_vector (63 downto 0) := x"AAAA_AAAA_AAAA_AAAA" 
    );
    port (
        -- carry_in : in std_logic;
        in1 : in std_logic_vector (NUM_BLOCKS_4_BITS*4 - 1 downto 0);
        in2 : in std_logic_vector (NUM_BLOCKS_4_BITS*4 - 1 downto 0);
        -- carry_out : out std_logic;
        FU_out : out std_logic_vector (NUM_BLOCKS_4_BITS*4 - 1 downto 0)
    );
end lut_FU;

architecture Behavioral of lut_FU is
  -- We create signals from 0 to the next value 
  constant NUM_BITS : integer := NUM_BLOCKS_4_BITS*4;
  signal HS0, HS1 : std_logic_vector (NUM_BITS - 1 downto 0); -- half-sum
  signal FS : std_logic_vector (NUM_BITS downto 0); 
  signal carry_out_vector : std_logic_vector (NUM_BITS - 1 downto 0);
  signal carry : std_logic_vector (NUM_BLOCKS_4_BITS  downto 0);
begin
  
  carry(0) <= '0'; -- carry_in; to allow > and < FU 
  FS(NUM_BITS) <= carry(NUM_BLOCKS_4_BITS);
  
  FU_GEN: for j in 0 to NUM_BLOCKS_4_BITS - 1 generate
  begin
      -- First stage
    STAGE1_GEN : for i in 0 to 3 generate
      attribute LOCK_PINS : string;          
      attribute DONT_TOUCH : string;            
      attribute FU_LUT_ELEMENT: string;
      attribute FU_POSITION : positive;
      attribute NUM_FU_COLUMNS : positive;         
      attribute PBLOCK_FINE_GRAIN : string;
      attribute PBLOCK_COLUMN_OFFSET : integer;
      attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
      attribute DONT_TOUCH of LUT_INST : label is "TRUE";
      attribute FU_LUT_ELEMENT of LUT_INST: label is "TRUE";
      attribute FU_POSITION of LUT_INST: label is POSITION;
      attribute NUM_FU_COLUMNS of LUT_INST: label is FU_COLUMNS;
      attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;
      attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;
    begin
       LUT_INST : LUT6_2
          generic map (
             INIT => INIT1  -- LUT "equation"
          )
          port map (
             O6 => HS0(i + (j*4)),  -- O6  (LSb of half-sum)
             O5 => HS1(i + (j*4)),  -- O5  (MSb of half-sum)
             I5 => '1',     -- A6
             I4 => in1(i + (j*4)),    -- A5
             I3 => '0',     -- A4
             I2 => in2(i + (j*4)),    -- A3
             I1 => '0',     -- A2
             I0 => '0'      -- A1
          );
    end generate STAGE1_GEN;

    --TODO: check if it is necessary to add properties to fix a place to the CARRY BEL
    CARRY_INST : CARRY4
       port map (
          CO => carry_out_vector(4*j + 3 downto 4*j), -- 4-bit carry out
          O  => FS(4*j + 3 downto 4*j),  -- 4-bit full-sum output
          CI => carry(j),                -- 1-bit carry cascade input
          CYINIT => '0',               -- 1-bit carry initialization
          DI => HS1(4*j + 3 downto 4*j), -- 4-bit half-sum MSb input
          S  => HS0(4*j + 3 downto 4*j)  -- 4-bit half-sum LSb input
       ); 
    
    carry(j + 1) <= carry_out_vector(4*j + 3 );     

    -- Second stage the A name is for having the second stage LUTs bedore the first stage LUTs
    STAGE2_GEN : for i in 0 to 3 generate
      attribute LOCK_PINS : string;          
      attribute DONT_TOUCH : string;            
      attribute FU_LUT_ELEMENT: string;
      attribute FU_POSITION : positive;
      attribute NUM_FU_COLUMNS : positive;         
      attribute PBLOCK_FINE_GRAIN : string;
      attribute PBLOCK_COLUMN_OFFSET : integer;
      attribute LOCK_PINS of LUT_INST : label is "I5:A6,I4:A5,I3:A4,I2:A3,I1:A2,I0:A1";
      attribute DONT_TOUCH of LUT_INST : label is "TRUE";
      attribute FU_LUT_ELEMENT of LUT_INST: label is "TRUE";
      attribute FU_POSITION of LUT_INST: label is POSITION;
      attribute NUM_FU_COLUMNS of LUT_INST: label is FU_COLUMNS;
      attribute PBLOCK_FINE_GRAIN of LUT_INST : label is PBLOCK;
      attribute PBLOCK_COLUMN_OFFSET of LUT_INST : label is COLUMN_OFFSET;
    begin
       LUT_INST : LUT6_2  -- using LUT6_2 instead of LUT6 to prevent usage of O5
          generic map (
             INIT => INIT2  -- LUT "equation"
          )
          port map (
             O6 => FU_out(i + (j*4)),    -- O6
             O5 => open,
             I5 => FS(NUM_BITS),    -- A6  (overflow)
             I4 => FS(i + 1 + (j*4)), -- A5  (XS/2)
             I3 => '0',     -- A4
             I2 => FS(i + (j*4)),   -- A3  (XS)
             I1 => in1(i + (j*4)),    -- A2
             I0 => in2(i + (j*4))     -- A1
          );
    end generate STAGE2_GEN;
    
  end generate FU_GEN;
  

end Behavioral;
