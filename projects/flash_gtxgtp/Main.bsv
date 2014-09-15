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

import Vector::*;

import PortalMemory::*;
import MemTypes::*;
import MemreadEngine::*;
import MemwriteEngine::*;
import Pipe::*;

import AuroraImportFmc1::*;
import PageCache::*;
import DMABurstHelper::*;
import ChipscopeWrapper::*;


typedef TAdd#(8192,64) PageBytes;
//typedef 16 WordBytes;
typedef 16 WordBytes;
typedef TMul#(8,WordBytes) WordSz;

interface FlashRequest;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action returnReadHostBuffer(Bit#(32) idx);
	method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
	method Action sendTest(Bit#(32) data);
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
endinterface

interface FlashIndication;
	method Action readDone(Bit#(32) rbuf, Bit#(32) tag);
	method Action writeDone(Bit#(32) tag);
	method Action hexDump(Bit#(32) data);
endinterface

interface MainIfc;
	interface FlashRequest request;
	interface ObjectReadClient#(WordSz) dmaReadClient;
	interface ObjectWriteClient#(WordSz) dmaWriteClient;

	interface Aurora_Pins#(4) aurora_fmc1;
	interface Aurora_Clock_Pins aurora_clk_fmc1;
endinterface

typedef enum {Read,Write,Erase} CmdType deriving (Bits,Eq);
typedef struct { Bit#(5) channel; Bit#(5) chip; Bit#(8) block; Bit#(8) page; CmdType cmd; Bit#(8) tag; Bit#(8) bufidx;} FlashCmd deriving (Bits,Eq);

module mkMain#(FlashIndication indication, Clock clk250, Reset rst250)(MainIfc);
	
	Integer pageBytes = valueOf(PageBytes);
	Integer wordBytes = valueOf(WordBytes); 
	Integer pageWords = pageBytes/wordBytes;

	GtxClockImportIfc gtx_clk_fmc1 <- mkGtxClockImport;
	AuroraIfc auroraIntra1 <- mkAuroraIntra(gtx_clk_fmc1.gtx_clk_p_ifc, gtx_clk_fmc1.gtx_clk_n_ifc, clk250);
	CSDebugIfc csDebug <- mkChipscopeDebug();

	Reg#(Bit#(128)) latencyCnt <- mkReg(0);
	rule latencyCount;
		latencyCnt <= latencyCnt + 1;
	endrule

	rule setDebug;
		csDebug.ila.setDebug0(latencyCnt);
		csDebug.ila.setDebug1(0);
		csDebug.ila.setDebug2(0);
		csDebug.ila.setDebug3(0);
		csDebug.ila.setDebug4(0);
		csDebug.ila.setDebug5(0);
		csDebug.ila.setDebug6(0);
		csDebug.ila.setDebug7(0);
	endrule

/*
	Reg#(Bit#(16)) curTestData <- mkReg(0);
	rule sendTestData(curTestData < 16);
		auroraIntra1.send(zeroExtend({16'hbd, curTestData}));
		curTestData <= curTestData + 1;
	endrule
	*/
  
	Reg#(Bit#(32)) auroraTestIdx <- mkReg(0);
	
	rule sendAuroraTest(auroraTestIdx > 0);
		auroraIntra1.send(zeroExtend(auroraTestIdx), 7);
		
		auroraTestIdx <= auroraTestIdx - 1;
	endrule
	FIFO#(Bit#(32)) dataQ <- mkSizedFIFO(32);
	rule recvTestData;
		let datao <- auroraIntra1.receive;
		let data = tpl_1(datao);
		let ptype = tpl_2(datao);

		dataQ.enq({2'b0,ptype,data[23:0]});
	endrule
	rule dumpD;
		dataQ.deq;
		let data = dataQ.first;

		if ( data[10:0] == 0 )
			indication.hexDump(truncate(data));
	endrule

	

   MemreadEngineV#(WordSz,1,1)  re <- mkMemreadEngine;
   MemwriteEngineV#(WordSz,1,1) we <- mkMemwriteEngine;

   PageCacheIfc#(3) pageCache <- mkPageCache; // 8 pages

	DMAWriteEngineIfc#(WordSz) dmaWriter <- mkDmaWriteEngine(we.writeServers[0], we.dataPipes[0]);
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

	DMAReadEngineIfc#(WordSz) dmaReader <- mkDmaReadEngine(re.readServers[0], re.dataPipes[0]);
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


	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(32);
	rule driveFlashCmd;
		let cmd = flashCmdQ.first;

		if ( cmd.cmd == Read ) begin
			flashCmdQ.deq;
			dmaWriter.startWrite(cmd.tag, fromInteger(pageWords));

			pageCache.readPage( zeroExtend(cmd.page), cmd.tag);
			//$display( "starting page read %d at tag %d in buffer %", cmd.page, cmd.tag, freeidx );
		end else if ( cmd.cmd == Write ) begin
			flashCmdQ.deq;
			dmaReader.startRead(cmd.bufidx, fromInteger(pageWords));

			pageCache.writePage(zeroExtend(cmd.page), cmd.bufidx);
			//$display( "starting page write page %d at tag %d", cmd.page, cmd.tag );
		end
	endrule

	//(* mutually_exclusive = "startFlushDma, driveFlashCmd" *)
   

   interface FlashRequest request;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);

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

			
	endmethod
   method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) bufidx);
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
	endmethod
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
		CmdType cmd = Erase;
		FlashCmd fcmd = FlashCmd{
			channel: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: 0,
			cmd: cmd,
			tag: 0};

		flashCmdQ.enq(fcmd);
	endmethod
	method Action sendTest(Bit#(32) data);
		auroraTestIdx <= data;
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
   endinterface

   interface ObjectReadClient dmaReadClient = re.dmaClient;
   interface ObjectWriteClient dmaWriteClient = we.dmaClient;

   interface Aurora_Pins aurora_fmc1 = auroraIntra1.aurora;
   interface Aurora_Clock_Pins aurora_clk_fmc1 = gtx_clk_fmc1.aurora_clk;
endmodule

