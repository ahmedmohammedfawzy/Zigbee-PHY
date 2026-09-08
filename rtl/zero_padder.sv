// =============================================================================
// File        : zero_padder.sv
// Module      : zero_padder
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Computes the number of zero-padding bits appended to the framed PPDU
//   bitstream and the resulting total bit count, in accordance with the
//   IEEE 802.15.4 CSS PHY padding specification.
//
//   The PHY frame structure prior to padding is:
//     [ PHR (12 bits) | PSDU (payload_length x 8 bits) ]
//
//   Mathematical Specification:
//     pad_bits   = N - ((12 + payload_length * 8) mod N)
//     total_bits = 12 + payload_length * 8 + pad_bits
//     where block size N depends on data rate:
//       1 Mbps   (rate = 0) : N = 6
//       250 kbps (rate = 1) : N = 24
//
//   Hardware Implementation Note:
//     Because gcd(8, 6) = 2 and gcd(8, 24) = 8, the padding formula exhibits
//     a strict period-3 cyclic behavior governed entirely by (payload_length % 3):
//
//       rate=0 (N=6):
//         L % 3 = 0 -> rem = 0  -> pad = 6
//         L % 3 = 1 -> rem = 2  -> pad = 4
//         L % 3 = 2 -> rem = 4  -> pad = 2
//
//       rate=1 (N=24):
//         L % 3 = 0 -> rem = 12 -> pad = 12
//         L % 3 = 1 -> rem = 20 -> pad = 4
//         L % 3 = 2 -> rem = 4  -> pad = 20
//
//     To avoid costly non-power-of-2 hardware dividers and potential simulation
//     elaboration issues, pad_bits is decoded directly via a combinational lookup
//     table indexed by {rate, payload_length % 3}.
//
//   Note: When base_bits is an exact multiple of N, the formula appends a full
//   block of N zeros rather than zero bits. This preserves the specified MATLAB
//   behavior.
//
// -----------------------------------------------------------------------------
// Interface :
//
//   Inputs:
//     rate           [0]     Data rate select:
//                              0 = 1 Mbps   (N = 6)
//                              1 = 250 kbps (N = 24)
//
//     payload_length [7:0]   PSDU payload length in bytes (0 to 127).
//
//   Outputs:
//     pad_bits       [4:0]   Number of zero bits appended (2 to 24).
//
//     total_bits     [10:0]  Total framed bit count after padding.
//                            Maximum: 12 + 127*8 + 24 = 1052 bits.
//
// =============================================================================
module zero_padder (
  input logic rate,
  input logic [7:0] payload_length, // payload length in bytes
  output logic [4:0] pad_bits,
  output logic [10:0] total_bits
);

  logic [10:0] base_bits;
  logic [1:0] mod3;

  assign base_bits = 11'd12 + ({3'd0, payload_length} << 3); // shifting by 3 to *8
  assign mod3 = 2'(payload_length % 8'd3);

    // Pure truth-table decode: 0 arithmetic delay
    always_comb begin
      case ({rate, mod3})
        // rate = 0 (1 Mbps, N = 6)
        3'b0_00: pad_bits = 5'd6;
        3'b0_01: pad_bits = 5'd4;
        3'b0_10: pad_bits = 5'd2;

        // rate = 1 (250 kbps, N = 24)
        3'b1_00: pad_bits = 5'd12;
        3'b1_01: pad_bits = 5'd4;
        3'b1_10: pad_bits = 5'd20;

        default: pad_bits = 5'd0;
      endcase
    end

  assign total_bits = base_bits + {6'b0, pad_bits};
endmodule
