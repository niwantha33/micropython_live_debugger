# ESP32-S3 debugger test — simple step-by-step guide

Use the two physical ESP32-S3 USB connectors for different jobs during this test.

```text
USB-Serial/JTAG -> MicroPython REPL + upload
Native USB      -> debugger + RTA
```

Do not try to upload files through the native debugger COM.

## Step 1 — connect the Serial/JTAG cable

Open the COM port that gives:

```text
>>>
```

This is the only port to use for:

- project upload,
- Shell,
- checking files,
- recovery.

## Step 2 — keep the filesystem clean

The new debugger support is frozen into firmware.

Do not install `usb-device-cdc` with MIP.

Do not upload the old Pico debugger `boot.py`.

If an old `boot.py` is still present, rename it first rather than deleting project files:

```python
import os
print(os.listdir())
os.rename("boot.py", "boot_old.py")
```

Only run the rename if `boot.py` exists.

## Step 3 — flash the combined firmware

Flash:

```text
firmware_esp32s3.bin
address 0x0
```

Do not select separate bootloader/partition/app binaries at the same time.

## Step 4 — reconnect both cables

After reset:

- Serial/JTAG COM should give the normal `>>>` prompt.
- Native USB should expose the debugger COM.

The native debugger COM does not need to give a Python prompt.

## Step 5 — verify firmware API on Serial/JTAG

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

All values should be `True`.

## Step 6 — upload your program

Upload your Python project through the Serial/JTAG COM only.

Do not use the native debugger COM for upload.

## Step 7 — connect the debugger

In MicroPython Studio:

```text
Start Debug
  -> Connect only
  -> choose the native USB debugger COM
```

## Step 8 — breakpoint test

Test only:

1. set one breakpoint,
2. hit it,
3. inspect locals,
4. Continue,
5. remove the breakpoint.

If this works, the basic debugger transport is good.

## Step 9 — RTA test

Only after breakpoints work:

1. RTA On,
2. let the program run for 30 seconds,
3. do not repeatedly press Refresh Names,
4. RTA Off,
5. verify there is no watchdog reset.

## Recovery

If the debugger misbehaves:

1. close the debugger panel,
2. disconnect native USB,
3. keep Serial/JTAG connected,
4. use the normal `>>>` prompt to recover.

Do not erase the complete filesystem unless we have proved it is necessary.
