# Pico family — self-contained debugger test firmware (NOT released)

This is a **test candidate** on branch `feature/pico-frozen-debugger-v1`. It is
not merged or published to the stable firmware repository. The original Pico
firmware and RP2 debugger workflow on `main` remain unchanged.

## Goal

After flashing a compatible *frozen-debugger* UF2 once, developers should
**never have to upload** `boot.py`, `dbgref.py`, or `trace_pump.py` merely to
start the debugger.

| Target | REPL/upload | Dedicated debugger |
| --- | --- | --- |
| Pico, Pico W, Pico 2, Pico 2 W | USB CDC0 | USB CDC1 |
| ESP32-S3 (separate development branch) | Physical USB-Serial/JTAG | Physical native USB debugger CDC |

Both Pico CDC ports use **one physical USB cable**. Choose the REPL COM for
file operations and the debug CDC COM for `Start Debug → Connect only`.

## What's built into the new Pico UF2

- Original RP2 USB REPL CDC0 stays enabled.
- `usb-device` and `usb-device-cdc` are compiled as frozen packages.
- `mpy_studio_pico_boot.py` registers CDC1 before `mp_usbd_init()`.
- `mpy_studio_pico_start.py` starts the pump after `mp_usbd_init()`.
- `mpy_studio_pico_dbgref.py` and a *pinned* `mpy_studio_pico_trace_pump.py`
  are frozen; aliases `dbgref` and `trace_pump` resolve to the frozen modules.
- The upstream RP2 filesystem `_boot.py` remains untouched, and neither
  new helper writes to the board's filesystem.
- The source pump is pinned to Studio commit
  `a62aa231ee15bec41de0a8f9a7bdc89bbbaae975` and verified at Git blob
  `f7bded9d6180849e9e92cdd9e06bca4c223ca2bc` (protocol 5).

**Critical:** compiling and freezing do not prove that two CDC COM ports are
stable on physical RP2040/RP2350 hardware.

## One-time installation and daily use (after hardware validation)

1. Download the **correct board-specific** `debug-firmware-*-frozen-test`
   Actions artifact from this branch/PR. Do not use another board's UF2.
2. On the board, hold BOOTSEL while plugging USB in. Copy the candidate UF2
   onto the USB mass-storage drive. This updates firmware, not the
   `main.py`/project filesystem intentionally.
3. With the normal USB cable connected, locate the **REPL CDC0** COM port
   (the one showing `>>>`).
4. In MicroPython Studio, configure the REPL COM for project upload and Shell.
5. Choose **Start Debug → Connect only**, then select the distinct CDC1 COM.
6. Run your application; test breakpoint hit, inspect locals/call stack,
   Continue, remove breakpoint, then RTA On/Off.

Do **not** press the older **Upload debugger files** option with this UF2.
Do **not** install `usb-device-cdc` over MIP on this firmware.

### Existing Pico filesystem migration

Older Studio configurations uploaded `boot.py` to the Pico filesystem.
That legacy file can initialize USB again and conflict with the frozen USB
setup. **Do not automatically delete users' files.** Before flashing the
candidate, inspect `os.listdir('/')` on the REPL. If a previously uploaded
*Studio debugger boot.py* is present, back it up and rename that particular
legacy file manually. Preserve an unrelated user-written boot.py.
Do not overwrite or erase application files.

For an existing Pico with the **old** published UF2, the legacy debugger-file
upload workflow may still be required; this new candidate does not retroactively
change previously flashed devices.

### Acceptance checks before replacing published Pico firmware

- [ ] CI builds **all four** Pico boards and confirms the embedded pump.
- [ ] Fresh Pico 2 W boots with two stable USB CDC ports and a `>>>` REPL.
- [ ] Fresh Pico/Pico W/Pico 2 builds are separately checked on actual boards
      before those variants are marked supported.
- [ ] File upload over CDC0 still works (including a repeated upload).
- [ ] Debugger CDC1 connects without writing files to the Pico filesystem.
- [ ] Set/hit/remove breakpoint, locals, globals, step/Continue and call stack.
- [ ] RTA On for 30 seconds, RTA Off, no crash/USB re-enumeration.
- [ ] Soft reset, hardware reset, unplug/replug recover cleanly.
- [ ] Existing *stable* Pico debugger firmware and ESP32-S3 branch unaffected.

Only after board-specific hardware validation: review/merge intentionally and
publish each approved UF2. CI artifacts are **test-only**, never auto-deployed.

## Firmware integration and USB disappearance diagnostics

The frozen two-CDC image is experimental. Its source branch originally carried
`0020-rta-function-name-replies.sh`, which writes function names as unverified
0x03 replies. Firmware `main` now uses the alternative, opt-in and CRC-checked
`0020-rta-name-metadata.sh` (0x07) from PR #10. **Do not combine both**: the
firmware patch runner applies every `0*.sh` and both would add redundant VM
hook work/frames. This integration change removes the former emitter from the
frozen candidate branch. When this branch is integrated with firmware `main`,
retain the 0x07 metadata patch. It is disabled by default until host opt-in.

A Windows REPL error such as `FileNotFoundError: could not open COM8` means the
selected port **does not exist at that moment**. It alone cannot distinguish a
stale COM assignment from board reset/USB enumeration failure.

1. Unplug the board, capture `Get-PnpDevice -PresentOnly -Class Ports` from
   PowerShell, then reconnect the same cable and capture it again. For the
   frozen Pico candidate, expect a new CDC0 (REPL) and CDC1 (debugger) COM port.
2. Select the **current** CDC0 for REPL and the distinct CDC1 for debugger.
   Windows can reassign port numbers after reflash/re-enumeration.
3. With RTA OFF, check repeated connect/disconnect; then run RTA ON/OFF and
   repeat the listing. If both ports vanish unexpectedly, capture the time
   and the last REPL/device traceback; suspect reset, USB or firmware crash.
4. If the REPL port works but CDC1 is missing, inspect the board's boot output.
   A *legacy* Studio `boot.py` may try to initialise USB a second time and
   conflict with the frozen early bootstrap. Back up and inspect the file;
   **never automatically delete or overwrite user boot.py**.
5. If no valid COM ports appear, do not repeatedly connect to the old number.
   Restore the exact board-specific last-working UF2 only if recovery is
   required and user files have been backed up. No automated flashing.

Build success only verifies code compilation; two stable Windows COM ports,
REPL/file upload and debugger operation require a real-board smoke test.

## RTA time explanation

`Observed VM %` is **not CPU utilization**. It is the percentage of recorded
exclusive MicroPython execution-segment elapsed time attributed to a function
identifier. The table's Total is inclusive time; sleeping/waiting/FreeRTOS
idle are not isolated as a scheduler CPU-load measurement. A value such as
`0x3fcb4310 98.7%` means the RTA name is unresolved; it is not evidence of
98.7% CPU usage. Do not label this as CPU% without a separate scheduler
runtime measurement.
