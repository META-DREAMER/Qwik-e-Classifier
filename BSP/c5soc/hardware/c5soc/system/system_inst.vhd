	component system is
		port (
			clk_50_clk                          : in    std_logic                     := 'X';             -- clk
			reset_50_reset_n                    : in    std_logic                     := 'X';             -- reset_n
			kernel_clk_clk                      : out   std_logic;                                        -- clk
			fpga_memory_mem_a                   : out   std_logic_vector(14 downto 0);                    -- mem_a
			fpga_memory_mem_ba                  : out   std_logic_vector(2 downto 0);                     -- mem_ba
			fpga_memory_mem_ck                  : out   std_logic_vector(0 downto 0);                     -- mem_ck
			fpga_memory_mem_ck_n                : out   std_logic_vector(0 downto 0);                     -- mem_ck_n
			fpga_memory_mem_cke                 : out   std_logic_vector(0 downto 0);                     -- mem_cke
			fpga_memory_mem_cs_n                : out   std_logic_vector(0 downto 0);                     -- mem_cs_n
			fpga_memory_mem_dm                  : out   std_logic_vector(3 downto 0);                     -- mem_dm
			fpga_memory_mem_ras_n               : out   std_logic_vector(0 downto 0);                     -- mem_ras_n
			fpga_memory_mem_cas_n               : out   std_logic_vector(0 downto 0);                     -- mem_cas_n
			fpga_memory_mem_we_n                : out   std_logic_vector(0 downto 0);                     -- mem_we_n
			fpga_memory_mem_reset_n             : out   std_logic;                                        -- mem_reset_n
			fpga_memory_mem_dq                  : inout std_logic_vector(31 downto 0) := (others => 'X'); -- mem_dq
			fpga_memory_mem_dqs                 : inout std_logic_vector(3 downto 0)  := (others => 'X'); -- mem_dqs
			fpga_memory_mem_dqs_n               : inout std_logic_vector(3 downto 0)  := (others => 'X'); -- mem_dqs_n
			fpga_memory_mem_odt                 : out   std_logic_vector(0 downto 0);                     -- mem_odt
			fpga_memory_oct_rzqin               : in    std_logic                     := 'X';             -- rzqin
			fpga_sdram_status_local_init_done   : out   std_logic;                                        -- local_init_done
			fpga_sdram_status_local_cal_success : out   std_logic;                                        -- local_cal_success
			fpga_sdram_status_local_cal_fail    : out   std_logic;                                        -- local_cal_fail
			memory_mem_a                        : out   std_logic_vector(14 downto 0);                    -- mem_a
			memory_mem_ba                       : out   std_logic_vector(2 downto 0);                     -- mem_ba
			memory_mem_ck                       : out   std_logic;                                        -- mem_ck
			memory_mem_ck_n                     : out   std_logic;                                        -- mem_ck_n
			memory_mem_cke                      : out   std_logic;                                        -- mem_cke
			memory_mem_cs_n                     : out   std_logic;                                        -- mem_cs_n
			memory_mem_ras_n                    : out   std_logic;                                        -- mem_ras_n
			memory_mem_cas_n                    : out   std_logic;                                        -- mem_cas_n
			memory_mem_we_n                     : out   std_logic;                                        -- mem_we_n
			memory_mem_reset_n                  : out   std_logic;                                        -- mem_reset_n
			memory_mem_dq                       : inout std_logic_vector(39 downto 0) := (others => 'X'); -- mem_dq
			memory_mem_dqs                      : inout std_logic_vector(4 downto 0)  := (others => 'X'); -- mem_dqs
			memory_mem_dqs_n                    : inout std_logic_vector(4 downto 0)  := (others => 'X'); -- mem_dqs_n
			memory_mem_odt                      : out   std_logic;                                        -- mem_odt
			memory_mem_dm                       : out   std_logic_vector(4 downto 0);                     -- mem_dm
			memory_oct_rzqin                    : in    std_logic                     := 'X';             -- oct_rzqin
			peripheral_hps_io_emac0_inst_TX_CLK : out   std_logic;                                        -- hps_io_emac0_inst_TX_CLK
			peripheral_hps_io_emac0_inst_TXD0   : out   std_logic;                                        -- hps_io_emac0_inst_TXD0
			peripheral_hps_io_emac0_inst_TXD1   : out   std_logic;                                        -- hps_io_emac0_inst_TXD1
			peripheral_hps_io_emac0_inst_TXD2   : out   std_logic;                                        -- hps_io_emac0_inst_TXD2
			peripheral_hps_io_emac0_inst_TXD3   : out   std_logic;                                        -- hps_io_emac0_inst_TXD3
			peripheral_hps_io_emac0_inst_RXD0   : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RXD0
			peripheral_hps_io_emac0_inst_MDIO   : inout std_logic                     := 'X';             -- hps_io_emac0_inst_MDIO
			peripheral_hps_io_emac0_inst_MDC    : out   std_logic;                                        -- hps_io_emac0_inst_MDC
			peripheral_hps_io_emac0_inst_RX_CTL : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RX_CTL
			peripheral_hps_io_emac0_inst_TX_CTL : out   std_logic;                                        -- hps_io_emac0_inst_TX_CTL
			peripheral_hps_io_emac0_inst_RX_CLK : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RX_CLK
			peripheral_hps_io_emac0_inst_RXD1   : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RXD1
			peripheral_hps_io_emac0_inst_RXD2   : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RXD2
			peripheral_hps_io_emac0_inst_RXD3   : in    std_logic                     := 'X';             -- hps_io_emac0_inst_RXD3
			peripheral_hps_io_sdio_inst_CMD     : inout std_logic                     := 'X';             -- hps_io_sdio_inst_CMD
			peripheral_hps_io_sdio_inst_D0      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D0
			peripheral_hps_io_sdio_inst_D1      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D1
			peripheral_hps_io_sdio_inst_CLK     : out   std_logic;                                        -- hps_io_sdio_inst_CLK
			peripheral_hps_io_sdio_inst_D2      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D2
			peripheral_hps_io_sdio_inst_D3      : inout std_logic                     := 'X';             -- hps_io_sdio_inst_D3
			peripheral_hps_io_uart0_inst_RX     : in    std_logic                     := 'X';             -- hps_io_uart0_inst_RX
			peripheral_hps_io_uart0_inst_TX     : out   std_logic;                                        -- hps_io_uart0_inst_TX
			peripheral_hps_io_i2c0_inst_SDA     : inout std_logic                     := 'X';             -- hps_io_i2c0_inst_SDA
			peripheral_hps_io_i2c0_inst_SCL     : inout std_logic                     := 'X';             -- hps_io_i2c0_inst_SCL
			peripheral_hps_io_gpio_inst_GPIO41  : inout std_logic                     := 'X';             -- hps_io_gpio_inst_GPIO41
			peripheral_hps_io_gpio_inst_GPIO42  : inout std_logic                     := 'X';             -- hps_io_gpio_inst_GPIO42
			peripheral_hps_io_gpio_inst_GPIO43  : inout std_logic                     := 'X';             -- hps_io_gpio_inst_GPIO43
			peripheral_hps_io_gpio_inst_GPIO44  : inout std_logic                     := 'X'              -- hps_io_gpio_inst_GPIO44
		);
	end component system;

	u0 : component system
		port map (
			clk_50_clk                          => CONNECTED_TO_clk_50_clk,                          --            clk_50.clk
			reset_50_reset_n                    => CONNECTED_TO_reset_50_reset_n,                    --          reset_50.reset_n
			kernel_clk_clk                      => CONNECTED_TO_kernel_clk_clk,                      --        kernel_clk.clk
			fpga_memory_mem_a                   => CONNECTED_TO_fpga_memory_mem_a,                   --       fpga_memory.mem_a
			fpga_memory_mem_ba                  => CONNECTED_TO_fpga_memory_mem_ba,                  --                  .mem_ba
			fpga_memory_mem_ck                  => CONNECTED_TO_fpga_memory_mem_ck,                  --                  .mem_ck
			fpga_memory_mem_ck_n                => CONNECTED_TO_fpga_memory_mem_ck_n,                --                  .mem_ck_n
			fpga_memory_mem_cke                 => CONNECTED_TO_fpga_memory_mem_cke,                 --                  .mem_cke
			fpga_memory_mem_cs_n                => CONNECTED_TO_fpga_memory_mem_cs_n,                --                  .mem_cs_n
			fpga_memory_mem_dm                  => CONNECTED_TO_fpga_memory_mem_dm,                  --                  .mem_dm
			fpga_memory_mem_ras_n               => CONNECTED_TO_fpga_memory_mem_ras_n,               --                  .mem_ras_n
			fpga_memory_mem_cas_n               => CONNECTED_TO_fpga_memory_mem_cas_n,               --                  .mem_cas_n
			fpga_memory_mem_we_n                => CONNECTED_TO_fpga_memory_mem_we_n,                --                  .mem_we_n
			fpga_memory_mem_reset_n             => CONNECTED_TO_fpga_memory_mem_reset_n,             --                  .mem_reset_n
			fpga_memory_mem_dq                  => CONNECTED_TO_fpga_memory_mem_dq,                  --                  .mem_dq
			fpga_memory_mem_dqs                 => CONNECTED_TO_fpga_memory_mem_dqs,                 --                  .mem_dqs
			fpga_memory_mem_dqs_n               => CONNECTED_TO_fpga_memory_mem_dqs_n,               --                  .mem_dqs_n
			fpga_memory_mem_odt                 => CONNECTED_TO_fpga_memory_mem_odt,                 --                  .mem_odt
			fpga_memory_oct_rzqin               => CONNECTED_TO_fpga_memory_oct_rzqin,               --   fpga_memory_oct.rzqin
			fpga_sdram_status_local_init_done   => CONNECTED_TO_fpga_sdram_status_local_init_done,   -- fpga_sdram_status.local_init_done
			fpga_sdram_status_local_cal_success => CONNECTED_TO_fpga_sdram_status_local_cal_success, --                  .local_cal_success
			fpga_sdram_status_local_cal_fail    => CONNECTED_TO_fpga_sdram_status_local_cal_fail,    --                  .local_cal_fail
			memory_mem_a                        => CONNECTED_TO_memory_mem_a,                        --            memory.mem_a
			memory_mem_ba                       => CONNECTED_TO_memory_mem_ba,                       --                  .mem_ba
			memory_mem_ck                       => CONNECTED_TO_memory_mem_ck,                       --                  .mem_ck
			memory_mem_ck_n                     => CONNECTED_TO_memory_mem_ck_n,                     --                  .mem_ck_n
			memory_mem_cke                      => CONNECTED_TO_memory_mem_cke,                      --                  .mem_cke
			memory_mem_cs_n                     => CONNECTED_TO_memory_mem_cs_n,                     --                  .mem_cs_n
			memory_mem_ras_n                    => CONNECTED_TO_memory_mem_ras_n,                    --                  .mem_ras_n
			memory_mem_cas_n                    => CONNECTED_TO_memory_mem_cas_n,                    --                  .mem_cas_n
			memory_mem_we_n                     => CONNECTED_TO_memory_mem_we_n,                     --                  .mem_we_n
			memory_mem_reset_n                  => CONNECTED_TO_memory_mem_reset_n,                  --                  .mem_reset_n
			memory_mem_dq                       => CONNECTED_TO_memory_mem_dq,                       --                  .mem_dq
			memory_mem_dqs                      => CONNECTED_TO_memory_mem_dqs,                      --                  .mem_dqs
			memory_mem_dqs_n                    => CONNECTED_TO_memory_mem_dqs_n,                    --                  .mem_dqs_n
			memory_mem_odt                      => CONNECTED_TO_memory_mem_odt,                      --                  .mem_odt
			memory_mem_dm                       => CONNECTED_TO_memory_mem_dm,                       --                  .mem_dm
			memory_oct_rzqin                    => CONNECTED_TO_memory_oct_rzqin,                    --                  .oct_rzqin
			peripheral_hps_io_emac0_inst_TX_CLK => CONNECTED_TO_peripheral_hps_io_emac0_inst_TX_CLK, --        peripheral.hps_io_emac0_inst_TX_CLK
			peripheral_hps_io_emac0_inst_TXD0   => CONNECTED_TO_peripheral_hps_io_emac0_inst_TXD0,   --                  .hps_io_emac0_inst_TXD0
			peripheral_hps_io_emac0_inst_TXD1   => CONNECTED_TO_peripheral_hps_io_emac0_inst_TXD1,   --                  .hps_io_emac0_inst_TXD1
			peripheral_hps_io_emac0_inst_TXD2   => CONNECTED_TO_peripheral_hps_io_emac0_inst_TXD2,   --                  .hps_io_emac0_inst_TXD2
			peripheral_hps_io_emac0_inst_TXD3   => CONNECTED_TO_peripheral_hps_io_emac0_inst_TXD3,   --                  .hps_io_emac0_inst_TXD3
			peripheral_hps_io_emac0_inst_RXD0   => CONNECTED_TO_peripheral_hps_io_emac0_inst_RXD0,   --                  .hps_io_emac0_inst_RXD0
			peripheral_hps_io_emac0_inst_MDIO   => CONNECTED_TO_peripheral_hps_io_emac0_inst_MDIO,   --                  .hps_io_emac0_inst_MDIO
			peripheral_hps_io_emac0_inst_MDC    => CONNECTED_TO_peripheral_hps_io_emac0_inst_MDC,    --                  .hps_io_emac0_inst_MDC
			peripheral_hps_io_emac0_inst_RX_CTL => CONNECTED_TO_peripheral_hps_io_emac0_inst_RX_CTL, --                  .hps_io_emac0_inst_RX_CTL
			peripheral_hps_io_emac0_inst_TX_CTL => CONNECTED_TO_peripheral_hps_io_emac0_inst_TX_CTL, --                  .hps_io_emac0_inst_TX_CTL
			peripheral_hps_io_emac0_inst_RX_CLK => CONNECTED_TO_peripheral_hps_io_emac0_inst_RX_CLK, --                  .hps_io_emac0_inst_RX_CLK
			peripheral_hps_io_emac0_inst_RXD1   => CONNECTED_TO_peripheral_hps_io_emac0_inst_RXD1,   --                  .hps_io_emac0_inst_RXD1
			peripheral_hps_io_emac0_inst_RXD2   => CONNECTED_TO_peripheral_hps_io_emac0_inst_RXD2,   --                  .hps_io_emac0_inst_RXD2
			peripheral_hps_io_emac0_inst_RXD3   => CONNECTED_TO_peripheral_hps_io_emac0_inst_RXD3,   --                  .hps_io_emac0_inst_RXD3
			peripheral_hps_io_sdio_inst_CMD     => CONNECTED_TO_peripheral_hps_io_sdio_inst_CMD,     --                  .hps_io_sdio_inst_CMD
			peripheral_hps_io_sdio_inst_D0      => CONNECTED_TO_peripheral_hps_io_sdio_inst_D0,      --                  .hps_io_sdio_inst_D0
			peripheral_hps_io_sdio_inst_D1      => CONNECTED_TO_peripheral_hps_io_sdio_inst_D1,      --                  .hps_io_sdio_inst_D1
			peripheral_hps_io_sdio_inst_CLK     => CONNECTED_TO_peripheral_hps_io_sdio_inst_CLK,     --                  .hps_io_sdio_inst_CLK
			peripheral_hps_io_sdio_inst_D2      => CONNECTED_TO_peripheral_hps_io_sdio_inst_D2,      --                  .hps_io_sdio_inst_D2
			peripheral_hps_io_sdio_inst_D3      => CONNECTED_TO_peripheral_hps_io_sdio_inst_D3,      --                  .hps_io_sdio_inst_D3
			peripheral_hps_io_uart0_inst_RX     => CONNECTED_TO_peripheral_hps_io_uart0_inst_RX,     --                  .hps_io_uart0_inst_RX
			peripheral_hps_io_uart0_inst_TX     => CONNECTED_TO_peripheral_hps_io_uart0_inst_TX,     --                  .hps_io_uart0_inst_TX
			peripheral_hps_io_i2c0_inst_SDA     => CONNECTED_TO_peripheral_hps_io_i2c0_inst_SDA,     --                  .hps_io_i2c0_inst_SDA
			peripheral_hps_io_i2c0_inst_SCL     => CONNECTED_TO_peripheral_hps_io_i2c0_inst_SCL,     --                  .hps_io_i2c0_inst_SCL
			peripheral_hps_io_gpio_inst_GPIO41  => CONNECTED_TO_peripheral_hps_io_gpio_inst_GPIO41,  --                  .hps_io_gpio_inst_GPIO41
			peripheral_hps_io_gpio_inst_GPIO42  => CONNECTED_TO_peripheral_hps_io_gpio_inst_GPIO42,  --                  .hps_io_gpio_inst_GPIO42
			peripheral_hps_io_gpio_inst_GPIO43  => CONNECTED_TO_peripheral_hps_io_gpio_inst_GPIO43,  --                  .hps_io_gpio_inst_GPIO43
			peripheral_hps_io_gpio_inst_GPIO44  => CONNECTED_TO_peripheral_hps_io_gpio_inst_GPIO44   --                  .hps_io_gpio_inst_GPIO44
		);

