// ============================================================================
//  sram_sp  --  generic single-port wrapper over the Sky130 OpenRAM macro
//               sky130_sram_1kbyte_1rw1r_32x256_8  (256 words x 32 bits).
//
//  Use this file ONLY for hardening (OpenLane).  Requires AW = 8, DW = 32.
//  The macro's csb0 / web0 are active-low; the read-only port (…1) is tied off.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module sram_sp #(
    parameter AW = 8,
    parameter DW = 32
) (
`ifdef USE_POWER_PINS
    inout  wire            vccd1,
    inout  wire            vssd1,
`endif
    input  wire            clk,
    input  wire            ce,
    input  wire            we,
    input  wire [AW-1:0]   addr,
    input  wire [DW-1:0]   wdata,
    output wire [DW-1:0]   rdata
);

  sky130_sram_1kbyte_1rw1r_32x256_8 u_mem (
`ifdef USE_POWER_PINS
      .vccd1 (vccd1),
      .vssd1 (vssd1),
`endif
      // read/write port
      .clk0  (clk),
      .csb0  (~ce),          // active-low select
      .web0  (~we),          // active-low write
      .wmask0(4'b1111),      // all four byte lanes
      .addr0 (addr),
      .din0  (wdata),
      .dout0 (rdata),
      // read-only port -- unused
      .clk1  (clk),
      .csb1  (1'b1),
      .addr1 ({AW{1'b0}}),
      .dout1 ()
  );

endmodule

`default_nettype wire
