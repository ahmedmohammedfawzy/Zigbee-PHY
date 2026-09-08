// =============================================================================
// File        : csk_modulator.sv
// Module      : csk_modulator
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Synthesizes the time-domain Chirp Spread Spectrum (CSS) transmit signal
//   by modulating base chirps from a lookup table (chirp_rom) with four
//   consecutive Differential QPSK (DQPSK) phase symbols, followed by a silent
//   guard gap in accordance with IEEE 802.15.4 CSS PHY subclause 6.5a.2.7.
//
//   Mathematical Specification:
//     A complete chirp sequence comprises 4 subchirps (each of duration Tsub)
//     modulated by 4 DQPSK diagonal phases {p0, p1, p2, p3}:
//       s(t) = c(t) * exp(j * theta_k)   for t in subchirp k in {0, 1, 2, 3}
//
//     Because DQPSK phases are strictly on the diagonals:
//       theta_k in { pi/4, 3*pi/4, 5*pi/4, 7*pi/4 }  <->  pk in { 2'd0, 2'd1, 2'd2, 2'd3 }
//
//     Complex multiplication (Ic + j*Qc) * (Ir + j*Qr) simplifies to:
//       pk = 2'd0 (+1 + 1j) : I_out =  Ic - Qc , Q_out =  Ic + Qc
//       pk = 2'd1 (-1 + 1j) : I_out = -Ic - Qc , Q_out =  Ic - Qc
//       pk = 2'd2 (-1 - 1j) : I_out = -Ic + Qc , Q_out = -Ic - Qc
//       pk = 2'd3 (+1 - 1j) : I_out =  Ic + Qc , Q_out = -Ic + Qc
//
//   Hardware Implementation Note:
//     Accepting DQPSK symbols in 2-bit phase representation replaces 4 signed
//     DSP multipliers and 2 adder stages with a simple adder/subtractor mux,
//     and cuts input/shadow storage flip-flops by 67%.
//
// -----------------------------------------------------------------------------
// Interface :
//
//   Inputs:
//     clk             [0]    System clock.
//     reset           [0]    Synchronous active-high system reset.
//     sample_ce       [0]    Clock enable asserted at the baseband DAC sampling
//                            rate (32 MHz).
//     i_group_valid   [0]    Handshake signal indicating valid input chirp group.
//     chirp_index   [2:0]    Chirp sub-band / sequence index (1 to 4).
//     group_odd       [0]    Indicator for odd/even chirp frame alignment (affects gap).
//     p0, p1, p2, p3[1:0]    2-bit DQPSK phase indices for subchirps 0 to 3
//                            (0 = pi/4, 1 = 3*pi/4, 2 = 5*pi/4, 3 = 7*pi/4).
//
//   Outputs:
//     ready_to_recieve [0]    Ready signal to accept a new chirp symbol group.
//     busy             [0]    High whenever the modulator is generating a chirp or gap.
//     sample_valid     [0]    Asserted with each valid DAC sample tick (matches sample_ce).
//     sample_real    [7:0]    8-bit signed In-Phase sample output.
//     sample_imag    [7:0]    8-bit signed Quadrature sample output.
//     group_done       [0]    1-cycle pulse marking completion of active chirps + gap.
//
// =============================================================================

