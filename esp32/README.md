# ESP32-S3 debugger hardware-test layout

For the current hardware-validation phase use the two ESP32-S3 USB interfaces
for separate jobs:

```text
USB-Serial/JTAG connector  -> MicroPython REPL + file upload
Native USB connector       -> MicroPython Studio debugger + RTA
```

This is intentional for the current test. Do not use the native debugger COM
port for MIP, raw REPL, or project file upload.

## Why

Hardware testing proved that the USB-Serial/JTAG path is reliable for the
MicroPython REPL and file transfer, while the native USB debugger CDC is already
working for breakpoint set/clear/continue and RTA control.

Keeping those paths separate also reduces USB traffic while the ESP32-specific
RTA watchdog issue is validated.

## Boot sequence

The debugger code is frozen into the firmware.

Before TinyUSB starts, `mpy_studio_boot` creates one native CDC interface for
the debugger. The normal REPL remains on USB-Serial/JTAG.

After `mp_usbd_init()`, `mpy_studio_start.py` starts the frozen
`trace_pump` thread.

This two-phase startup avoids starting the debugger thread while USB is still
being initialised.

## What to connect

Connect both board USB connectors during the current test:

1. **Serial/JTAG USB** — use this in MicroPython Studio as the project/device
   port for upload and Shell.
2. **Native USB** — select this only from **Start Debug -> Connect only**.

Windows COM numbers can change. Identify the Serial/JTAG port by the normal
MicroPython `>>>` prompt.

## Do not install usb-device-cdc

The required `usb-device` and `usb-device-cdc` packages are frozen into the
test firmware.

Do not run MIP installation for `usb-device-cdc` on either port.

## First debugger test

Use a small program and test in this order:

1. upload through Serial/JTAG,
2. run the program,
3. Connect only to the native debugger COM,
4. set one breakpoint,
5. hit the breakpoint,
6. inspect locals,
7. continue,
8. remove the breakpoint.

Only then test RTA.

## RTA test

The ESP32 test firmware uses bounded native-CDC buffering and shorter pump
bursts to avoid long IRQ-off buffer compaction under RTA traffic.

Start with a 30-second test:

1. RTA On,
2. let the program run,
3. do not press Refresh Names repeatedly,
4. RTA Off,
5. confirm there is no watchdog reset.

## Task Map

The RP2 Task Map implementation uses RP2040/RP2350-specific memory offsets.
It remains disabled on ESP32-S3 until a separate implementation is validated.


## Hardware-validation checkpoint — 2026-10-08 (FROZEN FOR TESTING)

**Development remains on `feature/esp32-s3-debugger-v1`, PR #4. Do not merge or publish this candidate.**
Last verified CI candidate: `e36296ad62ebaac1e94a368711ea5ea7abcb596e`;
workflow [37687220777](https://github.com/niwantha33/micropython_live_debugger/actions/runs/37687220777)
completed successfully and uploaded artifact `debug-firmware-esp32s3-test`.
An earlier run [37682501856](https://github.com/niwantha33/micropython_live_debugger/actions/runs/37682501856) was cancelled; compilation alone never proves device stability.

Observed on the ESP32-S3 test board (not a full acceptance or 30-second stress test):

- USB-Serial/JTAG port (shown as COM11): normal project execution and MicroPython `os.uname()` response;
  firmware reports ESP32-S3, MicroPython `1.30.0-preview`, upstream `a129b2fba1`.
- Native debug USB port (shown as COM13): Studio debugger connected.
- `set_bp main:hello:10 rel=5` returned `bp 0 @ main.hello:5 ip=19 fun=1070307040`.
  A `BP_HIT` was received and Continue/Locals/Globals/Call Stack were invoked.
  The stack reply was `[(1070307040, 19), (1070289424, 4017)]`.
- RTA captured 1,056 events across 12 function identifiers in a 3.17-second trace,
  and `RTA Off` received the `RTA trace disabled` reply.

**Still outstanding:** verify a full 30-second RTA On/Off run without CPU1 Interrupt WDT,
USB disconnect or COM-port reset; verify breakpoint removal/step variants and local values
on this exact candidate; verify firmware build identity on-device independently.
Keep the physical Serial port reliable. Never install `usb-device-cdc` with MIP
for this firmware: it is frozen. Do not upload the Pico debugger's `boot.py` or
`trace_pump.py` to the ESP32.

### How to interpret RTA time

`Observed VM % = function exclusive interval time / sum of all measured exclusive interval time × 100`.
Function *Total* in the existing viewer is **inclusive** time, while the percentage is
calculated from **exclusive** time; neither is FreeRTOS CPU utilization.
The current RTA firmware timestamps MicroPython execution-context transitions,
so blocked/sleeping/native time is not separately classified. For example,
the observed `0x3fcb4310` ~98.7% is an unresolved function identifier, **not** proof
of 98.7% ESP32 CPU usage. Function-name resolution and a distinct true scheduler
CPU/idle metric are future improvements; avoid claiming to measure them already.

### Pico coexistence policy

Keep the stable Pico/RP2 debugger and its published UF2s unchanged while a separate
`feature/pico-frozen-debugger-v1` candidate implements frozen, self-starting
Pico debugger helpers. The Studio host's candidate "Connect only" experience
is developed separately on `feature/frozen-debugger-connect-only`.
No firmware from these test branches is automatically released.
