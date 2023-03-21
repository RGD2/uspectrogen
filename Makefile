
all: usg.bin

prog: usg.bin icezprog
	./icezprog usg.bin

reset: icezprog
	./icezprog .

icezprog: icezprog.c
	gcc -o icezprog -Wall -Os icezprog.c -lwiringPi -lrt -lstdc++

usg.json: top.v fifo.v serial.v pulsegen.v 
	yowasp-yosys -p 'synth_ice40 -top top -json usg.json' top.v fifo.v serial.v pulsegen.v 

usg.asc: usg.json usg.pcf
	#arachne-pnr -d 8k -P tq144:4k -p usg.pcf -o usg.asc usg.blif
	yowasp-nextpnr-ice40 --hx8k --package tq144:4k --freq 40 --json usg.json --pcf usg.pcf --asc usg.asc

usg.bin: usg.asc
	#icetime -d hx8k -c 25 usg.asc
	yowasp-icepack usg.asc usg.bin
	
sinetest: sinetest.c
	gcc -o sinetest sinetest.c -lm -lrt -Wno-int-to-pointer-cast	

fake: sinetest
	nice -20 ./sinetest

clean:
	rm -f testbench testbench.vcd
	rm -f usg.json usg.asc usg.bin
	rm -f sinetest

.PHONY: all prog reset fake clean

