library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common_types_pkg.ALL;

ENTITY fast_icap_sysarr IS
   generic (
      -- Users to add parameters here
      MEM_A_BITS : integer := 9;
      FPGA_IDCODE : std_logic_vector (31 downto 0) := x"03727093"; -- 7z020
      -- User parameters ends
      -- Do not modify the parameters beyond this line


      -- Parameters of Axi Slave Bus Interface S_AXI_CTRL
      C_S_AXI_CTRL_DATA_WIDTH : integer   := 32;
      C_S_AXI_CTRL_ADDR_WIDTH : integer   := 6;

      -- Parameters of Axi Slave Bus Interface S_AXI_MEM
      C_S_AXI_MEM_ID_WIDTH     : integer  := 1;
      C_S_AXI_MEM_DATA_WIDTH   : integer  := 32;
      C_S_AXI_MEM_ADDR_WIDTH   : integer  := 16;
      C_S_AXI_MEM_AWUSER_WIDTH : integer  := 0;
      C_S_AXI_MEM_ARUSER_WIDTH : integer  := 0;
      C_S_AXI_MEM_WUSER_WIDTH  : integer  := 0;
      C_S_AXI_MEM_RUSER_WIDTH  : integer  := 0;
      C_S_AXI_MEM_BUSER_WIDTH  : integer  := 0
   );
   port (
      -- Users to add ports here
      Icap_Clk      : in  std_logic;
      -- User ports ends
      -- Do not modify the ports beyond this line


      -- Ports of Axi Slave Bus Interface S_AXI_CTRL
      s_axi_ctrl_aclk   : in std_logic;
      s_axi_ctrl_aresetn   : in std_logic;
      s_axi_ctrl_awaddr : in std_logic_vector(C_S_AXI_CTRL_ADDR_WIDTH-1 downto 0);
      s_axi_ctrl_awprot : in std_logic_vector(2 downto 0);
      s_axi_ctrl_awvalid   : in std_logic;
      s_axi_ctrl_awready   : out std_logic;
      s_axi_ctrl_wdata  : in std_logic_vector(C_S_AXI_CTRL_DATA_WIDTH-1 downto 0);
      s_axi_ctrl_wstrb  : in std_logic_vector((C_S_AXI_CTRL_DATA_WIDTH/8)-1 downto 0);
      s_axi_ctrl_wvalid : in std_logic;
      s_axi_ctrl_wready : out std_logic;
      s_axi_ctrl_bresp  : out std_logic_vector(1 downto 0);
      s_axi_ctrl_bvalid : out std_logic;
      s_axi_ctrl_bready : in std_logic;
      s_axi_ctrl_araddr : in std_logic_vector(C_S_AXI_CTRL_ADDR_WIDTH-1 downto 0);
      s_axi_ctrl_arprot : in std_logic_vector(2 downto 0);
      s_axi_ctrl_arvalid   : in std_logic;
      s_axi_ctrl_arready   : out std_logic;
      s_axi_ctrl_rdata  : out std_logic_vector(C_S_AXI_CTRL_DATA_WIDTH-1 downto 0);
      s_axi_ctrl_rresp  : out std_logic_vector(1 downto 0);
      s_axi_ctrl_rvalid : out std_logic;
      s_axi_ctrl_rready : in std_logic;

      -- Ports of Axi Slave Bus Interface S_AXI_MEM
      s_axi_mem_aclk : in std_logic;
      s_axi_mem_aresetn : in std_logic;
      s_axi_mem_awid : in std_logic_vector(C_S_AXI_MEM_ID_WIDTH-1 downto 0);
      s_axi_mem_awaddr  : in std_logic_vector(C_S_AXI_MEM_ADDR_WIDTH-1 downto 0);
      s_axi_mem_awlen   : in std_logic_vector(7 downto 0);
      s_axi_mem_awsize  : in std_logic_vector(2 downto 0);
      s_axi_mem_awburst : in std_logic_vector(1 downto 0);
      s_axi_mem_awlock  : in std_logic;
      s_axi_mem_awcache : in std_logic_vector(3 downto 0);
      s_axi_mem_awprot  : in std_logic_vector(2 downto 0);
      s_axi_mem_awqos   : in std_logic_vector(3 downto 0);
      s_axi_mem_awregion   : in std_logic_vector(3 downto 0);
      s_axi_mem_awuser  : in std_logic_vector(C_S_AXI_MEM_AWUSER_WIDTH-1 downto 0);
      s_axi_mem_awvalid : in std_logic;
      s_axi_mem_awready : out std_logic;
      s_axi_mem_wdata   : in std_logic_vector(C_S_AXI_MEM_DATA_WIDTH-1 downto 0);
      s_axi_mem_wstrb   : in std_logic_vector((C_S_AXI_MEM_DATA_WIDTH/8)-1 downto 0);
      s_axi_mem_wlast   : in std_logic;
      s_axi_mem_wuser   : in std_logic_vector(C_S_AXI_MEM_WUSER_WIDTH-1 downto 0);
      s_axi_mem_wvalid  : in std_logic;
      s_axi_mem_wready  : out std_logic;
      s_axi_mem_bid  : out std_logic_vector(C_S_AXI_MEM_ID_WIDTH-1 downto 0);
      s_axi_mem_bresp   : out std_logic_vector(1 downto 0);
      s_axi_mem_buser   : out std_logic_vector(C_S_AXI_MEM_BUSER_WIDTH-1 downto 0);
      s_axi_mem_bvalid  : out std_logic;
      s_axi_mem_bready  : in std_logic;
      s_axi_mem_arid : in std_logic_vector(C_S_AXI_MEM_ID_WIDTH-1 downto 0);
      s_axi_mem_araddr  : in std_logic_vector(C_S_AXI_MEM_ADDR_WIDTH-1 downto 0);
      s_axi_mem_arlen   : in std_logic_vector(7 downto 0);
      s_axi_mem_arsize  : in std_logic_vector(2 downto 0);
      s_axi_mem_arburst : in std_logic_vector(1 downto 0);
      s_axi_mem_arlock  : in std_logic;
      s_axi_mem_arcache : in std_logic_vector(3 downto 0);
      s_axi_mem_arprot  : in std_logic_vector(2 downto 0);
      s_axi_mem_arqos   : in std_logic_vector(3 downto 0);
      s_axi_mem_arregion   : in std_logic_vector(3 downto 0);
      s_axi_mem_aruser  : in std_logic_vector(C_S_AXI_MEM_ARUSER_WIDTH-1 downto 0);
      s_axi_mem_arvalid : in std_logic;
      s_axi_mem_arready : out std_logic;
      s_axi_mem_rid  : out std_logic_vector(C_S_AXI_MEM_ID_WIDTH-1 downto 0);
      s_axi_mem_rdata   : out std_logic_vector(C_S_AXI_MEM_DATA_WIDTH-1 downto 0);
      s_axi_mem_rresp   : out std_logic_vector(1 downto 0);
      s_axi_mem_rlast   : out std_logic;
      s_axi_mem_ruser   : out std_logic_vector(C_S_AXI_MEM_RUSER_WIDTH-1 downto 0);
      s_axi_mem_rvalid  : out std_logic;
      s_axi_mem_rready  : in std_logic
   );
