module tx_top #(
  parameter CHIRP_INDEX = 1,
  parameter SAMPLE_DIV = 1
)(
  input  logic       clk,
  input  logic       reset,
  input  logic       start_Tx,
  input  logic       rate,

  input  logic [7:0] payload_length,
  input  logic       payload_wr_en,
  input  logic [6:0] payload_addr,
  input  logic [7:0] payload_din,

  output logic       done_Tx,
  output logic signed [7:0] Tx_real,
  output logic signed [7:0] Tx_imag
);

localparam integer SAMPLE_DIV_W = (SAMPLE_DIV <= 1) ? 1 : $clog2(SAMPLE_DIV);
localparam logic [SAMPLE_DIV_W-1:0] SAMPLE_DIV_LAST = SAMPLE_DIV_W'(SAMPLE_DIV - 1);

logic [6:0] payload_rd_addr;
logic [7:0] payload_rd_data;
logic tx_active;
logic controller_start;

logic cont_chip_i, cont_chip_q;
logic cont_chip_valid;
logic cont_done, cont_busy;
logic cont_done_seen; // reg to store that controller have finished payload
logic [1:0] qpsk_phase;

logic dq_valid;
logic [1:0] dq_phase;

logic downstream_ready;

logic sample_ce;
logic [1:0] p0, p1, p2, p3;
logic csk_ready_to_recieve;
logic csk_busy;

logic [1:0] gp_count;
logic gp_full;
logic gp_odd;

payload_ram u_payload_ram (
	.clk    (clk),
	.wr_en  (payload_wr_en),
	.wr_addr(payload_addr),
	.wr_data(payload_din),
	.rd_addr(payload_rd_addr),
	.rd_data(payload_rd_data)
);

assign controller_start = start_Tx && !tx_active && (payload_length <= 127);
assign downstream_ready = tx_active && !gp_full;

tx_controller tx_controller (
	.clk             (clk),
	.reset           (reset),
	.rate            (rate),
	.start           (controller_start),
	.payload_length  (payload_length),
	.payload_data    (payload_rd_data),
	.downstream_ready(downstream_ready),
	.payload_addr    (payload_rd_addr),
	.done_Tx         (cont_done),
	.busy            (cont_busy),
	.chip_valid      (cont_chip_valid),
	.chip_i          (cont_chip_i),
	.chip_q          (cont_chip_q)
);

qpsk_mapper u_qpsk_mapper (
	.chip_i    (cont_chip_i),
	.chip_q    (cont_chip_q),
	.qpsk_phase(qpsk_phase)
);

dqpsk_encoder dqpsk_encoder (
	.clk        (clk),
	.reset      (reset),
	.init_packet(controller_start),
	.in_valid   (cont_chip_valid),
	.downstream_ready     (downstream_ready),
	.in_phase   (qpsk_phase),
	.out_valid  (dq_valid),
	.out_phase  (dq_phase)
);

csk_modulator #(
	.CHIRP_INDEX(CHIRP_INDEX)
 ) csk_modulator (
	.clk             (clk),
	.reset           (reset),
	.sample_ce       (sample_ce),
	.i_group_valid   (gp_full),
	.group_odd       (gp_odd),
	.p0              (p0),
	.p1              (p1),
	.p2              (p2),
	.p3              (p3),
	.ready_to_recieve(csk_ready_to_recieve),
	.busy            (csk_busy),
	.sample_real     (Tx_real),
	.sample_imag     (Tx_imag)
);

generate
  if (SAMPLE_DIV == 1) begin : g_sample_ce_one
    assign sample_ce = 1'b1;
  end else begin : g_sample_ce_div
    logic [SAMPLE_DIV_W-1:0] sample_div_count;
    assign sample_ce = (sample_div_count == SAMPLE_DIV_LAST);
    always_ff @(posedge clk) begin
      if (reset || sample_ce) sample_div_count <= '0;
      else sample_div_count <= sample_div_count + 1'b1;
    end
  end
endgenerate

always_ff @(posedge clk) begin
  if (reset) begin
    tx_active <= 1'b0;
    cont_done_seen <= 1'b0;
    gp_count <= 2'b0;
    gp_full <= 1'b0;
    gp_odd <= 1'b1;
    done_Tx <= 1'b0;
    p0 <= 0; p1 <= 0;p2 <= 0;p3 <= 0;
  end else begin
    done_Tx <= 1'b0;
    if (controller_start) begin
      tx_active <= 1'b1;
      cont_done_seen <= 1'b0;
      gp_count <= 2'b0;
      gp_full <= 1'b0;
      gp_odd <= 1'b1;
    end else begin
      if (cont_done) cont_done_seen <= 1'b1;
      if (gp_full && csk_ready_to_recieve) gp_full <= 1'd0;
      if (dq_valid) begin
        unique case (gp_count)
        2'd0: begin p0 <= dq_phase; gp_count<=2'd1; end
        2'd1: begin p1 <= dq_phase; gp_count<=2'd2; end
        2'd2: begin p2 <= dq_phase; gp_count<=2'd3; end
        2'd3: begin
          p3 <= dq_phase;
          gp_count <= 2'd0;
          gp_full <= 1'b1;
          gp_odd <= ~gp_odd;
        end
        endcase
      end
      if (tx_active && cont_done_seen && !cont_busy && !csk_busy && !gp_full && gp_count == 2'd0) begin
        done_Tx <= 1'b1;
        tx_active <= 1'b0;
      end
    end
  end
end

endmodule
