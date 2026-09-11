// ============================================================================
//  sram_sp  --  black-box stub for synthesis / elaboration checks.
//  The real timing/area comes from the macro .lib during hardening.
// ============================================================================
`default_nettype none

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
(* blackbox *)
module sram_sp #(
    parameter AW = 8,
    parameter DW = 32
) (
    input  wire            clk,
    input  wire            ce,
    input  wire            we,
    input  wire [AW-1:0]   addr,
    input  wire [DW-1:0]   wdata,
    output wire [DW-1:0]   rdata
);
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */

`default_nettype wire
