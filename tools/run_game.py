#!/usr/bin/env python3
"""
run_game.py - Runs the real Godot game, or tells you exactly what is missing.

    python3 tools/run_game.py --check     # prove the setup works (no window)
    python3 tools/run_game.py             # play it (opens a window)
    python3 tools/run_game.py --editor    # open the project in the editor

This launches godot/scenes/main.tscn through the actual engine. It has nothing
to do with prototype/index.html, which is an older hand-written JavaScript
mock-up and is not Godot.

--check is the important one. It boots the project headless and runs the smoke
scene, which instantiates main.tscn and plays 1800 frames across all five arena
variants, then exercises the stage map and the upgrade draft. If that passes,
the Godot setup is correct and the only thing a window adds is pixels. It works
on machines with no GPU at all.

Godot is looked for in $GODOT, then PATH, then the usual install locations for
this OS. Nothing is downloaded and nothing is installed.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot"
WANT_VERSION = "4.3"


def candidate_paths() -> list[Path]:
    """Common places the Godot binary ends up, per OS."""
    home = Path.home()
    names = [
        "Godot_v4.3-stable_linux.x86_64",
        "Godot_v4.3-stable_win64.exe",
        "Godot",
        "godot",
    ]
    roots: list[Path] = [
        home / "Downloads",
        home / "Applications",
        home / ".local" / "bin",
        Path("/usr/local/bin"),
        Path("/usr/bin"),
        Path("/opt/godot"),
    ]
    if sys.platform == "darwin":
        roots.append(Path("/Applications/Godot.app/Contents/MacOS"))
        roots.append(home / "Applications" / "Godot.app" / "Contents" / "MacOS")
    if sys.platform == "win32":
        for env in ("LOCALAPPDATA", "PROGRAMFILES"):
            base = os.environ.get(env)
            if base:
                roots.append(Path(base) / "Godot")

    found: list[Path] = []
    for folder in roots:
        for name in names:
            path = folder / name
            if path.is_file():
                found.append(path)
    return found


def find_godot() -> str | None:
    override = os.environ.get("GODOT")
    if override:
        resolved = shutil.which(override) or (override if Path(override).is_file() else None)
        if resolved:
            return str(resolved)
        print(f"$GODOT is set to {override!r} but that is not an executable.", file=sys.stderr)

    on_path = shutil.which("godot") or shutil.which("godot4")
    if on_path:
        return on_path

    for path in candidate_paths():
        if os.access(path, os.X_OK) or sys.platform == "win32":
            return str(path)
    return None


def version_of(binary: str) -> str:
    try:
        out = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return ""
    text = (out.stdout or "") + (out.stderr or "")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[-1] if lines else ""


def explain_missing() -> int:
    print("Godot not found.", file=sys.stderr)
    print("", file=sys.stderr)
    print("Download Godot 4.3 stable, STANDARD edition (not .NET/C#):", file=sys.stderr)
    print("  https://godotengine.org/download/archive/4.3-stable/", file=sys.stderr)
    print("", file=sys.stderr)
    print("It is a single executable - no installer, no dependencies.", file=sys.stderr)
    print("Then either put it on PATH as `godot`, or point $GODOT at it:", file=sys.stderr)
    print("", file=sys.stderr)
    if sys.platform == "win32":
        print('  set GODOT=C:\\path\\to\\Godot_v4.3-stable_win64.exe', file=sys.stderr)
    else:
        print("  export GODOT=~/Downloads/Godot_v4.3-stable_linux.x86_64", file=sys.stderr)
        print("  chmod +x $GODOT", file=sys.stderr)
    print("  python3 tools/run_game.py --check", file=sys.stderr)
    return 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--check", action="store_true", help="headless proof, no window")
    parser.add_argument("--editor", action="store_true", help="open in the Godot editor")
    args = parser.parse_args()

    binary = find_godot()
    if binary is None:
        return explain_missing()

    version = version_of(binary)
    print(f"Godot   : {binary}")
    print(f"Version : {version or 'unknown'}")
    if version and not version.startswith(WANT_VERSION):
        print("", file=sys.stderr)
        print(f"This project targets Godot {WANT_VERSION}. Version {version} may", file=sys.stderr)
        print("refuse to open it or offer an unwanted conversion.", file=sys.stderr)
    print(f"Project : {PROJECT}")
    print("")

    # First run has to import assets, otherwise class_name lookups fail.
    subprocess.run(
        [binary, "--headless", "--path", str(PROJECT), "--import"],
        capture_output=True,
        timeout=900,
    )

    if args.editor:
        return subprocess.call([binary, "--path", str(PROJECT), "--editor"])

    if args.check:
        print("Booting the project headless and playing main.tscn...")
        print("")
        result = subprocess.run(
            [binary, "--headless", "--path", str(PROJECT), "res://tests/smoke.tscn"],
            capture_output=True,
            text=True,
            timeout=1800,
        )
        noise = ("mesh_get_surface_count", 'Parameter "m"', "ObjectDB instances leaked",
                 "resources still in use", "at: cleanup", "at: clear")
        for line in (result.stdout or "").splitlines():
            if not any(token in line for token in noise):
                print(line)
        passed = "SMOKE LULUS" in (result.stdout or "")
        print("")
        if passed:
            print("Setup is correct: the engine ran the real scenes end to end.")
            print("Now see it with pixels:  python3 tools/run_game.py")
            return 0
        print("Setup problem - the run above did not finish cleanly.", file=sys.stderr)
        for line in (result.stderr or "").splitlines()[-15:]:
            print(line, file=sys.stderr)
        return 1

    print("Launching. Portrait 1080x1920; drag to move, click to fire.")
    return subprocess.call([binary, "--path", str(PROJECT)])


if __name__ == "__main__":
    raise SystemExit(main())
