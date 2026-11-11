"""Summarizes guard activity since the last hook review in docs/hook-reviews.md."""
import datetime
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_FILE = ROOT / ".claude" / "hook-log.jsonl"
REVIEWS_FILE = ROOT / "docs" / "hook-reviews.md"
sys.path.insert(0, str(ROOT / ".claude" / "hooks"))

MAX_DAYS = 14
MAX_FIRINGS = 10


def last_review():
    dates = re.findall(r"^## (\d{4}-\d{2}-\d{2})", REVIEWS_FILE.read_text(encoding="utf-8"), re.M)
    return datetime.date.fromisoformat(max(dates))


def firings_since(day):
    """Firings after the given review day, so a review clears everything logged that day."""
    if not LOG_FILE.exists():
        return []
    start = datetime.datetime.combine(day + datetime.timedelta(days=1), datetime.time()).timestamp()
    entries = [json.loads(line) for line in LOG_FILE.read_text(encoding="utf-8").splitlines() if line]
    return [entry for entry in entries if entry["time"] >= start]


def review_status(today=None):
    """Returns why a review is due, or an empty string."""
    day = last_review()
    age = ((today or datetime.date.today()) - day).days
    if age >= MAX_DAYS:
        return f"{age} days since the last one"
    firings = len(firings_since(day))
    return f"{firings} guard firings" if firings >= MAX_FIRINGS else ""


def main():
    from guard import COMMAND_RULES, RAW_RULES

    day = last_review()
    counts = Counter(entry["rule"] for entry in firings_since(day))
    rules = [rule[0] for rule in COMMAND_RULES + RAW_RULES] + ["protected-file"]
    print(f"Since {day}:")
    for rule, count in counts.most_common():
        print(f"  {count:4} {rule}")
    print("Never fired:", ", ".join(r for r in rules if r not in counts) or "none")


if __name__ == "__main__":
    main()
