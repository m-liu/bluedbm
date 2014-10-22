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
import FlashEmu::*;
//import FlashTBVirtex::*;


//typedef TAdd#(8192,64) PageBytes;
//typedef 16 WordBytes;
//typedef 16 WordBytes;
//typedef TMul#(8,WordBytes) WordSz;

interface FlashRequest;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action returnReadHostBuffer(Bit#(32) idx);
	method Action writePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
	method Action erasePage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block);
	method Action sendTest(Bit#(32) data);
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
	//Integer pageWords = pageSizeUser/wordBytes;

	Integer numDmaChannels = valueOf(NumDmaChannels);

	Reg#(Bool) started <- mkReg(False);
	Reg#(Bit#(64)) testIn <- mkReg(0);

	Reg#(Bit#(16)) debugCmdTag <- mkReg(0);
	Reg#(Bit#(16)) debugCmdBus <- mkReg(0);
	Reg#(Bit#(16)) debugCmdChip <- mkReg(0);
	Reg#(Bit#(16)) debugCmdBlk <- mkReg(0);
	Reg#(Bit#(16)) debugCmdPage <- mkReg(0);
	Reg#(Bit#(16)) debugFreeBuf <- mkReg(0);
	Reg#(Bit#(16)) debugDmaWrInd <- mkReg(0);
	Reg#(Bit#(64)) debugRCnt <- mkReg(0);
	Reg#(Tuple2#(Bit#(128), TagT)) debugRd <- mkRegU();
	Reg#(Bit#(64)) cmdCnt <- mkReg(0);

	GtxClockImportIfc gtx_clk_fmc1 <- mkGtxClockImport;
	`ifdef BSIM
		FlashCtrlVirtexIfc flashCtrl <- mkFlashEmu();
	`else
		FlashCtrlVirtexIfc flashCtrl <- mkFlashCtrlVirtex(gtx_clk_fmc1.gtx_clk_p_ifc, gtx_clk_fmc1.gtx_clk_n_ifc, clk250);
	`endif

	//TbIfc flashTb <- mkFlashTBVirtex();
	`ifndef BSIM
		CSDebugIfc csDebug <- mkChipscopeDebug();
	`endif

	//connect tb to flashCtrl
	//mkConnection(flashCtrl.user.sendCmd, flashTb.driver.sendCmdTb);
	//mkConnection(flashCtrl.user.writeWord, flashTb.driver.writeWordTb);
	//mkConnection(flashCtrl.user.readWord, flashTb.driver.readWordTb);
	//mkConnection(flashCtrl.user.writeDataReq, flashTb.driver.writeDataReqTb);
	//mkConnection(flashCtrl.user.ackStatus, flashTb.driver.ackStatusTb);



	//echo VIN/VOUT
	/*
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
	*/

	//distribute read data to the dma writers
	//Tag to Dma Writer Index look up table
	Vector#(NumTags, Reg#(Bit#(TLog#(NumDmaChannels)))) tag2DmaIndTable <- replicateM(mkRegU());
	Vector#(NumDmaChannels, FIFO#(Tuple2#(Bit#(WordSz), TagT))) dmaWriterBufs <- replicateM(mkSizedFIFO(16)); //TODO what's a good size here? BRAM FIFO? Maybe make it page sized and pipeline the next rule
	FIFO#(Bit#(TLog#(NumDmaChannels))) distrIndPipeQ <- mkFIFO();
	FIFO#(Tuple2#(Bit#(128), TagT)) distrDataPipeQ <- mkFIFO();

	rule distrToDMAWriter;
		let rd <- flashCtrl.user.readWord();
		let data = tpl_1(rd);
		let tag = tpl_2(rd);
		let ind = tag2DmaIndTable[tag];
		distrIndPipeQ.enq(ind);
		distrDataPipeQ.enq(rd);
		$display("main.bsv: read rd = %x, tag = %d, dmaInd=%d", data, tag, ind);
	endrule

	rule distrToDMAWriter2;
		let ind = distrIndPipeQ.first;
		distrIndPipeQ.deq;
		let rd = distrDataPipeQ.first;
		distrDataPipeQ.deq;
		dmaWriterBufs[ind].enq(rd);
		debugRd <= rd;
		debugRCnt <= debugRCnt + 1;
	endrule



	/////////////// DMA Writer with flash controller //////////////////////////////////////
	MemwriteEngineV#(WordSz,1,NumDmaChannels) we <- mkMemwriteEngine;
	Vector#(NumDmaChannels, FreeBufferClientIfc) dmaWriterFreeBufferClient;
	Vector#(NumDmaChannels, DMAWriteEngineIfc#(WordSz)) dmaWriters;
	for ( Integer wIdx = 0; wIdx < numDmaChannels; wIdx = wIdx + 1 ) begin
		//let pageCache = pageCaches[wIdx];
		let dmaWrBuf = dmaWriterBufs[wIdx];

		DMAWriteEngineIfc#(WordSz) dmaWriter <- mkDmaWriteEngine(we.writeServers[wIdx], we.dataPipes[wIdx]);
		dmaWriters[wIdx] = dmaWriter;
		rule dmaWriteData;
			//let r <- pageCache.readWord;
			let r = dmaWrBuf.first;
			dmaWrBuf.deq();
			let d = tpl_1(r);
			let t = tpl_2(r);
			//$display ( "reading %d %d @ %d", d[31:0], t, wIdx );
			dmaWriter.write(d,zeroExtend(t));
		endrule

		dmaWriterFreeBufferClient[wIdx] = dmaWriter.bufClient;
	end
	FreeBufferManagerIfc writeBufMan <- mkFreeBufferManager(dmaWriterFreeBufferClient);
	rule dmaWriteDoneCheck;
		let r <- writeBufMan.done;
		let rbuf = tpl_1(r);
		let tag = tpl_2(r);
		indication.readDone(zeroExtend(rbuf), zeroExtend(tag));
		
	endrule

	//TODO: DMA reader 

	Vector#(NumDmaChannels, DMAReadEngineIfc#(WordSz)) dmaReaders;
	MemreadEngineV#(WordSz,1,NumDmaChannels)  re <- mkMemreadEngine;
	/*
	for ( Integer rIdx = 0; rIdx < numDmaChannels; rIdx = rIdx + 1 ) begin
		let pageCache = pageCaches[rIdx];

		DMAReadEngineIfc#(WordSz) dmaReader <- mkDmaReadEngine(re.readServers[rIdx], re.dataPipes[rIdx]);
		dmaReaders[rIdx] = dmaReader;

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
	end // for loop
	*/

	Reg#(Bit#(32)) curReqsInQ <- mkReg(0);
	Reg#(Bit#(32)) numReqsRequested <- mkReg(0);
	rule driveNewReqs(started&& curReqsInQ + numReqsRequested < fromInteger(valueOf(NumTags))-32 );
		numReqsRequested <= numReqsRequested + 32;
		indication.reqFlashCmd(curReqsInQ, 32);
		$display( "Requesting more flash commands" );
	endrule


	FIFO#(FlashCmd) flashCmdQ <- mkSizedFIFO(valueOf(NumTags));
	rule driveFlashCmd (started);
		let cmd = flashCmdQ.first;
		flashCmdQ.deq;

		//debug
		debugCmdTag <= zeroExtend(cmd.tag);
		debugCmdBus <= zeroExtend(cmd.bus);
		debugCmdChip <=zeroExtend(cmd.chip);
		debugCmdBlk <= zeroExtend(cmd.block);
		debugCmdPage <=zeroExtend(cmd.page);
		cmdCnt <= cmdCnt + 1;
		
		if ( cmd.op == READ_PAGE ) begin
			curReqsInQ <= curReqsInQ -1;
			let freebuf <- writeBufMan.getFreeBufIdx;
			debugFreeBuf <= zeroExtend(freebuf);
			// temporary stuff
		
			Bit#(TLog#(NumDmaChannels)) dmaInd = truncate(cmd.bus);
			let dmaWriter = dmaWriters[dmaInd];
			//let pageCache = pageCaches[cmd.bus];

			//FIXME: tag width
			$display( "starting page read %d at tag %d in buffer %d, bus/dmawriterInd=%d", cmd.page, cmd.tag, freebuf, dmaInd);
			dmaWriter.startWrite(zeroExtend(cmd.tag), freebuf, fromInteger(pageWords));

			//pageCache.readPage( zeroExtend(cmd.page), cmd.tag);
		end else if ( cmd.op == WRITE_PAGE ) begin
			/*
			curReqsInQ <= curReqsInQ -1;

			let dmaReader = dmaReaders[cmd.channel];
			let pageCache = pageCaches[cmd.channel];

			dmaReader.startRead(cmd.bufidx, fromInteger(pageWords));

			pageCache.writePage(zeroExtend(cmd.page), cmd.bufidx);
			$display( "starting page write page %d at tag %d", cmd.page, cmd.tag );
			*/
		end
		
		//store tag and dmaWrInd in look up table
		Bit#(TLog#(NumDmaChannels)) dmaWrInd = truncate(cmd.bus);
		tag2DmaIndTable[cmd.tag] <= dmaWrInd;

		debugDmaWrInd <= zeroExtend(dmaWrInd);

		//forward command to flash controller
		flashCtrl.user.sendCmd(cmd);

	endrule


	`ifndef BSIM
	rule setDebug;
		DataIfc recPacketData = tpl_1(flashCtrl.debug.debugRecPacket);
		Bit#(128) recPacketLo = recPacketData[127:0];
		Bit#(128) recPacketHi = zeroExtend(recPacketData[239:128]);

		/*
		csDebug.ila.setDebug0(flashTb.debug.debugRdata);
		csDebug.ila.setDebug1(zeroExtend(tpl_1(flashTb.debug.debugTagRdCnt))); //tag
		csDebug.ila.setDebug2(zeroExtend(tpl_2(flashTb.debug.debugTagRdCnt))); //rdata cnt
		csDebug.ila.setDebug3(zeroExtend(flashTb.debug.debugCmdCnt));
		csDebug.ila.setDebug4(zeroExtend(flashTb.debug.debugErrCnt));
		csDebug.ila.setDebug5(zeroExtend(flashTb.debug.debugState));
		csDebug.ila.setDebug6(zeroExtend(flashTb.debug.debugLatencyCnt));
		*/
	   
		csDebug.ila.setDebug0(tpl_1(debugRd)); //data
		csDebug.ila.setDebug1(zeroExtend(tpl_2(debugRd))); //tag
		csDebug.ila.setDebug2(zeroExtend(cmdCnt)); //cmdCnt
		csDebug.ila.setDebug3(zeroExtend({debugCmdTag, debugCmdBus, debugCmdChip, debugCmdBlk, debugCmdPage})); //addr
		csDebug.ila.setDebug4(zeroExtend({debugFreeBuf, debugDmaWrInd})); //dma related

		csDebug.ila.setDebug5(zeroExtend({dmaWriters[0].getDebugWrRef, dmaWriters[0].getDebugBurstOff})); //dma addr
		csDebug.ila.setDebug6(dmaWriters[0].getDebugDmaData); //dma data bursts
		csDebug.ila.setDebug7(zeroExtend({dmaWriters[0].getDebugWrDoneRbuf, dmaWriters[0].getDebugWrTag})); //dma done signals
		//csDebug.ila.setDebug8(zeroExtend(pack(tpl_2(flashCtrl.debug.debugRecPacket)))); //packet type
		csDebug.ila.setDebug8(zeroExtend(debugRCnt)); //global read burst cnt
		csDebug.ila.setDebug9(recPacketHi);
		csDebug.ila.setDebug10(recPacketLo);
	endrule
	

	`endif



   interface FlashRequest request;
	method Action readPage(Bit#(32) channel, Bit#(32) chip, Bit#(32) block, Bit#(32) page, Bit#(32) tag);
		
		//CmdType cmd = Read;
		FlashCmd fcmd = FlashCmd{
			tag: truncate(tag),
			op: READ_PAGE,
			bus: truncate(channel),
			chip: truncate(chip),
			block: truncate(block),
			page: truncate(page)


			//bufidx: ?, TODO what does this do?
			};

		flashCmdQ.enq(fcmd);
		curReqsInQ <= curReqsInQ +1;
		numReqsRequested <= numReqsRequested - 1;
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
	method Action sendTest(Bit#(32) data);
		testIn <= zeroExtend(data);
	endmethod
	method Action addWriteHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		/*
		for (Integer i = 0; i < numDmaChannels; i = i + 1) begin
			dmaReaders[i].addBuffer(truncate(idx), offset, pointer);
		end
		*/
	endmethod
	method Action addReadHostBuffer(Bit#(32) pointer, Bit#(32) offset, Bit#(32) idx);
		writeBufMan.addBuffer(offset, pointer);
	endmethod
	method Action returnReadHostBuffer(Bit#(32) idx);
		writeBufMan.returnFreeBuf(truncate(idx));
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

