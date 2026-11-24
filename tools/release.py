#!/usr/bin/env python3
"""Builds the Windows release: exports headless and zips build/TowerGame-<version>-windows.zip.

Needs Godot's export templates for the exact Godot version installed. This script never
downloads anything; if they are missing it says what to install and exits non-zero.
"""
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check import ROOT, find_godot  # noqa: E402

PRESET = "Windows Desktop"
EXPORT_SECONDS = 300


def project_version(root=ROOT):
    text = (root / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="([^"]+)"', text, re.M)
    return match.group(1) if match else "0.9.0"


def godot_version(godot):
    """e.g. '4.7.2.stable' from `godot --version` ('4.7.2.stable.official.abc123')."""
    out = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=60).stdout.strip()
    parts = out.split(".")
    return ".".join(parts[:4]) if len(parts) >= 4 else out


def templates_dir(version):
    base = os.environ.get("APPDATA") or str(Path.home() / ".local" / "share")
    return Path(base) / "Godot" / "export_templates" / version


def main():
    godot = find_godot()
    if not godot:
        print("Godot not found. Install it or set the GODOT environment variable.")
        return 1
    version = godot_version(godot)
    templates = templates_dir(version)
    if not (templates / "windows_release_x86_64.exe").exists():
        short = version.replace(".stable", "")
        print(f"Export templates for Godot {version} are not installed (looked in {templates}).")
        print("Install them in the editor: Editor > Manage Export Templates > Download and Install.")
        print(f"Or download Godot_v{short}-stable_export_templates.tpz from "
              f"https://github.com/godotengine/godot/releases/tag/{short}-stable, then use "
              "Manage Export Templates > Install From File.")
        return 1
    game_version = project_version()
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    exe = build / "TowerGame.exe"
    exe.unlink(missing_ok=True)
    result = subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "--export-release", PRESET, str(exe)],
        capture_output=True, text=True, timeout=EXPORT_SECONDS,
    )
    output = result.stdout + result.stderr
    if result.returncode != 0 or not exe.exists() or "ERROR" in output:
        print(output[-3000:])
        print("Export failed.")
        return 1
    archive = build / f"TowerGame-{game_version}-windows.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(exe, "TowerGame.exe")
    print(f"Built {archive} ({archive.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
