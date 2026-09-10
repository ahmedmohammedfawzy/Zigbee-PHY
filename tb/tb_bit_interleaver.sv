// =============================================================================
// tb_bit_interleaver.sv
// Self-contained testbench for bit_interleaver.sv
//
// Verification strategy:
//   compute_expected() independently reconstructs the 64-bit permutation
//   from the IEEE 802.15.4 spec's mapping table (transcribed directly from
//   the standard, not copied from bit_interleaver.sv's own comments), so a
//   bug in the RTL's permutation table will not silently match a bug here.
// =============================================================================

`timescale 1ns/1ps

module tb_bit_interleaver;

  // -------------------------------------------------------------------------
  // DUT ports
  // -------------------------------------------------------------------------
  logic [63:0] in_bits;
  logic [63:0] out_bits;

  bit_interleaver dut (
    .in_bits (in_bits),
    .out_bits(out_bits)
  );

  int pass_count = 0;
  int fail_count = 0;

  // -------------------------------------------------------------------------
  // Independent permutation table (verilog-index convention: bit 63 = first
  // transmitted bit). out_bits[v] = in_bits[map[v]].
  // -------------------------------------------------------------------------
  function automatic logic [5:0] map_idx(input int v);
    case (v)
      63: return 63; 62: return 62; 61: return 61; 60: return 60;
      59: return 11; 58: return 10; 57: return 9;  56: return 8;
      55: return 55; 54: return 54; 53: return 53; 52: return 52;
      51: return 3;  50: return 2;  49: return 1;  48: return 0;
      47: return 47; 46: return 46; 45: return 45; 44: return 44;
      43: return 27; 42: return 26; 41: return 25; 40: return 24;
      39: return 39; 38: return 38; 37: return 37; 36: return 36;
      35: return 19; 34: return 18; 33: return 17; 32: return 16;
      31: return 31; 30: return 30; 29: return 29; 28: return 28;
      27: return 43; 26: return 42; 25: return 41; 24: return 40;
      23: return 23; 22: return 22; 21: return 21; 20: return 20;
      19: return 35; 18: return 34; 17: return 33; 16: return 32;
      15: return 15; 14: return 14; 13: return 13; 12: return 12;
      11: return 59; 10: return 58; 9:  return 57; 8:  return 56;
      7:  return 7;  6:  return 6;  5:  return 5;  4:  return 4;
      3:  return 51; 2:  return 50; 1:  return 49; 0:  return 48;
      default: return v;
    endcase
  endfunction

  function automatic logic [63:0] compute_expected(input logic [63:0] x);
    logic [63:0] y;
    begin
      for (int v = 0; v < 64; v++)
        y[v] = x[map_idx(v)];
      return y;
    end
  endfunction

  // -------------------------------------------------------------------------
  // check
  // -------------------------------------------------------------------------
  task automatic check(input logic [63:0] pattern, input string label);
    logic [63:0] exp;
    begin
      in_bits = pattern;
      #10;
      exp = compute_expected(pattern);
      if (out_bits === exp) begin
        $display("  PASS | %-28s | in=%h out=%h", label, pattern, out_bits);
        pass_count++;
      end else begin
        $display("  FAIL | %-28s | in=%h  RTL=%h  EXP=%h  DIFF=%h",
                   label, pattern, out_bits, exp, out_bits ^ exp);
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
    $display("  tb_bit_interleaver — Bit Interleaver Testbench");
    $display("================================================================");

    $display("\n--- Structural patterns ---");
    check(64'h0000_0000_0000_0000, "all zeros");
    check(64'hFFFF_FFFF_FFFF_FFFF, "all ones");
    check(64'hAAAA_AAAA_AAAA_AAAA, "alternating A");
    check(64'h5555_5555_5555_5555, "alternating 5");
    check(64'hFFFF_FFFF_0000_0000, "high half ones");
    check(64'h0000_0000_FFFF_FFFF, "low half ones");

    $display("\n--- Single-bit impulses (confirms permutation table entry-by-entry) ---");
    for (int b = 0; b < 64; b++) begin
      check(64'h1 << b, $sformatf("single bit %0d", b));
    end

    $display("\n--- Walking two-symbol pattern (mimics real A/B codeword usage) ---");
    check({32'hFFFF_FFFF, 32'h0000_0000}, "A=zeros B=ones");
    check({32'h0000_0000, 32'hFFFF_FFFF}, "A=ones  B=zeros");
    check({32'hAAAA_AAAA, 32'h5555_5555}, "A=5555  B=AAAA");

    $display("\n--- Random patterns ---");
    for (int i = 0; i < 20; i++) begin
      logic [63:0] r;
      r = {$random, $random};
      check(r, $sformatf("random %0d", i));
    end

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