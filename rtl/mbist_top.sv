// ============================================================================
//  mbist_top  --  SRAM + March C- MBIST controller + test collar
//
//  This is the hardened macro.  For simulation/formal the `sram_sp` instance
//  resolves to the behavioural model in tb/;  for synthesis it resolves to
//  rtl/sram_sp_blackbox.v;  for hardening it resolves to rtl/sram_sp_sky130.sv
//  (a thin wrapper over the Sky130 OpenRAM macro).  Exactly one of those
//  files is compiled per flow -- never glob rtl/*.sv.
//
//  The collar select is  (bist_mode | bist_busy)  so the functional path can
//  never reach the memory while a test is running, even if the SoC forgets to
//  raise bist_mode.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module mbist_top #(
    parameter int unsigned ADDR_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 32
) (
`ifdef USE_POWER_PINS
    inout  wire                   VPWR,
    inout  wire                   VGND,
`endif
    input  wire                   clk,
    input  wire                   rst_n,

    // ---- functional memory port (from the SoC) -------------------------
    input  wire                   func_ce,
    input  wire                   func_we,
    input  wire [ADDR_WIDTH-1:0]  func_addr,
    input  wire [DATA_WIDTH-1:0]  func_wdata,
    output wire [DATA_WIDTH-1:0]  func_rdata,

    // ---- BIST control / status ---------------------------------------
    input  wire                   bist_start,       // 1-cycle pulse
    input  wire                   bist_mode,        // hold high around the test window
    output wire                   bist_busy,
    output wire                   bist_done,
    output wire                   bist_fail,
    output wire [ADDR_WIDTH-1:0]  bist_fail_addr,
    output wire [DATA_WIDTH-1:0]  bist_fail_bits
);

  // ---- controller <-> collar ------------------------------------------
  wire                    b_ce, b_we;
  wire [ADDR_WIDTH-1:0]   b_addr;
  wire [DATA_WIDTH-1:0]   b_wdata, b_rdata;

  // ---- collar <-> sram ----------------------------------------------
  wire                    s_ce, s_we;
  wire [ADDR_WIDTH-1:0]   s_addr;
  wire [DATA_WIDTH-1:0]   s_wdata, s_rdata;

  wire                    collar_sel = bist_mode | bist_busy;

  // --------------------------------------------------------------------
  mbist_march_ctrl #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) u_ctrl (
      .clk            (clk),
      .rst_n          (rst_n),
      .bist_start     (bist_start),
      .bist_busy      (bist_busy),
      .bist_done      (bist_done),
      .bist_fail      (bist_fail),
      .bist_fail_addr (bist_fail_addr),
      .bist_fail_bits (bist_fail_bits),
      .mem_ce         (b_ce),
      .mem_we         (b_we),
      .mem_addr       (b_addr),
      .mem_wdata      (b_wdata),
      .mem_rdata      (b_rdata)
  );

  mbist_collar #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) u_collar (
      .sel     (collar_sel),
      .f_ce    (func_ce),
      .f_we    (func_we),
      .f_addr  (func_addr),
      .f_wdata (func_wdata),
      .f_rdata (func_rdata),
      .b_ce    (b_ce),
      .b_we    (b_we),
      .b_addr  (b_addr),
      .b_wdata (b_wdata),
      .b_rdata (b_rdata),
      .s_ce    (s_ce),
      .s_we    (s_we),
      .s_addr  (s_addr),
      .s_wdata (s_wdata),
      .s_rdata (s_rdata)
  );

  sram_sp #(
      .AW (ADDR_WIDTH),
      .DW (DATA_WIDTH)
  ) u_sram (
`ifdef USE_POWER_PINS
      .vccd1 (VPWR),
      .vssd1 (VGND),
`endif
      .clk   (clk),
      .ce    (s_ce),
      .we    (s_we),
      .addr  (s_addr),
      .wdata (s_wdata),
      .rdata (s_rdata)
  );

endmodule

`default_nettype wire
