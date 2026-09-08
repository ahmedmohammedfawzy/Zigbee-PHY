// =============================================================================
// File        : qpsk_mapper.sv
// Module      : qpsk_mapper
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Maps incoming paired In-Phase (I) and Quadrature (Q) binary chips to their
//   corresponding 2-bit differential phase increment in accordance with the
//   IEEE 802.15.4 CSS PHY QPSK constellation mapping (Table 26c / subclause 6.5a.2.5).
//
//   Mathematical Specification:
//     Binary chip inputs are converted to bipolar baseband levels:
//       chip = 1 -> +1
//       chip = 0 -> -1
//
//     Per IEEE 802.15.4 CSS subclause 6.5a.2.5:
//       S = ((I + Q) - j*(I - Q)) / 2
//
//     Mapping Table (IEEE 802.15.4 Table 26c):
//       {chip_i, chip_q} | Bipolar (I, Q) | Complex Symbol S | Phase (Delta theta) | Phase Code (qpsk_phase)
//       -----------------+----------------+------------------+---------------------+------------------------
//             2'b11      |    (+1, +1)    |        +1        |          0          |         2'd0
//             2'b01      |    (-1, +1)    |       +1j        |        pi/2         |         2'd1
//             2'b00      |    (-1, -1)    |        -1        |         pi          |         2'd2
//             2'b10      |    (+1, -1)    |       -1j        |       3*pi/2        |         2'd3
//
//   Hardware Implementation Note:
//     The output qpsk_phase represents a relative phase shift in multiples of pi/2:
//       Delta theta = qpsk_phase * (pi/2)
//
//     This value feeds directly into the downstream DQPSK encoder as a 2-bit
//     phase increment.
//
// -----------------------------------------------------------------------------
// Interface :
//
//   Inputs:
//     chip_i          [0]    In-Phase chip bit (1 => +1, 0 => -1).
//     chip_q          [0]    Quadrature chip bit (1 => +1, 0 => -1).
//
//   Outputs:
//     qpsk_phase    [1:0]    2-bit phase shift index representing
//                            Delta theta in {0, pi/2, pi, 3*pi/2}.
//
// =============================================================================

module qpsk_mapper (
  input  logic chip_i, // 1 => +1, 0 => -1
  input  logic chip_q,
  output logic [1:0] qpsk_phase
);

  always_comb begin
    unique case ({chip_i, chip_q})
      2'b11: begin qpsk_phase = 2'd0; end // (0 rad)
      2'b01: begin qpsk_phase = 2'd1; end // (pi/2 rad)
      2'b00: begin qpsk_phase = 2'd2; end // (pi rad)
      2'b10: begin qpsk_phase = 2'd3; end // (3*pi/2 rad)
    endcase
  end

endmodule
