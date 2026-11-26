# Native debugger firmware — build instructions

This repository builds firmware candidates for MicroPython Studio. Official downloads and publication rules are in [micropython_live_dbg_firmware](https://github.com/niwantha33/micropython_live_dbg_firmware).

## Recommended: reproducible CI

Use the appropriate source branch or PR and its GitHub Actions workflow. Candidate builds retain the exact source commit, upstream MicroPython revision, board identifier, checksum and matching ELF (and map when available).

- Default branch: [Build debugger firmware](../.github/workflows/build-firmware.yml) — native RP2 patch build.
- [Integrated RP2 candidate](https://github.com/niwantha33/micropython_live_debugger/pull/13): frozen CDC bootstrap and debugger pump, four Pico targets. Use its **Build frozen Pico + RTA integration candidate** workflow, not the older native-only build, when evaluating Studio's frozen debugger.
- [ESP32-S3 integration](https://github.com/niwantha33/micropython_live_debugger/pull/4): separate board-specific build and transport.

Select the correct board artifact and verify VERSION.txt and SHA256 before flashing a dedicated test board. CI compilation is not hardware qualification or release approval. Do not publish directly from source CI.

## Local legacy RP2 build

The existing `apply.sh` and `build.sh` are development scripts for the native RP2 patch chain; they do not reproduce the complete frozen candidate workflow by themselves.

**Warning:** `apply.sh` runs `git checkout .` and `git clean -fd` against MPY_DIR. Use a disposable MicroPython clone, never a working tree with user changes. `build.sh` removes board build directories and writes UF2 files in the source repository.

On Linux or WSL with an ARM toolchain, CMake, Git and Python installed, use the upstream SHA in `MICROPYTHON_REF`. Review the CI workflow for exact dependency and build steps. The local scripts already isolate PATH from Windows tools and force matching picotool discovery.

## Qualification

The corresponding Studio repository provides `npm run qualify` for software tests and `npm run qualify:hardware` for opt-in physical tests. Use a dedicated board, correct firmware and explicitly selected USB interfaces. Preserve the report with exact firmware artifact metadata and Studio commit.

Never promote a distribution pin based only on a successful build. Keep historical source commits, branches and release assets available for reproducibility.
