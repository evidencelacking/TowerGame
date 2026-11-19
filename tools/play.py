"""Launches the game: imports first when Godot's class cache is stale, then runs it full screen.

  python tools/play.py [--demo] [--scene res://path.tscn] [extra Godot arguments]

--demo starts a new tower with a huge balance, the top star rating and everything unlocked (#262).
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import ensure_imported, find_game_exe, find_godot  # noqa: E402


def main(extra):
    exe = find_game_exe()
    if not exe:
        print("Godot not found. Install it or set the GODOT environment variable.")
        return 1
    # Import with the console exe when there is one: it waits for the import to finish.
    problems = ensure_imported(ROOT, find_godot() or exe)
    if problems:
        print("\n".join(problems))
        return 1
    # "--scene res://x.tscn" runs that scene instead of the main one (Godot takes it positionally).
    args = []
    demo = "--demo" in extra
    it = iter([a for a in extra if a != "--demo"])
    for a in it:
        args.append(next(it, "") if a == "--scene" else a)
    if demo:  # Godot hands everything after "--" to the game (OS.get_cmdline_user_args).
        args += ["--demo"] if "--" in args else ["--", "--demo"]
    return subprocess.call([exe, "--path", str(ROOT), "--fullscreen", *args])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
