// ============================================================================
//  mbist_march_ctrl  --  March C- Memory Built-In Self-Test controller
// ----------------------------------------------------------------------------
//  Drives a single-port synchronous SRAM through the March C- algorithm
//  (10N complexity, detects SAF, TF, AF and unlinked CF):
//
//    element 0 :  (w0)        any order        -- init all cells to 0
//    element 1 :  (r0, w1)    ascending
//    element 2 :  (r1, w0)    ascending
//    element 3 :  (r0, w1)    descending
//    element 4 :  (r1, w0)    descending
//    element 5 :  (r0)        any order
//
//  Timing model: the memory is synchronous with one-cycle read latency.
//  The controller issues one operation per clock (single-issue) and compares
//  read data one cycle later via a small pipeline register.
//
//  Data backgrounds are solid (all-0 / all-1). Extend f_op_dat() for
//  checkerboard / row-stripe patterns to raise coupling-fault coverage.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module mbist_march_ctrl #(
    parameter int unsigned ADDR_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // ---- control / status -------------------------------------------------
    input  wire                   bist_start,      // 1-cycle pulse; accepted in IDLE/DONE
    output wire                   bist_busy,        // test in progress
    output wire                   bist_done,        // test finished (result valid)
    output reg                    bist_fail,        // sticky: at least one miscompare
    output reg  [ADDR_WIDTH-1:0]  bist_fail_addr,   // address of the FIRST failing word
    output reg  [DATA_WIDTH-1:0]  bist_fail_bits,   // per-bit XOR of first failing word

    // ---- memory interface (to collar) -----------------------------------
    output wire                   mem_ce,           // chip enable  (active high)
    output wire                   mem_we,           // write enable (active high)
    output wire [ADDR_WIDTH-1:0]  mem_addr,
    output wire [DATA_WIDTH-1:0]  mem_wdata,
    input  wire [DATA_WIDTH-1:0]  mem_rdata
);

  // --------------------------------------------------------------------------
  //  Local parameters
  // --------------------------------------------------------------------------
  localparam [ADDR_WIDTH-1:0] ADDR_MIN = {ADDR_WIDTH{1'b0}};
  localparam [ADDR_WIDTH-1:0] ADDR_MAX = {ADDR_WIDTH{1'b1}};

  localparam [1:0] S_IDLE  = 2'd0,
                   S_RUN   = 2'd1,
                   S_DRAIN = 2'd2,   // let the final read's compare land
                   S_DONE  = 2'd3;

  // --------------------------------------------------------------------------
  //  March C- element / operation decode (pure combinational functions)
  // --------------------------------------------------------------------------
  //  o = 0 -> first operation of the element, o = 1 -> second operation.
  function automatic logic f_elem_up(input logic [2:0] e);
    case (e)
      3'd0, 3'd1, 3'd2, 3'd5: f_elem_up = 1'b1;   // ascending / any-order
      3'd3, 3'd4:             f_elem_up = 1'b0;   // descending
      default:                f_elem_up = 1'b1;
    endcase
  endfunction

  function automatic logic [1:0] f_elem_nops(input logic [2:0] e);
    case (e)
      3'd0, 3'd5: f_elem_nops = 2'd1;             // (w0) , (r0)
      default:    f_elem_nops = 2'd2;             // (rX, wY)
    endcase
  endfunction

  // 1 = write, 0 = read
  function automatic logic f_op_wr(input logic [2:0] e, input logic o);
    case (e)
      3'd0:    f_op_wr = 1'b1;                    // w0
      3'd5:    f_op_wr = 1'b0;                    // r0
      default: f_op_wr = (o == 1'b1);             // read then write
    endcase
  endfunction

  // background polarity written / expected by this operation
  function automatic logic f_op_dat(input logic [2:0] e, input logic o);
    case (e)
      3'd0:    f_op_dat = 1'b0;                   // w0
      3'd1:    f_op_dat = (o == 1'b1);            // r0 , w1
      3'd2:    f_op_dat = (o == 1'b0);            // r1 , w0
      3'd3:    f_op_dat = (o == 1'b1);            // r0 , w1
      3'd4:    f_op_dat = (o == 1'b0);            // r1 , w0
      3'd5:    f_op_dat = 1'b0;                   // r0
      default: f_op_dat = 1'b0;
    endcase
  endfunction

  // --------------------------------------------------------------------------
  //  State
  // --------------------------------------------------------------------------
  reg  [1:0]              state;
  reg  [2:0]              elem_idx;      // 0 .. 5
  reg                     op_idx;        // 0 .. 1
  reg  [ADDR_WIDTH-1:0]   addr;

  // read-compare pipeline (address issued in cycle N, data checked in N+1)
  reg                     cmp_valid;
  reg  [DATA_WIDTH-1:0]   cmp_exp;
  reg  [ADDR_WIDTH-1:0]   cmp_addr;

  // --------------------------------------------------------------------------
  //  Current-operation decode
  // --------------------------------------------------------------------------
  wire       cur_up   = f_elem_up  (elem_idx);
  wire [1:0] cur_nops = f_elem_nops(elem_idx);
  wire       cur_wr   = f_op_wr    (elem_idx, op_idx);
  wire       cur_dat  = f_op_dat   (elem_idx, op_idx);

  wire       op_last   = (cur_nops == 2'd1) || (op_idx == 1'b1);
  wire       addr_last = cur_up ? (addr == ADDR_MAX) : (addr == ADDR_MIN);
  wire       elem_done = op_last && addr_last;
  wire       all_done  = (state == S_RUN) && elem_done && (elem_idx == 3'd5);

  wire       accept_start = ((state == S_IDLE) || (state == S_DONE)) && bist_start;

  // --------------------------------------------------------------------------
  //  Sequencer
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      elem_idx  <= 3'd0;
      op_idx    <= 1'b0;
      addr      <= ADDR_MIN;
      cmp_valid <= 1'b0;
      cmp_exp   <= {DATA_WIDTH{1'b0}};
      cmp_addr  <= {ADDR_WIDTH{1'b0}};
    end else begin
      unique case (state)
        // ------------------------------------------------------------------
        S_IDLE: begin
          cmp_valid <= 1'b0;
          if (bist_start) begin
            state    <= S_RUN;
            elem_idx <= 3'd0;
            op_idx   <= 1'b0;
            addr     <= ADDR_MIN;      // element 0 is ascending
          end
        end
        // ------------------------------------------------------------------
        S_RUN: begin
          // schedule this cycle's read for comparison next cycle
          cmp_valid <= ~cur_wr;
          cmp_exp   <= {DATA_WIDTH{cur_dat}};
          cmp_addr  <= addr;

          if (all_done) begin
            state <= S_DRAIN;
          end else if (!op_last) begin
            op_idx <= 1'b1;                       // same address, second op
          end else begin
            op_idx <= 1'b0;
            if (!addr_last) begin
              addr <= cur_up ? (addr + 1'b1) : (addr - 1'b1);
            end else begin
              elem_idx <= elem_idx + 3'd1;
              addr     <= f_elem_up(elem_idx + 3'd1) ? ADDR_MIN : ADDR_MAX;
            end
          end
        end
        // ------------------------------------------------------------------
        S_DRAIN: begin
          cmp_valid <= 1'b0;
          state     <= S_DONE;
        end
        // ------------------------------------------------------------------
        S_DONE: begin
          cmp_valid <= 1'b0;
          if (bist_start) begin
            state    <= S_RUN;
            elem_idx <= 3'd0;
            op_idx   <= 1'b0;
            addr     <= ADDR_MIN;
          end
        end
        // ------------------------------------------------------------------
        default: state <= S_IDLE;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  //  Response analyzer -- capture the FIRST failing word only
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n || accept_start) begin
      bist_fail      <= 1'b0;
      bist_fail_addr <= {ADDR_WIDTH{1'b0}};
      bist_fail_bits <= {DATA_WIDTH{1'b0}};
    end else if (cmp_valid && (mem_rdata != cmp_exp) && !bist_fail) begin
      bist_fail      <= 1'b1;
      bist_fail_addr <= cmp_addr;
      bist_fail_bits <= mem_rdata ^ cmp_exp;
    end
  end

  // --------------------------------------------------------------------------
  //  Outputs
  // --------------------------------------------------------------------------
  assign bist_busy = (state == S_RUN) || (state == S_DRAIN);
  assign bist_done = (state == S_DONE);

  assign mem_ce    = (state == S_RUN);
  assign mem_we    = (state == S_RUN) & cur_wr;
  assign mem_addr  = addr;
  assign mem_wdata = {DATA_WIDTH{cur_dat}};

  // --------------------------------------------------------------------------
  //  Formal properties  (yosys read_verilog -DFORMAL / SymbiYosys)
  // --------------------------------------------------------------------------
`ifdef FORMAL
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // the trace starts in reset so every register holds a defined value
  initial assume (!rst_n);

  always @(posedge clk) if (f_past_valid) begin
    // ---- safety ------------------------------------------------------
    assert (!(bist_busy && bist_done));
    assert ((cur_nops == 2'd1) || (cur_nops == 2'd2));
    assert (elem_idx <= 3'd5);
    if (state == S_RUN) assert (mem_ce);
    if (bist_done)      assert (!mem_ce);

    // ---- a detected failure is sticky until restart or reset -------
    if ($past(rst_n) && rst_n && $past(bist_fail) && !$past(accept_start))
      assert (bist_fail);
  end

  // ---- reachability -------------------------------------------------
  always @(posedge clk) begin
    cover (f_past_valid && bist_done);
    cover (f_past_valid && bist_done && !bist_fail);
    cover (f_past_valid && bist_done &&  bist_fail);
  end
`endif

endmodule

`default_nettype wire
