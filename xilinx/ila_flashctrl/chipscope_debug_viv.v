
module chipscope_debug_viv (
	input v_clk0,
	input v_rst0,
	input [63:0] v_debug_vin,
	output [63:0] v_debug_vout,

	input [127:0] v_debug_0, 
	input [127:0] v_debug_1,
	input [127:0] v_debug_2, 
	input [127:0] v_debug_3, 
	input [127:0] v_debug_4, 
	input [127:0] v_debug_5, 
	input [127:0] v_debug_6, 
	input [127:0] v_debug_7,
	input [127:0] v_debug_8,
	input [127:0] v_debug_9,
	input [127:0] v_debug_10 
);

	
//	(* mark_debug = "true", keep = "true" *) wire [15:0] v_test;
//	assign v_test = v_debug0_0;

	(* mark_debug = "true" *) reg [127:0] v_debug_0_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_1_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_2_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_3_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_4_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_5_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_6_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_7_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_8_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_9_reg;
	(* mark_debug = "true" *) reg [127:0] v_debug_10_reg;

	(* mark_debug = "true" *) reg [63:0] v_debug_vin_reg;
	(* mark_debug = "true" *) reg [63:0] v_debug_vout_reg;
	(* mark_debug = "true" *)	wire [63:0] v_debug_vout_wire;


	always @  (posedge v_clk0)  begin
		v_debug_0_reg 		<=		v_debug_0;
		v_debug_1_reg 		<=		v_debug_1;
		v_debug_2_reg 		<=		v_debug_2;
		v_debug_3_reg 		<=		v_debug_3;
		v_debug_4_reg 		<= 	v_debug_4;
		v_debug_5_reg		<=	 	v_debug_5;
		v_debug_6_reg 		<=	 	v_debug_6;
		v_debug_7_reg 		<=	 	v_debug_7;
		v_debug_8_reg 		<=	 	v_debug_8;
		v_debug_9_reg 		<=	 	v_debug_9;
		v_debug_10_reg 	<=	 	v_debug_10;
		v_debug_vin_reg 	<= 	v_debug_vin;
		v_debug_vout_reg 	<= 	v_debug_vout_wire;
	end

	assign v_debug_vout = v_debug_vout_reg;

	vio_flashctrl vio_flashctrl_0 (
		.clk(v_clk0),
		.probe_in0(v_debug_in_reg),
		.probe_out0(v_debug_vout_wire)
	);


	ila_flashctrl ila_flashctrl_0 (
		.clk(v_clk0),
		.probe0(v_debug_0_reg), 
		.probe1(v_debug_1_reg),
		.probe2(v_debug_2_reg),
		.probe3(v_debug_3_reg),
		.probe4(v_debug_4_reg),
		.probe5(v_debug_5_reg),
		.probe6(v_debug_6_reg),
		.probe7(v_debug_7_reg),
		.probe8(v_debug_8_reg), 
		.probe9(v_debug_9_reg), 
		.probe10(v_debug_10_reg) 
	);

endmodule
