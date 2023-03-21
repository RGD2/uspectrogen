
module top (
	input clk_100MHz,
      	output reg led1, led2, led3,
	output reg SCLK, SST, OTRIG,
	input rx,
	output tx,
	input slmosi,
	output slmiso,
	input slsck,
	input slce0n,
	input slce1n,
    output test
);


	// Clock Generator

	wire clk, pll_locked;

`ifdef TESTBENCH
	assign clk = clk_100MHz, pll_locked = 1;
`else
	wire clk_40MHz;

	SB_PLL40_PAD #(
		.FEEDBACK_PATH("SIMPLE"),
		.DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
		.DELAY_ADJUSTMENT_MODE_RELATIVE("FIXED"),
		.PLLOUT_SELECT("GENCLK"),
		.FDA_FEEDBACK(4'b1111),
		.FDA_RELATIVE(4'b1111),
		.DIVR(4'b0100),		// DIVR =  4
		.DIVF(7'b0011111),	// DIVF = 31
		.DIVQ(3'b100),		// DIVQ =  4
		.FILTER_RANGE(3'b010)	// FILTER_RANGE = 2
	) pll (
		.PACKAGEPIN   (clk_100MHz),
		.PLLOUTGLOBAL (clk_40MHz ),
		.LOCK         (pll_locked),
		.BYPASS       (1'b0      ),
		.RESETB       (1'b1      )
	);

	assign clk = clk_40MHz;
`endif

    wire [1:3] led;

	// Reset Generator

	reg [7:0] resetstate = 0;
	reg resetn = 0;

	always @(posedge clk) begin
		resetstate <= pll_locked ? resetstate + !(&resetstate) : 0;
		resetn <= &resetstate;
	end

	// serial receiver
    wire [7:0] rxbyte;
    wire newrx;
	serialrx rxer (.clk(clk), .rxserialin(rx), .newrxstrobe(newrx), .rxbyte(rxbyte));
    
	// rxfifo
	//
    reg read_i;  // control from state machine
	wire [7:0] data_o;
	wire fifoFull_o, fifoEmpty_o;
	fifo rxqueue(
		.clk(clk),
		.nreset(resetn),
		.read_i(read_i),
		.write_i(newrx),
		.data_i(rxbyte),
		.data_o(data_o),
		.fifoFull_o(fifoFull_o),
		.fifoEmpty_o(fifoEmpty_o)
	);
	
    reg [31:0] time;
    reg utick;
    always @(posedge clk) begin
        time <= time + 1;
        utick <= (time[11:0]==0); // 102 us ticks
    end

    reg [2:0] fc; // fast clock
    always @(posedge clk) begin
        fc <= fc + 1;
    end
    wire tic = fc[2]; // 5 MHz clk

    always @(tic) begin
        SCLK <= ~tic;
    end

    // serial loopback (for testing)
    serialtx testloop (.clk(clk), .resetn(resetn), .xmit(newrx), .txchar(rxbyte), .rsout(tx));

    assign test = tx;

    // main FSM
    reg [8:0] plscnt;

    always @(posedge tic) begin
        if (plscnt == 9'd380) begin
            plscnt <= 0;
        end else begin
            plscnt <= plscnt + 1;
        end
    end

    always @(plscnt) begin
        if (plscnt < 9'd6 )
            SST <= 1'b1;
        else
            SST <= 1'b0;

        if (plscnt == 9'd88)
            OTRIG <= 1'b1;
        else
            OTRIG <= 1'b0;

    end
    
    assign slmiso = lsmosi; // Loopback for SPI testing

    // LED diagnostics - makes a single clk pulse visible
    pulsegen visibleblink1 (.sysclk(clk), .step(utick), .trigger(led[1]), .preset(16'd410), .pulse(led1));
    pulsegen visibleblink2 (.sysclk(clk), .step(utick), .trigger(led[2]), .preset(16'd410), .pulse(led2));
    pulsegen visibleblink3 (.sysclk(clk), .step(utick), .trigger(led[3]), .preset(16'd410), .pulse(led3));
endmodule
