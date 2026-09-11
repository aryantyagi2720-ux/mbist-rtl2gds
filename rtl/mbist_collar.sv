// ============================================================================
//  mbist_collar  --  test wrapper that multiplexes the SRAM ports between
//                    the functional (mission-mode) path and the BIST path.
//
//  sel = 1 : the SRAM is owned by the MBIST controller
//  sel = 0 : the SRAM is driven by the functional interface
//
//  Read data is fanned out to both consumers; each ignores it when not
//  selected.  Purely combinational -- it adds one 2:1 mux delay in front of
//  the memory, which STA sees as an ordinary register-to-macro path.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module mbist_collar #(
    parameter int unsigned ADDR_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  wire                   sel,

    // ---- functional side ------------------------------------------------
    input  wire                   f_ce,
    input  wire                   f_we,
    input  wire [ADDR_WIDTH-1:0]  f_addr,
    input  wire [DATA_WIDTH-1:0]  f_wdata,
    output wire [DATA_WIDTH-1:0]  f_rdata,

    // ---- BIST side ----------------------------------------------------
    input  wire                   b_ce,
    input  wire                   b_we,
    input  wire [ADDR_WIDTH-1:0]  b_addr,
    input  wire [DATA_WIDTH-1:0]  b_wdata,
    output wire [DATA_WIDTH-1:0]  b_rdata,

    // ---- SRAM side ----------------------------------------------------
    output wire                   s_ce,
    output wire                   s_we,
    output wire [ADDR_WIDTH-1:0]  s_addr,
    output wire [DATA_WIDTH-1:0]  s_wdata,
    input  wire [DATA_WIDTH-1:0]  s_rdata
);

  assign s_ce    = sel ? b_ce    : f_ce;
  assign s_we    = sel ? b_we    : f_we;
  assign s_addr  = sel ? b_addr  : f_addr;
  assign s_wdata = sel ? b_wdata : f_wdata;

  assign f_rdata = s_rdata;
  assign b_rdata = s_rdata;

endmodule

`default_nettype wire
