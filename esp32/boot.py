# boot.py -- ESP32-S3 single-cable dual-CDC debugger wiring.
#
# One physical native USB connection:
#   CDC0: built-in MicroPython REPL
#   CDC1: MicroPython Studio debugger/RTA
#
# usb.device.get().init(..., builtin_driver=True) keeps the built-in REPL CDC
# and adds the debugger CDC to the same TinyUSB composite device. MicroPython
# executes boot.py before mp_usbd_init(), so the composite descriptor is ready
# before the host enumerates the USB device.

import sys


def _esp32_taskmap():
    # RP2 trace_pump uses RP2040/RP2350 object-layout offsets through mem32.
    # Those offsets are intentionally disabled on Xtensa ESP32-S3.
    return "unsupported: ESP32-S3 Task Map requires port-specific scheduler introspection"


def _esp32_tasks():
    try:
        import asyncio
        return repr(asyncio.core._task_queue)
    except Exception as e:
        return "err: " + repr(e)


def _enable_dual_cdc():
    import usb.device
    from usb.device.cdc import CDCInterface

    dbg_cdc = CDCInterface(timeout=0, txbuf=4096, rxbuf=512)

    # Preserve the normal built-in CDC REPL and add this CDC as interface #1.
    usb.device.get().init(dbg_cdc, builtin_driver=True)

    import dbgref
    dbgref.cdc = dbg_cdc

    import trace_pump

    # Disable RP2-only asyncio pointer decoding before starting the pump.
    trace_pump.get_taskmap = _esp32_taskmap
    trace_pump.get_tasks = _esp32_tasks

    trace_pump.start()
    print("[boot] ESP32-S3 dual CDC debugger configured")


try:
    _enable_dual_cdc()
except Exception as e:
    sys.print_exception(e)
    print("[boot] ESP32-S3 debugger CDC setup failed; REPL remains available")
