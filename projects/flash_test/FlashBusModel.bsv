import FIFOF::*;
import FIFO::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;

import ControllerTypes::*;

//For BSIM: use hashed read data (so we don't have to write before read)
typedef 1 BSIM_USE_HASHED_DATA; 

typedef enum {
	ST_CMD,
	ST_OP_DELAY,
	ST_BUS_RESERVE,
	ST_WRITE_BUS_RESERVE,
	ST_WRITE_REQ,
	ST_ERASE,
	ST_ERROR,
	ST_READ_TRANSFER,
	ST_WRITE_DATA,
	ST_WRITE_ACK,
	ST_READ_DATA
} ChipState deriving (Bits, Eq);

function Bit#(128) getDataHash (Bit#(16) dataCnt, Bit#(8) page, Bit#(16) block, ChipT chip, BusT bus);
	Bit#(8) dataCntTrim = truncate(dataCnt << 3);
	Bit#(8) blockTrim = truncate(block);
	Bit#(8) chipTrim = zeroExtend(chip);
	Bit#(8) busTrim = zeroExtend(bus);

	Vector#(8, Bit#(16)) dataAggr = newVector();
	for (Integer i=7; i >= 0; i=i-1) begin
		Bit#(8) dataHi = truncate(dataCntTrim + fromInteger(i) + 8'hA0 + (blockTrim<<4)+ (chipTrim<<2) + (busTrim<<6));
		Bit#(8) dataLow = truncate( (~dataHi) + blockTrim );
		dataAggr[i] = {dataHi, dataLow};
	end
	return pack(dataAggr);
endfunction


