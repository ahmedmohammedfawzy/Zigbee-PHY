vlog ../rtl/*.sv ../tb/*.sv

vsim -voptargs=+acc work.tb_zero_padder
add wave *

# vcd file dump.vcd
# vcd add -r /async_fifo_tb/*

run -all
