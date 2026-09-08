// =============================================================================
// File        : dqpsk_encoder.sv
// Module      : dqpsk_encoder
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Implements the Differential Quadrature Phase-Shift Keying (DQPSK) encoder
//   with a 4-stage feedback memory in accordance with IEEE 802.15.4 CSS PHY
//   subclause 6.5a.2.6.
//
//   Mathematical Specification:
//     The stream of QPSK symbols is differentially encoded via a feedback memory
//     of length 4:
//       S[n] = X[n] * S[n-4]
//
//     All four memory stages are initialized at the start of every packet to:
//       S[-4] = S[-3] = S[-2] = S[-1] = exp(j * pi/4) = (1 + 1j) / sqrt(2)
//
//   Clarifying the Phase Math (Why it never lands on axes):
//     1. The incoming symbol X[n] from the QPSK mapper is a RELATIVE phase
//        shift (delta):
//          X[n] in { +1, +j, -1, -j } -> delta_theta in { 0, +pi/2, +pi, +3*pi/2 }
//
//     2. The feedback memory S[n-4] is initialized to a DIAGONAL baseline:
//          S_init = exp(j * pi/4) -> theta_init = +pi/4 (45 deg)
//
//     3. Complex multiplication S[n] = X[n] * S[n-4] corresponds to adding angles:
//          theta_out = theta_feedback + delta_theta
//
//        Because you are adding multiples of 90 deg (pi/2) to an initial 45 deg (pi/4):
//          - 45 deg + 0 deg   =  45 deg (pi/4)   -> Point (+1, +1)
//          - 45 deg + 90 deg  = 135 deg (3*pi/4) -> Point (-1, +1)
//          - 45 deg + 180 deg = 225 deg (5*pi/4) -> Point (-1, -1)
//          - 45 deg + 270 deg = 315 deg (7*pi/4) -> Point (+1, -1)
//
//        The transmitted output phase theta_out is ALWAYS one of the 4 diagonal
//        constellation points {pi/4, 3*pi/4, 5*pi/4, 7*pi/4}. It NEVER lands on
//        the axes (0, pi/2, pi, 3*pi/2).
//
//   Hardware Implementation Note:
//     Because there are strictly 4 diagonal output phases spaced by pi/2, we
//     represent the output as a 2-bit index:
//       out_phase = 2'd0 -> pi/4   ( 45 deg)
//       out_phase = 2'd1 -> 3*pi/4 (135 deg)
//       out_phase = 2'd2 -> 5*pi/4 (225 deg)
//       out_phase = 2'd3 -> 7*pi/4 (315 deg)
//
//     The initial state exp(j * pi/4) corresponds to index 2'd0.
//     Differential encoding is implemented as a simple 2-bit unsigned modulo-4
//     addition (+), completely eliminating complex multipliers and magnitude overflow.
//
// -----------------------------------------------------------------------------
// Interface :
//
//   Inputs:
//     clk              [0]    System clock.
//     reset            [0]    Synchronous active-high system reset.
//     init_packet      [0]    Synchronous pulse asserting at packet start to
//                             initialize the 4-stage feedback memory to pi/4 (2'd0).
//     in_valid         [0]    Handshake signal indicating valid input phase delta.
//     downstream_ready [0]    Downstream backpressure / ready qualification signal.
//     in_phase       [1:0]    2-bit input phase delta (0=0 deg, 1=+90 deg, 2=+180 deg, 3=+270 deg)
//                            from qpsk_mapper.
//
//   Outputs:
//     out_valid        [0]    Asserted when a valid DQPSK phase symbol is produced.
//     out_phase      [1:0]    2-bit transmitted diagonal phase index (0=pi/4, 1=3*pi/4,
//                             2=5*pi/4, 3=7*pi/4) passed directly to CSK modulator.
//
// =============================================================================

module dqpsk_encoder (
  input  logic       clk,
  input  logic       reset,
  input  logic       init_packet,
  input  logic       in_valid,
  input  logic       downstream_ready,
  input  logic [1:0] in_phase,

  output logic       out_valid,
  output logic [1:0] out_phase
);

  // 4-stage feedback memory holding 2-bit diagonal phase states
  logic [1:0] fb_phase [0:3];
  logic [1:0] tap_select;

  // ---------------------------------------------------------------------------
  // 1. Combinational Differential Phase Addition
  // ---------------------------------------------------------------------------
  // out_phase = (fb_phase + in_phase) mod 4
  // 2-bit unsigned addition wraps modulo-4 naturally.
  assign out_valid = in_valid && downstream_ready;
  assign out_phase = fb_phase[tap_select] + in_phase;

  // ---------------------------------------------------------------------------
  // 2. Sequential State & Circular Memory Update
  // ---------------------------------------------------------------------------
  integer k;
  always_ff @(posedge clk) begin
    if (reset || init_packet) begin
      tap_select <= 2'd0;
      for (k = 0; k < 4; k = k + 1) begin
        // Initialize all 4 feedback stages to exp(j * pi/4) -> index 2'd0
        fb_phase[k] <= 2'd0;
      end
    end else if (out_valid) begin
      // Store current output diagonal phase into circular feedback buffer
      fb_phase[tap_select] <= out_phase;
      // Advance circular pointer (wraps 0 -> 1 -> 2 -> 3 -> 0)
      tap_select           <= tap_select + 2'd1;
    end
  end

endmodule
