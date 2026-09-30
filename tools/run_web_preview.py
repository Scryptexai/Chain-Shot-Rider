#!/usr/bin/env python3
"""
run_web_preview.py - One command to see the real Godot game in a browser.

    python3 tools/run_web_preview.py            # export + serve on :8081
    python3 tools/run_web_preview.py --port 9000
    python3 tools/run_web_preview.py --install-templates
    python3 tools/run_web_preview.py --skip-export      # serve an existing build

What this renders is the actual engine: the Godot runtime compiled to
WebAssembly, drawing through WebGL2. It is NOT prototype/index.html, which is
a hand-written JavaScript mock-up with no Godot in it at all.

The script does four things, each of which fails with an explanation rather
than a stack trace:

  1. Finds the Godot binary ($GODOT, then PATH) and checks it is 4.3.
  2. Checks the 4.3 export templates are installed, because the export fails
     without them and the message is easy to miss in a wall of output.
  3. Exports the "Web" preset into build/web/.
  4. Serves build/web/ with the cross-origin isolation headers the build
     needs, since a plain static server gets a black canvas.

Native desktop needs none of this - `godot --path godot/` just runs the game.
The web route exists for sharing a link and for previewing without an editor.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot"
WEB_DIR = ROOT / "build" / "web"
GODOT_VERSION = "4.3"
TEMPLATE_DIR_NAME = "4.3.stable"
TEMPLATES_URL = (
    "https://github.com/godotengine/godot/releases/download/"
    "4.3-stable/Godot_v4.3-stable_export_templates.tpz"
)
# Files Godot looks for. Verified by running the export without them: it
# reports the missing path itself, which is where these names come from.
REQUIRED_TEMPLATES = ("web_release.zip", "web_debug.zip")


def template_root() -> Path:
    """Where Godot keeps export templates on this OS."""
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
        return base / "Godot" / "export_templates" / TEMPLATE_DIR_NAME
    if sys.platform == "darwin":
        return (
            Path.home()
            / "Library"
            / "Application Support"
            / "Godot"
            / "export_templates"
            / TEMPLATE_DIR_NAME
        )
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "godot" / "export_templates" / TEMPLATE_DIR_NAME


def find_godot() -> str | None:
    candidate = os.environ.get("GODOT")
    if candidate and shutil.which(candidate):
        return shutil.which(candidate)
    if candidate and Path(candidate).is_file():
        return candidate
    return shutil.which("godot")


def godot_version(binary: str) -> str:
    try:
        out = subprocess.run(
            [binary, "--version"], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return (out.stdout or out.stderr).strip().splitlines()[-1] if out.stdout or out.stderr else ""


def missing_templates() -> list[str]:
    root = template_root()
    return [name for name in REQUIRED_TEMPLATES if not (root / name).is_file()]


def install_templates() -> int:
    """Downloads and unpacks the .tpz. Only runs when asked explicitly."""
    import urllib.request

    root = template_root()
    root.mkdir(parents=True, exist_ok=True)
    archive = root.parent / "Godot_v4.3-stable_export_templates.tpz"
    print(f"Downloading {TEMPLATES_URL}")
    print("  (~700 MB, one time)")
    try:
        urllib.request.urlretrieve(TEMPLATES_URL, archive)
    except Exception as exc:  # noqa: BLE001 - any network failure is the same story
        print(f"Download failed: {exc}", file=sys.stderr)
        print("", file=sys.stderr)
        print("Install them by hand instead:", file=sys.stderr)
        print("  Godot editor -> Editor -> Manage Export Templates -> Download", file=sys.stderr)
        return 1

    # A .tpz is a zip whose entries live under a top-level templates/ folder.
    print(f"Unpacking into {root}")
    with zipfile.ZipFile(archive) as zf:
        for member in zf.namelist():
            if member.endswith("/"):
                continue
            name = member.split("/", 1)[-1] if member.startswith("templates/") else member
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
    archive.unlink(missing_ok=True)
    still_missing = missing_templates()
    if still_missing:
        print(f"Unpacked, but still missing: {', '.join(still_missing)}", file=sys.stderr)
        return 1
    print("Export templates ready.")
    return 0


def export_web(binary: str) -> int:
    WEB_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        binary,
        "--headless",
        "--path",
        str(PROJECT),
        "--export-release",
        "Web",
        "../build/web/index.html",
    ]
    print(f"Exporting: {' '.join(cmd)}")
    result = subprocess.run(cmd)
    if result.returncode != 0 or not (WEB_DIR / "index.html").is_file():
        print("", file=sys.stderr)
        print("Export failed. Most common cause is missing export templates;", file=sys.stderr)
        print("run this script with --install-templates.", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--skip-export", action="store_true", help="serve an existing build")
    parser.add_argument("--install-templates", action="store_true")
    args = parser.parse_args()

    if args.install_templates:
        code = install_templates()
        if code != 0:
            return code

    if not args.skip_export:
        binary = find_godot()
        if binary is None:
            print("Godot not found.", file=sys.stderr)
            print("", file=sys.stderr)
            print("Install Godot 4.3 stable (standard, not .NET), then either put", file=sys.stderr)
            print("it on PATH as `godot` or point $GODOT at it:", file=sys.stderr)
            print("  GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 \\", file=sys.stderr)
            print("      python3 tools/run_web_preview.py", file=sys.stderr)
            return 2

        version = godot_version(binary)
        print(f"Godot: {binary}  ({version or 'version unknown'})")
        if version and not version.startswith(GODOT_VERSION):
            print(
                f"Warning: project targets Godot {GODOT_VERSION}, this is {version}.",
                file=sys.stderr,
            )

        gaps = missing_templates()
        if gaps:
            print("", file=sys.stderr)
            print(f"Export templates missing from {template_root()}:", file=sys.stderr)
            for name in gaps:
                print(f"  - {name}", file=sys.stderr)
            print("", file=sys.stderr)
            print("Fix with either:", file=sys.stderr)
            print("  python3 tools/run_web_preview.py --install-templates", file=sys.stderr)
            print("  Godot editor -> Editor -> Manage Export Templates -> Download", file=sys.stderr)
            return 3

        if export_web(binary) != 0:
            return 1

    if not (WEB_DIR / "index.html").is_file():
        print(f"No build at {WEB_DIR}/index.html - drop --skip-export.", file=sys.stderr)
        return 2

    # Hand off to the server that sends COOP/COEP; same headers, one place.
    serve = ROOT / "tools" / "serve_web_build.py"
    print("")
    print(f"Serving the real Godot build -> http://localhost:{args.port}/")
    return subprocess.call([sys.executable, str(serve), str(args.port)])


if __name__ == "__main__":
    raise SystemExit(main())
