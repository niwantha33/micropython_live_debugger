import ast
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

PUMP = Path(__file__).resolve().parents[1] / "frozen" / "mpy_studio_trace_pump.py"


class ScopeReplies(unittest.TestCase):
    def load(self, dbg):
        spec = importlib.util.spec_from_file_location("esp32_pump", PUMP)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"dbg": dbg}):
            spec.loader.exec_module(module)
        return module

    def test_correct_scope(self):
        pump = self.load(types.SimpleNamespace(globals=lambda depth: {"__name__": "fixture", "count": 73419}))
        reply = pump._globals_reply(0)
        self.assertEqual(ast.literal_eval(reply.split("globals=", 1)[1]), {"count": "73419"})

    def test_no_fallback(self):
        for dbg in (types.SimpleNamespace(), types.SimpleNamespace(globals=lambda depth: None),
                    types.SimpleNamespace(globals=lambda depth: {"__name__": "mpy_studio_trace_pump", "cmds": 5})):
            self.assertIn("globals_unavailable=", self.load(dbg)._globals_reply(0))

    def test_oversized_and_unicode_are_not_truncated(self):
        for value in ("x" * 300, "é" * 180):
            reply = self.load(types.SimpleNamespace(globals=lambda depth: {"value": value}))._globals_reply(0)
            self.assertIn("globals_unavailable=", reply)
            self.assertLessEqual(len(reply.encode()), 250)

    def test_unsupported_depth_is_explicit(self):
        def unsupported(depth):
            raise ValueError("depth")
        self.assertIn("globals_unavailable=", self.load(types.SimpleNamespace(globals=unsupported))._globals_reply(1))
