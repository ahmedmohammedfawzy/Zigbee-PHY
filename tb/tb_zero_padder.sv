// =============================================================================
// tb_zero_padder.sv
// Self-contained testbench for zero_padder.sv
//
// Verification strategy:
//   compute_expected() mirrors the MATLAB formula independently:
//     pad_bits  = n - mod(12 + payload_length*8, n)    [n=6 or 24]
//     total_bits = 12 + payload_length*8 + pad_bits
// =============================================================================

`timescale 1ns/1ps

module tb_zero_padder;

  // -------------------------------------------------------------------------
  // DUT ports
  // -------------------------------------------------------------------------
  logic        rate;
  logic [7:0]  payload_length;
  logic [4:0]  pad_bits;
  logic [10:0] total_bits;

  // -------------------------------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------------------------------
  zero_padder dut (
    .rate           (rate),
    .payload_length (payload_length),
    .pad_bits       (pad_bits),
    .total_bits     (total_bits)
  );

  // -------------------------------------------------------------------------
  // Pass / fail counters
  // -------------------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;

  // -------------------------------------------------------------------------
  // compute_expected
  //   Uses pure integer arithmetic to compute the expected padding
  //   then compare with hardware output
  // -------------------------------------------------------------------------
  task automatic compute_expected (
    input  logic        r,
    input  logic [7:0]  plen,
    output logic [4:0]  exp_pad,
    output logic [10:0] exp_total
  );
    int n, base, rem;
    begin
      n         = r ? 24 : 6;
      base      = 12 + int'(plen) * 8;
      rem       = base % n;
      exp_pad   = 5'(n - rem);
      exp_total = 11'(base + (n - rem));
    end
  endtask

  // -------------------------------------------------------------------------
  // check
  //   Applies one input combination, waits for combinational settle,
  //   computes the expected values, compares, and reports.
  // -------------------------------------------------------------------------
  task automatic check (
    input logic       r,
    input logic [7:0] plen,
    input string      label
  );
    logic [4:0]  exp_pad;
    logic [10:0] exp_total;
    begin
      rate           = r;
      payload_length = plen;
      #10; // combinational settle time

      compute_expected(r, plen, exp_pad, exp_total);

      if (pad_bits === exp_pad && total_bits === exp_total) begin
        $display("  PASS | %-30s | rate=%0d pay=%3d | pad=%2d  total=%4d",
                  label, r, plen, pad_bits, total_bits);
        pass_count++;
      end else begin
        $display("  FAIL | %-30s | rate=%0d pay=%3d | Got pad=%2d total=%4d | Exp pad=%2d total=%4d",
                  label, r, plen, pad_bits, total_bits, exp_pad, exp_total);
        fail_count++;
      end
    end
  endtask

  // -------------------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------------------
  initial begin
    $display("");
    $display("================================================================");
    $display("  tb_zero_padder — Zero Padder Testbench");
    $display("================================================================");

    // -----------------------------------------------------------------------
    // Group 1: 1 Mb/s (rate=0, n=6)
    //   Only 3 distinct pad values exist (period-3 cycle):
    //     pay=1 → base=20,  rem=2 → pad=4
    //     pay=2 → base=28,  rem=4 → pad=2
    //     pay=3 → base=36,  rem=0 → pad=6  ← already aligned, still adds n
    // -----------------------------------------------------------------------
    $display("\n--- 1 Mb/s (rate=0, n=6) : all three padding values ---");
    check(0,   1, "pay=1   rem=2 pad=4      ");
    check(0,   2, "pay=2   rem=4 pad=2      ");
    check(0,   3, "pay=3   rem=0 pad=6 ALIGN"); // ← critical: never outputs 0

    $display("\n--- 1 Mb/s : HDL spec test cases ---");
    check(0,  20, "pay=20  TC1 from spec    ");
    check(0,  55, "pay=55  TC2 from spec    ");
    check(0, 100, "pay=100 TC3 from spec    ");
    check(0, 127, "pay=127 TC4 max payload  ");

    // -----------------------------------------------------------------------
    // Group 2: 250 kb/s (rate=1, n=24)
    //   3 distinct pad values (period-3 cycle):
    //     pay=1 → base=20,  rem=20 → pad=4
    //     pay=2 → base=28,  rem=4  → pad=20
    //     pay=3 → base=36,  rem=12 → pad=12
    // -----------------------------------------------------------------------
    $display("\n--- 250 kb/s (rate=1, n=24) : all three padding values ---");
    check(1,   1, "pay=1   rem=20 pad=4     ");
    check(1,   2, "pay=2   rem=4  pad=20    ");
    check(1,   3, "pay=3   rem=12 pad=12    ");

    $display("\n--- 250 kb/s : spec test cases ---");
    check(1,  25, "pay=25  spec default     ");
    check(1, 127, "pay=127 max payload      ");

    // -----------------------------------------------------------------------
    // Group 3: Edge cases
    // -----------------------------------------------------------------------
    $display("\n--- Edge cases ---");
    // pay=0: base=12
    //   1M:   12 % 6  = 0 → pad=6  (already aligned, full block appended)
    //   250k: 12 % 24 = 12 → pad=12
    check(0,   0, "pay=0 1M   base=12 pad=6 ");
    check(1,   0, "pay=0 250k base=12 pad=12");

    // Maximum 8-bit payload (out of spec but RTL must not break)
    check(0, 255, "pay=255 1M   out of spec ");
    check(1, 255, "pay=255 250k out of spec ");

    // -----------------------------------------------------------------------
    // Group 4: Exhaustive sweep — all 128 in-spec payload lengths, both rates
    //   Covers every possible input within the IEEE 802.15.4a CSS spec.
    //   Since compute_expected is independent of the RTL, any deviation
    //   from the MATLAB formula will show up here.
    // -----------------------------------------------------------------------
    $display("\n--- Exhaustive sweep: pay=0..127 x rate=0,1 ---");
    for (int plen = 0; plen <= 127; plen++) begin
      check(1'b0, 8'(plen), "sweep 1M  ");
      check(1'b1, 8'(plen), "sweep 250k");
    end

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("");
    $display("================================================================");
    $display("  RESULT :  %0d PASS    %0d FAIL    (total %0d)",
              pass_count, fail_count, pass_count + fail_count);
    $display("================================================================");

    if (fail_count == 0) begin
      $display("  ALL TESTS PASSED");
      $finish;
    end else begin
      $fatal(1, "  %0d TEST(S) FAILED — check output above", fail_count);
    end
  end

endmodule
