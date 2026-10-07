# ESP32-S3 debugger test path

This port intentionally does **not** reuse the RP2 dual-USB-CDC wiring.

## Transport v1: dedicated UART

For the first ESP32-S3 hardware validation, keep the normal MicroPython
REPL/flash interface untouched and carry debugger frames over UART1 to a
separate 3.3 V USB-UART adapter.

This isolates debugger transport problems from USB-console/bootloader problems
and preserves the existing framed protocol and VS Code serial bridge.

### Wiring

Choose two free GPIOs for your board:

- ESP32-S3 debug TX -> USB-UART RX
- ESP32-S3 debug RX <- USB-UART TX
- ESP32-S3 GND -> USB-UART GND

Use **3.3 V logic**. Do not connect a 5 V UART signal to ESP32 GPIO.

The module does not hard-code pins because ESP32-S3 boards expose different
GPIOs. Example only:

```python
import esp32_debug_uart
esp32_debug_uart.start(tx=17, rx=18)
```

Default debug baud is 115200 for compatibility with the current Studio serial
bridge. Once the control path is hardware-verified, the transport can be raised
to 921600 for RTA throughput.

## Files required on the device

Upload:

- the current Studio `trace_pump.py`
- the current Studio `dbgref.py`
- `esp32_debug_uart.py` from this directory

Do **not** upload the RP2 dual-CDC `boot.py`.

Then start the transport manually from the normal REPL using the board-specific
TX/RX pins.

In Studio, choose **Connect only** and select the USB-UART adapter COM port as
the debugger port.

## First hardware gate

Before testing Studio transport, verify the firmware API at the normal REPL:

```python
import dbg
print(hasattr(dbg, "set_bp"))
print(hasattr(dbg, "clear_bp"))
print(hasattr(dbg, "step"))
print(hasattr(dbg, "rta_on"))
print(hasattr(dbg, "rta_off"))
```

All five must print `True`.

## Deliberately deferred

- RP2-style dual CDC on ESP32-S3
- architecture-specific asyncio Task Map pointer decoding
- automatic boot-time UART pin selection
- ESP32-C3 (after S3 hardware validation)
