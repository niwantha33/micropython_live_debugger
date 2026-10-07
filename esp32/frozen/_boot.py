# _boot.py -- frozen ESP32-S3 MicroPython Studio debugger bootstrap.
#
# Runs before user boot.py and before mp_usbd_init().
# One physical USB cable enumerates:
#   CDC0: built-in MicroPython REPL
#   CDC1: MicroPython Studio debugger/RTA

import sys


def _esp32_taskmap():
    return "unsupported: ESP32-S3 Task Map requires port-specific scheduler introspection"


def _esp32_tasks():
    try:
        import asyncio
        return repr(asyncio.core._task_queue)
    except Exception as e:
        return "err: " + repr(e)


def _start_debug_usb():
    import usb.device
    from usb.device.cdc import CDCInterface

    dbg_cdc = CDCInterface(timeout=0, txbuf=4096, rxbuf=512)

    # Keep the built-in TinyUSB CDC REPL and append the debugger CDC.
    usb.device.get().init(
        dbg_cdc,
        builtin_driver=True,
        product_str="MicroPython Studio ESP32-S3",
    )

    import dbgref
    dbgref.cdc = dbg_cdc

    import trace_pump
    # Never use RP2 object-layout offsets on Xtensa.
    trace_pump.get_taskmap = _esp32_taskmap
    trace_pump.get_tasks = _esp32_tasks
    trace_pump.start()


try:
    _start_debug_usb()
except Exception as e:
    # Debug USB failure must never brick the normal REPL.
    sys.print_exception(e)