END ENTITY;

ARCHITECTURE arch_imp OF fast_icap_sysarr IS

   --~ constant MEM_A_BITS : integer := C_S_AXI_MEM_ADDR_WIDTH - 2; --assuming 32b
   
   signal start, ready, ack    : std_logic;
   signal start2, ready2, ack2 : std_logic;
   signal cfg                  : std_logic_vector (MAX_BITS_CFG - 1 downto 0);
   signal mem_en_a             : std_logic;
   signal mem_be_a             : std_logic_vector (3 downto 0);
   signal mem_addr_a           : std_logic_vector (MEM_A_BITS-1 downto 0);
   signal mem_d_a, mem_q_a     : std_logic_vector (31 downto 0);
   signal mem_en_b, mem_we_b   : std_logic;
   signal mem_addr_b           : std_logic_vector (MEM_A_BITS-1 downto 0);
   signal mem_d_b, mem_q_b     : std_logic_vector (31 downto 0);
   
   signal frame_addr : std_logic_vector (31 downto 0);
   signal cfg_words  : integer range 0 to CFG_W_MAX;
   signal Reconfiguration_element : reconfiguration_t;
   
   attribute mark_debug : string;
   attribute mark_debug of mem_en_a: signal is "true";
   attribute mark_debug of mem_be_a: signal is "true";
   attribute mark_debug of mem_addr_a: signal is "true";
   attribute mark_debug of mem_d_a: signal is "true";
   attribute mark_debug of mem_q_a: signal is "true";
   attribute mark_debug of mem_en_b: signal is "true";
   attribute mark_debug of mem_addr_b: signal is "true";
   attribute mark_debug of mem_d_b: signal is "true";
   attribute mark_debug of mem_q_b: signal is "true";
   
   
BEGIN

