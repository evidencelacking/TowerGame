"""Project checks used by git hooks and CI. Silent on success to save tokens.

  --staged           pre-commit: secret scan, clean-room check, then tests relevant to staged files
  --full             pre-push and CI: every test
  --commit-msg FILE  commit-msg: format rules
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from secret_screen import find_secrets  # noqa: E402
from sim_lint import lint_simulation  # noqa: E402

CLOSING_KEYWORD = re.compile(r"(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b:?\s+(\S+/\S+)?#\d+")
VALID_SUBJECT = re.compile(r"\brefs #\d+|^(chore|docs|test|ci)(\(.+\))?: ")
GAME_FILES = re.compile(r"\.(gd|tscn|tres)$|^project\.godot$")

# Clean room: the repo is public and must hold nothing of the original game or of any port of it.
# Patterns are regexes so that this file never contains the forbidden text itself.
FORBIDDEN_PATHS = re.compile(r"(^|/)references/|\.(pdf|hlp|exe|iso)$", re.I)
FORBIDDEN_TEXT = {
    "a path in a private port": re.compile(r"port[\\/]generated|analysis[\\/]|Sky[s]craper"),
    "the local references folder": re.compile(r"Tower Game[\\/]+references"),
}
# Docs that may name the local, git-ignored references folder, and nothing else.
REFERENCES_FOLDER_DOCS = {
    "docs/gameplay-reference.md", "docs/roadmap.md", "docs/plan.md",
    ".claude/agents/gameplay-expert.md",
}
MAX_SCAN_BYTES = 1_000_000


def git(*args, cwd=ROOT):
    return subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace"
    ).stdout


def hooks_active(root=ROOT):
    """True when git runs the repo's hooks folder. Worktrees may name it by absolute path."""
    active = (root / git("rev-parse", "--git-path", "hooks", cwd=root).strip()).resolve()
    common = (root / git("rev-parse", "--git-common-dir", cwd=root).strip()).resolve()
    return active in (root / "hooks", common.parent / "hooks")


def find_godot():
    found = os.environ.get("GODOT") or shutil.which("godot_console") or shutil.which("godot")
    if found:
        return found
    pattern = os.path.expandvars(
        r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine*\*console.exe"
    )
    matches = glob.glob(pattern)
    return matches[0] if matches else None


GAME_TEST_SECONDS = 240
IMPORT_SECONDS = 120
CLASS_CACHE = Path(".godot") / "global_script_class_cache.cfg"


def find_game_exe():
    """The windowed (non-console) Godot exe if present, else the console one."""
    pattern = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine*\*win64.exe")
    windowed = [m for m in glob.glob(pattern) if "console" not in m.lower()]
    return windowed[0] if windowed else find_godot()


def class_cache_stale(root=ROOT):
    """True when Godot's class cache is missing or older than any .gd file. A stale cache
    makes scripts that use class_name fail to compile, and Godot only rebuilds it on import."""
    cache = root / CLASS_CACHE
    if not cache.exists():
        return True
    built = cache.stat().st_mtime
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if any(f.endswith(".gd") and os.stat(os.path.join(folder, f)).st_mtime > built for f in files):
            return True
    return False


def ensure_imported(root=ROOT, godot=None):
    """Runs a headless import when the class cache is stale. Returns error lines, or []."""
    if not class_cache_stale(root):
        return []
    godot = godot or find_godot()
    if not godot:
        return ["Godot not found. Install it or set the GODOT environment variable."]
    with tempfile.TemporaryFile(mode="w+") as log:
        process = subprocess.Popen(
            [godot, "--headless", "--path", str(root), "--import"], stdout=log, stderr=subprocess.STDOUT
        )
        try:
            process.wait(timeout=IMPORT_SECONDS)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            return [f"Godot import timed out after {IMPORT_SECONDS} s."]
    # Import can leave the cache untouched when no script changed; mark it fresh.
    cache = root / CLASS_CACHE
    if not cache.exists():
        return ["Godot import did not create the class cache."]
    os.utime(cache)
    return []