module csk_modulator #(
  parameter integer CHIRP_INDEX = 1
)(
  input  logic clk,
  input  logic reset,
  input  logic sample_ce,
  input  logic i_group_valid,
  input  logic group_odd,

  input  logic [1:0] p0,
  input  logic [1:0] p1,
  input  logic [1:0] p2,
  input  logic [1:0] p3,

  output logic ready_to_recieve,
  output logic busy,
  output logic sample_valid,
  output logic signed [7:0] sample_real,
  output logic signed [7:0] sample_imag,
  output logic group_done
);

  logic active;
  logic pending_valid;
  logic [8:0] sample_index;
  logic [7:0] rom_addr;
  logic signed [5:0] chirp_real, chirp_imag;

  // Stored active and pending 2-bit phases
  logic [1:0] rp0, rp1, rp2, rp3;
  logic [1:0] prp0, prp1, prp2, prp3;
  logic [1:0] sel_phase;

  logic stored_odd, pending_odd;
  logic [6:0] gap_len;
  logic [8:0] last_index;
  logic at_final;
  logic finishing;

  // Sign-extended 7-bit base chirp values to prevent addition overflow
  logic signed [6:0] ext_real, ext_imag;
  logic signed [7:0] calc_real_8, calc_imag_8;

  chirp_rom #(.CHIRP_INDEX(CHIRP_INDEX)) u_chirp_rom (
    .addr        (rom_addr),
    .chirp_real  (chirp_real),
    .chirp_imag  (chirp_imag)
  );

  assign busy        = active;
  assign at_final    = active && (sample_index == last_index);
  assign finishing   = at_final && sample_ce;
  assign ready_to_recieve = !active || !pending_valid || finishing;

  // Sign extension from 6 bits to 7 bits
  assign ext_real = signed'({chirp_real[5], chirp_real});
  assign ext_imag = signed'({chirp_imag[5], chirp_imag});

  always_comb begin
    // -------------------------------------------------------------------------
    // 1. Guard Gap Timing Calculation (Standard Asymmetric Lengths)
    // -------------------------------------------------------------------------
    case (CHIRP_INDEX)
      1: gap_len = stored_odd ? 7'd70 : 7'd10;
      2: gap_len = stored_odd ? 7'd60 : 7'd20;
      3: gap_len = stored_odd ? 7'd50 : 7'd30;
      4: gap_len = 7'd40;
      default: gap_len = 7'd40;
    endcase

    last_index = (9'd152 - 9'd1) + {2'd0, gap_len};
    rom_addr   = sample_index[7:0];

    // -------------------------------------------------------------------------
    // 2. Subchirp Selection (Select 2-bit active phase)
    // -------------------------------------------------------------------------
    if (sample_index < 9'd38) begin
      sel_phase = rp0;
    end else if (sample_index < 9'd76) begin
      sel_phase = rp1;
    end else if (sample_index < 9'd114) begin
      sel_phase = rp2;
    end else begin
      sel_phase = rp3;
    end

    // -------------------------------------------------------------------------
    // 3. Multiplier-Free Complex Modulation via Add/Sub Mux
    // -------------------------------------------------------------------------
    unique case (sel_phase)
      2'd0: begin // +1 + 1j (pi/4)
        calc_real_8 = 8'(ext_real - ext_imag);
        calc_imag_8 = 8'(ext_real + ext_imag);
      end
      2'd1: begin // -1 + 1j (3pi/4)
        calc_real_8 = 8'(-ext_real - ext_imag);
        calc_imag_8 = 8'( ext_real - ext_imag);
      end
      2'd2: begin // -1 - 1j (5pi/4)
        calc_real_8 = 8'(-ext_real + ext_imag);
        calc_imag_8 = 8'(-ext_real - ext_imag);
      end
      2'd3: begin // +1 - 1j (7pi/4)
        calc_real_8 = 8'( ext_real + ext_imag);
        calc_imag_8 = 8'(-ext_real + ext_imag);
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Double-Buffering Tasks
  // ---------------------------------------------------------------------------
  task automatic load_current_from_input;
    begin
      rp0          <= p0;
      rp1          <= p1;
      rp2          <= p2;
      rp3          <= p3;
      stored_odd   <= group_odd;
    end
  endtask

  task automatic load_pending_from_input;
    begin
      prp0          <= p0;
      prp1          <= p1;
      prp2          <= p2;
      prp3          <= p3;
      pending_odd   <= group_odd;
    end
  endtask

  task automatic promote_pending;
    begin
      rp0          <= prp0;
      rp1          <= prp1;
      rp2          <= prp2;
      rp3          <= prp3;
      stored_odd   <= pending_odd;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Sequential Pipeline & State Engine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (reset) begin
      active        <= 1'b0;
      pending_valid <= 1'b0;
      sample_valid  <= 1'b0;
      sample_real   <= 8'sd0;
      sample_imag   <= 8'sd0;
      group_done    <= 1'b0;
      sample_index  <= 9'd0;
      stored_odd    <= 1'b0;
      pending_odd   <= 1'b0;
      rp0 <= 2'd0; rp1 <= 2'd0; rp2 <= 2'd0; rp3 <= 2'd0;
      prp0 <= 2'd0; prp1 <= 2'd0; prp2 <= 2'd0; prp3 <= 2'd0;
    end else begin
      sample_valid <= 1'b0;
      group_done   <= 1'b0;

      if (!active) begin
        if (i_group_valid) begin
          load_current_from_input();
          active        <= 1'b1;
          pending_valid <= 1'b0;
          sample_index  <= 9'd0;
        end
      end else begin
        if (sample_ce) begin
          sample_valid <= 1'b1;

          // Emit modulated sample during active chirp, zero during guard gap
          if (sample_index < 9'd152) begin
            sample_real <= calc_real_8;
            sample_imag <= calc_imag_8;
          end else begin
            sample_real <= 8'sd0;
            sample_imag <= 8'sd0;
          end

          // Group completion and queue progression
          if (at_final) begin
            group_done   <= 1'b1;
            sample_index <= 9'd0;
            if (pending_valid) begin
              promote_pending();
              active <= 1'b1;
              if (i_group_valid) begin
                load_pending_from_input();
                pending_valid <= 1'b1;
              end else begin
                pending_valid <= 1'b0;
              end
            end else if (i_group_valid) begin
              load_current_from_input();
              active        <= 1'b1;
              pending_valid <= 1'b0;
            end else begin
              active        <= 1'b0;
              pending_valid <= 1'b0;
            end
          end else begin
            sample_index <= sample_index + 9'd1;
            if (i_group_valid && !pending_valid) begin
              load_pending_from_input();
              pending_valid <= 1'b1;
            end
          end
        end else if (i_group_valid && !pending_valid) begin
          load_pending_from_input();
          pending_valid <= 1'b1;
        end
      end
    end
  end

endmodule
