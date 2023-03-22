// This section gets included in a case within the controller in serial.v
// Separate file because you should only customize this part for a given app
// set x to send-back a 16 bit word, or {x,y} to atomically save a second word
// (or sample a 32 bit register) and send the high/first word.
// Second word must be read back with a separate "." command sent right after.
// Set Registers to control things
// Registers must be defined in your top.v before controller();
// and should be set in antilatch.v to themselves.
// You can use any ASCII one-letter string as a command case, except 0-9 a-f,
// because those are recognized as being nibbles, and are shifted into the 'r'
// register as they are received.'fr' is the 'full r' and can be extended
// arbitrary so you can write whole arrays at once (any multiple of nibbles).

"r": x <= r; // readback without write 
// -- usage send '1068r' -> '1068 x1068', 
// later just send 'r'->' x1068' 0x1068 -> 16'd4200 -> 42.00 ms fuel pulse width.
// Good idea to read back in case digits get out of alignment. 
".": x <= y; // lower word readback, append after command codes that sample 32 bit data.

// Append custom cases after here
"E": exposure <= fr;
"L": ledreg <= r;


