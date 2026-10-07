# ESP32-S3 debugger hardware-test layout

For the current hardware-validation phase use the two ESP32-S3 USB interfaces
for separate jobs:

```text
USB-Serial/JTAG connector  -> MicroPython REPL + file upload
Native USB connector       -> MicroPython Studio debugger + RTA
```

This is intentional for the current test. Do not use the native debugger COM
port for MIP, raw REPL, or project file upload.

## Why

Hardware testing proved that the USB-Serial/JTAG path is reliable for the
MicroPython REPL and file transfer, while the native USB debugger CDC is already
working for breakpoint set/clear/continue and RTA control.

Keeping those paths separate also reduces USB traffic while the ESP32-specific
RTA watchdog issue is validated.

## Boot sequence

The debugger code is frozen into the firmware.

Before TinyUSB starts, `mpy_studio_boot` creates one native CDC interface for
the debugger. The normal REPL remains on USB-Serial/JTAG.

After `mp_usbd_init()`, `mpy_studio_start.py` starts the frozen
`trace_pump` thread.

This two-phase startup avoids starting the debugger thread while USB is still
being initialised.

## What to connect

Connect both board USB connectors during the current test:

1. **Serial/JTAG USB** — use this in MicroPython Studio as the project/device
   port for upload and Shell.
2. **Native USB** — select this only from **Start Debug -> Connect only**.

Windows COM numbers can change. Identify the Serial/JTAG port by the normal
MicroPython `>>>` prompt.

## Do not install usb-device-cdc

The required `usb-device` and `usb-device-cdc` packages are frozen into the
test firmware.

Do not run MIP installation for `usb-device-cdc` on either port.

## First debugger test

Use a small program and test in this order:

1. upload through Serial/JTAG,
2. run the program,
3. Connect only to the native debugger COM,
4. set one breakpoint,
5. hit the breakpoint,
6. inspect locals,
7. continue,
8. remove the breakpoint.

Only then test RTA.

## RTA test

The ESP32 test firmware uses bounded native-CDC buffering and shorter pump
bursts to avoid long IRQ-off buffer compaction under RTA traffic.

Start with a 30-second test:

1. RTA On,
2. let the program run,
3. do not press Refresh Names repeatedly,
4. RTA Off,
5. confirm there is no watchdog reset.

## Task Map

The RP2 Task Map implementation uses RP2040/RP2350-specific memory offsets.
It remains disabled on ESP32-S3 until a separate implementation is validated.
