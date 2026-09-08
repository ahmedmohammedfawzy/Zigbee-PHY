// =============================================================================
// File        : tx_controller.sv
// Module      : tx_controller
// Project     : IEEE 802.15.4 CSS PHY Transmitter
// =============================================================================
//
// Description :
//   Top-level transmit controller for the CSS PHY. Builds the framed bit
//   stream (PHR + PSDU + zero padding), groups bits into I/Q pairs, maps
//   groups of pairs into symbols, encodes symbols into codewords for either
//   the 1 Mbps or 250 kbps rate, and serializes the resulting codeword bits
//   out as chip_i / chip_q.
//
//   Rate modes:
//     rate = 0 : 1 Mbps  - 3-bit symbols -> 4-bit codewords (no interleaving)
//     rate = 1 : 250 kbps - 6-bit symbols -> 32-bit codewords, two symbols
//                (A then B) are interleaved into a 64-bit codeword pair
//                before being shifted out.
//
//   done_Tx pulses for one clock cycle when the final chip of the frame has
//   been emitted and the controller returns to ST_IDLE.
// =============================================================================

module tx_controller(
  input  logic       clk,
  input  logic       reset,
  input  logic       rate,             // 0 = 1 Mbps, 1 = 250 kbps
  input  logic       start,            // pulse to begin a new transmission
  input  logic [7:0] payload_length,   // PSDU length in bytes (0-127)
  input  logic [7:0] payload_data,     // byte read from payload memory at payload_addr
  output logic [6:0] payload_addr,     // byte address into payload memory
  output logic       done_Tx,          // 1-cycle pulse at end of transmission
  output logic       chip_i,           // serialized I-channel chip output
  output logic       chip_q            // serialized Q-channel chip output
);

  // ---------------------------------------------------------------------
  // FSM states
  //   ST_IDLE       : waiting for start
  //   ST_SYNC       : shifting out preamble + SFD chips
  //   ST_COLLECT_A  : shifting in bit-pairs to build symbol A
  //                   (1M: this is the only collect stage per symbol;
  //                    250k: this builds the first of the two symbols
  //                    that get interleaved together)
  //   ST_COLLECT_B  : (250k only) shifting in bit-pairs to build symbol B
  //   ST_EMIT_1M    : serializing the 4-bit 1M codeword
  //   ST_EMIT_250K  : serializing the 64-bit interleaved 250k codeword pair
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SYNC,
    ST_COLLECT_A,
    ST_COLLECT_B,
    ST_EMIT_1M,
    ST_EMIT_250K
  } state_t;

  state_t state;

  // Framing signals
  logic [11:0] phr;                    // 12-bit PHY header from phr_generator
  logic [10:0] total_bits;             // total framed bit count (PHR+PSDU+pad)
  logic [10:0] total_pairs;            // total_bits / 2 (bits are consumed as I/Q pairs)
  logic [4:0]  pad_bits;               // zero-padding bit count (unused directly here,
                                        // folded into total_bits by zero_padder)

  // Preamble/SFD sequencing
  logic [6:0] sync_index;              // index into preamble/SFD ROM
  logic       sync_chip, sync_valid;   // current sync chip value / valid flag

  // Latched transmission parameters / bit-pair sourcing
  logic [7:0]  payload_length_latched; // payload_length captured at start
  logic        pair_i, pair_q;         // current I/Q bit pair being collected
  logic [10:0] pair_index;             // running index over all I/Q pairs in the frame

  logic [2:0] collect_count;           // counts bit-pairs collected within current symbol

  // Symbol / codeword storage
  logic [5:0]  symbol_i, symbol_q;         // shift registers accumulating pair bits into symbols
  logic [3:0]  cw_i_1m, cw_q_1m;           // 1 Mbps codewords (from 3-bit symbol)
  logic [31:0] cw_i_250k_a, cw_q_250k_a;   // 250k codeword for symbol A (current collect)
  logic [31:0] cw_i_250k_b, cw_q_250k_b;   // 250k codeword for symbol B (latched from A)

  // Interleaver I/O: {symbol_B_codeword, symbol_A_codeword} -> interleaved bits
  logic [63:0] inter_i_in, inter_q_in;
  logic [63:0] inter_i_out, inter_q_out;

  logic [6:0] emit_index;              // bit position counter while serializing a codeword

  // ---------------------------------------------------------------------
  // Sub-module instances
  // ---------------------------------------------------------------------

  // Builds the 12-bit PHY header from the latched payload length
  phr_generator u_phr_generator (
	.payload_length(payload_length_latched),
	.phr_bits      (phr)
  );

  // Computes zero-padding bits and total framed bit count (PHR + PSDU + pad),
  // per the rate-dependent block size (N=6 for 1M, N=24 for 250k)
  zero_padder u_zero_padder (
	.rate          (rate),
	.payload_length(payload_length_latched),
	.pad_bits      (pad_bits),
	.total_bits    (total_bits)
  );

  // Preamble + SFD chip ROM, indexed by sync_index; sequence length depends on rate
  preamble_sfd_rom u_preamble_sfd_rom (
	.rate (rate),
	.index(sync_index),
	.chip (sync_chip),
	.valid(sync_valid)
  );

  // 1 Mbps symbol->codeword mappers (3-bit symbol -> 4-bit codeword), one per channel
  symbol_mapper_1m u_i_symbol_mapper_1m (
	.symbol  (symbol_i[2:0]),
	.codeword(cw_i_1m)
  );

  symbol_mapper_1m u_q_symbol_mapper_1m (
	.symbol  (symbol_q[2:0]),
	.codeword(cw_q_1m)
  );

  // 250 kbps symbol->codeword mappers (6-bit symbol -> 32-bit codeword), one per channel.
  // These continuously reflect whatever is currently in symbol_i/symbol_q; the result
  // is only latched into cw_*_250k_b (and consumed) at the appropriate FSM transitions.
  symbol_mapper_250k u_i_symbol_mapper_250k (
	.symbol  (symbol_i),
	.codeword(cw_i_250k_a)
  );

  symbol_mapper_250k u_q_symbol_mapper_250k (
	.symbol  (symbol_q),
	.codeword(cw_q_250k_a)
  );

  // Pack symbol B (older, latched) and symbol A (newer) codewords together
  // for interleaving: {B, A} as the 64-bit interleaver input.
  assign inter_i_in = {cw_i_250k_b, cw_i_250k_a};
  assign inter_q_in = {cw_q_250k_b, cw_q_250k_a};

  bit_interleaver u_i_bit_interleaver (
	.in_bits (inter_i_in),
	.out_bits(inter_i_out)
  );

  bit_interleaver u_q_bit_interleaver (
	.in_bits (inter_q_in),
	.out_bits(inter_q_out)
  );

  // ---------------------------------------------------------------------
  // Payload memory addressing
  //
  // pair_index counts every I/Q bit-pair in the frame, starting at 0:
  //   pairs [0 .. 5]                  -> PHR bits (6 pairs = 12 bits)
  //   pairs [6 .. payload_pair_end-1] -> PSDU (payload) bits
  //   pairs [payload_pair_end .. )    -> zero-padding bits (implicit; pair_i/q
  //                                      default to 0 below once past payload_pair_end)
  //
  // Each payload byte supplies 4 bit-pairs (8 bits / 2), so:
  //   payload_pair_end = 6 + payload_length*4
  //
  // Within a payload byte, pair_payload_index (0..3 per byte, wrapping via
  // payload_addr) selects which 2-bit slice (bit_select, bit_select+1) of
  // payload_data forms the current I/Q pair.
  // ---------------------------------------------------------------------
  logic [10:0] payload_pair_end;
  logic [8:0]  pair_payload_index;
  logic [2:0]  bit_select;
  always_comb begin
    total_pairs = total_bits >> 1;
    payload_pair_end = 11'd6 + ({3'd0, payload_length_latched} << 2);
    pair_payload_index = 9'd0;
    bit_select = 3'd0;
    payload_addr = 7'd0;
    if ((pair_index >= 11'd6) && (pair_index < payload_pair_end)) begin
      // Currently in the payload region: compute byte address and bit offset
      pair_payload_index = 9'(pair_index - 11'd6);
      payload_addr = pair_payload_index[8:2];              // byte index (pair_payload_index / 4)
      bit_select   = {pair_payload_index[1:0], 1'b0};       // bit offset within byte (0,2,4,6)
    end
  end

  // ---------------------------------------------------------------------
  // Bit-pair source mux: selects PHR bits, payload bits, or zero (padding)
  // depending on where pair_index currently falls in the frame.
  // ---------------------------------------------------------------------
  always_comb begin
    pair_i = 1'b0;
    pair_q = 1'b0;
    if (pair_index < 11'd6) begin
      // PHR region: pull the two bits for this pair directly out of phr
      pair_i = phr[pair_index * 2];
      pair_q = phr[pair_index * 2 + 1];
    end else if (pair_index < payload_pair_end) begin
      // Payload region: pull the two bits out of the currently addressed byte
      pair_i = payload_data[bit_select];
      pair_q = payload_data[bit_select + 3'd1];
    end
    // else: padding region -> pair_i/pair_q stay 0 (zero padding)
  end

  // ---------------------------------------------------------------------
  // Output chip mux: drives chip_i/chip_q based on current FSM state.
  //   ST_SYNC      -> preamble/SFD ROM output (same chip on both channels)
  //   ST_EMIT_1M   -> serialize cw_i_1m/cw_q_1m MSB-first (4 bits)
  //   ST_EMIT_250K -> serialize interleaved 64-bit codewords MSB-first
  //   default      -> idle / collecting: outputs held low
  // ---------------------------------------------------------------------
  always_comb begin
    case (state)
      ST_SYNC: begin
        chip_i = sync_chip;
        chip_q = sync_chip;
      end
      ST_EMIT_1M: begin
        chip_i = cw_i_1m[3-emit_index];
        chip_q = cw_q_1m[3-emit_index];
      end
      ST_EMIT_250K: begin
        chip_i = inter_i_out[63-emit_index];
        chip_q = inter_q_out[63-emit_index];
      end
      default: begin
        chip_i = 1'b0;
        chip_q = 1'b0;
      end
    endcase
  end

  // ---------------------------------------------------------------------
  // Main sequential FSM
  // ---------------------------------------------------------------------
  always_ff @(posedge clk, posedge reset) begin
   if (reset) begin
     // Async reset: clear all state and counters
     state <= ST_IDLE;
     payload_length_latched <= 0;
     sync_index <= 0;
     pair_index <= 0;
     collect_count <= 0;
     emit_index <= 0;
     symbol_i <= 0;
     symbol_q <= 0;
     cw_q_250k_b <= 0;
     cw_i_250k_b <= 0;
   end else begin
     // done_Tx defaults low each cycle; only pulses high explicitly below
     // when a transmission completes.
     done_Tx <= 1'b0;
     case (state)

       // -----------------------------------------------------------------
       // ST_IDLE: wait for start, latch transmission parameters, and reset
       // all per-transmission counters before entering the sync sequence.
       // -----------------------------------------------------------------
       ST_IDLE: begin
         if (start) begin
           payload_length_latched <= payload_length;
           sync_index <= 0;
           pair_index <= 0;
           collect_count <= 0;
           emit_index <= 0;
           symbol_i <= 0;
           symbol_q <= 0;
           cw_q_250k_b <= 0;
           cw_i_250k_b <= 0;
           state <= ST_SYNC;
         end
       end

       // -----------------------------------------------------------------
       // ST_SYNC: shift out preamble+SFD chips. Sequence length depends on
       // rate (47 chips @1M, 95 chips @250k, 0-indexed) before moving on
       // to collecting the first symbol.
       // -----------------------------------------------------------------
       ST_SYNC: begin
         if (!rate && sync_index == 47)
           state <= ST_COLLECT_A;
         else if (rate && sync_index == 95)
           state <= ST_COLLECT_A;
         else
           sync_index <= sync_index + 7'd1;
       end

       // -----------------------------------------------------------------
       // ST_COLLECT_A: shift bit-pairs into symbol_i/symbol_q one pair per
       // cycle. For 1M, 3 pairs (6 bits) form a symbol and we go straight
       // to emit. For 250k, 6 pairs (12 bits) form symbol A; its codeword
       // is then latched into the "B" registers (to be interleaved with
       // the *next* symbol, which becomes the new "A") and we proceed to
       // collect symbol B.
       // -----------------------------------------------------------------
       ST_COLLECT_A: begin
         if (!rate && collect_count == 3) begin
           collect_count <= 0;
           emit_index <= 0;
           state <= ST_EMIT_1M;
         end else if (rate && collect_count == 6) begin
           collect_count <= 0;
           cw_i_250k_b <= cw_i_250k_a;   // latch symbol A's codeword as "B" for interleaving
           cw_q_250k_b <= cw_q_250k_a;
           state <= ST_COLLECT_B;
         end else begin
           symbol_i <= {symbol_i[4:0], pair_i};  // shift new pair bit into symbol
           symbol_q <= {symbol_q[4:0], pair_q};
           pair_index <= 11'd1 + pair_index;
           collect_count <= collect_count + 3'd1;
         end
       end

       // -----------------------------------------------------------------
       // ST_COLLECT_B: (250k only) collect the second symbol's 6 bit-pairs.
       // Once complete, symbol_i/symbol_q hold symbol B, whose codeword
       // (cw_i_250k_a / cw_q_250k_a, via the combinational mapper) will be
       // interleaved together with the previously latched symbol A
       // (cw_*_250k_b) when ST_EMIT_250K reads inter_*_out.
       // -----------------------------------------------------------------
       ST_COLLECT_B: begin
         if (collect_count == 6) begin
           collect_count <= 0;
           emit_index <= 0;
           state <= ST_EMIT_250K;
         end else begin
           symbol_i <= {symbol_i[4:0], pair_i};
           symbol_q <= {symbol_q[4:0], pair_q};
           pair_index <= 11'd1 + pair_index;
           collect_count <= collect_count + 3'd1;
         end
       end

       // -----------------------------------------------------------------
       // ST_EMIT_1M: serialize the 4-bit 1M codeword (MSB first via the
       // chip mux above). After the last bit, either finish the
       // transmission (pulse done_Tx) or loop back to collect the next
       // symbol.
       // -----------------------------------------------------------------
       ST_EMIT_1M: begin
         if (emit_index == 7'd3) begin
           emit_index <= 7'd0;
           if (pair_index >= total_pairs) begin
             done_Tx <= 1'b1;
             state <= ST_IDLE;
           end else state <= ST_COLLECT_A;
         end else emit_index <= emit_index + 7'd1;
       end

       // -----------------------------------------------------------------
       // ST_EMIT_250K: serialize the 64-bit interleaved codeword pair
       // (symbols A+B). After the last bit, either finish the
       // transmission (pulse done_Tx) or loop back to collect the next
       // pair of symbols.
       // -----------------------------------------------------------------
       ST_EMIT_250K: begin
         if (emit_index == 7'd63) begin
           emit_index <= 7'd0;
           if (pair_index >= total_pairs) begin
             done_Tx <= 1'b1;
             state <= ST_IDLE;
           end else state <= ST_COLLECT_A;
         end else emit_index <= emit_index + 7'd1;
       end

       default: state <= ST_IDLE;
     endcase
   end
  end
endmodule
