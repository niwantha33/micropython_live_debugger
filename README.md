# MicroPython Studio — Native Debugger Source

This is the firmware engineering repository for MicroPython Studio. It contains changes to the MicroPython virtual machine and board-side debugger transport. It is not a separate end-user IDE or the official firmware download location.

## Where to go

| Repository | Responsibility |
| --- | --- |
| [MicroPython Studio](https://github.com/niwantha33/micropython-studio) | VS Code extension, REPL, file transfers, debugger UI, runtime analysis and qualification |
| **This repository** | Native VM patches, board-specific debugger integration, firmware candidate builds |
| [MicroPython Studio debugger firmware](https://github.com/niwantha33/micropython_live_dbg_firmware) | Official board-specific firmware downloads, pinned releases and weekly test candidates |

For installation and normal debugging, start with the Studio repository and download firmware for your exact board from the firmware distribution repository. Do not flash historical UF2 files checked into this source tree or use development artifacts as approved releases.

## Firmware architecture

The native debugger adds a bytecode dispatch hook to the upstream MicroPython VM and a built-in `dbg` module for breakpoints, stepping, paused state inspection and trace events. A board-side pump bridges the native debugger and the dedicated USB CDC channel. Studio's host bridge consumes that protocol.

The frozen RP2 candidate keeps CDC0 for REPL and file transfers and CDC1 for debugging. ESP32-S3 uses separate Serial/JTAG and native USB connections. These board integrations are development candidates; compilation and hardware qualification are distinct.

## Source and build status

| Source | Purpose |
| --- | --- |
| `main` | Default native patch history; not automatically the approved distributed firmware |
| [RP2 integrated candidate PR #13](https://github.com/niwantha33/micropython_live_debugger/pull/13) | Frozen RP2 integration, paused globals and stepping corrections; includes the earlier #12 work |
| [ESP32-S3 PR #4](https://github.com/niwantha33/micropython_live_debugger/pull/4) | Separate ESP32-S3 integration |

The RP2 candidate at `fb1a08186b060bf757191ba9f4fad273ff2abd38` passed the [four-board candidate build](https://github.com/niwantha33/micropython_live_debugger/actions/runs/45800043339). Two consecutive Pico 2 W physical qualification runs were reported successful with the corresponding Studio test branch. This is evidence for that tested combination, not approval for other boards or general release.

## Repository layout

- `firmware/patches/`: ordered native source modifications; `firmware/MICROPYTHON_REF` pins upstream MicroPython.
- `firmware/BUILD.md`: build and safety instructions.
- `rp2/` on the integrated candidate: frozen startup modules and tests.
- `host/` and `target/`: original prototype tools and test fixtures. Not current Studio installation instructions.
- `protocol/SPEC.md`: historical wire protocol reference; consult the matching Studio bridge and firmware pump for the current implementation.
- `.github/workflows/`: build-only candidate CI with version metadata and matching ELF symbols.

## Building and publishing

See [firmware build instructions](firmware/BUILD.md). Use the exact source revision and the board-specific CI workflow. A CI build does not establish physical hardware compatibility.

The distribution repository maintains independent pinned inputs, checksums, and publication policy. Changes here must not silently replace published firmware or advance those pins. Keep source branches and commits referenced by existing distributions available.

[Historical development notes](ROADMAP.md) describe the original prototype, not current release status.

## License

[MIT](LICENSE). Built on MicroPython by Damien George and contributors.
