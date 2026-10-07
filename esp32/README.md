# ESP32-S3 single-USB debugger test

This port uses **one physical native USB connector** and exposes two logical
CDC serial interfaces through the same ESP32-S3 TinyUSB device:

- CDC0 — normal MicroPython REPL
- CDC1 — MicroPython Studio debugger / breakpoints / RTA

No external USB-UART adapter is required.

## Firmware behaviour

The debugger bootstrap is frozen into the test firmware.

The build keeps the stock ESP32 frozen `_boot.py` and appends:

```python
import mpy_studio_boot
```

The frozen `mpy_studio_boot` module:

1. creates a second `CDCInterface`,
2. calls `usb.device.get().init(..., builtin_driver=True)`,
3. keeps the built-in CDC REPL,
4. binds CDC1 to `dbgref.cdc`,
5. starts the frozen Studio `trace_pump`.

The `usb-device` and `usb-device-cdc` MicroPython-lib packages are frozen
into the image through the ESP32 manifest.

## Expected result after flashing

Flash only the combined test image, reset the board, and reconnect the same USB
cable.

Windows should enumerate two serial ports:

- one port for the normal MicroPython REPL,
- one port for the debugger.

No manual `boot.py`, package installation, or second cable is required.

## First validation

On the normal REPL:

```python
import dbg
print(hasattr(dbg, "set_bp"))
print(hasattr(dbg, "clear_bp"))
print(hasattr(dbg, "step"))
print(hasattr(dbg, "step_in"))
print(hasattr(dbg, "step_out"))
print(hasattr(dbg, "locals"))
print(hasattr(dbg, "call_stack"))
print(hasattr(dbg, "rta_on"))
print(hasattr(dbg, "rta_off"))
```

All should be `True`.

Then use MicroPython Studio → Start Debug → Connect only and select the other
CDC COM port.

## Deliberately deferred

The RP2 Task Map implementation uses RP2040/RP2350-specific object memory
offsets. That path is disabled on ESP32-S3 until a port-specific implementation
is hardware-verified.

Breakpoints, stepping, locals, call stack and RTA continue to use the common
debugger API.
