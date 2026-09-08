module tx_top(
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

logic [6:0] payload_rd_addr;
logic [7:0] payload_rd_data;
logic tx_active;
logic controller_start;

logic cont_chip_i, cont_chip_q;
logic qpsk_phase;

payload_ram u_payload_ram (
	.clk    (clk),
	.wr_en  (payload_wr_en),
	.wr_addr(payload_addr),
	.wr_data(payload_din),
	.rd_addr(payload_rd_addr),
	.rd_data(payload_rd_data)
);

assign controller_start = start_Tx && !tx_active && (payload_length <= 127);

tx_controller u_tx_controller (
	.clk           (clk),
	.reset         (reset),
	.rate          (rate),
	.start         (controller_start),
	.payload_length(payload_length),
	.payload_data  (payload_rd_data),
	.payload_addr  (payload_rd_addr),
	.done_Tx       (done_Tx),
	.chip_i        (cont_chip_i),
	.chip_q        (cont_chip_q)
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
	.in_valid   (in_valid),
	.accept     (accept),
	.in_phase   (qpsk_phase),
	.out_valid  (out_valid),
	.out_phase  (out_phase)
);

endmodule
