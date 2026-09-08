// =============================================================================
// File        : preamble_sfd_rom.sv
// Module      : preamble_sfd_rom
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Combinational lookup table storing the synchronization sequences (Preamble
//   and SFD) for both IEEE 802.15.4 CSS PHY transmission modes.
//
//   Frame Synchronization Structure:
//     - 1 Mbps   (rate = 0): 48 chips total
//         [ Preamble: 32 chips of '1' | SFD_1M: 16 chips ]
//     - 250 kbps (rate = 1): 96 chips total
//         [ Preamble: 80 chips of '1' | SFD_250K: 16 chips ]
//
//   Hardcoded SFD Patterns (MSB transmitted first):
//     - SFD_1M   : 16'b0111_0100_1001_1100 (0x749C)
//     - SFD_250K : 16'b0111_1010_0010_0011 (0x7A23)
//
//   Output Handshaking:
//     The 'valid' flag asserts high strictly while 'index' resides within the
//     active sync window (index < 48 for 1M, index < 96 for 250k), serving as
//     an automatic address bounds gate for downstream streaming pipelines.
//
// -----------------------------------------------------------------------------
// Interface :
//
//   Inputs:
//     rate  [0]    Data rate select:
//                    0 = 1 Mbps   (48 chips total)
//                    1 = 250 kbps (96 chips total)
//
//     index [6:0]  Chip offset counter within the synchronization header (0..127).
//
//   Outputs:
//     chip  [0]    Sync chip value at the current index position.
//
//     valid [0]    Active-high indicator that 'index' is within valid sync bounds.
//
// =============================================================================
module preamble_sfd_rom (
  input  logic       rate,
  input  logic [6:0] index,
  output logic       chip,
  output logic       valid
);
  localparam logic [15:0] SFD_1M   = 16'b0111010010011100;
  localparam logic [15:0] SFD_250K = 16'b0111101000100011;

  // Both preamble lengths are multiples of 16, so index[3:0] is the SFD-local
  // offset in the 16-chip SFD windows.
  always_comb begin
    chip = 1'b0;
    valid = 1'b0;
    if (!rate) begin // 1M
      if (index < 7'd32) begin
        chip = 1'b1;
        valid = 1'b1;
      end else if (index < 7'd48) begin
        chip = SFD_1M[4'd15 - index[3:0]];
        valid = 1'b1;
      end
    end else begin // 250K
      if (index < 7'd80) begin
        chip = 1'b1;
        valid = 1'b1;
      end else if (index < 7'd96) begin
        chip = SFD_250K[4'd15 - index[3:0]];
        valid = 1'b1;
      end
    end
  end
endmodule
