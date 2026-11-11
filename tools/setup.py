"""One-time setup for a fresh clone: activates the git hooks and checks tools."""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import find_godot  # noqa: E402
from issue import find_gh  # noqa: E402

subprocess.run(["git", "config", "core.hooksPath", "hooks"], cwd=ROOT, check=True)
print("Git hooks active.")
print("Godot:", find_godot() or "MISSING")
print("GitHub CLI:", find_gh() or "MISSING")
print("Python:", shutil.which("python") or sys.executable)