interface FlashBusModelIfc;
	method Action sendCmd(FlashCmd cmd);
	method Action writeWord (Tuple2#(Bit#(128), TagT) taggedData);
	method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord ();
	method ActionValue#(TagT) writeDataReq();
	method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus ();
endinterface

(* descending_urgency = "chipWriteAck, chipWriteAck_1, chipWriteAck_2, chipWriteAck_3, chipWriteAck_4, chipWriteAck_5, chipWriteAck_6, chipWriteAck_7" *) 
module mkFlashBusModel(FlashBusModelIfc);
	
	Integer t_Read = 75; //read delay
	Integer t_Write = 500; //write delay
	Integer t_Erase = 1500; //erase delay
	Integer readBurstDelay = 8; //read bursts 128 bits every 8 cycles //TODO adjust this 

	Integer chipsPerBus = valueOf(ChipsPerBus);
	Reg#(Bit#(128)) flashArr[chipsPerBus][blocksPerCE][pagesPerBlock][pageWords];
	
	//enq commands to each chip (emulated sb)
	Vector#(ChipsPerBus, FIFO#(FlashCmd)) flashChipCmdQs <- replicateM(mkSizedFIFO(16));
	FIFO#(Tuple2#(Bit#(WordSz), TagT)) busReadQ <- mkFIFO();
	Reg#(Bool) busInUse <- mkReg(False);
	Reg#(ChipT) busReservedChipIdx <- mkReg(0);
	FIFO#(Tuple2#(TagT, StatusT)) ackQ <- mkSizedFIFO(valueOf(NumTags));
	FIFOF#(TagT) writeReqQ <- mkSizedFIFOF(3); 
	//2 page buffer
	FIFOF#(Tuple2#(Bit#(WordSz), TagT)) writeBuffer <- mkSizedFIFOF(pageSizeUser*2+1);
	//simulate the round robin sb using a counter
	Reg#(Bit#(16)) chipSel <- mkReg(0);
	
	rule checkWriteReqFull if (!writeReqQ.notFull);
		$display("**ERROR: FlashBusModel: Write data request buffer should never be full");
	endrule

	rule checkWriteBufferFull if (!writeBuffer.notFull);
		$display("**ERROR: FlashBusModel: Write buffer should never be full");
	endrule

	rule chipSelIncr;
		if (chipSel == fromInteger(chipsPerBus-1)) begin
			chipSel <= 0;
		end
		else begin
			chipSel <= chipSel + 1;
		end
		//$display("chipSel=%d", chipSel);
	endrule


	for (Integer c=0; c<chipsPerBus; c=c+1) begin
		Reg#(ChipState) chipSt <- mkReg(ST_CMD);
		Reg#(ChipState) chipStReturn <- mkReg(ST_CMD);
		Reg#(Bit#(32)) delayCnt <- mkReg(0);
		Reg#(Bit#(16)) readDlyCnt <- mkReg(fromInteger(readBurstDelay));
		Reg#(Bit#(16)) readBurstCnt <- mkReg(0);
		Reg#(Bit#(16)) writeBurstCnt <-  mkReg(0);
		Reg#(Bit#(4)) writeDataReqIssued <- mkReg(0);
		Reg#(Bit#(4)) writeDataReqProcessed <- mkReg(0);

		rule chipHandleCmd if (chipSt==ST_CMD);
			let cmd = flashChipCmdQs[c].first;
			if (cmd.page > fromInteger(pagesPerBlock-1)) begin
				$display("**ERROR: cmd page exceeds simulation pages available. Sim pages=%d", pagesPerBlock);
				chipSt <= ST_ERROR;
			end
			else if (cmd.block > fromInteger(blocksPerCE-1)) begin
				$display("**ERROR: cmd block exceeds simulation blocks available. Sim blocks=%d", blocksPerCE);
				chipSt <= ST_ERROR;
			end
			else begin
				case (cmd.op) 
					READ_PAGE: 
						begin
							delayCnt <= fromInteger(t_Read);
							chipSt <= ST_OP_DELAY;
							chipStReturn <= ST_BUS_RESERVE;
							$display("%m FlashBus chip[%d] starting READ cmd...", cmd.chip);
						end
					WRITE_PAGE:
						begin
							chipSt <= ST_WRITE_REQ;
							delayCnt <= fromInteger(t_Write);
							$display("%m FlashBus chip[%d] starting WRITE cmd...", cmd.chip);
						end
					ERASE_BLOCK:
						begin
							chipSt <= ST_OP_DELAY;
							chipStReturn <= ST_ERASE;
							delayCnt <= fromInteger(t_Erase);
							$display("%m FlashBus chip[%d] starting ERASE cmd...", cmd.chip);
						end
					default: 
						begin
							chipSt <= ST_ERROR;//throw error TODO
							$display("**ERROR: FlashBusModel invalid op");
						end
				endcase
			end
		endrule

		//wait rule (tRead, tWrite, tErase)
		rule chipOpDelay if (chipSt==ST_OP_DELAY);
			if (delayCnt==0) begin
				chipSt <= chipStReturn;
				$display("FlashBus chip[%d] op delay done", c);
			end
			else begin
				delayCnt <= delayCnt-1;
			end
		endrule

		//READ: take control of bus
		rule chipReadBusReserve if (chipSt==ST_BUS_RESERVE && !busInUse && chipSel==fromInteger(c));
			busReservedChipIdx <= fromInteger(c);
			busInUse <= True;
			chipSt <= ST_READ_TRANSFER;
			$display("FlashBus reserved bus for chip = %d", c);
		endrule

		//READ: transfer read only if selected and bus is reserved
		rule chipReadTransfer if (chipSt==ST_READ_TRANSFER && busInUse && busReservedChipIdx==fromInteger(c));
			let cmd = flashChipCmdQs[c].first;
			//transfer 128bits every 8 cycles (to emulate flash behavior)
			if (readDlyCnt > 0) begin
				readDlyCnt <= readDlyCnt - 1;
			end
			else begin
				readDlyCnt <= fromInteger(readBurstDelay);
				if (valueOf(BSIM_USE_HASHED_DATA)==1) begin
					let dataHashed = getDataHash (readBurstCnt, cmd.page, cmd.block, cmd.chip, cmd.bus);
					busReadQ.enq(tuple2(dataHashed, cmd.tag));
				end
				else begin
					busReadQ.enq(tuple2(flashArr[c][cmd.block][cmd.page][readBurstCnt], cmd.tag));
				end
				if (readBurstCnt==fromInteger(pageWords-1)) begin
					flashChipCmdQs[c].deq;
					readBurstCnt <= 0;
					chipSt <= ST_CMD;
					busInUse <= False;
					$display("%m FlashBus chip[%d] done read", cmd.chip);
				end
				else begin
					readBurstCnt <= readBurstCnt + 1;
				end
			end

		endrule

		//write request for data; when selected and have enough page buffers
		rule chipWriteDataReq if (chipSt==ST_WRITE_REQ && chipSel==fromInteger(c) 
											&& (writeDataReqIssued - writeDataReqProcessed) < 2);
			let cmd = flashChipCmdQs[c].first;
			writeReqQ.enq(cmd.tag);
			chipSt <= ST_WRITE_BUS_RESERVE;
			writeDataReqIssued <= writeDataReqIssued + 1;
		endrule

		//write data reserve bus
		rule chipWriteBusReserve if (chipSt==ST_WRITE_BUS_RESERVE && !busInUse 
												&& flashChipCmdQs[c].first.tag==tpl_2(writeBuffer.first)
												&& chipSel==fromInteger(c)	);
			busReservedChipIdx <= fromInteger(c);
			busInUse <= True;
			chipSt <= ST_WRITE_DATA;
		endrule
	
		//write data if we have received the whole page
		rule chipWriteData if (chipSt==ST_WRITE_DATA && busInUse && busReservedChipIdx==fromInteger(c));
			let cmd = flashChipCmdQs[c].first;
			if (cmd.tag==tpl_2(writeBuffer.first)) begin
				flashArr[c][cmd.block][cmd.page][writeBurstCnt] <= tpl_1(writeBuffer.first);
				writeBuffer.deq;
			end
			else begin
				$display("**ERROR: FlashBusModel incorrect burst received. Cmd tag=%d, burst tag=%d",
							flashChipCmdQs[c].first.tag, tpl_2(writeBuffer.first));
			end

			if (writeBurstCnt==fromInteger(pageSizeUser-1)) begin //done transfer
				//wait tWrite
				chipSt <= ST_OP_DELAY;
				chipStReturn <= ST_WRITE_ACK;
				writeDataReqProcessed <= writeDataReqProcessed + 1;
				busInUse <= False;
				writeBurstCnt <= 0;
			end
			else begin
				writeBurstCnt <= writeBurstCnt + 1;
			end
		endrule

		//write ack
		rule chipWriteAck if (chipSt==ST_WRITE_ACK);
			let cmd = flashChipCmdQs[c].first;
			flashChipCmdQs[c].deq;
			ackQ.enq(tuple2(cmd.tag, WRITE_DONE));
			chipSt <= ST_CMD;
		endrule

		//erase
		rule chipErase if (chipSt==ST_ERASE);
			//TODO
			/*
			let cmd = flashChipCmdQs[c].first;
			flashChipCmdQs[c].deq;
			//erase entire block
			for (Integer p=0; p<pagesPerBlock; p=p+1) begin 
				for (Integer w=0; w<pageSizeUser; w=w+1) begin
					flashArr[c][cmd.block][p][w] <= -1; //FFF..
				end
			end
			ackQ.enq(tuple2(cmd.tag, ERASE_DONE));
			chipSt <= ST_CMD;
			*/
		endrule

	end //chipsPerBus

	method Action sendCmd(FlashCmd cmd);
		flashChipCmdQs[cmd.chip].enq(cmd);
	endmethod

	method Action writeWord (Tuple2#(Bit#(128), TagT) taggedData);
		writeBuffer.enq(taggedData);
	endmethod

	method ActionValue#(Tuple2#(Bit#(128), TagT)) readWord ();
		busReadQ.deq;
		return busReadQ.first;
	endmethod

	method ActionValue#(TagT) writeDataReq();
		writeReqQ.deq;
		return writeReqQ.first;
	endmethod

	method ActionValue#(Tuple2#(TagT, StatusT)) ackStatus ();
		ackQ.deq;
		return ackQ.first;
	endmethod



endmodule
