# Efficiency

Plan by token cost, keep Opus for leadership, and cut merge conflicts.

## Who does what

| Role | Model | Does |
|---|---|---|
| Coordinator (the main session) | Opus | Plans, makes design calls, breaks work into briefs, solves hard problems, reviews only when risky |
| Builders (sessions) | Sonnet | Implement one issue each, and stop at a green PR |
| Reviewers (agents) | Sonnet | Read-only review of large or risky diffs before a merge |
| Searches and reads | Haiku | Code sweeps and lookups |
| Specialists | Sonnet | `gameplay-expert` answers rules questions and reviews gameplay issues; `rules-keeper` checks changes against the reference; `issue-reviewer` clears merged work |

- **The coordinator merges green PRs.** A session's own raw merge command is refused by the guard.
  A merge costs two calls: `issue.py merge PR` (it checks CI, which lints `scripts/sim/`, and that
  the branch has main), then `issue.py finish`.
- **The coordinator doesn't redo a builder's work,** such as a merge or a fix. It sends the
  builder a message instead.
- **Replies to the owner are short.**

## When a session is too long

Every turn re-reads the whole conversation, so a long session costs more per step.

- **Hand off at the first automatic compaction,** or after about 3 finished tasks, whichever
  comes first. Write a short handoff: open PRs, running sessions, decisions pending and next
  steps. Then start fresh.
- **A builder session ends when its PR merges.** Follow-up work goes to a new session.

## Rough cost of each kind of work

Tiers are relative. Sonnet costs a fraction of Opus per token, so a High job on Sonnet can cost
less than a Medium one on Opus.

| Work | Tier | Who |
|---|---|---|
| Answering a question, or a design decision with the owner | Low | Opus |
| Filing an issue, small docs edits | Low | Sonnet |
| A data-only change (a number in the room catalogue) | Low | Sonnet |
| A rules question about the original | Low | `gameplay-expert` |
| A code review of a large PR | Medium (about 100k tokens) | Sonnet agent |
| Merging main into a branch with conflicts | Medium to High | The builder that owns the branch |
| A HUD or UI feature | Medium | Sonnet |
| A sim feature: a room, a rule, a tenant behaviour | High | Sonnet session |
| A whole new system (elevators, the economy) | Very high | Sonnet session after an Opus design |
| A long-running coordinator session | Grows with length | Hand off at the threshold |

Order work design (Low) before building (High), so a build session never stalls on a question.
Send the owner's notes in one message, and group Low items into one session.

## Fewer merge conflicts

- **No stacked PRs.** Every PR is based on main.
- **No parallel sessions on the sim core** (`scripts/sim/`). Parallel work is fine across docs,
  tools and the view.
- **One item per line** in lists that many features extend (room catalogues, test lists), so two
  features add different lines.
- **A long-lived branch merges main** before opening its PR, and again before merging.

## CI

The repo is public, so Actions minutes are free, but keep runs useful:

- CI runs on PRs and on pushes to main (`.github/workflows/test.yml`), not for docs-only PRs.
- A newer push to a PR cancels the older run.
- Push once a PR is finished: the pre-push hook already runs every test locally.
