"""Runs the automated UI tester (#262): the real game in demo mode, driven by synthetic mouse input.

  python tools/ui_test.py [--window] [--out REPORT.txt] [--shots DIR]

Headless by default (what CI runs). --window opens a real window, which also saves a screenshot of
every failing case into --shots. The report goes to --out (default: your temp folder, outside the
repo). Known failures are listed in tools/ui_expected.json. Exit code 1 on any unexpected failure.
"""
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import ensure_imported, find_game_exe, find_godot, kill_tree  # noqa: E402

TIMEOUT_SECONDS = 600


def run(window=False, out=None, shots=None):
    """Returns (exit code, output text). The tester's own FAIL count decides the code."""
    godot = find_game_exe() if window else find_godot()
    if not godot:
        return 1, "Godot not found. Install it or set the GODOT environment variable."
    problems = ensure_imported(ROOT, find_godot() or godot)
    if problems:
        return 1, "\n".join(problems)
    out = out or str(Path(tempfile.gettempdir()) / "tower_ui_test_report.txt")
    shots = shots or str(Path(tempfile.gettempdir()) / "tower_ui_test_shots")
    cmd = [godot]
    if not window:
        cmd.append("--headless")
    cmd += ["--path", str(ROOT), "--script", "res://tools/ui_test.gd", "--", f"out={out}", f"shots={shots}"]
    # Output goes to a file, not a pipe (see check.run_game_tests).
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as log:
        process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=TIMEOUT_SECONDS)
            timed_out = False
        except subprocess.TimeoutExpired:
            kill_tree(process)
            timed_out = True
        log.seek(0)
        output = log.read()
    if timed_out:
        return 1, f"UI tester timed out after {TIMEOUT_SECONDS} s.\n" + "\n".join(output.splitlines()[-10:])
    summary = re.search(r"UI TEST pass=(\d+) fail=(\d+)", output)
    if not summary or "SCRIPT ERROR" in output or "Parse Error" in output:
        errors = [line for line in output.splitlines() if re.search(r"ERROR|Error", line)]
        return 1, "UI tester did not finish.\n" + "\n".join(errors[:20] or output.splitlines()[-10:])
    start = output.find("case ")
    table = output[start:] if start >= 0 else output
    return (1 if int(summary.group(2)) else 0), table.rstrip() + f"\n(report written to {out})"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--window", action="store_true", help="open a window (needed for screenshots)")
    parser.add_argument("--out", help="report file (default: temp folder)")
    parser.add_argument("--shots", help="screenshot folder for failures (windowed runs)")
    args = parser.parse_args(argv)
    code, text = run(args.window, args.out, args.shots)
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
