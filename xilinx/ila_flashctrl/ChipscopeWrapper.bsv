
interface DebugVIO;
	method Action setDebugVin (Bit#(64) i);
	method Bit#(64) getDebugVout();
endinterface

interface DebugILA;
	method Action setDebug0 (Bit#(128) i);
	method Action setDebug1 (Bit#(128) i);
	method Action setDebug2 (Bit#(128) i);
	method Action setDebug3 (Bit#(128) i);
	method Action setDebug4 (Bit#(128) i);
	method Action setDebug5 (Bit#(128) i);
	method Action setDebug6 (Bit#(128) i);
	method Action setDebug7 (Bit#(128) i);
	method Action setDebug8 (Bit#(128) i);
	method Action setDebug9 (Bit#(128) i);
	method Action setDebug10 (Bit#(128) i);
endinterface


interface CSDebugIfc; 
	interface DebugVIO vio;
	interface DebugILA ila;
endinterface 

import "BVI" chipscope_debug_viv =
module mkChipscopeDebug(CSDebugIfc);
	default_clock clk0;
	default_reset rst0;

	input_clock clk0(v_clk0) <- exposeCurrentClock;
	input_reset rst0(v_rst0) <- exposeCurrentReset;

interface DebugVIO vio;
   method setDebugVin (v_debug_vin) enable((*inhigh*)en38);
	method v_debug_vout getDebugVout;
endinterface 


interface DebugILA ila;
		method setDebug0 (v_debug_0) enable((*inhigh*)en0_0);
		method setDebug1 (v_debug_1) enable((*inhigh*)en0_1);
		method setDebug2 (v_debug_2) enable((*inhigh*)en0_2);
		method setDebug3 (v_debug_3) enable((*inhigh*)en0_3);
		method setDebug4 (v_debug_4) enable((*inhigh*)en0_4);
		method setDebug5 (v_debug_5) enable((*inhigh*)en0_5);
		method setDebug6 (v_debug_6) enable((*inhigh*)en0_6);
		method setDebug7 (v_debug_7) enable((*inhigh*)en0_7);
		method setDebug8 (v_debug_8) enable((*inhigh*)en0_8);
		method setDebug9 (v_debug_9) enable((*inhigh*)en0_9);
		method setDebug10 (v_debug_10) enable((*inhigh*)en0_10);
endinterface

schedule 
(
	ila_setDebug0, ila_setDebug1, ila_setDebug2, ila_setDebug3, ila_setDebug4, ila_setDebug5, ila_setDebug6, ila_setDebug7, ila_setDebug8, ila_setDebug9, ila_setDebug10,
	vio_setDebugVin, vio_getDebugVout
)
CF
(
	ila_setDebug0, ila_setDebug1, ila_setDebug2, ila_setDebug3, ila_setDebug4, ila_setDebug5, ila_setDebug6, ila_setDebug7, ila_setDebug8, ila_setDebug9, ila_setDebug10,
	vio_setDebugVin, vio_getDebugVout
);

endmodule
