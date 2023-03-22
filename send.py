import serial
from sys import argv

try: 
    with serial.Serial('/dev/ttyAMA0', 2500000) as ser:
        ser.write(bytes(argv[1], encoding='utf-8'))

except (KeyboardInterrupt):
    pass


