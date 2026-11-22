# Hook reviews

Newest first. The latest date here sets when the next review is due. Firings logged on that
date count as reviewed.

## 2026-11-22

Firings since 2026-11-19: script-logic 9, owner-move 4, protected-file 3, manual-full-check 1.
The log still records rule and tool only.

- **Working as designed:** script-logic (Write nudges, clustered in one builder run);
  protected-file (asks, as intended); manual-full-check.
- **Fix (proposed again, needs owner approval):** owner-move fired 4 more times. Sessions only
  ever run `issue.py finish`, so these are most likely handoff or comment text that names the
  owner's `ready`/`close`/`status` commands. Anchor the pattern to a command position (start of
  the command or after `&&`, `;`, `|`), not anywhere in the text. guard.py is protected.
- **Add (still waiting):** log the first 120 characters of each denied command.
- **Retire:** none. **Trim:** CLAUDE.md is 49 lines.

## 2026-11-19

Firings since 2026-11-12: script-logic 8, history-rewrite 6, unbounded-script 5, raw-api 1,
owner-move 1. The log records rule and tool only, so most firings can't be traced to a command.

- **Working as designed:** script-logic (deny-once nudge per new script); history-rewrite, most
  likely builders resetting reused worktree branches to origin/main, which a fresh branch avoids;
  raw-api.
- **Fix (proposed, needs owner approval):** owner-move fired on a heredoc that wrote HANDOFF.md
  and only mentioned the owner's close command in its text. Match owner moves only when
  `issue.py` is the command being run, not text inside a heredoc body.
- **Fix (still waiting):** the unbounded-script tightening from 2026-11-11.
- **Add (proposed):** log the first 120 characters of the command with each firing, so reviews
  can tell a real catch from a false positive. Protected file, so it waits for the owner.
- **Retire:** none. The never-fired rules guard rare but costly mistakes.
- **Trim:** CLAUDE.md is under 60 lines.

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
