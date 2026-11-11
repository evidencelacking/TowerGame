import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path[:0] = [str(ROOT / "tools")]

import check  # noqa: E402

# Built at run time so this file does not contain the forbidden text itself.
PORT_NAME = "Sky" + "scraper"
GENERATED = "port" + "/generated"
ANALYSIS = "analysis" + "/"
REFERENCES = "D:\\Claude\\Tower Game\\" + "references"


def problems(files):
    return check.clean_room_problems(list(files), files.get)


class CleanRoom(unittest.TestCase):
    def test_ordinary_files_pass(self):
        self.assertEqual(problems({"scripts/main.gd": "extends Node\n", "README.md": "Hello"}), [])

    def test_reference_files_fail(self):
        for name in ["references/manual.txt", "docs/references/a.md", "guide.pdf", "x/SIMTOWER.HLP", "game.exe", "a.iso"]:
            self.assertEqual(len(problems({name: None})), 1, name)

    def test_private_port_text_fails(self):
        for text in [GENERATED, ANALYSIS + "calls.md", "the " + PORT_NAME + " repo", "analy" + "sis\\notes"]:
            self.assertEqual(len(problems({"docs/x.md": text})), 1, text)

    def test_the_references_folder_is_named_only_in_allowed_docs(self):
        for name in check.REFERENCES_FOLDER_DOCS:
            self.assertEqual(problems({name: "local copies in " + REFERENCES}), [], name)
        self.assertEqual(len(problems({"docs/workflow.md": REFERENCES})), 1)
        self.assertEqual(len(problems({"scripts/main.gd": "# " + REFERENCES})), 1)

    def test_allowed_docs_may_not_name_a_port(self):
        self.assertEqual(len(problems({"docs/roadmap.md": GENERATED})), 1)

    def test_this_repository_is_clean(self):
        self.assertEqual(check.clean_room_problems(check.tracked_files(), check.read_tracked), [])


if __name__ == "__main__":
    unittest.main()
