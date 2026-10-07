# ESP32-S3 single-USB debugger test

The ESP32-S3 port uses **one physical native USB connection** and exposes two
logical CDC serial interfaces through the MicroPython TinyUSB runtime device:

- CDC0 — normal MicroPython REPL / file workflow
- CDC1 — MicroPython Studio debugger / breakpoints / RTA

No external USB-UART adapter is required.

## Why this differs from the first test artifact

The first ESP32-S3 artifact proved that the debugger C API builds and links on
Xtensa/ESP-IDF, but its proposed transport was a conservative UART fallback.
The actual Studio target is the same user experience as Pico: two logical COM
ports over one USB cable.

MicroPython's ESP32-S3 port at the pinned revision enables native USB device and
runtime `machine.USBDevice` support. The test `boot.py` creates a second
`CDCInterface` and calls:

```python
usb.device.get().init(dbg_cdc, builtin_driver=True)
```

`builtin_driver=True` preserves the built-in REPL CDC while adding the
debugger CDC to the same composite USB device.

## Files to place on the ESP32-S3 filesystem

- `boot.py` from this test package
- current Studio `trace_pump.py`
- `dbgref.py`

The `usb.device.cdc` helper package must also be available on the board (same
runtime USB helper used by the Pico dual-CDC debugger setup).

Reset the board after installing these files. Windows should enumerate two COM
ports from the single ESP32-S3 USB cable.

## First validation

Normal REPL:

```python
import dbg
print(hasattr(dbg, "set_bp"))
print(hasattr(dbg, "clear_bp"))
print(hasattr(dbg, "step"))
print(hasattr(dbg, "rta_on"))
print(hasattr(dbg, "rta_off"))
```

All should be `True`.

Then confirm Windows shows two COM ports. Keep the normal REPL on CDC0 and use
CDC1 with MicroPython Studio → Start Debug → Connect only.

## Deliberately disabled for first ESP32-S3 hardware validation

The RP2 Task Map implementation reads internal asyncio object fields using
RP2040/RP2350-specific memory offsets. The ESP32-S3 boot shim replaces that
function with an explicit unsupported result rather than guessing Xtensa object
layout.

Breakpoints, stepping, locals, call stack and RTA use the common debugger API
and remain enabled.
