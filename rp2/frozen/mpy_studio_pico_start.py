# Late Pico debugger start, executed by RP2 main.c AFTER mp_usbd_init().
#
# Important: RP2 runs the earlier bootstrap with pyexec_frozen_module(),
# which does NOT cache it as an imported module. Never import
# mpy_studio_pico_boot from here: that would re-run CDC initialization.

try:
    import sys
    import mpy_studio_pico_dbgref as dbgref

    if dbgref.cdc is not None:
        import mpy_studio_pico_trace_pump as trace_pump
        sys.modules["trace_pump"] = trace_pump
        trace_pump.start()
except Exception as exc:
    import sys
    sys.print_exception(exc)
    print("[mpy-studio] Pico debugger pump unavailable; REPL preserved")
