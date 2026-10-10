# MicroPython Live Debugger

A live, bytecode-level MicroPython debugger, validated on Pico 2 W and under isolated development for other Pico boards and ESP32 targets.
Set breakpoints, step through code, inspect named locals, view the call stack,
and use **conditional breakpoints** — all on a running board, over USB, with a
VS Code UI.

No JTAG. No `sys.settrace`. No print-debugging.

## Board and firmware status — 8 October 2026

| Target | Current evidence | Safe distribution status |
| --- | --- | --- |
| Raspberry Pi Pico 2 W | Existing debugger works on real hardware, including breakpoints/stepping/RTA | Current published UF2 remains unchanged; newer frozen no-upload candidate awaits hardware validation |
| Pico / Pico W / Pico 2 | New frozen firmware builds passed CI for all four Pico targets ([run 37741930577](https://github.com/niwantha33/micropython_live_debugger/actions/runs/37741930577)) | New candidates are **test artifacts only**; do not treat compile success as hardware acceptance |
| ESP32-S3 | Serial COM for REPL/upload, native USB COM for debug; breakpoint and short RTA verified | Test branch [PR #4](https://github.com/niwantha33/micropython_live_debugger/pull/4); 30-second RTA, soft reset and recovery pending; not published |
| ESP32-C3 | Hardware feasibility review: fixed USB Serial/JTAG, no programmable USB OTG | **No debug firmware candidate yet.** [Design and later board test](esp32c3/README.md) |

**No-upload debugging:** the planned supported workflow is **flash the correct
debugger-enabled firmware once → REPL/file-upload port → Start Debug → Connect only
on the independent debugger port**. For Pico the two CDC ports share one cable;
on the tested ESP32-S3 the two physical connectors serve different purposes.
Older Pico UF2 firmware may still need the explicitly selected *legacy* file
upload; do not overwrite users' unrelated `boot.py` files.

**Release isolation:** Pico frozen firmware is in
[`feature/pico-frozen-debugger-v1`](https://github.com/niwantha33/micropython_live_debugger/tree/feature/pico-frozen-debugger-v1)
(draft PR #6), S3 in `feature/esp32-s3-debugger-v1` (PR #4), and the C3
feasibility investigation in `feature/esp32-c3-feasibility-v1`.
The matching Studio UX lives in
[`feature/frozen-debugger-connect-only`](https://github.com/niwantha33/micropython-studio/tree/feature/frozen-debugger-connect-only)
(draft PR #52). **Do not merge, replace published binaries, or advertise hardware
support until board-specific acceptance.**

**RTA semantics:** `Observed VM %` is the proportion of *exclusive elapsed
MicroPython execution-segment time* captured by the tracer; it is not MCU CPU
utilization. `Total` is inclusive time. Native waits/sleeps and unresolved
function addresses must not be labelled as CPU load.

## Features

- **Breakpoints** — click in the gutter, just like a real debugger
- **Step over / step in / step out / continue**
- **Named locals** — see `x = 32, y = 30, z = 62` not raw stack slots
- **Call stack** with function names, click a frame to jump to source
- **Conditional breakpoints** — `b > 1`, supports Python `and / or / not`
- **Live line highlight** of the paused line
- **Connect only** with new firmware that freezes the debugger helpers (separate candidates); explicit legacy file-upload option retained for older Pico firmware
- **Robust port handling** — friendly errors when COM port is busy
- **Two USB CDCs** — debugger frames on CDC1, REPL stays untouched on CDC0

## Target hardware

**Raspberry Pi Pico 2 W (RP2350).** Dual USB-CDC built in.

ESP32-S3: USB-Serial/JTAG REPL and native USB debugger have been exercised on hardware, with 30-second RTA/recovery acceptance pending; see PR #4. ESP32-C3: feasibility research only; its fixed USB Serial/JTAG controller **cannot implement the S3 TinyUSB dual-CDC gadget layout**.

## Quick start

### 1. Flash the firmware

1. Hold **BOOTSEL**, plug Pico USB in — it appears as `RP2350` drive
2. Drag `firmware.uf2` onto it
3. Pico reboots automatically

### 2. Install the VS Code extension

```
code --install-extension micropython-studio-1.0.0.vsix
```

Or in VS Code: `Ctrl+Shift+P` → **Install from VSIX**.

### 3. First debug session

1. Open a `.py` file with a function (`def foo(): ...`)
2. Click the **▶ Start Debug** button in the status bar
3. Click in the gutter to set a breakpoint
4. In the REPL: `import yourfile; yourfile.foo()`
5. Execution pauses at your breakpoint. The panel shows locals + call stack.

## How it works

We patch the MicroPython VM (`py/vm.c`) with a one-line hook in the bytecode
dispatch loop. The hook calls into a new module `moddbg.c` which:

- Holds the breakpoint table (slot → ip) and stepping flags
- Snapshots a shadow call stack at pause time
- Exposes `dbg.set_bp / clear_bp / locals / frame_info / call_stack / resume / step / step_in / step_out` to Python

A Python-side **trace pump** (`trace_pump.py`) runs in a second thread, drains
debug frames from the C ring buffer to a dedicated USB-CDC interface, and
parses commands from the host.

The VS Code extension talks to that CDC port via `dbg_bridge.py` (pyserial),
parses event frames (`bp_hit`, `reply`), and renders the UI. Conditional
breakpoints are evaluated **client-side in the extension** — when a BP fires
with a condition, the extension fetches locals, evaluates `b > 1` in JS, and
either pauses or silently resumes.

## Building from source

Requires WSL (or Linux/macOS) with the Pico SDK toolchain installed.

```bash
git clone --recursive https://github.com/niwantha33/micropython_live_debugger
cd micropython_live_debugger
export MPY_DIR=$HOME/micropython
git clone --recursive https://github.com/micropython/micropython.git $MPY_DIR

# Build all firmwares (Pico W, Pico 2 W, Pico, Pico 2)
cd firmware
./build.sh
```

The script [build.sh](firmware/build.sh) automatically:
1. Resets the MicroPython repository to a clean state.
2. Applies all patches sequentially.
3. Clears stale CMake configurations for each target.
4. Generates four separate `.uf2` firmware binaries in the `firmware/` directory:
   * `firmware_pico_w.uf2` — Raspberry Pi Pico W (Wi-Fi RP2040)
   * `firmware_pico2_w.uf2` — Raspberry Pi Pico 2 W (Wi-Fi RP2350)
   * `firmware_pico2.uf2` — Raspberry Pi Pico 2 (non-Wi-Fi RP2350)
   * `firmware_pico.uf2` — Raspberry Pi Pico (non-Wi-Fi RP2040)

## Repo layout

```
firmware/
  patches/                  numbered debugger patches for MicroPython
  firmware_pico_w.uf2       Pre-built firmware for Pico W (Wi-Fi RP2040)
  firmware_pico2_w.uf2      Pre-built firmware for Pico 2 W (Wi-Fi RP2350)
  firmware_pico2.uf2        Pre-built firmware for Pico 2 (non-Wi-Fi RP2350)
  firmware_pico.uf2         Pre-built firmware for Pico (non-Wi-Fi RP2040)
host/
  trace_pump.py             Runs on the Pico, pumps debug frames over CDC1
  dbgref.py                 Holds reference to CDC1 device
target/
  nested.py                 Test program (3-level call stack)
protocol/                   Wire format spec
```

## Wire protocol

Frames are `[0xAA][type][len][payload]`.

| Type | Direction   | Meaning           |
|------|-------------|-------------------|
| 0x01 | board → pc  | trace event       |
| 0x02 | board → pc  | bp_hit            |
| 0x03 | board → pc  | reply text        |
| 0x10 | pc → board  | continue          |
| 0x11 | pc → board  | step              |
| 0x12 | pc → board  | locals            |
| 0x13 | pc → board  | step_in           |
| 0x14 | pc → board  | step_out          |
| 0x15 | pc → board  | set_bp_line       |
| 0x16 | pc → board  | clear_bp          |
| 0x17 | pc → board  | call_stack        |

## Status

**v1.0.1 — bugfix release.** Stable end-to-end on Raspberry Pi Pico 2 W.

### v1.0.1 changes
- Upload corruption fixed (raw-paste flow control)
- Download corruption fixed (HEXLEN/HEXSTART markers + chunked print)
- Single-file and folder uploads now share the reliable one-shot path
- mip PC-side fallback works again on devices without WiFi
- Shell terminal no longer leaks venv-activate text into the REPL

Verified working with:
- Synchronous code (loops, function calls, recursion)
- **Async code** — breakpoints hit inside `asyncio` coroutines
- Multi-frame call stacks (3+ levels deep)
- Conditional breakpoints with Python operators

Known limitations:
- Step-in across function boundaries doesn't update the source highlight
  (only known BP locations are mapped to lines)
- BPs are limited by firmware slot count (default 8)
- No watch expressions yet
- Only one breakpoint condition at a time (no hit-counts)
- VS Code Python extension auto-activates venv into terminals — disabled
  workspace setting on first run

## Roadmap

See [ROADMAP.md](ROADMAP.md). Next:
- ESP32-S3 30-second RTA and reconnect hardware acceptance
- Pico family self-contained firmware hardware acceptance (PR #6)
- ESP32-C3 transport feasibility and board identification (see esp32c3/README.md)
- Watch expressions
- Persistent device console (one port owner, no contention)
- Variable edit (poke value into running program)

## License

MIT — see [LICENSE](LICENSE).

If you make changes or derivative work, please let me know:
- Email: niwantha33@gmail.com
- Repo: https://github.com/niwantha33/micropython_live_debugger

So improvements can be folded back upstream.

## Credits

Built on MicroPython by Damien George and contributors.
