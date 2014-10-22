import FIFOF::*;
import FIFO::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;
import RegFile::*;


import ControllerTypes::*;
import FlashCtrlVirtex::*;
import FlashBusModel::*;

//simulator options
//Integer BSIM_CHIPS_PER_BUS 	= 2;
//Integer BSIM_BLOCKS_PER_CHIP 	= 2;
//Integer BSIM_PAGES_PER_BLOCK	= 2;
//Integer BSIM_BUSES				= 4;

//use hashed read data (so we don't have to write before read)
//Integer BSIM_USE_HASHED_DATA	= 1; 

/*
interface FlashCtrlUser;
	method Action sendCmd (FlashCmd cmd);
	method Action writeWord (Bit#(128) data, TagT tag);
	method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord ();
	method ActionValue#(TagT) writeDataReq();
	method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus ();
endinterface
interface FlashCtrlVirtexIfc;
	interface FlashCtrlUser user;
	interface Aurora_Pins#(4) aurora;
	interface FCVirtexDebug debug;
endinterface
*/

typedef enum {
	ACCEPT_CMD,
	SEND_DATA,
	WAIT,
	FINISHED_CMD
} EmuState deriving (Bits, Eq);


(* descending_urgency = "forwardReads, forwardReads_1, forwardReads_2, forwardReads_3, forwardReads_4, forwardReads_5, forwardReads_6, forwardReads_7" *) 
(* descending_urgency = "forwardWrDataReq, forwardWrDataReq_1, forwardWrDataReq_2, forwardWrDataReq_3, forwardWrDataReq_4, forwardWrDataReq_5, forwardWrDataReq_6, forwardWrDataReq_7" *)
(* descending_urgency = "forwardAck, forwardAck_1, forwardAck_2, forwardAck_3, forwardAck_4, forwardAck_5, forwardAck_6, forwardAck_7" *)
module mkFlashEmu(FlashCtrlVirtexIfc);

	//FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(16); //should not have back pressure
	//FIFO#(Tuple2#(Bit#(128), TagT)) wrDataQ <- mkSizedFIFO(16); //TODO size?

	//Reg#(EmuState) state <- mkReg(SEND_DATA);
	//Reg#(Bit#(32)) rdataCnt <- mkReg(0);
	//Reg#(Bit#(32)) waitCnt <- mkReg(fromInteger(waitCycles));

	//Flash bus models
	Vector#(NUM_BUSES, FlashBusModelIfc) flashBuses <- replicateM(mkFlashBusModel());

	RegFile#(TagT, FlashCmd) tagTable <- mkRegFileFull();
	FIFO#(Tuple2#(Bit#(WordSz), TagT)) rdDataQ <- mkSizedFIFO(16); //TODO size?
	FIFO#(TagT) wrDataReqQ <- mkSizedFIFO(16);
	FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkSizedFIFO(16);
	
	//handle reads, acks, writedataReq
	for (Integer b=0; b < valueOf(NUM_BUSES); b=b+1) begin
		rule forwardReads;
			let rd <- flashBuses[b].readWord();
			rdDataQ.enq(rd);
		endrule

		rule forwardWrDataReq;
			let req <- flashBuses[b].writeDataReq();
			wrDataReqQ.enq(req);
		endrule
	
		rule forwardAck;
			let ack <- flashBuses[b].ackStatus();
			ackQ.enq(ack);
		endrule
	end


	interface FlashCtrlUser user;
		method Action sendCmd (FlashCmd cmd);
			tagTable.upd(cmd.tag, cmd);
			flashBuses[cmd.bus].sendCmd(cmd);
			$display("FlashEmu: received cmd: tag=%d, bus=%d, chip=%d, blk=%d, page=%d", cmd.tag, cmd.bus, cmd.chip, cmd.block, cmd.page);
		endmethod

		method Action writeWord (Tuple2#(Bit#(WordSz), TagT) taggedData);
			FlashCmd cmd = tagTable.sub(tpl_2(taggedData));
			flashBuses[cmd.tag].writeWord(taggedData);
		endmethod
			
		method ActionValue#(Tuple2#(Bit#(WordSz), TagT)) readWord ();
			rdDataQ.deq();
			return rdDataQ.first();
		endmethod

		method ActionValue#(TagT) writeDataReq();
			wrDataReqQ.deq();
			return wrDataReqQ.first();
		endmethod

		method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus();
			ackQ.deq();
			return ackQ.first();
		endmethod
	endinterface

	interface FCVirtexDebug debug = ?;

	interface Aurora_Pins aurora = ?;

endmodule



	/*
	rule doHandleCmd if (state==SEND_DATA);
		FlashCmd cmd = flashCmdQ.first;
		Bit#(16) data0 = truncate(rdataCnt);
		Bit#(16) data1 = zeroExtend(cmd.tag);
		Bit#(16) data2 = zeroExtend(cmd.bus);
		Bit#(16) data3 = zeroExtend(cmd.chip);
		Bit#(16) data4 = zeroExtend(cmd.block);
		Bit#(16) data5 = zeroExtend(cmd.page);
		Bit#(128) rData = zeroExtend({data0, data1, data2, data3, data4, data5});
		rdDataQ.enq(tuple2(rData, cmd.tag));
		$display("@%t: Flash Emu enqueued cnt=%d, tag=%x, data=%x", $time, rdataCnt, cmd.tag, rData);

		if (rdataCnt == fromInteger(pageSizeUser/16)-1) begin
			state <= FINISHED_CMD;
			rdataCnt <= 0;
		end
		else begin
			state <= WAIT;
			rdataCnt <= rdataCnt + 1;
		end

	endrule

	rule doWait if (state==WAIT);
		if (waitCnt == 0) begin
			state <= SEND_DATA;
			waitCnt <= fromInteger(waitCycles);
		end
		else begin
			waitCnt <= waitCnt - 1;
		end
	endrule


	rule doFinish if (state==FINISHED_CMD);
		flashCmdQ.deq;
		let cmd = flashCmdQ.first;
		state <= SEND_DATA;
		$display("@%t: Flash Emu: finished command tag=%x, bus=%x, chip=%x, block=%x, page=%x", $time,
			cmd.tag, cmd.bus, cmd.chip, cmd.block, cmd.page);	
	endrule
	*/
