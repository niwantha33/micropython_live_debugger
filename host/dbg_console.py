# dbg_console.py — combined reader + command sender on one COM port.
#
# Usage:
#   python dbg_console.py COM3
#
# While running:
#   c<enter>  = continue
#   s<enter>  = step
#   q<enter>  = quit

import sys
import threading
import time
import serial


def reader_loop(ser, stop_evt):
    buf = bytearray()
    while not stop_evt.is_set():
        data = ser.read(64)
        if not data:
            continue
        buf.extend(data)
        while len(buf) >= 3 and buf[0] == 0xAA:
            t = buf[1]
            n = buf[2]
            total = 3 + n
            if len(buf) < total:
                break
            payload = bytes(buf[3:total])
            if t == 0x01 and n == 3:
                ip = payload[0] | (payload[1] << 8)
                print(f"TRACE ip=0x{ip:04X} op=0x{payload[2]:02X}")
            elif t == 0x02 and n == 2:
                ip = payload[0] | (payload[1] << 8)
                print(f"BP_HIT ip=0x{ip:04X}  <<< paused")
            elif t == 0x03:
                print(f"LOCALS {payload.decode(errors='replace')}")
            else:
                print(f"frame type=0x{t:02X} len={n} payload={payload.hex()}")
            del buf[:total]
        while buf and buf[0] != 0xAA:
            buf.pop(0)


def main():
    if len(sys.argv) < 2:
        print("usage: python dbg_console.py <COMx>")
        sys.exit(1)
    port = sys.argv[1]
    ser = serial.Serial(port, 115200, timeout=0.1, write_timeout=1.0,
                        dsrdtr=False, rtscts=False)
    time.sleep(0.1)
    stop_evt = threading.Event()
    t = threading.Thread(target=reader_loop, args=(ser, stop_evt), daemon=True)
    t.start()
    print(f"open {port}. c=continue s=over i=in o=out l=locals p=poke g=global q=quit")
    try:
        while True:
            cmd = input("> ").strip()
            cmd_lower = cmd.lower()
            if cmd_lower == "q":
                break
            elif cmd_lower == "c":
                ser.write(bytes([0xAA, 0x10, 0x00]))
                ser.flush()
                print("sent: continue")
            elif cmd_lower == "s":
                ser.write(bytes([0xAA, 0x11, 0x00]))
                ser.flush()
                print("sent: step")
            elif cmd_lower == "i":
                ser.write(bytes([0xAA, 0x13, 0x00]))
                ser.flush()
                print("sent: step-in")
            elif cmd_lower == "o":
                ser.write(bytes([0xAA, 0x14, 0x00]))
                ser.flush()
                print("sent: step-out")
            elif cmd_lower == "l":
                ser.write(bytes([0xAA, 0x12, 0x00]))
                ser.flush()
                print("sent: locals")
            elif cmd_lower.startswith("p "):
                parts = cmd.split(" ", 2)
                if len(parts) >= 3:
                    try:
                        slot = int(parts[1])
                        expr = parts[2]
                        payload = bytes([slot]) + expr.encode()
                        frame = bytes([0xAA, 0x18, len(payload)]) + payload
                        ser.write(frame)
                        ser.flush()
                        print(f"sent: poke slot {slot} with {expr}")
                    except Exception as e:
                        print("invalid poke command: ", e)
                else:
                    print("usage: p <slot> <expr>")
            elif cmd_lower.startswith("g "):
                parts = cmd.split(" ", 2)
                if len(parts) >= 3:
                    try:
                        name = parts[1]
                        expr = parts[2]
                        name_bytes = name.encode()
                        if len(name_bytes) > 255:
                            print("global name too long")
                            continue
                        payload = bytes([len(name_bytes)]) + name_bytes + expr.encode()
                        frame = bytes([0xAA, 0x19, len(payload)]) + payload
                        ser.write(frame)
                        ser.flush()
                        print(f"sent: poke global {name} with {expr}")
                    except Exception as e:
                        print("invalid poke global command: ", e)
                else:
                    print("usage: g <name> <expr>")
            else:
                print("?")
    finally:
        stop_evt.set()
        time.sleep(0.2)
        ser.close()


if __name__ == "__main__":
    main()
