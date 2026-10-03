#!/usr/bin/env python3
"""Static checks for the Godot project that a linter cannot do.

gdlint verifies that GDScript is well formed and well styled. It does not know
that `GameConfig.num("bullet.baseSpeed")` has to correspond to a key that
actually exists in the JSON, that `SimWorld.MAX_ENEMIES` has to be defined, or
that a scene file may not point at a script that was moved. Every one of those
is a runtime crash, and all three are cheap to catch here.

Three real bugs were found by exactly these checks during development:
a config accessor that silently returned an empty dictionary, a scene resource
path that did not resolve, and a dangling cross-file symbol.

Usage: python3 tools/validate_godot.py [--quiet]
Exit code 0 when clean, 1 when any check fails.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT = ROOT / "godot"
CONFIG = ROOT / "Config" / "arena_config.json"

ACCESSOR = re.compile(r'GameConfig\.(num|integer|flag|text|dict|list|color)\("([^"]*)"\)')
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
MEMBER = re.compile(r"^(?:const|var|static func|func|enum)\s+(\w+)", re.M)
# Kelas dalam (`class Actor:` menjorok di dalam file) adalah anggota yang sah
# dan dipakai sebagai tipe: CharacterPool.Actor. Tanpa pola ini validator
# menyebut tipe yang benar-benar ada sebagai tidak terdefinisi.
INNER_CLASS = re.compile(r"^\s*class\s+(\w+)\s*:", re.M)
ENUM_BODY = re.compile(r"^enum\s+(\w+)\s*\{([^}]*)\}", re.M)
EXT_PATH = re.compile(r'path="res://([^"]+)"')
# load()/preload() targets are resolved at runtime, so a moved shader or scene
# fails only when that code path first runs — often minutes into a session.
RES_LOAD = re.compile(r'(?:pre)?load\(\s*"res://([^"]+)"\s*\)')
RES_CONST = re.compile(r'^\s*const\s+\w+\s*:?=\s*"res://([^"]+)"', re.M)


def resolve(root: dict, path: str):
    """Walks a dotted path through dicts and list indices."""
    node = root
    if not path:
        return node
    for part in path.split("."):
        if isinstance(node, dict):
            if part not in node:
                return None
            node = node[part]
        elif isinstance(node, list) and part.isdigit():
            index = int(part)
            if index >= len(node):
                return None
            node = node[index]
        else:
            return None
    return node


def check_config_sync(problems: list[str]) -> None:
    copy = GODOT / "config" / "arena_config.json"
    if not copy.exists():
        problems.append("godot/config/arena_config.json missing — run tools/sync_config.py")
        return
    if json.loads(copy.read_text()) != json.loads(CONFIG.read_text()):
        problems.append("godot config copy is stale — run tools/sync_config.py")


def check_config_keys(problems: list[str]) -> int:
    config = json.loads(CONFIG.read_text())
    checked = 0
    for gd in sorted(GODOT.rglob("*.gd")):
        for kind, path in ACCESSOR.findall(gd.read_text()):
            checked += 1
            if path == "":
                continue  # documented: empty path returns the whole config
            if resolve(config, path) is None:
                problems.append(f"{gd.relative_to(ROOT)}: config key '{path}' does not exist")
    return checked


def check_symbols(problems: list[str]) -> int:
    sources = {p: p.read_text() for p in GODOT.rglob("*.gd")}
    defined: dict[str, set[str]] = {}
    for text in sources.values():
        found = CLASS_NAME.search(text)
        if not found:
            continue
        members = set(MEMBER.findall(text))
        members.update(INNER_CLASS.findall(text))
        for enum_name, body in ENUM_BODY.findall(text):
            members.add(enum_name)
            members.update(v.strip() for v in body.split(",") if v.strip())
        defined[found.group(1)] = members
    checked = 0
    for path, text in sources.items():
        for cls, member in re.findall(r"\b(" + "|".join(defined) + r")\.(\w+)", text):
            checked += 1
            if member in ("new",) or member in defined[cls]:
                continue
            problems.append(f"{path.relative_to(ROOT)}: {cls}.{member} is not defined")
    return checked


def check_runtime_resources(problems: list[str]) -> int:
    """Resources referenced from code rather than from a scene file."""
    checked = 0
    for gd in sorted(GODOT.rglob("*.gd")):
        text = gd.read_text()
        for rel in set(RES_LOAD.findall(text)) | set(RES_CONST.findall(text)):
            checked += 1
            # Template seperti "res://assets/models/rigged/%s.glb" diisi saat
            # runtime. Yang bisa diperiksa di sini adalah foldernya ada dan
            # berisi setidaknya satu berkas dengan akhiran yang sama.
            if "%" in rel:
                folder = (GODOT / rel).parent
                suffix = pathlib.Path(rel).suffix
                if not folder.is_dir() or not any(folder.glob(f"*{suffix}")):
                    problems.append(
                        f"{gd.relative_to(ROOT)}: 'res://{rel}' tidak punya berkas yang cocok"
                    )
                continue
            if not (GODOT / rel).exists():
                problems.append(f"{gd.relative_to(ROOT)}: 'res://{rel}' not found")
    return checked


def check_scene_paths(problems: list[str]) -> int:
    checked = 0
    for scene in GODOT.rglob("*.tscn"):
        for rel in EXT_PATH.findall(scene.read_text()):
            checked += 1
            if not (GODOT / rel).exists():
                problems.append(f"{scene.relative_to(ROOT)}: resource 'res://{rel}' not found")
    return checked


def check_autoloads(problems: list[str]) -> None:
    project = GODOT / "project.godot"
    if not project.exists():
        problems.append("godot/project.godot missing")
        return
    text = project.read_text()
    for rel in re.findall(r'="\*res://([^"]+)"', text):
        if not (GODOT / rel).exists():
            problems.append(f"project.godot: autoload 'res://{rel}' not found")
    main = re.search(r'run/main_scene="res://([^"]+)"', text)
    if main and not (GODOT / main.group(1)).exists():
        problems.append(f"project.godot: main_scene 'res://{main.group(1)}' not found")


def main() -> int:
    quiet = "--quiet" in sys.argv
    if not GODOT.exists():
        print("no godot/ directory; nothing to validate")
        return 0
    problems: list[str] = []
    check_config_sync(problems)
    keys = check_config_keys(problems)
    symbols = check_symbols(problems)
    scenes = check_scene_paths(problems)
    runtime = check_runtime_resources(problems)
    check_autoloads(problems)

    if not quiet:
        print(f"config keys checked : {keys}")
        print(f"symbol uses checked : {symbols}")
        print(f"scene refs checked  : {scenes}")
        print(f"runtime res checked : {runtime}")
    if problems:
        print(f"\nFAIL — {len(problems)} problem(s):")
        for item in problems:
            print(f"  {item}")
        return 1
    print("\nOK — no problems found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
