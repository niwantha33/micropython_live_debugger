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
import json

rta_events = []

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
            elif t == 0x04 and n >= 2:
                ip = payload[0] | (payload[1] << 8)
                msg = payload[2:].decode(errors="replace")
                print(f"EXCEPTION ip=0x{ip:04X} msg={msg}  <<< paused")
            elif t == 0x05 and n == 8:
                fun = payload[0] | (payload[1] << 8) | (payload[2] << 16) | (payload[3] << 24)
                ts = payload[4] | (payload[5] << 8) | (payload[6] << 16) | (payload[7] << 24)
                print(f"RTA_ENTRY fun=0x{fun:08X} ts={ts}")
                rta_events.append({"name": f"fun_0x{fun:08X}", "ph": "B", "ts": ts, "pid": 1, "tid": 1})
            elif t == 0x06 and n == 8:
                fun = payload[0] | (payload[1] << 8) | (payload[2] << 16) | (payload[3] << 24)
                ts = payload[4] | (payload[5] << 8) | (payload[6] << 16) | (payload[7] << 24)
                print(f"RTA_EXIT  fun=0x{fun:08X} ts={ts}")
                rta_events.append({"name": f"fun_0x{fun:08X}", "ph": "E", "ts": ts, "pid": 1, "tid": 1})
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
    print(f"open {port}. c=continue s=over i=in o=out l=locals p=poke g=global h=halt q=quit")
    try:
        while True:
            try:
                cmd = input("> ").strip()
            except KeyboardInterrupt:
                ser.write(bytes([0xAA, 0x20, 0x00]))
                ser.flush()
                print("\nsent: halt (Ctrl-C)")
                continue

            cmd_lower = cmd.lower()
            if cmd_lower == "q":
                break
            elif cmd_lower == "rtadump":
                try:
                    with open("rta_trace.json", "w") as f:
                        json.dump(rta_events, f)
                    print(f"saved {len(rta_events)} RTA events to rta_trace.json")
                except Exception as e:
                    print("failed to save RTA events:", e)
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
            elif cmd_lower == "h":
                ser.write(bytes([0xAA, 0x20, 0x00]))
                ser.flush()
                print("sent: halt")
            elif cmd_lower.startswith("l"):
                parts = cmd.split(" ", 1)
                try:
                    depth = int(parts[1]) if len(parts) > 1 else 0
                    ser.write(bytes([0xAA, 0x12, 0x01, depth]))
                    ser.flush()
                    print(f"sent: locals depth {depth}")
                except Exception as e:
                    print("invalid locals command: ", e)
            elif cmd_lower.startswith("p "):
                parts = cmd.split(" ", 3)
                if len(parts) >= 3:
                    try:
                        slot = int(parts[1])
                        depth = 0
                        expr = ""
                        if len(parts) == 4:
                            try:
                                depth = int(parts[2])
                                expr = parts[3]
                            except ValueError:
                                expr = cmd.split(" ", 2)[2]
                        else:
                            expr = parts[2]
                        
                        payload = bytes([slot, depth]) + expr.encode()
                        frame = bytes([0xAA, 0x18, len(payload)]) + payload
                        ser.write(frame)
                        ser.flush()
                        print(f"sent: poke slot {slot} (depth {depth}) with {expr}")
                    except Exception as e:
                        print("invalid poke command: ", e)
                else:
                    print("usage: p <slot> [depth] <expr>")
            elif cmd_lower.startswith("g "):
                parts = cmd.split(" ", 3)
                if len(parts) >= 3:
                    try:
                        name = parts[1]
                        depth = 0
                        expr = ""
                        if len(parts) == 4:
                            try:
                                depth = int(parts[2])
                                expr = parts[3]
                            except ValueError:
                                expr = cmd.split(" ", 2)[2]
                        else:
                            expr = parts[2]
                            
                        name_bytes = name.encode()
                        if len(name_bytes) > 255:
                            print("global name too long")
                            continue
                        payload = bytes([depth, len(name_bytes)]) + name_bytes + expr.encode()
                        frame = bytes([0xAA, 0x19, len(payload)]) + payload
                        ser.write(frame)
                        ser.flush()
                        print(f"sent: poke global {name} (depth {depth}) with {expr}")
                    except Exception as e:
                        print("invalid poke global command: ", e)
                else:
                    print("usage: g <name> [depth] <expr>")
            else:
                print("?")
    finally:
        stop_evt.set()
        time.sleep(0.2)
        ser.close()


if __name__ == "__main__":
    main()
