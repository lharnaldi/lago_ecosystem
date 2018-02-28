source projects/base_system/block_design.tcl

property -dict [list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100} CONFIG.MMCM_DIVCLK_DIVIDE {1} CONFIG.MMCM_CLKOUT1_DIVIDE {10} CONFIG.CLKOUT2_JITTER {124.615}] [get_bd_cells pll_0]

# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset:5.0 rst_0

# LED

# Create c_counter_binary
cell xilinx.com:ip:c_counter_binary:12.0 cntr_0 {
  Output_Width 32
} {
  CLK pll_0/clk_out1
}

# Create xlslice
cell xilinx.com:ip:xlslice:1.0 slice_0 {
  DIN_WIDTH 32 DIN_FROM 26 DIN_TO 26 DOUT_WIDTH 1
} {
  Din cntr_0/Q
  Dout led_o
}

# STS

# Create xlconstant
cell xilinx.com:ip:xlconstant:1.1 const_0

# Create dna_reader
cell labdpr:user:dna_reader:1.0 dna_0 {} {
  aclk ps_0/FCLK_CLK0
  aresetn rst_0/peripheral_aresetn
}

# Create xlconcat
cell xilinx.com:ip:xlconcat:2.1 concat_0 {
  NUM_PORTS 2
  IN0_WIDTH 32
  IN1_WIDTH 64
} {
  In0 const_0/dout
  In1 dna_0/dna_data
}

# Create axi_sts_register
cell labdpr:user:axi_sts_register:1.0 sts_0 {
  STS_DATA_WIDTH 96
  AXI_ADDR_WIDTH 32
  AXI_DATA_WIDTH 32
} {
  sts_data concat_0/dout
}

# Create all required interconnections
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {
  Master /ps_0/M_AXI_GP0
  Clk Auto
} [get_bd_intf_pins sts_0/S_AXI]

set_property RANGE 4K [get_bd_addr_segs ps_0/Data/SEG_sts_0_reg0]
set_property OFFSET 0x40000000 [get_bd_addr_segs ps_0/Data/SEG_sts_0_reg0]

# Delete input/output port
delete_bd_objs [get_bd_ports exp_p_tri_io]
delete_bd_objs [get_bd_ports exp_n_tri_io]

# Create input port
create_bd_port -dir I -from 7 -to 0 exp_p_tri_io
create_bd_port -dir I -from 1 -to 0 exp_n_tri_io
create_bd_port -dir O -from 2 -to 2 exp_n_tri_io

cell xilinx.com:ip:selectio_wiz:5.1 selio_wiz_0 {
  BUS_IO_STD LVCMOS33
  SYSTEM_DATA_WIDTH 10 
  SELIO_CLK_BUF BUFIO 
  SERIALIZATION_FACTOR 4
  SELIO_CLK_IO_STD LVCMOS33
  CLK_FWD_IO_STD LVCMOS33
} {
  
}
