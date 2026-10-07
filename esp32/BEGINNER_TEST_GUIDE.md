# ESP32-S3 debugger test — simple step-by-step guide

> **Current hardware-test rule (important)**
>
> Use the board's **Serial Port connector** for MicroPython REPL, file upload,
> package installation and recovery.
>
> Use the board's **native USB connector** only for the debugger/RTA transport.
>
> Do **not** try to upload files or run MIP through the native USB COM ports
> during this test phase.

---

## 1. Understand the two USB connectors on the board

Your ESP32-S3 board has two physical USB connectors.

For testing, think of them like this:

### Connector A — Serial Port (this is the upload/REPL port)

Use this connector for all normal MicroPython work:

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

### Connector B — native USB (debugger transport)

This connector is used only for the debugger/RTA test.

Windows currently shows two COM ports from this connector (for example COM12
and COM13). During this hardware-test phase they are **not upload ports**.

Use Studio **Start Debug → Connect only** to find which one answers the debugger
handshake. Do not run MIP, file upload, or package installation on either native
USB COM port.

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

## 8. Check the native USB COM ports

Keep using the **Serial Port connector** for the MicroPython `>>>` prompt.

The native USB connector may show two COM ports, for example:

```text
COM12
COM13
```

Do not test them with file upload or MIP.

In Studio choose **Start Debug → Connect only** and try the two native USB COM
ports one at a time.

The debugger port is the one that answers the debugger handshake.

The other native USB COM port is not used for upload in this test phase.

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
  use Serial Port for REPL/upload/recovery
  use native USB for debugger only
  use Connect only on the native USB COM ports
  test in small steps

DO NOT:
  upload files through native USB COM12/COM13
  run MIP through native USB COM12/COM13
  install usb-device-cdc manually
  upload the Pico boot.py
  run Pico debugger setup files
  erase project files
  test Task Map yet
  publish the firmware before hardware validation
```
