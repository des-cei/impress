-- Module for performing BRAM-based partial reconfiguration of the FPGA 
-- through the ICAP by concatenating sub-clock region elements together 
-- rather than performing a readback for later writing the modified data 
-- (although this feature could be implemented as well).
-- 
-- This interface is common to all possible implementations.  This is a simple 
-- implementation for the 7 series with no readback capability nor the 
-- possibility of writing directly to the ICAP, although these features could 
-- be implemented.  The ICAP component is instantiated inside this module.
-- 
-- The Start, Ack, and Ready signals use a two-phase handshake, i.e. are 
-- triggered by toggling their value.  This allows this module to communicate 
-- with logic at a different frequency (although in that case it would be 
-- necessary to register the inputs and outputs externally to avoid 
-- metastability).
-- 
-- There are 4 externally observable states:
-- 0:  Start  =  Ack  =  Ready:  idle
-- 1:  Start /=  Ack  =  Ready:  not reconfiguring; waiting for fetch
-- 2:  Start  =  Ack /=  Ready:  input fetched; reconfiguring
-- 3:  Start /=  Ack /=  Ready:  reconfiguring; new input supplied (waiting)
-- Start should only be externally issued during states 0 and 2 (Start = Ack). 
-- The module is busy whenever the 3 signals are not equal (states 1,2,3).  
-- If Start is re-issued before the bitstream tail has been started to be 
-- written, said tail will not be written and instead a new command will be 
-- fetched.  Ready will be asserted as soon as reconfiguration is done 
-- (and Ack 1 clock cycle later once the new command has been fetched).  
-- If Start is re-issued once the bitstream tail has been started to be 
-- written but before it has finished, Ready will be asserted when the tail 
-- has finished being written and the module has moved to an idle state.
-- 
-- 
-- PORTS:
-- 
-- Clk:  clock for the module, ICAP, and external BRAM memory.
-- Reset:  module reset (active high or low depending on RESET_POLARITY).
-- Start:  trigger reconfig process.  Edge-sensitive (two-phase handshake).
--         Expected to be 0 after Reset.
-- Ack:  toggles when input data has been read and new input can be provided.
--       Input data can be changed when Ack = Start.  Resets to 0.
-- Ready:  toggles when the process has finished (when Ready = Ack = Start).
--         Resets to 0.
-- 
-- Frame_addr:  frame address where reconfig starts (padded with zeroes).
-- Cfg_words:  number of (meaningful) words to write, INCLUDING THE PADDING.  
--             Cfg_words = 101 * (number of frames + 1 padding frame)                      
-- Elements:  number of cells (vertical divisions) in the reconfigured region.
-- Heights:  height in words of each cell (HEIGHT_BITS bits); linearized as a 
--           single bit-array with the MSbits representing the highest cell.  
--           These values should add up 101.                                               
-- Cfg:  memory addresses where the bitstreams are located in the external RAM 
--       (linearized as a single bit-array).
-- 
-- Mem_En:  memory enable (read/write).
-- Mem_WE:  write enable (whole word).
-- Mem_Addr:  word address.
-- Mem_D:  memory input (write).
-- Mem_Q:  memory output (read) - 1 clock cycle latency.
-- 
-- PARAMETERS:
-- 
-- MAX_ELEMS:  maximum number of cells (max value of Elements).
-- HEIGHT_BITS:  bits of Heights that correspond to each value.
-- CFG_W_MAX:  maximum number of words to reconfig (excluding the pad frame).
-- MEM_A_BITS:  memory address width (bits) and width of values in Cfg.
-- MEM_D_BITS:  memory data width (bits).  Do not re-assign this value.
-- FPGA_IDCODE:  32-bit Device ID of the specific FPGA model
-- RESET_POLARITY:  '1' for active high reset, '0' for active low.



library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL; -- unsigned

library unisim;
use unisim.vcomponents.ICAPE2;

library work;
use work.common_types_pkg.ALL;  


