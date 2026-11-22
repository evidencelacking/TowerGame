"""Timing harness for the view and sim (#399): not part of the test suite.

  python tools/perf.py [samples=300] [frames=400] [warmup=700]
  python tools/perf.py save=<path> [ticks=2550] [noview]   per-system day profile of a save (#419)
  python tools/perf.py mixed [ticks=2550] [noview]         the same on the mixed fixture
  python tools/perf.py loop save=<path>|mixed speed=1|2|3 [frames=120 warmup=500]   real frame loop

Builds a 60-floor tower with a dozen elevators and several hundred people, headless, and prints the
mean and p95 milliseconds of a sim tick, the view's figures, thought-icon picking, the renderer's
_process and the sound ambience (tools/perf.gd). The run ends when the Godot script quits, or is
killed after TIMEOUT_SECONDS; the exit code is Godot's, so a tower that came up short fails.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import ensure_imported, find_godot, kill_tree  # noqa: E402

TIMEOUT_SECONDS = 900  # a day of a large real save can take minutes


def script_for(args):
    """The save and fixture profiler for save=, mixed or loop; else the synthetic tower."""
    if any(a.startswith("save=") or a in ("mixed", "loop") for a in args):
        return "res://tools/perf_save.gd"
    return "res://tools/perf.gd"


def main(args):
    godot = find_godot()
    if not godot:
        print("Godot not found. Install it or set the GODOT environment variable.")
        return 1
    problems = ensure_imported(ROOT, godot)
    if problems:
        print("\n".join(problems))
        return 1
    out = ROOT / "perf_output.txt"
    with open(out, "w", encoding="utf-8") as log:
        process = subprocess.Popen(
            [godot, "--headless", "--path", str(ROOT), "--script", script_for(args), "--", *args],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            code = process.wait(timeout=TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            print(f"Timed out after {TIMEOUT_SECONDS} s; partial output in {out}")
            return 1
    print(out.read_text(encoding="utf-8", errors="replace"))
    out.unlink()
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
