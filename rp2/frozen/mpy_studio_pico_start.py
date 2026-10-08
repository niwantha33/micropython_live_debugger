# Late Pico debugger start, called after mp_usbd_init().
# Running the pump after USB initialization prevents the CDC I/O race.

try:
    import mpy_studio_pico_boot
    # Do not start the pump if descriptor registration failed.
    import mpy_studio_pico_dbgref
    if mpy_studio_pico_dbgref.cdc is not None:
        mpy_studio_pico_boot.start_pump()
except Exception as exc:
    import sys
    sys.print_exception(exc)
    print("[mpy-studio] Pico debugger pump unavailable; REPL preserved")