ENTITY icap_ctrl IS
   generic (
      -- MAX_ELEMS   : positive := 5;    -- max number of vertical cells
      -- HEIGHT_BITS : positive := 8;    -- >= log2(max cell height)
      -- CFG_W_MAX   : positive := 4000; -- max num words to rcfg
      MEM_A_BITS  : positive := 9;   -- bits of memory address
      MEM_D_BITS  : positive := 32;   -- bits of memory data (LEAVE AS 32)
      FPGA_IDCODE : std_logic_vector (31 downto 0) := x"03727093"; -- 7z020
      RESET_POLARITY : std_logic := '1'
   );
   port (
      -- Main control signals
      Clk, Reset : in  std_logic;
      Start      : in  std_logic;  -- edge-sensitive
      Ack        : out std_logic;  -- edge-sensitive
      Ready      : out std_logic;  -- edge-sensitive
      
      -- Reconfiguration parameters
      Frame_addr : in  std_logic_vector (31 downto 0);
      Cfg_words  : in  integer range 0 to CFG_W_MAX;
      -- Elements   : in  integer range 0 to MAX_ELEMS; -- number of cells
      -- Heights    : in  std_logic_vector (MAX_ELEMS*HEIGHT_BITS-1 downto 0);
      Cfg        : in  std_logic_vector (MAX_BITS_CFG - 1 downto 0);
      Reconfiguration_element: in reconfiguration_t;
      
      -- Memory
      Mem_En     : out std_logic;
      Mem_WE     : out std_logic;
      Mem_Addr   : out std_logic_vector (MEM_A_BITS-1 downto 0);
      Mem_D      : out std_logic_vector (MEM_D_BITS-1 downto 0);
      Mem_Q      : in  std_logic_vector (MEM_D_BITS-1 downto 0)
   );
   attribute mark_debug : string;
   attribute mark_debug of Mem_Addr: signal is "true";
END ENTITY;



