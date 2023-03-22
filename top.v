
module top (
	input clk_100MHz,
      	output led1, led2, led3,
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


    controller ctrl (.clk(clk), .resetn(resetn), .rx(rx), .tx(tx));

    assign {led1,led2,led3} = ctrl.ledreg;
	
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

    reg tic, tic_;
    always @(posedge clk) begin
        {tic_, tic} <= {tic, fc[2]};
    end
    wire tick = tic>tic_; // 5 MHz flag


    always @(posedge clk) begin
        SCLK <= ~tic;
    end


    // main FSM
    // controls SST, OTRIG

    reg [31:0] cntr;
    reg [1:0] state;

    always @(posedge clk) begin
        SST <= SST;
        OTRIG <= 1'b0; // default, will be 1-shot
        cntr <= cntr;
        state <= state;

        if (tick) begin
            if (cntr) begin
                cntr <= cntr  - 1;
            end else begin
                case (state)
                    0: begin
                        cntr <= 32'd5;
                        SST <= 1'b1;
                    end
                    1: cntr <= ctrl.exposure;
                    2: begin
                        cntr <= 32'd88;
                        SST <= 1'b0;
                    end
                    3: begin
                        cntr <= 32'd286;
                        OTRIG <= 1'b1;
                    end
                endcase
                state <= state + 1;
            end
        end
    end

    
    assign slmiso = slmosi; // Loopback for SPI testing

    // LED diagnostics - makes a single clk pulse visible
    //pulsegen visibleblink1 (.sysclk(clk), .step(utick), .trigger(led[1]), .preset(16'd410), .pulse(led1));
    //pulsegen visibleblink2 (.sysclk(clk), .step(utick), .trigger(led[2]), .preset(16'd410), .pulse(led2));
    //pulsegen visibleblink3 (.sysclk(clk), .step(utick), .trigger(led[3]), .preset(16'd410), .pulse(led3));
endmodule
