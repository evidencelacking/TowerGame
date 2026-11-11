"""GitHub Issues state machine. The transition table is the only source of truth.

Claude:  start N | ask N "question" | handoff N PR | finish N PR "evidence" | merge PR
         gameplay-review N "verdict" (comment from the gameplay-expert's review; no state change)
Owner:   ready N | close N | status N backlog|wontfix
Setup:   bootstrap

The Claude guard denies Claude the owner commands. Claude reaches Done only through finish,
which needs a merged PR citing the issue and refuses playtests, which only a person can judge.
The guard denies raw `gh pr merge`; merge refuses a PR unless CI passed and it has main.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKLOG_FILE = ROOT / "tools" / "backlog.json"

STATES = ["backlog", "ready", "in-progress", "blocked", "review", "done", "wontfix"]
TYPES = ["feature", "bug", "chore", "design", "playtest"]
GAMEPLAY_LABEL = "gameplay"  # Such an issue becomes ready only after the gameplay-expert review.
GAMEPLAY_REVIEW = "**Gameplay review:**"

AGENT_MOVES = {
    "start": {"ready": "in-progress", "backlog": "in-progress"},
    "ask": {"backlog": "blocked", "ready": "blocked", "in-progress": "blocked"},
    "handoff": {"in-progress": "review"},
    "finish": {"review": "done"},
}
OWNER_MOVES = {
    "ready": {"backlog": "ready", "blocked": "ready", "review": "ready"},
    "close": {"review": "done"},
    "backlog": {"blocked": "backlog"},
}
TERMINAL = {"done", "wontfix"}
QUEUE_LIMIT = 5  # Review issues before session start asks for the issue-reviewer agent.


class MoveError(Exception):
    pass


def next_state(command, current):
    """Returns the state a command leads to, or raises MoveError."""
    if command == "wontfix":
        if current in TERMINAL:
            raise MoveError(f"Issue is already {current}.")
        return "wontfix"
    moves = AGENT_MOVES.get(command) or OWNER_MOVES.get(command)
    if moves is None:
        raise MoveError(f"Unknown command: {command}")
    if current not in moves:
        raise MoveError(f"'{command}' is not allowed from {current}.")
    return moves[current]


def status_of(labels):
    """Enforces at most one status label on an issue. A new issue has none and counts as backlog."""
    found = [l[len("status::"):] for l in labels if l.startswith("status::")]
    if not found:
        return "backlog"
    if len(found) != 1:
        raise MoveError(f"Expected one status label, found {len(found)}.")
    return found[0]


def find_gh():
    return shutil.which("gh") or next(
        (p for p in [os.path.expandvars(r"%ProgramFiles%\GitHub CLI\gh.exe")] if Path(p).exists()),
        None,
    )


def gh(*args):
    executable = find_gh()
    if not executable:
        raise MoveError("GitHub CLI not found.")
    result = subprocess.run(
        [executable, *args], cwd=ROOT, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        raise MoveError(result.stderr.strip() or "gh failed.")
    return result.stdout


def issue_labels(number):
    data = json.loads(gh("issue", "view", str(number), "--json", "labels"))
    return [label["name"] for label in data["labels"]]


def gameplay_problem(labels, comments):
    """Why a gameplay issue may not become ready yet, or an empty string."""
    if GAMEPLAY_LABEL in labels and not any(c.startswith(GAMEPLAY_REVIEW) for c in comments):
        return "A gameplay issue needs the gameplay-expert review first: issue.py gameplay-review N \"verdict\""
    return ""


def issue_comments(number):
    data = json.loads(gh("issue", "view", str(number), "--json", "comments"))
    return [comment["body"].lstrip() for comment in data["comments"]]


def set_status(number, old, new, labels):
    remove = ["--remove-label", f"status::{old}"] if f"status::{old}" in labels else []
    gh("issue", "edit", str(number), *remove, "--add-label", f"status::{new}")


def cites(number, text):
    return re.search(rf"#{number}\b", text) is not None


def require_pr(number, pr, state):
    data = json.loads(gh("pr", "view", str(pr), "--json", "state,title,body"))
    if data["state"] != state:
        raise MoveError(f"PR {pr} is not {state.lower()}.")
    if not cites(number, f"{data['title']}\n{data['body']}"):
        raise MoveError(f"PR {pr} does not reference #{number}.")


PASSED = {"SUCCESS", "SKIPPED", "NEUTRAL"}
# Mirrors paths-ignore in .github/workflows/test.yml: CI never runs on a PR touching only these.
CI_SKIPS = re.compile(r"^(docs/|\.claude/)|\.md$")


def merge_problems(data, has_main):
    """Why a PR (gh pr view JSON) may not merge yet; empty when it may."""
    problems = []
    if data["state"] != "OPEN" or data.get("isDraft"):
        problems.append("it is not an open, ready PR")
    if data.get("baseRefName") != "main":
        problems.append("its base is not main")
    if not re.search(r"\brefs #\d+", f"{data['title']}\n{data['body']}"):
        problems.append("it references no issue with refs #N")
    checks = data.get("statusCheckRollup") or []
    files = [f["path"] for f in data.get("files") or []]
    if not checks and not (files and all(CI_SKIPS.search(path) for path in files)):
        problems.append("CI has not reported")
    failing = [c.get("name") or c.get("context") or "?" for c in checks
               if (c.get("conclusion") or c.get("state") or "PENDING") not in PASSED]
    if failing:
        problems.append("checks not passed: " + ", ".join(failing))
    if data.get("mergeable") != "MERGEABLE":
        problems.append("it has conflicts or GitHub has not decided yet")
    if not has_main:
        problems.append("the branch does not have the latest main; merge main into it")
    return problems


def merge(pr):
    fields = "state,isDraft,baseRefName,title,body,statusCheckRollup,mergeable,headRefOid,files"
    data = json.loads(gh("pr", "view", str(pr), "--json", fields))
    fetched = subprocess.run(["git", "fetch", "-q", "origin", "main", data["headRefOid"]], cwd=ROOT)
    # Fetching main by name also updates origin/main.
    has_main = fetched.returncode == 0 and subprocess.run(
        ["git", "merge-base", "--is-ancestor", "origin/main", data["headRefOid"]], cwd=ROOT,
    ).returncode == 0
    problems = merge_problems(data, has_main)
    if problems:
        raise MoveError(f"PR {pr} not merged: " + "; ".join(problems) + ".")
    gh("pr", "merge", str(pr), "--merge", "--match-head-commit", data["headRefOid"])
    print(f"PR {pr} merged. Now run issue.py finish for its issue.")


def finish_parts(labels, extra):
    """Returns (PR, evidence) for finish, or raises MoveError."""
    if "type::playtest" in labels:
        raise MoveError("Playtests need a person. The owner closes them.")
    pr, _, evidence = (extra or "").partition(" ")
    if not pr.isdigit() or not evidence.strip():
        raise MoveError('finish needs a merged PR and evidence: finish N PR "evidence"')
    return pr, evidence.strip()


def review_queue():
    """Issues waiting in review, or 0 when GitHub can't be reached."""
    try:
        found = gh("issue", "list", "--label", "status::review", "--limit", "100", "--json", "number")
    except MoveError:
        return 0
    return len(json.loads(found))


