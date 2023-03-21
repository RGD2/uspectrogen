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

