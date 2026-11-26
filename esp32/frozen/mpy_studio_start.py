# mpy_studio_start.py -- late debugger start for ESP32-S3.
#
# Executed by the ESP32 port immediately AFTER mp_usbd_init(), so CDC0 is
# already a stable MicroPython REPL before the debugger thread begins.

try:
    import mpy_studio_boot
    mpy_studio_boot.start_pump()
except Exception as e:
    import sys
    sys.print_exception(e)
