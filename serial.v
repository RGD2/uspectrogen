// Contains simple byte-based serial controller
// For uploading/downloading hex data and generally
// driving an FPGA design via a serial port

// This runs on the RS232 full-duplex port on the RasPi

// Needs to run internally at 4x the selected baud rate

// Currently assuming 40 MHz main clk

// 40 / 2.5= 16/4 = 5
// 2.5M baud is 'fastest mode'
// subtract 1 for the max count, because it counts from zero, and the last
// will be == to the max count.

`define BAUDMAX 5'd4


module fifo #(
	parameter DATA_WIDTH = 8,
	parameter FIFO_DEPTH = 256, 
	parameter PTR_MSB    = 8,
	parameter ADDR_MSB   = 7
)
(
	input clk,
	input nreset,
	input read_i,
	input write_i,
	input [DATA_WIDTH-1:0] data_i,
	output [DATA_WIDTH-1:0] data_o,
	output fifoFull_o,
	output fifoEmpty_o
);

reg [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
initial memory[0] <= -1; // fill first cell to let Yosys infer a BRAM
reg [PTR_MSB:0] readPtr, writePtr;
wire [ADDR_MSB:0] writeAddr = writePtr[ADDR_MSB:0];
wire [ADDR_MSB:0] readAddr = readPtr[ADDR_MSB:0]; 

always @(posedge clk) begin
	if (~nreset) begin
		readPtr     <= 0;
		writePtr    <= 0;
	end else begin
		if(write_i && ~fifoFull_o)begin
			memory[writeAddr] <= data_i;
			writePtr <= writePtr + 1;
		end
		if(read_i && ~fifoEmpty_o)begin
			data_o <= memory[readAddr];
			readPtr <= readPtr + 1;
		end
	end
end

assign fifoEmpty_o = (writePtr == readPtr) ? 1'b1: 1'b0;
assign fifoFull_o  = ((writePtr[ADDR_MSB:0] == readPtr[ADDR_MSB:0])&(writePtr[PTR_MSB] != readPtr[PTR_MSB])) ? 1'b1 : 1'b0;

endmodule


module serialrx(input clk, rxserialin, output reg newrxstrobe, output reg[7:0] rxbyte);

// #### rx generator

// line always idles high if connected
// 8N1 format only: start bit is always 0, stop always 1.

reg[4:0] brgenctr;
reg[1:0] rxqclk;
reg[1:0] rxclkflg;
wire en_rxqclk; // feedback input to this block -> set high when rx negative edge first arrives to properly synchronise sampling to middle of bits
always @(posedge clk)
begin
    brgenctr <= en_rxqclk ? ((brgenctr == `BAUDMAX) ? 1 : {brgenctr + 1}) : 1;
    rxqclk <= en_rxqclk ? ((brgenctr == 1)? {rxqclk + 2'd1} : rxqclk) : 0; // receive quadrature clk -- idles as 0, on en_rxqclk edge spends only 1 system clk in rxqclk=0
    rxclkflg <= {rxclkflg[0], (rxqclk==2'd3)}; // delay sample time to middle of bit for clearer reception (initially spends nearly no time in state 0 -> start of state 3 is middle.
end
wire rxs = rxclkflg[0] > rxclkflg[1]; // strobe to sample bits

// ### rx byte state machine

reg[1:0] rxed;
reg[3:0] rxctr;
// 0 -> waiting for a run (rx: edge detect, tx: wait for push)
// 1..10 -> running (although start bit should be 0, stop bit should be 1)
// 11 -> push output (rx)

reg[9:0] serialin;

always @(posedge clk)
begin
    rxed <= {rxed[0], rxserialin}; // for edge detection
    // these next are defaults to be overridden depending on rxctr
    // so will implement as registers and not infer latches (must be assigned somehow under all possibilities)
    serialin <= serialin;
    newrxstrobe <= 1'b0;
    rxbyte <= rxbyte;
  casez (rxctr)
  4'd0: rxctr <= (rxed[0] < rxed[1]) ? 4'd1 : 0 ; // synchronises on negative edge of start bit
  4'd11: begin
        rxctr <= 4'd12;
        rxbyte <= serialin[8:1]; // copy data out first -- will be reliably stable next clock.
        end
  4'd12: begin
        rxctr <= 0;
        newrxstrobe <= (~serialin[0])&&(serialin[9]); // newly received strobe -- rxbyte set last clock so will be stable.
        // note start bit should always be 0, and stop bit always 1 -- else byte wasn't received properly.
        end
  default: begin
        rxctr <= rxs ? {rxctr + 1} : rxctr; // advances only on rxs == 1
        serialin <= rxs ? {rxserialin,serialin[9:1]} : serialin; // shift lsb in first
        end
  endcase
end
assign en_rxqclk = (rxctr > 0); // tells baud generator to run - so that it synchronises with incoming data.

endmodule



module serialtx(input clk, resetn, input xmit, input[7:0] txchar, output reg rsout);

// #### tx generator
//reg[9:0] btgenctr; // 19200
reg[4:0] btgenctr; // 500000

reg[1:0] txqclk;
reg[1:0] txclkflg;
wire en_txqclk; // ensures minimum latency when transmitting a new byte
always @(posedge clk)
begin
    btgenctr <= en_txqclk ? ((btgenctr == `BAUDMAX) ? 1 : {btgenctr + 1}) : 1;
    txqclk <= en_txqclk ? ((btgenctr == 1)? {txqclk+1} : txqclk) : 0;
    txclkflg <= {txclkflg[0], (txqclk==2'd1)}; // no delay necessary here
end
wire txs = txclkflg[0] > txclkflg[1]; // strobe to send bits


// ### tx byte state machine
// predefined inputs: xmit txchar
// xmit   : 0 1 1 1 0 
// txchar : x A B C C

reg txbdone; // signal that txbyte has been sent, for handshaking.

wire empty;
wire unloading = ~(en_txqclk||empty);

reg [1:0] ups;
reg fiforead, send;
always @(posedge clk)
begin
    ups <= {ups[0], unloading};
    fiforead <= fiforead ? 1'd0 : (ups[0] > ups[1]); // one byte read strobe per edge here
    send <= fiforead; // delay a cycle for fifo latency
end
// Transmit Request Strobe -> send high one clk to start tx process

// send fifo so we can burst-write multiple bytes
wire full;
wire[7:0] txbyte;
fifo txfifo(
  .clk(clk),
  .nreset(resetn),
  .read_i(fiforead),
  .write_i(xmit&&~full),
  .data_i(txchar),
  .data_o(txbyte),
  .fifoFull_o(full),
  .fifoEmpty_o(empty)
);


reg[3:0] txctr; // to count 10 bits
// txctr is slightly different
// 1 : wait for txs edge
// 2 : start bit (always 0)
// 3..10 : byte lsb first
// 11 : stop bit (always 1)
// 12 : done (goes to state 0 after one clk

reg[9:0] serialout;
//reg rsout; // actual output signal -- idles high

always @(posedge clk)
begin
    serialout <= serialout;
    rsout <= 1'b1;
    txbdone <= 1'b0;
  casez (txctr)
  4'd0: begin
        txctr <= send ? 4'd1 : 0; // wait here, or here for 1 clk if send is already true
        serialout <= send ? {1'b1, txbyte, 1'b0} : 10'b1_1111_1111_1;
        end
  4'd1: begin // here 1 clk to start the tx baud generator rolling
        txctr <= txs ? {txctr+1} : txctr;
        end
  4'd12: begin // here 1 clk to generate txbdone strobe
        txctr <= 4'd0; 
        txbdone <= 1'b1;
        end
  default: begin // here during most of transmission
        txctr <= txs ? {txctr+1} : txctr;
        {serialout,rsout} <= txs ? {1'b1, serialout}:{serialout,rsout}; // LSB first, when txs
        end
  endcase
end
assign en_txqclk = (txctr > 0);
//full duplex, not needed:  assign rstri =  ~(txctr > 0); // not in tristate if transmitting

endmodule


module controller(input clk, input resetn, input rx, output reg tx);

wire nrxs;
wire[7:0] rxbyte;
serialrx srx_inst(.clk(clk), .rxserialin(rx), .newrxstrobe(nrxs), .rxbyte(rxbyte)); 

wire [8:1] rxchar = rxbyte;

reg xmit; 
reg [8:1] txchar;
reg [2:0] pstate;
reg [31:0] fr; // main control register for writing
// adjust to accommodate longest vector/array you need to write at once
// eg: 95:0 works
// gets autopopulated with ascii-hex chars arriving over serial.
wire [15:0] r = fr[15:0]; // lowest 'word' of R, used all over.

reg [15:0 ] x, y; // write back words:
// set in specific cases, eg, x <= 16'... {x,y} <= 32'...

wire[4:1] tohex = x[15:12];
wire[8:1] hexd = {(tohex>9)?4'b0110:4'b0011,(tohex>9)?tohex - 4'd9:tohex};


always @(posedge clk)
begin
    // defaults (values to have each cycle, if not otherwise overridden)
    xmit <= 1;
    txchar <= hexd;
    pstate <= pstate + 1;
    // begin anti-latch section for control registers
    x <= x;
    y <= y; // low word temp for atomic 32bit quantity reads - just a temporary register, only 16bit reads are default.
    fr <= fr;
    `include "./ctrl_reg_antilatch.v"
    // end anti-latch section
    if (nrxs)
        case (rxchar[8:5]) // this reads ascii 0123456789abcdef as a nibble. Char will still get echoed as-is. Up to you to always send in groups of 4.
            4'b0110: if (rxchar[4:1] < 4'd7)  fr <= {fr[91:0], rxchar[4:1]+4'd9}; // use only lowercase a-f not A-F!
            4'b0011: if (rxchar[4:1] < 4'd10) fr <= {fr[91:0], rxchar[4:1]}; // 0-9
        endcase // wrote r with rxchar hex digit as binary nibble shifted in big-endian order

  casez (pstate)
    3'd0:
    begin
        pstate <= nrxs ? 1 : 0;
        xmit <= 0;
    end
    3'd1:
    begin
        txchar <= " "; // reception of a command: echos back everything by default 
        // But all recognised commands will echo a space on reception... so can scan for codes recognized that way.
        // anything echoed back: not recognized as a command.
        // scanning like that is unsafe however, so should not be routine.
        pstate <= 3'd3; // x will be written back in ' x0000' format by default case. 
        // unless skipped by setting pstate <= 3'd0 in specific cases.
    // reset indentation: Other code may want to search this file
    // so as to gather the opcodes in use automatically.
    // E.G. getCommandCodesInUse.sh
case (rxchar) // defines the 'operation codes' each is replaced with x, sent back in 
// This is the main section you may wish to modify as needed.
// keep clear of 0123456789abcdef -> these are recognised in groups of four to set the register 'r'
//OPS begin opcode section

`include "./ctrl_opcodes.v"

//EOC end opcode section
default: begin 
    txchar <= rxchar; // ensures that unrecognized chars just get echoed back -> confirms loop is working.
    pstate <= 3'd0;
end

endcase
    end
    // continue pstate case statement: these extra states move digits.
    3'd3: txchar <= "x";
    default: x <= {x[11:0],4'd0};
  endcase

end
// N.B. Could triple efficiency by sending data back in raw binary format
// which may be useful if BW becomes limited.
// It may also be useful if interfacing to a microcontroller
// which will prefer raw data bytes and not to have to worry about 
// ASCII encoding. But sending it encoded this way makes debugging much easier,
// because you can just use a serial terminal program, and so it is a fairly common practice.


serialtx stx_inst (.clk(clk), . resetn(resetn), .xmit(xmit), .txchar(txchar), .rsout(tx));
endmodule

