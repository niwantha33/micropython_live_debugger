"""Source-side regression test for Pico frozen USB debugger bootstrap.

Runs only on the CI host; never accesses or changes actual board files.
"""
import pathlib
import runpy
import sys
import types
import unittest
from unittest.mock import patch

FROZEN = pathlib.Path(__file__).resolve().parents[1] / "frozen"


class FrozenPicoBootstrapTests(unittest.TestCase):
    def test_usb_registration_is_early_and_pump_start_is_late(self):
        events = []
        dbgref = types.ModuleType("mpy_studio_pico_dbgref")
        dbgref.cdc = None
        pump = types.ModuleType("mpy_studio_pico_trace_pump")
        pump.start = lambda: events.append("start_pump")

        class FakeCDC:
            def __init__(self, **kwargs):
                events.append(("create_cdc", kwargs))

        usb = types.ModuleType("usb")
        usb.__path__ = []
        device = types.ModuleType("usb.device")
        device.__path__ = []
        cdc = types.ModuleType("usb.device.cdc")
        cdc.CDCInterface = FakeCDC
        device.get = lambda: types.SimpleNamespace(
            init=lambda obj, **kw: events.append(("init", obj, kw))
        )
        usb.device = device

        fake_modules = {
            "usb": usb,
            "usb.device": device,
            "usb.device.cdc": cdc,
            "mpy_studio_pico_dbgref": dbgref,
            "mpy_studio_pico_trace_pump": pump,
        }
        with patch.dict(sys.modules, fake_modules):
            ns = runpy.run_path(str(FROZEN / "mpy_studio_pico_boot.py"))
            self.assertEqual(events[0][0], "create_cdc")
            self.assertEqual(events[1][0], "init")
            self.assertTrue(events[1][2]["builtin_driver"])
            self.assertEqual(events[0][1]["timeout"], 0)
            self.assertIsNotNone(dbgref.cdc)
            self.assertIs(sys.modules["dbgref"], dbgref)
            self.assertNotIn("start_pump", events)
            # The first boot phase must not start a thread until USB is ready.
            boot = types.ModuleType("mpy_studio_pico_boot")
            boot.start_pump = ns["start_pump"]
            sys.modules["mpy_studio_pico_boot"] = boot
            runpy.run_path(str(FROZEN / "mpy_studio_pico_start.py"))
            self.assertEqual(events[-1], "start_pump")
            self.assertIs(sys.modules["trace_pump"], pump)

        # Undo the test-only aliases that may have been present beforehand.


if __name__ == "__main__":
    unittest.main()
