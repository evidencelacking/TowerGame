"""Claude PreToolUse guard. Rules live here, not in prose.

"deny" stops the call. "ask" hands the decision to the owner. Every rule must
be listed in docs/hooks.md, and each firing is logged for the hook review.
"""
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LOG_FILE = ROOT / ".claude" / "hook-log.jsonl"

CLOSING = r"\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b:?\s+(\S+/\S+)?#\d+"

COMMAND_RULES = [
    ("no-verify", "deny", r"\bgit\b.*--no-verify", "Hooks may not be skipped. Fix the failure."),
    # A bare mention at the end of a command only reads the setting.
    ("hooks-path", "deny", r"core\.hooksPath(?!\s*($|[;|&)\n]))|\b(unset|add|replace)\S*\s[^;|&\n]*core\.hooksPath", "Git hook activation is changed only by tools/setup.py."),
    ("force-push", "deny", r"\bgit\s+push\b.*(--force|--delete|\s-f\b|\s\+\S)", "Force and delete pushes are not allowed."),
    ("push-main", "ask", r"\bgit\s+push\b[^;|&\n]*\b(main|master)\b", "Pushing to main needs the owner's approval."),
    ("pr-merge", "deny", r"\bgh\s+pr\s+merge\b", "Use `python tools/issue.py merge PR`: it merges only a green PR that has main."),
    ("raw-issue-close", "deny", r"\bgh\s+issue\s+(close|reopen|delete)\b", "Only the owner closes issues."),
    ("raw-status-label", "deny", r"\bgh\s+issue\s+edit\b.*status::", "Use tools/issue.py so the state machine applies."),
    ("raw-api", "deny", r"\bgh\s+api\b", "Raw API calls bypass the state machine."),
    ("owner-move", "deny", r"issue\.py[\"']?\s+(ready|close|status)\b", "That move belongs to the owner."),
    ("history-rewrite", "ask", r"\bgit\s+(reset\s+--hard|clean\s+-\w*f|rebase\b|commit\b.*--amend)", "This can lose work, so the owner decides."),
    ("recursive-delete", "ask", r"\brm\s+-\w*r|\bRemove-Item\b.*-Recurse", "Recursive deletes need the owner's approval."),
    ("manual-full-check", "deny", r"check\.py[\"']?\s+--full", "git push runs the full check and CI repeats it; commit runs the relevant tests. Validate gameplay once per PR, before handoff: docs/workflow.md."),
    ("unbounded-script", "deny", r"(?s)^(?!.*\btimeout\s+\d).*--script\b", "Run Godot scripts under `timeout N`, with output in a file rather than behind tail, so a hang shows where it stopped."),
]
RAW_RULES = [
    ("pr-closing-keyword", "deny", r"(?is)\bgh\s+pr\s+(create|edit)\b.*" + CLOSING, "Use 'refs #N' in PRs. Only the owner closes issues."),
]
PROTECTED_PATHS = re.compile(
    r"(^|/)(\.claude/(settings\.json|hooks/)|hooks/|\.github/workflows/|tools/issue\.py)"
)
# Message text may legitimately mention these commands.
MESSAGE_TEXT = re.compile(r"(-m|--message|--title|--body)\s+(\"[^\"]*\"|'[^']*')")
FILE_TOOLS = {"Write", "Edit", "NotebookEdit"}
# The owner's private native port lives next to this repo. It must never be read, so that the
# game stays clean-room. The references folder is read only through the gameplay-expert agent.
PRIVATE_PORT = re.compile(r"(?i)(tower\\? game|towerg~\d)[\\/]+(port|analysis|original)\b")
PRIVATE_PORT_REASON = "The private port is off limits: this repo is clean-room. Ask gameplay-expert instead."
SHELL_TOOLS = {"Bash", "PowerShell"}
NEW_SCRIPT = re.compile(r"\.(gd|py|sh|ps1)$")
CHECKED_SCRIPTS = ROOT / ".claude" / "script-checks.txt"
SCRIPT_CHECK = (
    "Check this script's logic, then write it again. Does each value exist when it is read, "
    "given startup order and awaits? Can every loop end? Does it prove what it claims, and "
    "would it fail if that were false?"
)


def first_write_of_script(tool, path):
    """True once per new script, so the second attempt goes through."""
    if tool != "Write" or not NEW_SCRIPT.search(path) or Path(path).exists():
        return False
    checked = CHECKED_SCRIPTS.read_text(encoding="utf-8").split("\n") if CHECKED_SCRIPTS.exists() else []
    if path in checked:
        return False
    with CHECKED_SCRIPTS.open("a", encoding="utf-8") as handle:
        handle.write(path + "\n")
    return True


def evaluate(tool, tool_input):
    """Returns (rule, decision, reason), or None when the call is allowed."""
    targets = [str(tool_input.get(key, "")) for key in ("command", "file_path", "path", "pattern")]
    if any(PRIVATE_PORT.search(target) for target in targets):
        return "private-port", "deny", PRIVATE_PORT_REASON
    if tool in SHELL_TOOLS:
        raw = tool_input.get("command", "")
        for rule, decision, pattern, reason in RAW_RULES:
            if re.search(pattern, raw):
                return rule, decision, reason
        command = MESSAGE_TEXT.sub(" ", raw)
        for rule, decision, pattern, reason in COMMAND_RULES:
            if re.search(pattern, command):
                return rule, decision, reason
    elif tool in FILE_TOOLS:
        path = tool_input.get("file_path", "").replace("\\", "/")
        relative = path.split(ROOT.as_posix())[-1]
        if PROTECTED_PATHS.search(relative):
            return "protected-file", "ask", "Enforcement files change only with the owner's approval."
        if first_write_of_script(tool, path):
            return "script-logic", "deny", SCRIPT_CHECK
    return None


def log(rule, decision, tool):
    entry = {"time": int(time.time()), "rule": rule, "decision": decision, "tool": tool}
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")


def main():
    event = json.load(sys.stdin)
    tool = event.get("tool_name", "")
    result = evaluate(tool, event.get("tool_input", {}))
    if result is None:
        return 0
    rule, decision, reason = result
    log(rule, decision, tool)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": f"[{rule}] {reason}",
        }
    }))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # Fail closed: a broken guard must not allow calls.
        print(f"Guard failed: {error}", file=sys.stderr)
        sys.exit(2)
