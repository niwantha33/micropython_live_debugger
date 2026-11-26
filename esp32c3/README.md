# ESP32-C3 — board and transport notes

ESP32-C3 serial compatibility in MicroPython Studio and native firmware debugging are separate qualification scopes. A working REPL, upload or serial connection does not by itself establish breakpoint, stepping or RTA support.

ESP32-C3 has a fixed-function USB Serial/JTAG controller, unlike the configurable native USB OTG controller used by the ESP32-S3 debugger. Some C3 development boards also expose a separate USB-to-UART bridge. Identify the actual board, USB hardware IDs and COM assignments before selecting a port. Do not use ESP32-S3 firmware on an ESP32-C3.

The current firmware distribution does not provide an approved C3 native debugger image. Preserve existing working C3 installations. The historical C3 transport investigation is preserved in [PR #8](https://github.com/niwantha33/micropython_live_debugger/pull/8) and its exact [source revision](https://github.com/niwantha33/micropython_live_debugger/tree/eacdb3f91b3d43b1ac8544b6f8cc0a6de654f6cf). It is documentation, not a firmware implementation or a complete physical qualification report.

Reference: [Espressif USB Serial/JTAG console documentation](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32c3/api-guides/usb-serial-jtag-console.html).
