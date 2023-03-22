import serial
from sys import argv

try: 
    with Serial.serial('/dev/ttyAMA0', 2500000) as ser:
        ser.write(argv[1])


