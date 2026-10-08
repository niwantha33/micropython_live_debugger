# MicroPython Studio Pico/Pico W/Pico 2/Pico 2 W frozen debugger bootstrap.
#
# Runs after the stock frozen _boot.py mounts the filesystem, BEFORE
# mp_usbd_init(). Preserve the stock REPL CDC as CDC0 and create CDC1 for
# the debugger. Do not start a thread until USB initialization completes.
# The source is frozen, not uploaded onto the user's writable filesystem.

import sys


def configure_usb():
    import usb.device
    from usb.device.cdc import CDCInterface
    import mpy_studio_pico_dbgref as dbgref

    # These are the buffers of the previously working Pico 2 W debugger.
    # Keep Pico settings independent from ESP32-S3's smaller CDC buffers.
    dbg_cdc = CDCInterface(timeout=0, txbuf=4096, rxbuf=512)
    usb.device.get().init(dbg_cdc, builtin_driver=True)
    dbgref.cdc = dbg_cdc

    # Names used by the pinned Studio pump. Aliasing prevents an old
    # /dbgref.py on the filesystem from overriding the frozen reference.
    sys.modules["dbgref"] = dbgref


def start_pump():
    import mpy_studio_pico_trace_pump as trace_pump
    # Resolve Studio's symbol-lookup import to the exact frozen pump.
    sys.modules["trace_pump"] = trace_pump
    trace_pump.start()


try:
    configure_usb()
except Exception as exc:
    # Never intentionally prevent the stock REPL from booting.
    sys.print_exception(exc)
    print("[mpy-studio] Pico debugger CDC unavailable; REPL preserved")
