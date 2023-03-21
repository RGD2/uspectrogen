#!/bin/bash
make && scp usg.bin dice@dicepi1bp-nc.det.csiro.au:~/ && ssh dice@dicepi1bp-nc.det.csiro.au icezerotools/icezprog usg.bin