ARCHITECTURE series7_noreadback OF icap_ctrl IS
   type command_array_t is array (integer range <>) 
      of std_logic_vector (31 downto 0);
   
   constant COMMANDS_HEAD : command_array_t (0 to 9) := (
      x"FFFFFFFF", x"AA995566", x"20000000", x"20000000", -- Sync
      x"30008001", x"00000007", x"20000000", x"20000000", -- Reset CRC
      x"30018001", FPGA_IDCODE  -- Write FPGA_IDCODE to ID register
   );
   
   constant COMMANDS_TAIL : command_array_t (0 to 11) := (
      x"30002001", x"03BE0000", -- Park the FAR (set to B=7 T=0 R=15 C=0 F=0)
      x"30008001", x"00000007", x"20000000", x"20000000", -- Reset CRC again
      x"30008001", x"0000000D", -- Send command DESYNCH (Reset DALIGN Signal)
      x"20000000", x"20000000", -- NOOP until desynch is done
      x"20000000", x"20000000"  -- more NOOP (might not work otherwise)
   );
   
   signal icap_ce, icap_write : std_logic;
   signal icap_send, icap_i, icap_o : std_logic_vector (31 downto 0);
   signal icap_i_bitswap, icap_o_bitswap : std_logic_vector (31 downto 0);
   
   type icap_mode_t is (ICAP_NONE, ICAP_CMD, ICAP_MEM); --, ICAP_READ);
   signal icap_mode : icap_mode_t;
   
   function bitswap(x: std_logic_vector) return std_logic_vector is
      variable a, b : std_logic_vector (0 to x'length-1);
      variable res  : std_logic_vector (x'range);
   begin
      a := x;  -- ensure that indices go from 0 to x'length-1
      for i in 0 to x'length/8 - 1 loop  -- for each byte
         for j in 0 to 7 loop  -- for each bit in that byte
            b(8*i + (7-j)) := a(8*i + j);
         end loop;
      end loop;
      res := b;  -- ensure that result range is x'range
      return res;
   end function;
   


    --attribute mark_debug : string;
    attribute mark_debug of icap_ce: signal is "false";
    attribute mark_debug of icap_mode: signal is "false";
    attribute mark_debug of icap_write: signal is "false";
    attribute mark_debug of icap_i_bitswap: signal is "false";
    attribute mark_debug of icap_o_bitswap: signal is "false";
BEGIN


Mem_WE <= '0';  -- memory is read-only, since we don't do readback
Mem_D  <= (others => '-');


icap_write <= '0'; -- fixed to 0 (write)
icap_ce <= '0' when icap_mode /= ICAP_NONE else '1'; -- 0 enabled; 1 disabled
icap_i <=   icap_send when icap_mode = ICAP_CMD 
      else  Mem_Q     when icap_mode = ICAP_MEM 
      else  (others => '-');

icap_i_bitswap <= bitswap(icap_i);  -- bits in the ICAP signals are reversed
icap_o <= bitswap(icap_o_bitswap);





MAIN_PROC : process (Clk) is
   constant WORD_SIZE : integer := 32;
   constant CONST_NUM_ELEMENTS : integer := 100; --TODO ver si cambiar estos nombres para que se entienda mejor su funcion
   constant CONST_BITS_CFG_ELEMENT : integer := 4; -- A word contains the info of 2 LUTs (that equals to 4 constants)
   constant CONST_WORDS_HEIGHT : integer := 1;
   constant MUX_NUM_ELEMENTS : integer := 100;
   constant MUX_BITS_CFG_ELEMENT : integer := 4;
   constant MUX_WORDS_HEIGHT : integer := 1; 
   constant FU_NUM_ELEMENTS : integer := 25;
   constant FU_BITS_CFG_ELEMENT : integer := 5;
   constant FU_WORDS_HEIGHT : integer := 4;
   
   
   type state_t is (ST_IDLE, ST_HEAD, ST_FETCH, ST_ADDR, ST_DATA, ST_TAIL);
   variable state : state_t;
   
   variable start_old : std_logic;
   
   
   -- type heights_t is array (MAX_ELEMS-1 downto 0) 
         -- of integer range 0 to 2**HEIGHT_BITS-1;
   -- type cfg_t is array (MAX_ELEMS-1 downto 0) 
         -- of std_logic_vector (MEM_A_BITS-1 downto 0);
   type cfg_const_t is array (CONST_NUM_ELEMENTS - 1 downto 0) 
         of std_logic_vector (CONST_BITS_CFG_ELEMENT - 1 downto 0);
   type cfg_mux_t is array (MUX_NUM_ELEMENTS - 1 downto 0)
         of std_logic_vector (MUX_BITS_CFG_ELEMENT - 1 downto 0);
   type cfg_FU_t is array (FU_NUM_ELEMENTS - 1 downto 0)
         of std_logic_vector (FU_BITS_CFG_ELEMENT - 1 downto 0); 
   variable frame_addr_s : std_logic_vector (31 downto 0);
   variable cfg_words_s  : integer range 0 to CFG_W_MAX;
--   variable elements_s   : integer range 0 to MAX_ELEMS-1;
   -- variable heights_s    : heights_t;
   -- variable cfg_s        : cfg_t;
   variable cfg_const_s  : cfg_const_t;
   variable cfg_mux_s    : cfg_mux_t;
   variable cfg_FU_s     : cfg_FU_t;
   variable height_s     : integer range 0 to 31; 
   variable element_s      : integer range 0 to MAX_BITS_CFG - 1;
   variable reconfiguration_element_s : reconfiguration_t;
   
   variable i : integer range 0 to CFG_W_MAX;  -- word count
   variable h : integer range 0 to 3;--2**HEIGHT_BITS-1;  -- word in cell x frame
   variable c : integer range 0 to CONST_NUM_ELEMENTS-1;  -- cell count 
   variable num_frame : unsigned (1 downto 0);
   
   variable m : integer;
   variable n : integer;
   
   --attribute mark_debug : string;
   attribute mark_debug of cfg_const_s: variable is "false";
   attribute mark_debug of height_s: variable is "true";
   attribute mark_debug of reconfiguration_element_s: variable is "true";
   attribute mark_debug of state: variable is "true";
   attribute mark_debug of frame_addr_s: variable is "true";
   attribute mark_debug of cfg_mux_s: variable is "false";
   attribute mark_debug of cfg_FU_s: variable is "true";
   attribute mark_debug of i: variable is "true";
   attribute mark_debug of c: variable is "true";
   attribute mark_debug of h: variable is "true";
   
   
begin
   if rising_edge(Clk) then
      if Reset = RESET_POLARITY then
         state := ST_IDLE;
         start_old := '0';
         Ack <= '0';
         Ready <= '0';
         Mem_En   <= '0';
         Mem_Addr <= (others => '-');
         icap_mode <= ICAP_NONE;
         icap_send <= (others => '-'); -- don't care
--         cfg_s := (others => (others => '-')); -- improves timing
         cfg_mux_s := (others => (others => '-'));
         cfg_const_s := (others => (others => '-')); 
         frame_addr_s := (others => '-');
         i := 0; -- don't care
         
      else
         Mem_En   <= '0';
         Mem_Addr <= (others => '-');
         icap_mode <= ICAP_NONE;
         icap_send <= (others => '-');
         
         case state is
         when ST_IDLE =>
            -- Wait for Start to change
            if Start /= start_old then
               start_old := Start;
               i := 0;
               state := ST_HEAD;
            else
               i := 0; -- don't care
            end if; -- Start
            
            cfg_mux_s := (others => (others => '-'));
            cfg_const_s := (others => (others => '-')); 
--            cfg_s := (others => (others => '-')); -- don't care
            
         when ST_HEAD =>
            -- Send reconfiguration header (minus the address part)
            icap_mode <= ICAP_CMD;
            icap_send <= COMMANDS_HEAD(i);
            
            if i /= COMMANDS_HEAD'high then
               i := i+1;
            else
               i := i+1; -- don't care
               state := ST_FETCH;
            end if; -- i
            
            cfg_mux_s := (others => (others => '-'));
            cfg_const_s := (others => (others => '-')); 
--            cfg_s := (others => (others => '-')); -- don't care
            
         when ST_FETCH =>
            -- Register inputs (right after ST_HEAD or a previous ST_DATA)
            -- Lasts 1 clock cycle (but depending on state > depending on i=0)
            frame_addr_s := Frame_addr;
            cfg_words_s  := Cfg_words;
            -- elements_s := Elements - 1;
            reconfiguration_element_s := Reconfiguration_element;
            if Reconfiguration_element = const then
              for j in 0 to CONST_NUM_ELEMENTS - 1 loop
                cfg_const_s(j) := Cfg((j+1)*CONST_BITS_CFG_ELEMENT - 1 downto j*CONST_BITS_CFG_ELEMENT);
              end loop;
              cfg_mux_s := (others => (others => '-'));
              cfg_FU_s := (others => (others => '-'));
              height_s := CONST_WORDS_HEIGHT - 1;
              element_s  := CONST_NUM_ELEMENTS -1;
            elsif Reconfiguration_element = mux then
              for j in 0 to MUX_NUM_ELEMENTS -1 loop
                cfg_mux_s(j) := Cfg((j+1)*MUX_BITS_CFG_ELEMENT - 1 downto j*MUX_BITS_CFG_ELEMENT);
              end loop;
              cfg_const_s := (others => (others => '-'));
              cfg_FU_s := (others => (others => '-'));
              height_s := MUX_WORDS_HEIGHT - 1;
              element_s  := MUX_NUM_ELEMENTS - 1;
            elsif Reconfiguration_element = FU then
--               for j in 0 to FU_NUM_ELEMENTS -1 loop
--                 cfg_FU_s(j) := Cfg((j+1)*FU_BITS_CFG_ELEMENT - 1 downto j*FU_BITS_CFG_ELEMENT);
--               end loop;
              -- Each 32-bit word contains the info of BLOCK_PER_WORD FU blocks. The info of the first block starts at bit 0. 
              -- This way of storing the FU block information uses more words but is faster to update.
              for i in 0 to (FU_NUM_ELEMENTS / (WORD_SIZE / FU_BITS_CFG_ELEMENT)) - 1 loop
                for j in 0 to (WORD_SIZE / FU_BITS_CFG_ELEMENT) - 1 loop 
                    cfg_FU_s(j + i*(WORD_SIZE / FU_BITS_CFG_ELEMENT)) := Cfg(((j+1)*FU_BITS_CFG_ELEMENT - 1) + 32*i downto (j*FU_BITS_CFG_ELEMENT) + 32*i);
                end loop;
              end loop;
--              m := 0;
--              n := 0;
--              L1: loop 
--                for j in 0 to (WORD_SIZE / FU_BITS_CFG_ELEMENT)-1 loop 
--                  cfg_FU_s(m) := Cfg(((j+1)*FU_BITS_CFG_ELEMENT - 1) + 32*n downto (j*FU_BITS_CFG_ELEMENT) + 32*n);
--                  m := m + 1;
--                  exit L1 when m = FU_NUM_ELEMENTS;
--                end loop;
--                n := n + 1;
--              end loop;
              cfg_const_s := (others => (others => '-'));
              cfg_mux_s := (others => (others => '-'));
              height_s := FU_WORDS_HEIGHT - 1;
              element_s  := FU_NUM_ELEMENTS - 1;
            else
              cfg_mux_s := (others => (others => '-'));
              cfg_const_s := (others => (others => '-'));
              cfg_FU_s := (others => (others => '-'));
            end if;
            -- 
            -- for j in 0 to MAX_ELEMS-1 loop
            --    heights_s(j) := to_integer(unsigned(
            --          Heights(HEIGHT_BITS*(j+1)-1 downto HEIGHT_BITS*j) 
            --          )) - 1;
            --    cfg_s(j) := Cfg(MEM_A_BITS*(j+1)-1 downto MEM_A_BITS*j);
            -- end loop;
            
            -- Acknowledge input (ready to receive new inputs)
            Ack <= start_old;
            
            -- Meanwhile, send NOOP (just in case)
            icap_mode <= ICAP_CMD;
            icap_send <= x"20000000";
            
            i := 0;
            state := ST_ADDR;
            
         when ST_ADDR =>
            -- Send frame address and start cfg data write.
            icap_mode <= ICAP_CMD;
            case i is
               when 0 =>  icap_send <= x"30008001";  -- Send command:
               when 1 =>  icap_send <= x"00000001";  --   WCFG (Write cfg data)
               when 2 =>  icap_send <= x"20000000";  -- Noop
               when 3 =>  icap_send <= x"30002001";  -- Write to FAR
               when 4 =>  icap_send <= frame_addr_s; -- Address
               when 5 =>  icap_send <= x"20000000";  -- Noop (just in case)
               when 6 =>  icap_send <= x"30004000";  -- Write to FDRI (1)
               when 7 =>  icap_send <= x"5" & "0"    -- Write to FDRI (2)
                     & std_logic_vector(to_unsigned(cfg_words_s, 27));
               when others => icap_send <= (others => '-'); -- shouldn't happen
            end case; -- i
            
            if i /= 7 then
               i := i+1;
            else
               i := 0;
               h := 0;
               c := 0;
               num_frame := "00";
               state := ST_DATA;
            end if;
            
         when ST_DATA =>
            -- Write previous word (memory adds 1 cycle latency)
            if i /= 0 then
               icap_mode <= ICAP_MEM;
            else
               icap_mode <= ICAP_NONE;  -- previous word not yet available
            end if; -- i /= 0
            
            -- Tell memory to fetch word
            if i /= cfg_words_s then
               -- Write address; increment address
               Mem_En <= '1';
               -- TODO modificar esta descripcion que esta con lo anterior.
               -- We use the first 16 memory position to store the 1-word PBS to
               -- configure the 16 constants. To store the 4 mux 1-word PBS we use an 
               -- initial memory addresses from 10000 to 10011. In the mux case the height 
               -- is 2 and the same word is programmed twice (the first one reconfigures
               -- mux A and B, the second reconfigures C and D) 
               
               -- right now we only admit 2 frames, if we want to admit the four frames we 
               -- ned to add values 252 and 353.
               if i /= 50 and i /= 151 then 
                 if reconfiguration_element_s = const then
                   Mem_Addr(MEM_A_BITS-1 downto CONST_BITS_CFG_ELEMENT) <= (OTHERS => '0');
                   Mem_Addr(CONST_BITS_CFG_ELEMENT - 1 downto 0) <= cfg_const_s(c);                                 
                 elsif reconfiguration_element_s = mux then
                   -- We use address from 10000 to 11111
                   Mem_Addr(MEM_A_BITS-1 downto MUX_BITS_CFG_ELEMENT + 1) <= (OTHERS => '0');
                   Mem_Addr(MUX_BITS_CFG_ELEMENT) <= '1';
                   Mem_Addr(MUX_BITS_CFG_ELEMENT - 1 downto 0) <= cfg_mux_s(c);           
                 elsif reconfiguration_element_s = FU then
                   Mem_Addr(MEM_A_BITS-1 downto FU_BITS_CFG_ELEMENT + 4) <= (OTHERS => '0');
                   Mem_Addr(FU_BITS_CFG_ELEMENT + 3) <= '1'; --TODO we could delete this bit if we saved in distributed RAM the other values...
                   Mem_Addr(FU_BITS_CFG_ELEMENT + 2 downto 3) <= cfg_FU_s(c);
                   Mem_Addr(2) <= num_frame(0);
                   Mem_Addr(1 downto 0) <= std_logic_vector(to_unsigned(h, 2));
                 else
                   -- should not happen 
                   Mem_Addr <= (OTHERS => '0');
                 end if;  
                 
                 -- Increment h, c, i
                 if h /= height_s then
                    h := h+1;
                 else
                    h := 0;
                    if c /= element_s then
                       c := c+1;
                    else
                       num_frame := num_frame + 1;
                       c := 0;
                    end if;
                 end if;
               else
                 --Clock word we don't care about the contents 
                 Mem_Addr <= (OTHERS => '0');
               end if;          
                                             
               i := i+1;
               
            else  -- if i = cfg_word_s
               -- Next state (ST_TAIL if no new input; ST_FETCH if new input)
               if Start /= start_old then  -- new input: repeat write
                  Ready <= start_old; -- acknowledge completion (of this write)
                  start_old := Start;
                  i := 0; -- don't care
                  state := ST_FETCH;
               else  -- no new input: write COMMANDS_TAIL and finish
                  -- Ready will be acknowledged when ST_TAIL finishes
                  i := 0;
                  state := ST_TAIL;
               end if;  -- Start /= start_old
               
            end if; -- i /= cfg_word_s
            
         when ST_TAIL =>
            -- Send reconfiguration tail
            icap_mode <= ICAP_CMD;
            icap_send <= COMMANDS_TAIL(i);
            
            if i /= COMMANDS_TAIL'high then
               i := i+1;
            else
               i := i+1; -- don't care
               Ready <= start_old; -- acknowledge completion (of everything)
               state := ST_IDLE;
            end if; -- i
            
--            cfg_s := (others => (others => '-')); -- don't care
            cfg_mux_s := (others => (others => '-'));
            cfg_const_s := (others => (others => '-')); 
            
         end case; -- state
         
      end if; -- Reset
   end if; -- Clk
end process;



-- synthesis translate_off
-- DO_NOT_SIMULATE_ICAP : if false generate
-- synthesis translate_on

-- ICAP instantiation
ICAP_INST : ICAPE2
   generic map (
      ICAP_WIDTH => "X32"
   )
   port map (
      CLK   => clk            ,  -- Clock input
      CSIB  => icap_ce        ,  -- Clock enable input
      I     => icap_i_bitswap ,  -- 32-bit data input
      O     => icap_o_bitswap ,  -- 32-bit data output
      RDWRB => icap_write        -- Write input
   );

-- synthesis translate_off
-- end generate DO_NOT_SIMULATE_ICAP;
-- synthesis translate_on



END ARCHITECTURE;

