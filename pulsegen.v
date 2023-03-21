module pulsegen (input sysclk, input step, input trigger, input[15:0] preset, output reg pulse);

reg trigger_, step_;
reg[15:0] counter;
wire active = (counter != 0);
wire [16:0] counter_next = counter-1'd1;
 

always @(posedge sysclk) begin
    {trigger_, step_} <= {trigger, step};
    if (trigger > trigger_)
        counter <= preset;
    else if (step > step_)
        counter <= (active)? counter_next[15:0] : 16'd0;
    else
        counter <= counter;
    pulse <= active;
end
endmodule 
