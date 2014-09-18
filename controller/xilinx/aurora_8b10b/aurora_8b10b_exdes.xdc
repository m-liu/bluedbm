
################################################################################
##
## (c) Copyright 2010-2014 Xilinx, Inc. All rights reserved.
##
## This file contains confidential and proprietary information
## of Xilinx, Inc. and is protected under U.S. and
## international copyright and other intellectual property
## laws.
##
## DISCLAIMER
## This disclaimer is not a license and does not grant any
## rights to the materials distributed herewith. Except as
## otherwise provided in a valid license issued to you by
## Xilinx, and to the maximum extent permitted by applicable
## law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
## WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
## AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
## BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
## INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
## (2) Xilinx shall not be liable (whether in contract or tort,
## including negligence, or under any other theory of
## liability) for any loss or damage of any kind or nature
## related to, arising under or in connection with these
## materials, including for any direct, or any indirect,
## special, incidental, or consequential loss or damage
## (including loss of data, profits, goodwill, or any type of
## loss or damage suffered as a result of any action brought
## by a third party) even if such damage or loss was
## reasonably foreseeable or Xilinx had been advised of the
## possibility of the same.
##
## CRITICAL APPLICATIONS
## Xilinx products are not designed or intended to be fail-
## safe, or for use in any application requiring fail-safe
## performance, such as life-support or safety devices or
## systems, Class III medical devices, nuclear facilities,
## applications related to the deployment of airbags, or any
## other applications that could lead to death, personal
## injury, or severe property or environmental damage
## (individually and collectively, "Critical
## Applications"). Customer assumes the sole risk and
## liability of any use of Xilinx products in Critical
## Applications, subject only to applicable laws and
## regulations governing limitations on product liability.
##
## THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
## PART OF THIS FILE AT ALL TIMES.
##
##
################################################################################
## XDC generated for xc7a200t-fbg676-2 device
# 275.0MHz GT Reference clock constraint
create_clock -period 3.636 -name GT_REFCLK1 [get_pins gtp_clk_0/O]
####################### GT reference clock LOC #######################
set_property PACKAGE_PIN F11 [get_ports CLK_gtp_clk_0_p]
# TXOUTCLK Constraint: Value is selected based on the line rate (4.4 Gbps) and lane width (4-Byte)
#create_clock -name tx_out_clk_i -period 4.545	 [get_pins aurora_module_i/aurora_8b10b_i/inst/gt_wrapper_i/aurora_8b10b_multi_gt_i/gt0_aurora_8b10b_i/gtpe2_i/TXOUTCLK]
# SYNC_CLK constraint : Value is selected based on the line rate (4.4 Gbps) and lane width (4-Byte)
create_clock -period 4.545 -name sync_clk_i [get_pins */auroraIntraImport/aurora_module_i/clock_module_i/clkout1_buf/O]

# USER_CLK constraint : Value is selected based on the line rate (4.4 Gbps) and lane width (4-Byte)
create_clock -period 9.091 -name user_clk_i [get_pins */auroraIntraImport/aurora_module_i/clock_module_i/clkout0_buf/O]
# 20.0 ns period Board Clock Constraint
create_clock -period 20.000 -name init_clk_i [get_pins */auroraIntraClockDiv2_slowbuf/O]
# 20.0 ns period DRP Clock Constraint
create_clock -period 20.000 -name drp_clk_i -add [get_pins */auroraIntraClockDiv2_slowbuf/O]
#TODO #create_clock -name drp_clk_i -period 20.0 [get_ports DRP_CLK_IN]

###### CDC in RESET_LOGIC from INIT_CLK to USER_CLK ##############
set_max_delay -datapath_only -from [get_clocks init_clk_i] -to [get_clocks user_clk_i] 9.091



set_false_path -from [get_clocks clkout0] -to [get_clocks user_clk_i]
set_false_path -from [get_clocks user_clk_i] -to [get_clocks clkout0]
#set_false_path -from [get_clocks CLK_sysClkP] -to [get_clocks user_clk_i]



############################### GT LOC ###################################


# aurora X0Y4
set_property PACKAGE_PIN B7 [get_ports {pins_aurora_TXP[3]}]

# aurora X0Y5
set_property PACKAGE_PIN D8 [get_ports {pins_aurora_TXP[2]}]

# aurora X0Y6
set_property PACKAGE_PIN B9 [get_ports {pins_aurora_TXP[1]}]

# aurora X0Y7
set_property PACKAGE_PIN D10 [get_ports {pins_aurora_TXP[0]}]

