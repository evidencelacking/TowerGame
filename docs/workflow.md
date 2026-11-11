# Workflow

GitHub Issues is the system of record. Each issue has one `type::` and one `status::`
label, and `tools/issue.py` moves status. Its transition table is the authority.

```
backlog -> ready -> in-progress -> review -> done
```

| Move | From | To | Who | Command |
|---|---|---|---|---|
| Gameplay review | backlog | backlog | Claude, with the `gameplay-expert` agent | `issue.py gameplay-review N "verdict"` |
| Approve work | backlog | ready | Owner, and for a `gameplay` issue only after its review | `issue.py ready N` |
| Start | ready | in-progress | Claude | `issue.py start N` |
| Hand-start | backlog | in-progress | Claude, when the owner asks | `issue.py start N` |
| Block with a question | backlog, ready, in-progress | blocked | Claude | `issue.py ask N "question"` |
| Hand off | in-progress | review | Claude, needs an open PR citing the issue | `issue.py handoff N PR` |
| Rework | review | ready | Owner | `issue.py ready N` |
| Unblock | blocked | ready | Owner | `issue.py ready N` |
| Shelve | blocked | backlog | Owner | `issue.py status N backlog` |
| Finish | review | done | Owner | `issue.py close N` |
| Verified finish | review | done | Claude, needs a merged PR citing the issue, never a playtest | `issue.py finish N PR "evidence"` |
| Drop | any open state | wontfix | Owner | `issue.py status N wontfix` |

Claude asks on the issue instead of guessing when blocked, and the guard denies Claude the
owner's commands, so run those in your own terminal. Merge with `issue.py merge PR`, which refuses
unless CI passed, the branch has main and the PR cites an issue (see [efficiency.md](efficiency.md)).

## Gameplay issues

An issue that sets or changes a game rule, number or mechanic carries the `gameplay` label. Before
the owner approves it, the `gameplay-expert` agent reviews it against
[gameplay-reference.md](gameplay-reference.md): verdict (matches, differs or missing), the rules
it must cover, acceptance tests worth adding, and open questions. The coordinator records that with
`issue.py gameplay-review N "verdict"`, and `issue.py ready` refuses a `gameplay` issue until it
has been recorded. The `rules-keeper` agent checks the finished change against the same reference
and the simulation determinism rules.

The `issue-reviewer` agent clears merged work from review. It checks each issue against its
acceptance text, and closes it through `finish` or leaves it for the owner with a reason. The
session start notice asks for it once the queue is long.

## When to test

Validate at milestones, not after each change.

- **While working:** run only the one test suite or capture that answers a question. A
  failure is the reason to look closer.
- **On commit and push:** the git hooks run the tests, so don't run the full check by hand.
  The guard denies it.
- **Once per PR, before handoff:** gameplay validation. Run the simulation headless with a fixed
  seed, and look at the game.
- **The owner's playtest:** once 3 or more merged changes since the last playtest will likely
  alter gameplay noticeably, Claude prompts the owner to play.

## Before handoff

Complete the checklist in the pull request template. Say how the change was verified.
