include("$(PORT_DIR)/boards/manifest.py")

# Runtime USB helpers used by the frozen dual-CDC debugger bootstrap.
require("usb-device")
require("usb-device-cdc")

# Freeze _boot.py, trace_pump.py and dbgref.py into the debug firmware.
freeze("debugger_frozen")