-- Instantiation of Axi Bus Interface S_AXI_CTRL
S_AXI_CTRL_INST : entity work.s_axi_ctrl
   generic map (   
      C_S_AXI_DATA_WIDTH   => C_S_AXI_CTRL_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH   => C_S_AXI_CTRL_ADDR_WIDTH
   )
   port map (
      Start      => start,
      Ack        => ack,
      Ready      => ready,
      Cfg        => cfg,
      Frame_addr => frame_addr,
      Cfg_words  => cfg_words,
      Reconfiguration_element => Reconfiguration_element,
      
      S_AXI_ACLK  => s_axi_ctrl_aclk,
      S_AXI_ARESETN  => s_axi_ctrl_aresetn,
      S_AXI_AWADDR   => s_axi_ctrl_awaddr,
      S_AXI_AWPROT   => s_axi_ctrl_awprot,
      S_AXI_AWVALID  => s_axi_ctrl_awvalid,
      S_AXI_AWREADY  => s_axi_ctrl_awready,
      S_AXI_WDATA => s_axi_ctrl_wdata,
      S_AXI_WSTRB => s_axi_ctrl_wstrb,
      S_AXI_WVALID   => s_axi_ctrl_wvalid,
      S_AXI_WREADY   => s_axi_ctrl_wready,
      S_AXI_BRESP => s_axi_ctrl_bresp,
      S_AXI_BVALID   => s_axi_ctrl_bvalid,
      S_AXI_BREADY   => s_axi_ctrl_bready,
      S_AXI_ARADDR   => s_axi_ctrl_araddr,
      S_AXI_ARPROT   => s_axi_ctrl_arprot,
      S_AXI_ARVALID  => s_axi_ctrl_arvalid,
      S_AXI_ARREADY  => s_axi_ctrl_arready,
      S_AXI_RDATA => s_axi_ctrl_rdata,
      S_AXI_RRESP => s_axi_ctrl_rresp,
      S_AXI_RVALID   => s_axi_ctrl_rvalid,
      S_AXI_RREADY   => s_axi_ctrl_rready
   );

-- Instantiation of Axi Bus Interface S_AXI_MEM
S_AXI_MEM_INST : entity work.s_axi_mem
   generic map (
      MEM_A_BITS => MEM_A_BITS,
      C_S_AXI_ID_WIDTH  => C_S_AXI_MEM_ID_WIDTH,
      C_S_AXI_DATA_WIDTH   => C_S_AXI_MEM_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH   => C_S_AXI_MEM_ADDR_WIDTH,
      C_S_AXI_AWUSER_WIDTH => C_S_AXI_MEM_AWUSER_WIDTH,
      C_S_AXI_ARUSER_WIDTH => C_S_AXI_MEM_ARUSER_WIDTH,
      C_S_AXI_WUSER_WIDTH  => C_S_AXI_MEM_WUSER_WIDTH,
      C_S_AXI_RUSER_WIDTH  => C_S_AXI_MEM_RUSER_WIDTH,
      C_S_AXI_BUSER_WIDTH  => C_S_AXI_MEM_BUSER_WIDTH
   )
   port map (
      MEM_EN => mem_en_a,
      MEM_WE => open,
      MEM_BE => mem_be_a,
      MEM_A  => mem_addr_a ,
      MEM_D  => mem_d_a ,
      MEM_Q  => mem_q_a ,
      
      S_AXI_ACLK  => s_axi_mem_aclk,
      S_AXI_ARESETN  => s_axi_mem_aresetn,
      S_AXI_AWID  => s_axi_mem_awid,
      S_AXI_AWADDR   => s_axi_mem_awaddr,
      S_AXI_AWLEN => s_axi_mem_awlen,
      S_AXI_AWSIZE   => s_axi_mem_awsize,
      S_AXI_AWBURST  => s_axi_mem_awburst,
      S_AXI_AWLOCK   => s_axi_mem_awlock,
      S_AXI_AWCACHE  => s_axi_mem_awcache,
      S_AXI_AWPROT   => s_axi_mem_awprot,
      S_AXI_AWQOS => s_axi_mem_awqos,
      S_AXI_AWREGION => s_axi_mem_awregion,
      S_AXI_AWUSER   => s_axi_mem_awuser,
      S_AXI_AWVALID  => s_axi_mem_awvalid,
      S_AXI_AWREADY  => s_axi_mem_awready,
      S_AXI_WDATA => s_axi_mem_wdata,
      S_AXI_WSTRB => s_axi_mem_wstrb,
      S_AXI_WLAST => s_axi_mem_wlast,
      S_AXI_WUSER => s_axi_mem_wuser,
      S_AXI_WVALID   => s_axi_mem_wvalid,
      S_AXI_WREADY   => s_axi_mem_wready,
      S_AXI_BID   => s_axi_mem_bid,
      S_AXI_BRESP => s_axi_mem_bresp,
      S_AXI_BUSER => s_axi_mem_buser,
      S_AXI_BVALID   => s_axi_mem_bvalid,
      S_AXI_BREADY   => s_axi_mem_bready,
      S_AXI_ARID  => s_axi_mem_arid,
      S_AXI_ARADDR   => s_axi_mem_araddr,
      S_AXI_ARLEN => s_axi_mem_arlen,
      S_AXI_ARSIZE   => s_axi_mem_arsize,
      S_AXI_ARBURST  => s_axi_mem_arburst,
      S_AXI_ARLOCK   => s_axi_mem_arlock,
      S_AXI_ARCACHE  => s_axi_mem_arcache,
      S_AXI_ARPROT   => s_axi_mem_arprot,
      S_AXI_ARQOS => s_axi_mem_arqos,
      S_AXI_ARREGION => s_axi_mem_arregion,
      S_AXI_ARUSER   => s_axi_mem_aruser,
      S_AXI_ARVALID  => s_axi_mem_arvalid,
      S_AXI_ARREADY  => s_axi_mem_arready,
      S_AXI_RID   => s_axi_mem_rid,
      S_AXI_RDATA => s_axi_mem_rdata,
      S_AXI_RRESP => s_axi_mem_rresp,
      S_AXI_RLAST => s_axi_mem_rlast,
      S_AXI_RUSER => s_axi_mem_ruser,
      S_AXI_RVALID   => s_axi_mem_rvalid,
      S_AXI_RREADY   => s_axi_mem_rready
   );


