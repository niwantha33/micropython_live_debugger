# ESP32-C3 debugger feasibility — design checkpoint (2026-10-08)

**Status:** research and hardware identification only. **No ESP32-C3 debugger
image has been built, flashed, validated or published by this work.** This is a
separate exploratory branch. Do not alter stable Pico firmware or the
hardware-tested ESP32-S3 branch.

## Key hardware difference: ESP32-C3 is not ESP32-S3

The ESP32-C3 has a **fixed-function USB Serial/JTAG controller** that exposes
a CDC-ACM serial channel and JTAG. It does **not** provide the configurable
native USB OTG controller used by our ESP32-S3 TinyUSB debugger CDC.

Espressif official source:
[ESP-IDF 5.5: ESP32-C3 USB Serial/JTAG console](https://docs.espressif.com/projects/esp-idf/en/v5.5/esp32c3/api-guides/usb-serial-jtag-console.html).
This is a SoC-level fact; individual boards may add their own USB-UART bridge,
so inspect the **actual board**, not just the SoC label.

The pinned MicroPython `ESP32_GENERIC_C3` board supports UART REPL and the
ESP32 port defaults `MICROPY_HW_ENABLE_USBDEV` to `SOC_USB_OTG_SUPPORTED`.
Do not copy the S3 `usb.device.cdc.CDCInterface` / two-phase TinyUSB patch:
the C3 has no USB OTG gadget controller for it.

## Transport choices to evaluate (NOT IMPLEMENTED)

| Option | REPL / upload | Debugger / RTA | Preconditions |
| --- | --- | --- | --- |
| A: two independently exposed serial channels (preferred when available) | Existing working C3 USB Serial/JTAG or board USB-UART | Separate UART transport exposed via a second USB-UART interface | Check actual C3 board connectors, UART availability, routing, voltage and COM enumeration. Do not guess pins. |
| B: Wi-Fi debugger | Existing stable REPL port | Bounded authenticated local TCP transport | Separate transport implementation, reset/reconnect behaviour, security and timing validation. |
| C: shared serial multiplexing (last resort) | Shared COM | Framed debugger over same COM | Requires nontrivial protocol arbitration to preserve raw REPL / file upload; do not route two independent serial clients to one COM. |

**No option should be enabled automatically.** Avoid interpreting COM enumeration
as proof of usable debugging or file transfer. The PC-side Studio bridge currently
expects an independent debugger COM, so options B/C also require host changes.

## C3 execution and watchdog risks

- ESP32-C3 is a **single-core RISC-V** part, unlike dual-core ESP32-S3.
- The debugger VM breakpoint busy-wait and background pump have not been
  validated under single-core FreeRTOS scheduling/GIL interactions.
- Before porting any `dbg` hooks, audit pause/resume, sleep/yield, interrupt
  watchdog safety, stack usage, trace ring overflow and soft-reset cleanup.
- `Observed VM %` is *not* actual CPU usage; do not mistake long waits for CPU
  saturation.
- Keep the existing C3 normal REPL and ability to recover by USB working
  before testing a debugger firmware.

## Read-only baseline to collect when the actual C3 board is available

1. Photograph both sides of the board and label all physical connectors.
2. Connect its normal USB cable; note which Windows COM ports appear.
3. Open a normal MicroPython REPL and run:
   ```python
   import os
   print(os.uname())
   print(os.listdir("/"))
   ```
4. Record board/module identification and current firmware version.
5. Confirm ordinary upload and a `print()` script over the currently working
   REPL port. Do not flash, delete files, or install debugger helpers.
6. Only after exact board identification, choose transport A/B/C and document
   the recovery path. Never invent GPIO pin assignments.

## Proposed implementation sequence (gated)

- [x] Research USB controller / pinned C3 MicroPython target.
- [x] Keep C3 investigation isolated from Pico and S3 release work.
- [ ] Identify user's **specific** C3 board, USB connector(s), USB-UART bridge,
      available UART and actual COM ports (hardware evidence required).
- [ ] Select and document a separate transport preserving REPL/upload.
- [ ] Audit RISC-V C debugger hooks and single-core breakpoint servicing.
- [ ] Add target-specific, opt-in CI build for `ESP32_GENERIC_C3`, with no publish.
- [ ] Check build identity, startup, reboot and recovery before flashing.
- [ ] Hardware test: REPL/upload, connect, set/hit/clear breakpoint, locals,
      stack, step/continue.
- [ ] RTA On/Off for 30 seconds, watchdog/reset and buffer-loss observations.
- [ ] Explicit board-specific acceptance; only then consider publication.

### Other branches

- Stable Pico code/binaries: `main`, unchanged by this feasibility work.
- Pico frozen no-upload candidate: `feature/pico-frozen-debugger-v1`, draft PR #6.
- ESP32-S3 native USB test candidate: `feature/esp32-s3-debugger-v1`, PR #4.
- Studio Connect-only UX candidate: `feature/frozen-debugger-connect-only`, draft PR #52.
