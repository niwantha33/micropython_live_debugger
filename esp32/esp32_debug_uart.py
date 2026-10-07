# esp32_debug_uart.py
#
# ESP32-S3 debugger transport v1.
#
# RP2 uses a second USB CDC.  ESP32-S3 v1 deliberately uses a dedicated
# hardware UART so the normal MicroPython REPL/flash port remains untouched.
# The existing binary debugger protocol is unchanged.
#
# Hardware:
#   ESP32-S3 TX(debug) -> USB-UART RX
#   ESP32-S3 RX(debug) <- USB-UART TX
#   ESP32-S3 GND       -- USB-UART GND
#
# Start manually from the normal REPL for the first hardware tests:
#   import esp32_debug_uart
#   esp32_debug_uart.start(tx=17, rx=18)
#
# Do not connect 5V to ESP32 GPIO. Use a 3.3V UART adapter.

from machine import UART

_uart = None
_transport = None


class UARTDebugTransport:
    def __init__(self, uart):
        self._uart = uart
        # trace_pump's transport contract uses these names for CDC host state.
        # A hardware UART has no DTR/open enumeration state, so it is considered
        # permanently available while this object is installed.
        self.dtr = True

    def is_open(self):
        return True

    def read(self, n=-1):
        if n is None or n < 0:
            return self._uart.read()
        return self._uart.read(n)

    def write(self, data):
        return self._uart.write(data)


def _esp32_taskmap():
    # The RP2 implementation reads internal asyncio object fields through
    # machine.mem32 offsets. Those offsets are not portable across ESP32
    # architectures/builds and must never be guessed here.
    return "unsupported: ESP32 task-map needs a port-specific implementation"


def _esp32_tasks():
    # Safe presentation only: no architecture-specific pointer arithmetic.
    try:
        import asyncio
        q = asyncio.core._task_queue
        return repr(q)
    except Exception as e:
        return "err: " + repr(e)


def start(tx, rx, baud=115200, uart_id=1):
    global _uart, _transport

    if _transport is not None:
        print("esp32 debug UART: already configured")
        return

    # timeout=0 keeps the debugger pump non-blocking.
    _uart = UART(
        uart_id,
        baudrate=baud,
        tx=tx,
        rx=rx,
        bits=8,
        parity=None,
        stop=1,
        timeout=0,
        timeout_char=0,
        rxbuf=4096,
        txbuf=4096,
    )
    _transport = UARTDebugTransport(_uart)

    import dbgref
    dbgref.cdc = _transport

    import trace_pump
    # Replace RP2-only asyncio memory-layout helpers before starting the pump.
    trace_pump.get_taskmap = _esp32_taskmap
    trace_pump.get_tasks = _esp32_tasks
    trace_pump.start()

    print("esp32 debug UART: started uart=%d tx=%d rx=%d baud=%d" % (
        uart_id, tx, rx, baud
    ))


def stop():
    global _uart, _transport
    try:
        import trace_pump
        trace_pump.stop()
    except Exception:
        pass
    if _uart is not None:
        try:
            _uart.deinit()
        except Exception:
            pass
    _uart = None
    _transport = None
    print("esp32 debug UART: stopped")
