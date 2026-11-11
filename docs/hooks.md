# Hooks

Rules live in code. A test fails if a guard rule is missing from this page.

## Git hooks (`hooks/`, activated by `tools/setup.py`)

| Hook | Checks |
|---|---|
| `pre-commit` | Secrets and the clean-room check on staged files, the simulation lint, and tests relevant to what changed |
| `commit-msg` | `refs #N` or a `chore:`, `docs:`, `test:`, `ci:` prefix; no closing keywords |
| `pre-push` | Everything, and that hooks are active |

GitHub Actions repeats the full check, because local hooks can be skipped.

**Clean room.** The check fails when a tracked file is under `references/`, is a `.pdf`, `.hlp`,
`.exe` or `.iso`, or names a private port's folders or the local references folder. Only the
docs listed in `REFERENCES_FOLDER_DOCS` (in `tools/check.py`) may name that local, ignored folder.

## Claude guard (`.claude/hooks/guard.py`)

| Rule | Result | Stops |
|---|---|---|
| `private-port` | Deny | Reading or touching the owner's private native port; this repo is clean-room |
| `no-verify` | Deny | Skipping git hooks |
| `hooks-path` | Deny | Changing hook activation |
| `force-push` | Deny | Force and delete pushes |
| `raw-issue-close` | Deny | Closing, reopening, deleting issues directly |
| `raw-status-label` | Deny | Changing status labels directly |
| `raw-api` | Deny | Raw `gh api` calls |
| `owner-move` | Deny | Owner-only state machine moves |
| `pr-closing-keyword` | Deny | PR text that auto-closes issues |
| `manual-full-check` | Deny | Running the full check by hand, which push and CI already run |
| `unbounded-script` | Deny | Godot script runs with no time limit |
| `pr-merge` | Deny | Raw `gh pr merge`; `issue.py merge PR` merges only a green PR that has main |
| `script-logic` | Deny once | Writing a new script before its logic is checked |
| `push-main` | Ask | Pushing to main |
| `history-rewrite` | Ask | Hard resets, cleans, rebases, amends |
| `recursive-delete` | Ask | Recursive deletes |
| `protected-file` | Ask | Editing enforcement files |

`tools/issue.py finish` is Claude's only route to Done. It needs a merged PR citing the issue and
refuses playtests. `issue.py ready` refuses a `gameplay` issue until the `gameplay-expert` review
is recorded on it. Session start also reports a review queue of 5 or more issues.

These rules stop drift and mistakes. They match command text, so they are not a security
boundary against deliberate evasion.

## How hooks keep growing

**Triggers for a review** (run the `hook-review` skill):

- The session start notice: 14 days since the last review, or 10 guard firings
- Every milestone close
- Immediately, when the owner corrects the same thing twice

**Each review** adds, promotes, fixes, retires or trims rules, using the firing log
(`python tools/hook_report.py`) and past corrections. Results go in
[hook-reviews.md](hook-reviews.md).

**Health limits:** `CLAUDE.md` under 60 lines, the full check under 30 seconds, and hook
output limited to failures. A rule that never fires across two reviews must justify itself.
