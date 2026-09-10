// =============================================================================
// tb_tx_top.sv
// Self-checking full-chain testbench for tx_top.sv
//
// Strategy:
//   1. Load a payload into payload_ram, pulse start_Tx.
//   2. Capture every genuine Tx_real/Tx_imag sample using a hierarchical
//      probe on csk_modulator.active, delayed one cycle to align with when
//      sample_real/sample_imag actually hold the freshly-computed value.
//   3. Compare against a golden reference exported by css_verify_golden.m
//      (or its Python port) as a CSV file: two columns, real,imag, no header.
// =============================================================================
`timescale 1ns/1ps

module tb_tx_top;

  parameter int CHIRP_INDEX = 1;
  parameter int CLK_PERIOD  = 10;

  logic clk = 0;
  logic reset;
  logic start_Tx;
  logic rate;
  logic [7:0] payload_length;
  logic payload_wr_en;
  logic [6:0] payload_addr;
  logic [7:0] payload_din;
  logic done_Tx;
  logic signed [7:0] Tx_real, Tx_imag;

  always #(CLK_PERIOD/2) clk = ~clk;

  tx_top #(.CHIRP_INDEX(CHIRP_INDEX), .SAMPLE_DIV(1)) dut (
    .clk(clk), .reset(reset), .start_Tx(start_Tx), .rate(rate),
    .payload_length(payload_length),
    .payload_wr_en(payload_wr_en), .payload_addr(payload_addr), .payload_din(payload_din),
    .done_Tx(done_Tx), .Tx_real(Tx_real), .Tx_imag(Tx_imag)
  );

  // ---------------------------------------------------------------------------
  // Sample capture
  // ---------------------------------------------------------------------------
  logic valid_this_cycle;
  logic signed [7:0] cap_real_q[$];
  logic signed [7:0] cap_imag_q[$];

  always_ff @(posedge clk) begin
    if (reset)
      valid_this_cycle <= 1'b0;
    else
      valid_this_cycle <= dut.csk_modulator.active && dut.sample_ce;
  end

  always_ff @(posedge clk) begin
    if (!reset && valid_this_cycle) begin
      cap_real_q.push_back(Tx_real);
      cap_imag_q.push_back(Tx_imag);
    end
  end

  // ---------------------------------------------------------------------------
  // Golden reference load
  // ---------------------------------------------------------------------------
  int gold_real_q[$];
  int gold_imag_q[$];

  task automatic load_golden(input string fname);
    int fd, r, i_val, q_val;
    begin
      gold_real_q.delete(); gold_imag_q.delete();
      fd = $fopen(fname, "r");
      if (fd == 0) $fatal(1, "Cannot open golden file %s", fname);
      while (!$feof(fd)) begin
        r = $fscanf(fd, "%d,%d\n", i_val, q_val);
        if (r == 2) begin
          gold_real_q.push_back(i_val);
          gold_imag_q.push_back(q_val);
        end
      end
      $fclose(fd);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Payload write helper
  // ---------------------------------------------------------------------------
  task automatic write_payload(input byte pl[]);
    begin
      for (int i = 0; i < pl.size(); i++) begin
        @(posedge clk);
        payload_wr_en <= 1'b1;
        payload_addr  <= 7'(i);
        payload_din   <= pl[i];
      end
      @(posedge clk);
      payload_wr_en <= 1'b0;
    end
  endtask

  int pass_count = 0;
  int fail_count = 0;

  task automatic run_one_case(input byte pl[], input logic r, input string label);
    int n, mismatches, compare_len;
    begin
      reset = 1; start_Tx = 0; payload_wr_en = 0; rate = r;
      payload_length = pl.size();
      cap_real_q.delete(); cap_imag_q.delete();
      repeat (4) @(posedge clk);
      reset = 0;
      @(posedge clk);

      write_payload(pl);

      @(posedge clk);
      start_Tx <= 1'b1;
      @(posedge clk);
      start_Tx <= 1'b0;

      n = 0;
      while (!done_Tx && n < 2_000_000) begin
        @(posedge clk);
        n++;
      end
      if (n >= 2_000_000) $fatal(1, "TIMEOUT waiting for done_Tx (%s)", label);

      repeat (3) @(posedge clk);   // let the last delayed capture flush

      mismatches = 0;
      compare_len = (cap_real_q.size() < gold_real_q.size()) ? cap_real_q.size() : gold_real_q.size();

      if (cap_real_q.size() != gold_real_q.size())
        $display("  WARNING | %-20s | length mismatch: RTL=%0d  golden=%0d",
                   label, cap_real_q.size(), gold_real_q.size());

      for (int k = 0; k < compare_len; k++) begin
        if (cap_real_q[k] !== gold_real_q[k] || cap_imag_q[k] !== gold_imag_q[k]) begin
          if (mismatches < 10)
            $display("  MISMATCH @%0d | RTL=(%0d,%0d)  golden=(%0d,%0d)",
                       k, cap_real_q[k], cap_imag_q[k], gold_real_q[k], gold_imag_q[k]);
          mismatches++;
        end
      end

      if (mismatches == 0 && cap_real_q.size() == gold_real_q.size()) begin
        $display("  PASS | %-20s | %0d samples, 0 mismatches", label, compare_len);
        pass_count++;
      end else begin
        $display("  FAIL | %-20s | %0d/%0d mismatches", label, mismatches, compare_len);
        fail_count++;
      end
    end
  endtask

  initial begin
    $display("================================================================");
    $display("  tb_tx_top — Full-chain CSS PHY transmitter verification");
    $display("================================================================");

    // ---- Test case 1: 1 Mbps, payload = 20 bytes (0..19) ----
    begin
      byte pl0[20];
      for (int i = 0; i < 20; i++) pl0[i] = i;
      load_golden("golden_tx_iq.csv");
      run_one_case(pl0, 1'b0, "payload=20, 1Mbps");
    end

    // ---- Test case 2: 250 kbps, payload = 5 bytes (0..4) ----
    begin
      byte pl1[5];
      for (int i = 0; i < 5; i++) pl1[i] = i;
      load_golden("golden_tx_iq_250k.csv");
      run_one_case(pl1, 1'b1, "payload=5, 250kbps");
    end

      // ---- Test case 3: 1 Mbps, payload = 0 bytes (header only) ----
    begin
      byte pl2[];
      pl2 = new[0];
      load_golden("golden_tx_iq_L0.csv");
      run_one_case(pl2, 1'b0, "payload=0, 1Mbps");
    end
    // ---- Test case 4: 1 Mbps, payload = 127 bytes (max length) ----
    begin
      byte pl3[127];
      for (int i = 0; i < 127; i++) pl3[i] = i;
      load_golden("golden_tx_iq_L127.csv");
      run_one_case(pl3, 1'b0, "payload=127, 1Mbps");
    end

    $display("================================================================");
    $display("  RESULT: %0d PASS  %0d FAIL", pass_count, fail_count);
    $display("================================================================");

    if (fail_count == 0) $finish;
    else $fatal(1, "%0d case(s) FAILED", fail_count);
  end

endmodule