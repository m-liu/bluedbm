// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import FIFOF::*;
import FIFO::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import Vector::*;

import PortalMemory::*;
import MemTypes::*;
import MemreadEngine::*;
import MemwriteEngine::*;
import Pipe::*;

import AuroraGearbox::*;
import AuroraImportFmc1::*;
//import PageCache::*;
import DMABurstHelper::*;
import ChipscopeWrapper::*;
import ControllerTypes::*;
import FlashCtrlVirtex::*;
import FlashTBVirtex::*;


typedef TAdd#(8192,64) PageBytes;
//typedef 16 WordBytes;
typedef 16 WordBytes;
typedef TMul#(8,WordBytes) WordSz;

interface FlashRequest;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action returnReadHostBuffer(Bit#(32) idx);
	method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
	method Action sendTest(Bit#(32) dataHi, Bit#(32) dataLo);
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);

	method Action start(Bit#(32) dummy);
endinterface

interface FlashIndication;
	method Action readDone(Bit#(32) rbuf, Bit#(32) tag);
	method Action writeDone(Bit#(32) tag);
	method Action hexDump(Bit#(32) data);
	method Action reqFlashCmd(Bit#(32) inq, Bit#(32) count);
endinterface

interface MainIfc;
	interface FlashRequest request;
	interface ObjectReadClient#(WordSz) dmaReadClient;
	interface ObjectWriteClient#(WordSz) dmaWriteClient;

	interface Aurora_Pins#(4) aurora_fmc1;
	interface Aurora_Clock_Pins aurora_clk_fmc1;
endinterface

//typedef enum {Read,Write,Erase} CmdType deriving (Bits,Eq);
//typedef struct { Bit#(5) channel; Bit#(5) chip; Bit#(8) block; Bit#(8) page; CmdType cmd; Bit#(8) tag; Bit#(8) bufidx;} FlashCmd deriving (Bits,Eq);

module mkMain#(FlashIndication indication, Clock clk250, Reset rst250)(MainIfc);
	
	//Integer pageBytes = valueOf(PageBytes);
	//Integer wordBytes = valueOf(WordBytes); 
	//Integer pageWords = pageBytes/wordBytes;

	Reg#(Bool) started <- mkReg(False);
	Reg#(Bit#(64)) testIn <- mkReg(0);

	GtxClockImportIfc gtx_clk_fmc1 <- mkGtxClockImport;
	FlashCtrlVirtexIfc flashCtrl <- mkFlashCtrlVirtex(gtx_clk_fmc1.gtx_clk_p_ifc, gtx_clk_fmc1.gtx_clk_n_ifc, clk250);
	TbIfc flashTb <- mkFlashTBVirtex();
	CSDebugIfc csDebug <- mkChipscopeDebug();

	//connect tb to flashCtrl
	mkConnection(flashCtrl.user.sendCmd, flashTb.driver.sendCmdTb);
	mkConnection(flashCtrl.user.writeWord, flashTb.driver.writeWordTb);
	mkConnection(flashCtrl.user.readWord, flashTb.driver.readWordTb);
	mkConnection(flashCtrl.user.writeDataReq, flashTb.driver.writeDataReqTb);
	mkConnection(flashCtrl.user.ackStatus, flashTb.driver.ackStatusTb);

	
	rule setDebug;
		DataIfc recPacketData = tpl_1(flashCtrl.debug.debugRecPacket);
		Bit#(128) recPacketLo = recPacketData[127:0];
		Bit#(128) recPacketHi = zeroExtend(recPacketData[239:128]);

		csDebug.ila.setDebug0(flashTb.debug.debugRdata);
		csDebug.ila.setDebug1(zeroExtend(tpl_1(flashTb.debug.debugTagRdCnt))); //tag
		csDebug.ila.setDebug2(zeroExtend(tpl_2(flashTb.debug.debugTagRdCnt))); //rdata cnt
		csDebug.ila.setDebug3(zeroExtend(flashTb.debug.debugCmdCnt));
		csDebug.ila.setDebug4(zeroExtend(flashTb.debug.debugErrCnt));
		csDebug.ila.setDebug5(zeroExtend(flashTb.debug.debugState));
		csDebug.ila.setDebug6(zeroExtend(flashTb.debug.debugLatencyCnt));
		csDebug.ila.setDebug7(zeroExtend(pack(tpl_2(flashCtrl.debug.debugRecPacket)))); //packet type
		csDebug.ila.setDebug8(recPacketHi);
		csDebug.ila.setDebug9(recPacketLo);
		csDebug.ila.setDebug10(0);
	endrule


	//echo VIN/VOUT
	rule echoVin;
		if (started) begin
			csDebug.vio.setDebugVin(testIn);
		end
		else begin
			csDebug.vio.setDebugVin(csDebug.vio.getDebugVout);
		end
	endrule
	

	rule setVin;
		//flashTb.debug.debugVin(testIn);
		if (started) begin
			flashTb.debug.debugVin(testIn);
		end
		else begin
			flashTb.debug.debugVin(csDebug.vio.getDebugVout);
		end
	endrule

   MemreadEngineV#(WordSz,1,1)  re <- mkMemreadEngine;
   MemwriteEngineV#(WordSz,1,1) we <- mkMemwriteEngine;

   //PageCacheIfc#(3, 128) pageCache <- mkPageCache; // 8 pages

	DMAWriteEngineIfc#(WordSz) dmaWriter <- mkDmaWriteEngine(we.writeServers[0], we.dataPipes[0]);
	/*
	rule dmaWriteData;
		let r <- pageCache.readWord;
		let d = tpl_1(r);
		let t = tpl_2(r);
		//$display ( "reading %d %d", d[31:0], t );
		dmaWriter.write(d,t);
	endrule
	rule dmaWriteDone;
		let r <- dmaWriter.done;
		let rbuf = tpl_1(r);
		let tag = tpl_2(r);
		indication.readDone(zeroExtend(rbuf), zeroExtend(tag));
	endrule
	*/

	DMAReadEngineIfc#(WordSz) dmaReader <- mkDmaReadEngine(re.readServers[0], re.dataPipes[0]);
	/*
	rule dmaReadDone;
		let bufidx <- dmaReader.done;
		indication.writeDone(zeroExtend(bufidx));
	endrule
	rule dmaReadData;
		let r <- dmaReader.read;
		let d = tpl_1(r);
		let t = tpl_2(r);
		pageCache.writeWord(d,t);
		//$display( "writing %d %d", d[31:0], t );
	endrule
	*/

	
	Reg#(Bit#(32)) curReqsInQ <- mkReg(0);
	Reg#(Bit#(32)) numReqsRequested <- mkReg(0);
	/*
	rule driveNewReqs(started&& curReqsInQ + numReqsRequested < 64 );
		numReqsRequested <= numReqsRequested + 64;
		indication.reqFlashCmd(curReqsInQ, 64);
	endrule

	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(128);
	rule driveFlashCmd (started);
		let cmd = flashCmdQ.first;
		
		if ( cmd.cmd == Read ) begin
			curReqsInQ <= curReqsInQ -1;

			flashCmdQ.deq;
			dmaWriter.startWrite(cmd.tag, fromInteger(pageWords));

			pageCache.readPage( zeroExtend(cmd.page), cmd.tag);
			//$display( "starting page read %d at tag %d in buffer %", cmd.page, cmd.tag, freeidx );
		end else if ( cmd.cmd == Write ) begin
			curReqsInQ <= curReqsInQ -1;

			flashCmdQ.deq;
			dmaReader.startRead(cmd.bufidx, fromInteger(pageWords));

			pageCache.writePage(zeroExtend(cmd.page), cmd.bufidx);
			//$display( "starting page write page %d at tag %d", cmd.page, cmd.tag );
		end
	endrule

	//(* mutually_exclusive = "startFlushDma, driveFlashCmd" *)
   */

   interface FlashRequest request;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
		/*
		CmdType cmd = Read;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: truncate(page),
			cmd: cmd,
			bufidx: ?,
			tag: truncate(tag)};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
		*/
			
	endmethod
   method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);
		/*
		CmdType cmd = Write;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: truncate(page),
			cmd: cmd,
			bufidx: truncate(bufidx),
			tag: ?};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
		*/
	endmethod
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
		/*
		CmdType cmd = Erase;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: 0,
			cmd: cmd,
			tag: 0};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
		*/
	endmethod
	method Action sendTest(Bit#(32) dataHi, Bit#(32) dataLo);
		testIn <= {dataHi, dataLo};
	endmethod
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		dmaReader.addBuffer(truncate(idx), offset, pointer);
	endmethod
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		dmaWriter.addBuffer(offset, pointer);
	endmethod
	method Action returnReadHostBuffer(Bit#(32) idx);
		dmaWriter.returnFreeBuf(truncate(idx));
	endmethod
	method Action start(Bit#(32) dummy);
		started <= True;
	endmethod
   endinterface

   interface ObjectReadClient dmaReadClient = re.dmaClient;
   interface ObjectWriteClient dmaWriteClient = we.dmaClient;

   interface Aurora_Pins aurora_fmc1 = flashCtrl.aurora;
   interface Aurora_Clock_Pins aurora_clk_fmc1 = gtx_clk_fmc1.aurora_clk;
endmodule

