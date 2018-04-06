
module system (
	clk_50_clk,
	reset_50_reset_n,
	kernel_clk_clk,
	fpga_memory_mem_a,
	fpga_memory_mem_ba,
	fpga_memory_mem_ck,
	fpga_memory_mem_ck_n,
	fpga_memory_mem_cke,
	fpga_memory_mem_cs_n,
	fpga_memory_mem_dm,
	fpga_memory_mem_ras_n,
	fpga_memory_mem_cas_n,
	fpga_memory_mem_we_n,
	fpga_memory_mem_reset_n,
	fpga_memory_mem_dq,
	fpga_memory_mem_dqs,
	fpga_memory_mem_dqs_n,
	fpga_memory_mem_odt,
	fpga_memory_oct_rzqin,
	fpga_sdram_status_local_init_done,
	fpga_sdram_status_local_cal_success,
	fpga_sdram_status_local_cal_fail,
	memory_mem_a,
	memory_mem_ba,
	memory_mem_ck,
	memory_mem_ck_n,
	memory_mem_cke,
	memory_mem_cs_n,
	memory_mem_ras_n,
	memory_mem_cas_n,
	memory_mem_we_n,
	memory_mem_reset_n,
	memory_mem_dq,
	memory_mem_dqs,
	memory_mem_dqs_n,
	memory_mem_odt,
	memory_mem_dm,
	memory_oct_rzqin,
	peripheral_hps_io_emac0_inst_TX_CLK,
	peripheral_hps_io_emac0_inst_TXD0,
	peripheral_hps_io_emac0_inst_TXD1,
	peripheral_hps_io_emac0_inst_TXD2,
	peripheral_hps_io_emac0_inst_TXD3,
	peripheral_hps_io_emac0_inst_RXD0,
	peripheral_hps_io_emac0_inst_MDIO,
	peripheral_hps_io_emac0_inst_MDC,
	peripheral_hps_io_emac0_inst_RX_CTL,
	peripheral_hps_io_emac0_inst_TX_CTL,
	peripheral_hps_io_emac0_inst_RX_CLK,
	peripheral_hps_io_emac0_inst_RXD1,
	peripheral_hps_io_emac0_inst_RXD2,
	peripheral_hps_io_emac0_inst_RXD3,
	peripheral_hps_io_sdio_inst_CMD,
	peripheral_hps_io_sdio_inst_D0,
	peripheral_hps_io_sdio_inst_D1,
	peripheral_hps_io_sdio_inst_CLK,
	peripheral_hps_io_sdio_inst_D2,
	peripheral_hps_io_sdio_inst_D3,
	peripheral_hps_io_uart0_inst_RX,
	peripheral_hps_io_uart0_inst_TX,
	peripheral_hps_io_i2c0_inst_SDA,
	peripheral_hps_io_i2c0_inst_SCL,
	peripheral_hps_io_gpio_inst_GPIO41,
	peripheral_hps_io_gpio_inst_GPIO42,
	peripheral_hps_io_gpio_inst_GPIO43,
	peripheral_hps_io_gpio_inst_GPIO44);	

	input		clk_50_clk;
	input		reset_50_reset_n;
	output		kernel_clk_clk;
	output	[14:0]	fpga_memory_mem_a;
	output	[2:0]	fpga_memory_mem_ba;
	output	[0:0]	fpga_memory_mem_ck;
	output	[0:0]	fpga_memory_mem_ck_n;
	output	[0:0]	fpga_memory_mem_cke;
	output	[0:0]	fpga_memory_mem_cs_n;
	output	[3:0]	fpga_memory_mem_dm;
	output	[0:0]	fpga_memory_mem_ras_n;
	output	[0:0]	fpga_memory_mem_cas_n;
	output	[0:0]	fpga_memory_mem_we_n;
	output		fpga_memory_mem_reset_n;
	inout	[31:0]	fpga_memory_mem_dq;
	inout	[3:0]	fpga_memory_mem_dqs;
	inout	[3:0]	fpga_memory_mem_dqs_n;
	output	[0:0]	fpga_memory_mem_odt;
	input		fpga_memory_oct_rzqin;
	output		fpga_sdram_status_local_init_done;
	output		fpga_sdram_status_local_cal_success;
	output		fpga_sdram_status_local_cal_fail;
	output	[14:0]	memory_mem_a;
	output	[2:0]	memory_mem_ba;
	output		memory_mem_ck;
	output		memory_mem_ck_n;
	output		memory_mem_cke;
	output		memory_mem_cs_n;
	output		memory_mem_ras_n;
	output		memory_mem_cas_n;
	output		memory_mem_we_n;
	output		memory_mem_reset_n;
	inout	[39:0]	memory_mem_dq;
	inout	[4:0]	memory_mem_dqs;
	inout	[4:0]	memory_mem_dqs_n;
	output		memory_mem_odt;
	output	[4:0]	memory_mem_dm;
	input		memory_oct_rzqin;
	output		peripheral_hps_io_emac0_inst_TX_CLK;
	output		peripheral_hps_io_emac0_inst_TXD0;
	output		peripheral_hps_io_emac0_inst_TXD1;
	output		peripheral_hps_io_emac0_inst_TXD2;
	output		peripheral_hps_io_emac0_inst_TXD3;
	input		peripheral_hps_io_emac0_inst_RXD0;
	inout		peripheral_hps_io_emac0_inst_MDIO;
	output		peripheral_hps_io_emac0_inst_MDC;
	input		peripheral_hps_io_emac0_inst_RX_CTL;
	output		peripheral_hps_io_emac0_inst_TX_CTL;
	input		peripheral_hps_io_emac0_inst_RX_CLK;
	input		peripheral_hps_io_emac0_inst_RXD1;
	input		peripheral_hps_io_emac0_inst_RXD2;
	input		peripheral_hps_io_emac0_inst_RXD3;
	inout		peripheral_hps_io_sdio_inst_CMD;
	inout		peripheral_hps_io_sdio_inst_D0;
	inout		peripheral_hps_io_sdio_inst_D1;
	output		peripheral_hps_io_sdio_inst_CLK;
	inout		peripheral_hps_io_sdio_inst_D2;
	inout		peripheral_hps_io_sdio_inst_D3;
	input		peripheral_hps_io_uart0_inst_RX;
	output		peripheral_hps_io_uart0_inst_TX;
	inout		peripheral_hps_io_i2c0_inst_SDA;
	inout		peripheral_hps_io_i2c0_inst_SCL;
	inout		peripheral_hps_io_gpio_inst_GPIO41;
	inout		peripheral_hps_io_gpio_inst_GPIO42;
	inout		peripheral_hps_io_gpio_inst_GPIO43;
	inout		peripheral_hps_io_gpio_inst_GPIO44;
endmodule
