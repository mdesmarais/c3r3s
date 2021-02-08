import os.path
import struct
import sys
import zlib

import serial

PORT = '/dev/ttyACM0'
BAUDS = 115200
START_ADR = 0x80000

def wait_for_msg(ser, expected):
    buffer = ''
    while True:
        try:
            a = ser.read(len(expected)).decode('utf-8')
        except UnicodeDecodeError:
            continue

        buffer += a
        if expected in buffer:
            return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Missing kernel file')
        sys.exit(-1)
    
    kernel_file = open(sys.argv[1], 'rb')
    kernel_size = os.path.getsize(sys.argv[1])

    print('Kernel size', kernel_size)
    
    with serial.Serial(PORT, BAUDS, timeout=1) as ser:
        wait_for_msg(ser, 'c3r3s')
        ser.reset_input_buffer()
        print('c3r3s is up')
        ser.write(b'boot')
        wait_for_msg(ser, 'lstn')
        ser.reset_input_buffer()
        print('c3r3s is ready to accept a kernel')

        packet = b'send' + struct.pack('<LL', START_ADR, kernel_size)
        ser.write(packet)

        file_buffer = b''

        while True:
            data = kernel_file.read(512)
            if not data:
                break

            packet = struct.pack('<L', len(data)) + data
            ser.write(packet)

            file_buffer += data
            ack, = struct.unpack('<L', ser.read(4))

            if ack != len(file_buffer):
                print('Invalid received len', len(file_buffer), ack)
                sys.exit(-1)
        
        crc = zlib.crc32(file_buffer)
        packet = struct.pack('<L', crc)
        ser.write(packet)

        response = ser.read(4).decode('utf-8')

        print('response', response)
    
    kernel_file.close()