def bootstrap():
    for state in STATES:
        gh("label", "create", f"status::{state}", "--force", "--color", "5319e7")
    for kind in TYPES:
        gh("label", "create", f"type::{kind}", "--force", "--color", "0e8a16")
    gh("label", "create", GAMEPLAY_LABEL, "--force", "--color", "fbca04")
    if not BACKLOG_FILE.exists() or json.loads(
        gh("issue", "list", "--state", "all", "--limit", "1", "--json", "number")
    ):
        print("Labels ready. No seed backlog to create.")
        return
    backlog = json.loads(BACKLOG_FILE.read_text(encoding="utf-8"))
    for item in backlog:
        gh(
            "issue", "create", "--title", item["title"], "--body", item["body"],
            "--label", "status::backlog", "--label", f"type::{item['type']}",
        )
    print(f"Labels ready. Created {len(backlog)} backlog issues.")


def move(command, number, extra):
    labels = issue_labels(number)
    old = status_of(labels)
    new = next_state(command, old)
    if command == "ready":
        problem = gameplay_problem(labels, issue_comments(number))
        if problem:
            raise MoveError(problem)
    if command == "finish":
        pr, evidence = finish_parts(labels, extra)
        require_pr(number, pr, "MERGED")
        gh("issue", "comment", str(number), "--body", f"**Reviewed, PR #{pr}:** {evidence}")
    if command == "ask":
        if not extra:
            raise MoveError('ask needs a question: ask N "question"')
        gh("issue", "comment", str(number), "--body", f"**Blocked, question for owner:** {extra}")
    if command == "handoff":
        if not extra:
            raise MoveError("handoff needs an open PR number: handoff N PR")
        require_pr(number, extra, "OPEN")
    set_status(number, old, new, labels)
    if new in TERMINAL:
        reason = "completed" if new == "done" else "not planned"
        gh("issue", "close", str(number), "--reason", reason)
    print(f"#{number}: {old} -> {new}")


def main():
    args = sys.argv[1:]
    try:
        if args == ["bootstrap"]:
            bootstrap()
        elif len(args) == 2 and args[0] == "merge":
            merge(int(args[1]))
        elif len(args) >= 3 and args[0] == "gameplay-review":
            gh("issue", "comment", str(int(args[1])), "--body", f"{GAMEPLAY_REVIEW} {' '.join(args[2:])}")
            print(f"#{args[1]}: gameplay review recorded")
        elif len(args) >= 2 and args[0] == "status":
            if len(args) != 3 or args[2] not in ("backlog", "wontfix"):
                raise MoveError("Usage: status N backlog|wontfix")
            move(args[2], int(args[1]), None)
        elif len(args) >= 2:
            move(args[0], int(args[1]), " ".join(args[2:]) or None)
        else:
            print(__doc__)
            return 1
    except (MoveError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
