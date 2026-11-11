"""Prints a line at session start only when something needs attention."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import hooks_active  # noqa: E402
from hook_report import review_status  # noqa: E402
from issue import QUEUE_LIMIT, review_queue  # noqa: E402

if not hooks_active():
    print("Git hooks are not active. Run: python tools/setup.py")
due = review_status()
if due:
    print(f"Hook review due ({due}). Run the hook-review skill.")
waiting = review_queue()
if waiting >= QUEUE_LIMIT:
    print(f"{waiting} issues in review. Run the issue-reviewer agent.")