def kill_tree(process):
    """Kills a process and everything it started, so nothing holds the test log open."""
    if os.name == "nt":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)], capture_output=True, timeout=30)
    else:
        process.kill()
    process.wait(timeout=30)


def run_game_tests():
    godot = find_godot()
    if not godot:
        return ["Godot not found. Install it or set the GODOT environment variable."]
    problems = ensure_imported(ROOT, godot)
    if problems:
        return problems
    # Output goes to a file, not a pipe: on Windows a pipe held open by a leftover Godot
    # process kept the hook waiting for hours. A timeout kills the whole process tree.
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as log:
        process = subprocess.Popen(
            [godot, "--headless", "--path", str(ROOT), "--script", "res://tests/run_tests.gd"],
            stdout=log, stderr=subprocess.STDOUT,
        )
        try:
            code = process.wait(timeout=GAME_TEST_SECONDS)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            code = None
        log.seek(0)
        output = log.read()
    finished = "TESTS FINISHED failures=0" in output and "ERROR:" not in output
    # Parse errors can still exit 0, so require the runner's own all-clear too. A run that
    # finished but then hung on exit still counts.
    if finished and code in (0, None):
        return []
    if code is None and "TESTS FINISHED" not in output:
        return [f"Godot tests timed out after {GAME_TEST_SECONDS} s."] + output.splitlines()[-10:]
    lines = [l for l in output.splitlines() if re.search(r"FAIL|ERROR|Error", l)]
    return lines[:20] or ["Godot tests did not finish."]


def run_tool_tests():
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-q", "-s", "tools/tests"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    return [] if result.returncode == 0 else result.stderr.splitlines()[-20:]


def clean_room_problems(names, read):
    """Problems in tracked files. read(name) returns a file's text, or None if unreadable."""
    problems = []
    for name in names:
        if FORBIDDEN_PATHS.search(name):
            problems.append(f"{name}: reference or original-game file must not be tracked")
            continue
        text = read(name)
        if text is None:
            continue
        for what, pattern in FORBIDDEN_TEXT.items():
            if pattern.search(text) and not (
                name in REFERENCES_FOLDER_DOCS and what == "the local references folder"
            ):
                problems.append(f"{name}: names {what}")
    return problems


def read_tracked(name):
    path = ROOT / name
    if not path.is_file() or path.stat().st_size > MAX_SCAN_BYTES:
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def tracked_files():
    return git("ls-files").splitlines()


def scan_staged(files):
    problems = []
    for name in files:
        if Path(name).name == ".env" or name.endswith((".pem", ".key", ".keystore")):
            problems.append(f"{name}: file type must not be committed")
            continue
        text = git("show", f":{name}")
        for rule in find_secrets(text):
            problems.append(f"{name}: possible secret ({rule})")
    return problems


def staged():
    files = git("diff", "--cached", "--name-only", "--diff-filter=ACMR").split()
    problems = scan_staged(files)
    problems += clean_room_problems(files, lambda name: git("show", f":{name}") or None)
    if any(GAME_FILES.search(f) for f in files):
        problems += lint_simulation(ROOT) + run_game_tests()
    if any(f.startswith((".claude/", "tools/", "hooks/")) for f in files):
        problems += run_tool_tests()
    return problems


def full():
    problems = []
    if os.environ.get("CI") is None and not hooks_active():
        problems.append("Git hooks are not active. Run: python tools/setup.py")
    problems += clean_room_problems(tracked_files(), read_tracked)
    return problems + lint_simulation(ROOT) + run_game_tests() + run_tool_tests()


def commit_message(path):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    text = "\n".join(l for l in lines if not l.startswith("#"))
    if CLOSING_KEYWORD.search(text):
        return ["Closing keyword found: use 'refs #N'. Only the owner closes issues."]
    if not VALID_SUBJECT.search(lines[0] if lines else ""):
        return ["Subject needs 'refs #N' or a chore:, docs:, test: or ci: prefix."]
    return []


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--full"
    if mode == "--staged":
        problems = staged()
    elif mode == "--commit-msg":
        problems = commit_message(sys.argv[2])
    else:
        problems = full()
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
