import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


class UiExpected(unittest.TestCase):
    def test_every_known_failure_names_an_issue(self):
        data = json.loads((ROOT / "tools" / "ui_expected.json").read_text(encoding="utf-8"))
        cases = {k: v for k, v in data.items() if not k.startswith("_")}
        for case, why in cases.items():
            self.assertRegex(why, r"#\d+", f"{case} needs an issue number")
            self.assertRegex(case, r"^[a-z0-9_.]+$")


if __name__ == "__main__":
    unittest.main()
