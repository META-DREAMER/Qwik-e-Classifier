`define NUM_EFIS 1
`define MAX_WIDTH 64
 
`timescale 1ns / 1ps 
 
import avalon_mm_pkg::*; 
import verbosity_pkg::*; 
// Number of sinks and sources of the EFI component 
//   Assume 1 output (SRC) per EFI, but also for now, assume 1 SNK per EFI 
//   which is the bit vector comprising all arguments to the function. 
`define NUM_SNKS `NUM_EFIS 
`define NUM_SRCS `NUM_EFIS 
 
 
module efi_testbench; 
 
    localparam MAX_WIDTH=`MAX_WIDTH; 
    localparam NUM_SNKS=`NUM_SNKS; 
    localparam NUM_SRCS=`NUM_SRCS; 
 
    // ******** 
    // DPI functions and tasks used to communicate to DPI layer 
    import "DPI-C" context task dpi_init( input int num_efis, input int max_width, input int debug); 
    import "DPI-C" context task dpi_update(); 
    import "DPI-C" context task dpi_close(); 
    import "DPI-C" context task dpi_efi_return(input bit [31:0] id, input bit [MAX_WIDTH-1:0] data); 
 
    export "DPI-C" task dpi_efi_call; 
    // ******** 
 
    reg clk; 
    reg reset_n; 
 
    integer i; 
 
    // Sink Streams - these signals will feed the input arguments of the EFI 
    logic [NUM_SNKS-1:0] snk_valid; 
    logic [MAX_WIDTH-1:0] snk_data[NUM_SNKS]; 
    logic [NUM_SNKS-1:0] snk_ready; 
 
    // Source Streams - these signals will receive the result from the EFI 
    logic [NUM_SRCS-1:0] src_valid; 
    logic [MAX_WIDTH-1:0] src_data[NUM_SRCS]; 
    logic [NUM_SRCS-1:0] src_ready; 
 
    // How verbose do you want your debug output? 
    initial 
    begin 
        `ifdef DEBUG_VERBOSITY 
            //set_verbosity( VERBOSITY_DEBUG ); 
            set_verbosity( VERBOSITY_INFO ); 
        `else 
            set_verbosity( VERBOSITY_WARNING ); 
        `endif 
    end 
 
    initial 
    begin 
        reset_n = 1'b0; 
        #200 reset_n = 1'b1; 
        #50; 
        dpi_init(NUM_SRCS, MAX_WIDTH, (get_verbosity() >= VERBOSITY_INFO)); 
        forever begin 
          dpi_update(); 
          @(posedge clk); 
        end 
    end 
 
    final 
    begin 
      // dpi_close(); // DPI call in final block is illegal 
    end 
 
    // Kernel clk (200 MHz) 
    initial 
        clk = 1'b1; 
    always 
        #2.5 clk <= ~clk; 
 
   genvar s; 
   generate 
   for ( s=0; s<NUM_SNKS; s=s+1) 
   begin : src_bfm 
     altera_avalon_st_source_bfm #( 
       .ST_SYMBOL_W(1), 
       .ST_NUMSYMBOLS(MAX_WIDTH) 
     ) st_source ( 
       .clk(clk), 
       .reset(!resetn), 
       .src_data(snk_data[s]), 
       .src_channel(), 
       .src_valid(snk_valid[s]), 
       .src_startofpacket(), 
       .src_endofpacket(), 
       .src_error(), 
       .src_empty(), 
       .src_ready(snk_ready[s]) 
     ); 
   end 
   endgenerate 
 
   generate 
   for ( s=0; s<NUM_SRCS; s=s+1) 
   begin : snk_bfm 
     altera_avalon_st_sink_bfm #( 
       .ST_SYMBOL_W(1), 
       .ST_NUMSYMBOLS(MAX_WIDTH) 
     ) st_sink ( 
       .clk(clk), 
       .reset(!resetn), 
       .sink_data(src_data[s]), 
       .sink_channel(), 
       .sink_valid(src_valid[s]), 
       .sink_startofpacket(), 
       .sink_endofpacket(), 
       .sink_error(), 
       .sink_empty(), 
       .sink_ready(src_ready[s])); 
 
    // Process return data from each efi function 
    always@(posedge clk) 
    begin 
      if (snk_bfm[s].st_sink.get_transaction_queue_size() > 0) 
      begin 
        logic [MAX_WIDTH-1:0] return_val; 
 
        snk_bfm[s].st_sink.pop_transaction(); 
        return_val = snk_bfm[s].st_sink.get_transaction_data(); 
        if(get_verbosity() >= VERBOSITY_INFO) 
          $display( "%0d: Received from channel %2d value = 0x%h", $time, s, return_val); 
        dpi_efi_return( s, return_val ); 
      end 
    end 
    // Currently never stall efi hardware 
    initial 
    begin 
      snk_bfm[s].st_sink.init(); 
      snk_bfm[s].st_sink.set_ready(1'b1); 
    end 
 
   end 
   endgenerate 
 
 
    // TASK dpi_efi_call 
    task dpi_efi_call; 
        input bit [31:0] id; 
        input bit [MAX_WIDTH-1:0] data; 
 
        if(get_verbosity() >= VERBOSITY_INFO) 
            $display( "%0d: Writing to channel %2d with value = 0x%h", $time, id, data ); 
 
        case (id) 
          'hdeadbeef : begin 
            dpi_close(); 
            $finish; 
          end 
          0 : channel_write_src0(data); 
 
          default : begin 
            $display ("%0d: Invalid call id called: %d",$time,id); 
            dpi_close(); 
            $finish; 
          end 
        endcase 
    endtask

    task channel_write_src0;
        input [MAX_WIDTH-1:0] data; 
        src_bfm[0].st_source.set_transaction_data(data); 
        src_bfm[0].st_source.push_transaction(); 
 
        // Wait for a response 
        fork : get_response_block 
        begin 
          while(src_bfm[0].st_source.get_response_queue_size() == 0) 
            @(posedge clk); 
        end 
        begin 
          repeat (100) @(posedge clk); 
          print(VERBOSITY_ERROR, "No response received"); 
          $stop; 
        end 
        join_any : get_response_block 
        disable fork; 
 
        // Get the response and return it 
        src_bfm[0].st_source.pop_response(); 
    endtask
//Instantiates module efi_mac_0_mult_add_fix8bx4_mult_add_fix8bx4 with id 0
mult_add_fix8bx4 mult_add_fix8bx40 ( 
  .clock ( clk ),
  .resetn ( reset_n ),
  .iready ( src_ready[0] ),
  .dataa_0 ( snk_data[0][7:0] ),
  .datab_0 ( snk_data[0][15:8] ),
  .dataa_1 ( snk_data[0][23:16] ),
  .datab_1 ( snk_data[0][31:24] ),
  .dataa_2 ( snk_data[0][39:32] ),
  .datab_2 ( snk_data[0][47:40] ),
  .dataa_3 ( snk_data[0][55:48] ),
  .datab_3 ( snk_data[0][63:56] ),
  .ivalid ( snk_valid[0] ),
  .ovalid ( src_valid[0] ),
  .result ( src_data[0] ),
  .oready ( snk_ready[0] )
);
endmodule
