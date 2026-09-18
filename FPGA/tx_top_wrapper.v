`timescale 1ns / 1ps

module tx_top_wrapper #(
    parameter CHIRP_INDEX = 1,
    parameter SAMPLE_DIV  = 1
)(
    input  wire       clk,        // sys_clock as i/p to the  Block Design
    input  wire       reset,      // reset_rtl  as i/p to the Block Design
    input  wire       start_Tx,
    input  wire       rate,

    output wire       done_Tx
    
);

    wire [7:0] Tx_real;
    wire [7:0] Tx_imag;

    //  Payload 
    wire [7:0] payload_length = 8'd10; // set the lenght to 10 
    wire       payload_wr_en  = 1'b0;  // disable the writing because of the peyload_ram already reads from the $readmemb 
    wire [6:0] payload_addr   = 7'd0;
    wire [7:0] payload_din    = 8'd0;

    
    wire       clk_32MHz;
    wire [0:0] peripheral_reset_0;

    // 1. Instantiation ?? design_1_wrapper (??? ???????? ?? ???? design_1_wrapper.v)
    design_1_wrapper inst_design_1_wrapper (
        .sys_clock          (clk),                // Input Clock of the PLL that's the system clock, 100MHz
        .reset_rtl          (reset),              // Input Reset of the PLL
        .clk_out1_0         (clk_32MHz),          // Output Clock (32MHz) & Input clock to the RTL
        .peripheral_reset_0 (peripheral_reset_0) // Output Active-HIGH Reset & Input reset to the RTL
    );
    
    // Instantiation of ILA (Integrated Logic Anaylzer) IP Core
    ila_0 u_ila (
        .clk(clk_32MHz),           // clock source to the rtl design, clock signal name "clk_32MHz" that's output of the PLL
        .probe0(Tx_real),          // capture the output signal of 8-bit named Tx_real
        .probe0(Tx_imag),          // capture the output signal of 8-bit named Tx_imag
    );

    // 2. Instantiation of tx_top 
    tx_top #(
        .CHIRP_INDEX (CHIRP_INDEX),
        .SAMPLE_DIV  (SAMPLE_DIV)
    ) inst_tx_top (
        .clk            (clk_32MHz),           // clock source to the rtl design, clock signal name "clk_32MHz" that's output of the PLL
        .reset          (peripheral_reset_0),  // reset pin to the rtl design, reset signal name "peripheral_reset_0" that's output of the control reset system
        .start_Tx       (start_Tx),
        .rate           (rate),
        .payload_length (payload_length),
        .payload_wr_en  (payload_wr_en),
        .payload_addr   (payload_addr),
        .payload_din    (payload_din),
        .done_Tx        (done_Tx),
        .Tx_real        (Tx_real),
        .Tx_imag        (Tx_imag)
    );

endmodule