# =============================================================================
# =========================== Physical Constrains =============================
# =============================================================================

#============== clock =============
set_property PACKAGE_PIN Y9 [get_ports {clk}];
set_property IOSTANDARD LVCMOS33 [get_ports {clk}];

#============ inputs ==============
# reset -> SW0 (Slide Switch 0)
set_property PACKAGE_PIN F22 [get_ports {reset}];         # "SW0"
set_property IOSTANDARD LVCMOS33 [get_ports {reset}];


# start_Tx -> SW1 (Slide Switch 1)
set_property PACKAGE_PIN G22 [get_ports {start_Tx}];      # "SW1"
set_property IOSTANDARD LVCMOS33 [get_ports {start_Tx}];

# rate -> SW2 (Slide Switch 2)
set_property PACKAGE_PIN H22 [get_ports {rate}];          # "SW2"
set_property IOSTANDARD LVCMOS33 [get_ports {rate}];


#============ outputs ==============

# done_Tx -> LD0 (On-board LED 0)
set_property PACKAGE_PIN T22 [get_ports {done_Tx}];
set_property IOSTANDARD LVCMOS33 [get_ports {done_Tx}];



# =============================================================================
# =========================== Timing Constrains ===============================
# =============================================================================

#------------------- clock -------------------
set clk_32MHz [get_clocks -of_objects [get_pins design_1_i/clk_wiz_0/clk_out1]]

# ===========================================================
# ========================= inputs ==========================
# ===========================================================

#------------------- reset -------------------
set_input_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports reset]
set_input_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports reset]

#------------------- start_Tx -------------------
set_input_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports start_Tx]
set_input_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports start_Tx]

#------------------- rate -------------------
set_input_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports rate]
set_input_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports rate]


# ===========================================================
# ========================= outputs =========================
# ===========================================================
#------------------- done_Tx -------------------
set_output_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports done_Tx]
set_output_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports done_Tx]

#------------------- Tx_real [7:0] -------------------
set_output_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports Tx_real[*]]
set_output_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports Tx_real[*]]

#------------------- Tx_imag [7:0] -------------------
set_output_delay 0.5 -max -clock [get_clocks $clk_32MHz] [get_ports Tx_imag[*]]
set_output_delay 0.5 -min -clock [get_clocks $clk_32MHz] [get_ports Tx_imag[*]]


