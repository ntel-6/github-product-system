import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from {{PYTHON_PACKAGE}} import health


class SmokeTest(unittest.TestCase):
    def test_health(self) -> None:
        self.assertEqual(health(), {"ok": True})


if __name__ == "__main__":
    unittest.main()
