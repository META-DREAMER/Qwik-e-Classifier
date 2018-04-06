module global_routing
(
   input s,
   input clk,
   output g
);

`ifdef MODEL_TECH
  // Simulation only - modelsim
  assign g = s;
`else
  GLOBAL cal_clk_gbuf (.in(s), .out(g));
`endif

endmodule
