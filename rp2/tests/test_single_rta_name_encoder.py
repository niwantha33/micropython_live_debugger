"""Keep the firmware name metadata wire format unambiguous on branch merges.

Both historical 0020 prototypes would be applied by the firmware build's
firmware/patches/0*.sh glob. No new hardware is required for this assertion.
"""
from pathlib import Path
import unittest


PATCHES = Path(__file__).resolve().parents[2] / "firmware" / "patches"


class SingleRtaNameEncoderTests(unittest.TestCase):
    def test_at_most_one_rta_name_encoder_patch(self):
        candidates = sorted(p.name for p in PATCHES.glob("0020-rta-*.sh"))
        self.assertLessEqual(
            len(candidates), 1,
            "competing RTA name wire formats would both run: " + ", ".join(candidates),
        )


if __name__ == "__main__":
    unittest.main()
