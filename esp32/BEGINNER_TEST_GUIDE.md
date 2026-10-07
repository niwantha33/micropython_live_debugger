# ESP32-S3 debugger test — simple step-by-step guide

This guide is written for hardware testing. Follow the steps in order.

Do **not** skip ahead.

---

## 1. Understand the two USB connectors on the board

Your ESP32-S3 board has two physical USB connectors.

For testing, think of them like this:

### Connector A — normal serial / recovery connection

Use this connector when you need the normal MicroPython prompt:

```text
>>>
```

We use this connection to:

- check that MicroPython is alive,
- inspect files,
- remove an old `boot.py` if necessary,
- recover the board if the native USB debugger setup is wrong.

The Windows COM number can change. Do not rely on a fixed COM number.

Use the port that actually gives you the MicroPython `>>>` prompt.

### Connector B — native USB connection

This is the USB connector used by the new debugger firmware.

Our target is:

```text
one physical native USB cable
        |
        +-- CDC0 -> MicroPython REPL
        |
        +-- CDC1 -> MicroPython Studio debugger / RTA
```

Windows should eventually show **two COM ports from this one native USB connector**.

---

## 2. Important: do not install usb-device-cdc manually

For this ESP32-S3 debugger firmware:

```text
usb-device
usb-device-cdc
trace_pump
dbgref
dual-CDC bootstrap
```

are built into the test firmware.

You should **not** run MIP installation for:

```text
usb-device-cdc
```

If Studio shows:

```text
Starting mip installation for 'usb-device-cdc'
```

stop that step.

That is the old setup path and is not required for this ESP32-S3 test firmware.

---

## 3. If the board keeps restarting

An old file on the ESP32 filesystem may be interfering with the new firmware.

The most important file to check is:

```text
boot.py
```

Older debugger tests may have placed USB setup code inside this file.

The new ESP32-S3 firmware already performs the debugger USB setup internally.

So an old `boot.py` may try to configure USB a second time.

### Safe check

Connect using the port that gives the normal MicroPython prompt:

```text
>>>
```

Run:

```python
import os
print(os.listdir())
```

If you see:

```text
boot.py
```

do not delete it immediately.

Rename it first:

```python
import os
os.rename("boot.py", "boot_old.py")
```

Then reset the board.

This keeps the old file available if we need to inspect it later.

Do not erase `main.py` or your project files.

---

## 4. Flash the ESP32-S3 debugger firmware

Use the combined image:

```text
firmware_esp32s3.bin
```

Flash address:

```text
0x0
```

Use only the combined image for this test.

Do not also select:

```text
bootloader.bin
partition-table.bin
micropython.bin
```

when `firmware_esp32s3.bin` is selected.

---

## 5. After flashing

Disconnect the board.

Wait a few seconds.

Reconnect the board.

For the first check, keep the native USB cable connected.

Do not start MicroPython Studio debugger yet.

---

## 6. Check that MicroPython is alive

Find the COM port that gives:

```text
>>>
```

Then run:

```python
import os
print(os.uname())
```

If this works, the firmware booted.

If the board is continuously reconnecting, return to **Step 3** and check for an old filesystem `boot.py`.

---

## 7. Check the debugger firmware API

At the normal MicroPython prompt run:

```python
import dbg

print("set_bp", hasattr(dbg, "set_bp"))
print("clear_bp", hasattr(dbg, "clear_bp"))
print("step", hasattr(dbg, "step"))
print("step_in", hasattr(dbg, "step_in"))
print("step_out", hasattr(dbg, "step_out"))
print("locals", hasattr(dbg, "locals"))
print("call_stack", hasattr(dbg, "call_stack"))
print("rta_on", hasattr(dbg, "rta_on"))
print("rta_off", hasattr(dbg, "rta_off"))
```

Expected result:

```text
set_bp True
clear_bp True
step True
step_in True
step_out True
locals True
call_stack True
rta_on True
rta_off True
```

If any value is `False`, stop here.

Do not test Studio yet.

---

## 8. Check the two COM ports

Now look at Windows Device Manager or Studio's port list.

The native USB connector should create two logical serial ports.

Think of them as:

```text
COM-A -> REPL
COM-B -> debugger
```

The actual COM numbers are not important.

They may change after firmware updates or reconnects.

### How to identify the REPL port

Open one port.

Press Enter.

If you see:

```text
>>>
```

that is the REPL port.

Close it before testing the other port.

### The other port

The other CDC port is the debugger port.

Do not expect a Python `>>>` prompt from the debugger port.

---

## 9. Connect MicroPython Studio

For this ESP32-S3 firmware, do **not** choose:

```text
Upload debugger files
```

The debugger support is already built into the firmware.

Choose:

```text
Start Debug
    ->
Connect only
```

Then select the **debugger CDC COM port**, not the REPL port.

Expected first messages are similar to:

```text
connected to COMx
debug CDC open
cleared all bp slots
DEBUG CDC READY
```

---

## 10. First breakpoint test

Use a very small Python program first.

Example:

```python
import time

def test():
    x = 0
    while True:
        x += 1
        print(x)
        time.sleep(1)

test()
```

Set one breakpoint inside `test()`.

Check only these items first:

1. breakpoint can be set,
2. program stops,
3. locals are visible,
4. Continue works,
5. removing the breakpoint really removes it.

Do not test everything at once.

---

## 11. RTA test

Only after breakpoints work:

1. press **RTA On**,
2. let the program run for a few seconds,
3. press **RTA Off**,
4. check that RTA events and runtime rows appear.

Do not test Task Map yet.

The RP2 Task Map implementation uses RP2040/RP2350-specific memory offsets and is intentionally disabled for the first ESP32-S3 hardware test.

---

## 12. Recovery rule

If something goes wrong:

```text
debugger problem
    ->
close Studio
    ->
disconnect native USB
    ->
use the normal/recovery serial connection
    ->
get >>>
    ->
inspect files
    ->
rename old boot.py if present
```

Do not erase the complete filesystem unless we have confirmed that it is necessary.

---

## Current test rule

For the ESP32-S3 test firmware:

```text
DO:
  flash combined firmware
  use native USB
  use Connect only
  test in small steps

DO NOT:
  install usb-device-cdc with MIP
  upload the Pico boot.py
  run Pico debugger setup files
  erase project files
  test Task Map yet
  publish the firmware before hardware validation
```
