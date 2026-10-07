# mpy_studio_boot.py -- ESP32-S3 dual-CDC descriptor setup.
#
# Runs from the stock frozen _boot.py BEFORE mp_usbd_init().
# IMPORTANT: do not start threads here.
#
# One native USB cable:
#   CDC0: built-in MicroPython REPL / raw REPL / file upload
#   CDC1: MicroPython Studio debugger / RTA

import sys


def _esp32_taskmap():
    return "unsupported: ESP32-S3 Task Map requires port-specific scheduler introspection"


def _esp32_tasks():
    try:
        import asyncio
        return repr(asyncio.core._task_queue)
    except Exception as e:
        return "err: " + repr(e)


def configure_usb():
    import usb.device
    from usb.device.cdc import CDCInterface

    # Keep the Python CDC buffers small on ESP32-S3. usb-device's Buffer
    # implementation briefly disables IRQs while compacting data; very large
    # buffers can turn that into an interrupt-watchdog problem under RTA load.
    dbg_cdc = CDCInterface(timeout=0, txbuf=256, rxbuf=256)

    # Preserve the built-in TinyUSB CDC0 (MicroPython stdio) and append CDC1.
    # This must happen before mp_usbd_init().
    usb.device.get().init(
        dbg_cdc,
        builtin_driver=True,
        product_str="MicroPython Studio ESP32-S3",
    )

    import dbgref
    dbgref.cdc = dbg_cdc


def start_pump():
    # Called only AFTER mp_usbd_init() by mpy_studio_start.py.
    import trace_pump
    trace_pump.get_taskmap = _esp32_taskmap
    trace_pump.get_tasks = _esp32_tasks
    trace_pump.start()


try:
    configure_usb()
except Exception as e:
    # Never prevent the normal REPL from booting.
    sys.print_exception(e)
