#!/usr/bin/env python3
"""Copy the canonical config into the Godot project.

Config/arena_config.json at the repo root is the single source of truth: the web
prototype and the headless harness both read it directly. Godot can only load
files under res://, so it gets a copy. Run this after editing the config.
"""
import filecmp
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Config" / "arena_config.json"
DST = ROOT / "godot" / "config" / "arena_config.json"


def main() -> int:
    if not SRC.exists():
        print(f"missing source config: {SRC}", file=sys.stderr)
        return 1
    if DST.exists() and filecmp.cmp(SRC, DST, shallow=False):
        print("godot config already up to date")
        return 0
    DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SRC, DST)
    print(f"synced -> {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
