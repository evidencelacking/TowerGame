# Hook reviews

Newest first. The latest date here sets when the next review is due. Firings logged on that
date count as reviewed.

## 2026-11-12

No firings logged after 2026-11-11 (`hook_report.py`); the start-of-session count included
firings already reviewed on that date.

- **Fix:** the unbounded-script tightening from 2026-11-11 still waits for the owner.
- **Retire:** none. The never-fired rules (force-push, push-main, history-rewrite and the like)
  guard rare but costly mistakes, so silence is expected.
- **Add, Promote, Trim:** nothing new.

## 2026-11-11

Firings since 2026-11-10: script-logic 16, owner-move 4, raw-api 1, history-rewrite 1,
unbounded-script 1.

- **script-logic, owner-move, raw-api, history-rewrite:** working as designed. script-logic is a
  deny-once nudge on each new script; owner-move fired when coordinators reached for `ready`,
  which the owner has since covered by consenting to hand-starts (`issue.py start`). No change.
- **Fix (proposed, needs owner approval):** unbounded-script fired on a docs search whose
  pattern contained `--script` (`Select-String ... -Pattern 'capture|--script'`), not a Godot run.
  Tighten the pattern in `.claude/hooks/guard.py` to
  `(?s)^(?!.*\btimeout\s+\d).*--(headless|path)\b.*--script\b`, and add that search command
  to the allowed list in `tools/tests/test_workflow.py`. The edit is a protected file, so it waits
  for the owner.
- **Retire:** none; this is the first review after bootstrap.
- **Trim:** CLAUDE.md is under 60 lines. `check.py --full` timing not measured (the guard
  rightly blocks a manual full check; push times it).

## 2026-11-10

Bootstrap. The guard rules and git hooks were adapted from the strategy game's workflow, with
two additions for this repo: `private-port` (never read the owner's private native port) and the
clean-room check in `tools/check.py`. No firings yet.
