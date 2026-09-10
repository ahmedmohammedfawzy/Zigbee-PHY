// =============================================================================
// tb_dqpsk_encoder.sv
// Self-contained testbench for dqpsk_encoder.sv
//
// Verification strategy:
//   A software reference model independently implements the same 4-tap
//   circular accumulator: S[n] = (S[n-4] + delta[n]) mod 4, with all 4
//   taps initialized to 0 on reset/init_packet. Since out_valid/out_phase
//   are COMBINATIONAL (they reflect the DUT's *current* tap before the
//   clock edge that advances it), the reference model's "peek" is checked
//   BEFORE the clock edge, and its own state is advanced only after the
//   check — mirroring exactly when a real downstream consumer would latch
//   the value.
// =============================================================================

`timescale 1ns/1ps

module tb_dqpsk_encoder;

  logic clk = 0;
  logic reset;
  logic init_packet;
  logic in_valid;
  logic downstream_ready;
  logic [1:0] in_phase;
  logic out_valid;
  logic [1:0] out_phase;

  always #5 clk = ~clk;

  dqpsk_encoder dut (
    .clk(clk), .reset(reset), .init_packet(init_packet),
    .in_valid(in_valid), .downstream_ready(downstream_ready),
    .in_phase(in_phase),
    .out_valid(out_valid), .out_phase(out_phase)
  );

  int pass_count = 0;
  int fail_count = 0;

  // ---------------------------------------------------------------------------
  // Reference model: peek (read-only) vs advance (writes state), kept separate
  // so we can check against the DUT's pre-edge combinational output.
  // ---------------------------------------------------------------------------
  logic [1:0] ref_fb [0:3];
  logic [1:0] ref_tap;

  task automatic ref_init;
    begin
      ref_tap = 2'd0;
      for (int k = 0; k < 4; k++) ref_fb[k] = 2'd0;
    end
  endtask

  function automatic logic [1:0] ref_peek(input logic [1:0] delta);
    return ref_fb[ref_tap] + delta;
  endfunction

  task automatic ref_advance(input logic [1:0] delta);
    begin
      ref_fb[ref_tap] = ref_fb[ref_tap] + delta;
      ref_tap = ref_tap + 2'd1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drive one symbol: sample the DUT's combinational output BEFORE the clock
  // edge that advances its internal registers.
  // ---------------------------------------------------------------------------
  task automatic send_symbol(
    input logic [1:0] delta,
    input int stall_cycles,
    input string label
  );
    logic [1:0] exp;
    begin
      downstream_ready = 1'b0;
      in_phase = delta;
      in_valid = 1'b1;

      repeat (stall_cycles) begin
        @(posedge clk);
        #1;
        if (out_valid !== 1'b0) begin
          $display("  FAIL | %-20s | out_valid asserted during stall!", label);
          fail_count++;
        end
      end

      downstream_ready = 1'b1;
      #1; // let out_valid/out_phase settle combinationally, BEFORE the clock edge
      exp = ref_peek(delta);

      if (out_valid === 1'b1 && out_phase === exp) begin
        $display("  PASS | %-20s | delta=%0d -> out_phase=%0d", label, delta, out_phase);
        pass_count++;
      end else begin
        $display("  FAIL | %-20s | delta=%0d | RTL valid=%0b phase=%0d | EXP valid=1 phase=%0d",
                   label, delta, out_valid, out_phase, exp);
        fail_count++;
      end

      ref_advance(delta);   // now advance the reference model's state
      @(posedge clk);       // now let the DUT's registers actually update
      in_valid = 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic do_reset;
    begin
      reset = 1'b1; init_packet = 1'b0; in_valid = 1'b0; downstream_ready = 1'b0; in_phase = 2'd0;
      repeat (2) @(posedge clk);
      reset = 1'b0;
      ref_init();
      @(posedge clk);
    end
  endtask

  task automatic do_init_packet;
    begin
      init_packet = 1'b1;
      @(posedge clk);
      init_packet = 1'b0;
      ref_init();
    end
  endtask

  initial begin
    $display("");
    $display("================================================================");
    $display("  tb_dqpsk_encoder — DQPSK Encoder Testbench");
    $display("================================================================");

    // -------------------------------------------------------------------------
    // Group 1: reset initializes all 4 taps to 0 -> first 4 outputs equal delta
    // -------------------------------------------------------------------------
    $display("\n--- First 4 symbols after reset (taps still at init value 0) ---");
    do_reset();
    send_symbol(2'd0, 0, "sym0 delta=0");
    send_symbol(2'd1, 0, "sym1 delta=1");
    send_symbol(2'd2, 0, "sym2 delta=2");
    send_symbol(2'd3, 0, "sym3 delta=3");

    // -------------------------------------------------------------------------
    // Group 2: 5th symbol wraps back to tap 0, must add to sym0's stored result
    // -------------------------------------------------------------------------
    $display("\n--- Wraparound: symbols 5-8 feed back through taps 0-3 ---");
    send_symbol(2'd1, 0, "sym4 delta=1 (tap0)");
    send_symbol(2'd2, 0, "sym5 delta=2 (tap1)");
    send_symbol(2'd3, 0, "sym6 delta=3 (tap2)");
    send_symbol(2'd0, 0, "sym7 delta=0 (tap3)");

    // -------------------------------------------------------------------------
    // Group 3: long random sequence, no stalls
    // -------------------------------------------------------------------------
    $display("\n--- Long random sequence (40 symbols, no stalls) ---");
    do_reset();
    for (int i = 0; i < 40; i++) begin
      send_symbol(2'($urandom_range(0,3)), 0, $sformatf("rand sym %0d", i));
    end

    // -------------------------------------------------------------------------
    // Group 4: mid-packet init_packet reset (as tx_top asserts at controller_start)
    // -------------------------------------------------------------------------
    $display("\n--- Mid-stream init_packet re-initializes taps ---");
    send_symbol(2'd2, 0, "pre-init sym");
    do_init_packet();
    send_symbol(2'd1, 0, "post-init sym0 (should behave like fresh reset)");
    send_symbol(2'd3, 0, "post-init sym1");

    // -------------------------------------------------------------------------
    // Group 5: downstream_ready stalls (out_valid must stay low while stalled)
    // -------------------------------------------------------------------------
    $display("\n--- Handshake: downstream_ready stalls ---");
    do_reset();
    send_symbol(2'd0, 3, "stalled 3 cycles then accepted");
    send_symbol(2'd2, 0, "immediately accepted");

    // -------------------------------------------------------------------------
    // Group 6: full random sequence with random stalls
    // -------------------------------------------------------------------------
    $display("\n--- Random sequence with random stalls (30 symbols) ---");
    do_reset();
    for (int i = 0; i < 30; i++) begin
      send_symbol(2'($urandom_range(0,3)), $urandom_range(0,3), $sformatf("rand-stall sym %0d", i));
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