-- Add user logic here

ICAP_CTRL_INST : entity work.icap_ctrl
   generic map (
--      MAX_ELEMS   => 15,   -- max number of vertical cells
--      HEIGHT_BITS => 4,    -- >= log2(max cell height)
--      CFG_W_MAX   => 4095, -- max num words to rcfg
      MEM_A_BITS  => MEM_A_BITS, -- bits of memory address
      MEM_D_BITS  => 32,   -- bits of memory data (LEAVE AS 32)
      FPGA_IDCODE => FPGA_IDCODE, -- 7z010:03722093, 7z020:03727093
      RESET_POLARITY => '0'
   )
   port map (
      -- Main control signals
      Clk        => Icap_Clk,
      Reset      => s_axi_ctrl_aresetn,
      Start      => start2,
      Ack        => ack2,
      Ready      => ready2,
      
      -- Reconfiguration parameters
      Frame_addr => frame_addr,
      Cfg_words  => cfg_words,
--      Elements   => 15,
--      Heights    => x"2_888888_1_888888_2", -- tenemos un padding LUT arriba y abajo y una palabra de reloj.
      Cfg        => cfg,
      Reconfiguration_element => Reconfiguration_element,
      
      -- Memory
      Mem_En     => mem_en_b,
      Mem_WE     => mem_we_b,
      Mem_Addr   => mem_addr_b,
      Mem_D      => mem_d_b,
      Mem_Q      => mem_q_b
   );


BRAM_INST : entity work.bram_dual_be
   generic map (
      ADDR_WIDTH => MEM_A_BITS,
      DATA_WIDTH => 32
   )
   port map (
      AClk  => s_axi_mem_aclk,
      AEN   => mem_en_a,
      AWE   => mem_be_a,
      AAddr => mem_addr_a,
      ADin  => mem_d_a,
      ADout => mem_q_a,
      
      BClk  => Icap_Clk,
      BEN   => mem_en_b,
      BWE   => (3 downto 0 => mem_we_b),
      BAddr => mem_addr_b,
      BDin  => mem_d_b,
      BDout => mem_q_b
   );


-- Sync start, ack, and ready (with only 1 FF; this'll probably be enough)

SYNC_START_PROC : process (Icap_Clk) is
begin
   if rising_edge(Icap_Clk) then
      if s_axi_ctrl_aresetn = '0' then  -- important!  we don't want garbage
         start2 <= '0';
      else
         start2 <= start;
      end if; -- s_axi_ctrl_aresetn
   end if; -- Icap_Clk
end process;

SYNC_ACK_READY_PROC : process (s_axi_ctrl_aclk) is
begin
   if rising_edge(s_axi_ctrl_aclk) then
      if s_axi_ctrl_aresetn = '0' then  -- important!  we don't want garbage
         ack   <= '0';
         ready <= '0';
      else
         ack   <= ack2;
         ready <= ready2;
      end if; -- s_axi_ctrl_aresetn
   end if; -- s_axi_ctrl_aclk
end process;

-- User logic ends


END ARCHITECTURE;
