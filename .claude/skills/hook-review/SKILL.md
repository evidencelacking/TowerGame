---
name: hook-review
description: Review and grow this project's hooks. Use when the session start notice says a review is due, when a milestone closes, or when the owner asks.
---

1. Run `python tools/hook_report.py`.
2. Read the entries since the last review in `docs/hook-reviews.md`, and any corrections the owner gave since then.
3. Sort what you find:
   - **Add:** the same mistake or correction happened twice. Prefer a guard or check rule over more prose.
   - **Promote:** a prose rule in `CLAUDE.md` can now be enforced in code. Move it and delete the prose.
   - **Fix:** a rule fired wrongly. Show the case and tighten the pattern.
   - **Retire:** a rule never fired across two reviews and guards nothing likely. Propose removing it.
   - **Trim:** `python tools/check.py --full` takes over 30 seconds, or `CLAUDE.md` exceeds 60 lines.
4. Propose the changes to the owner. Enforcement files prompt for approval, so never work around that.
5. Each new rule gets a test in `tools/tests/` and a line in `docs/hooks.md`.
6. Add a dated `## YYYY-MM-DD` entry to `docs/hook-reviews.md` with what changed and why.
