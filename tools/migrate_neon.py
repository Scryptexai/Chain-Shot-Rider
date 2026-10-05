#!/usr/bin/env python3
"""Phase 1 of the NEON rebuild (docs/18): rewrite the config art direction.

Why a script and not a hand edit: Config/arena_config.json is 20 KB of tuned
numbers. A hand edit risks silently dropping a balance value nobody notices
until a run plays differently. This touches only the keys it names, leaves the
rest byte-identical in meaning, and can be re-run.

Run: python3 tools/migrate_neon.py && python3 tools/sync_config.py
"""
import collections
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Config" / "arena_config.json"

# --- docs/17 §17.3: the 14 core colours, read off the key art ---------------
ART = collections.OrderedDict(
    [
        ("note", "NEON art direction. Satu-satunya sumber warna untuk arena, HUD, dan prototipe web. Diturunkan dari key art 'Neon Bullet-Hell Combo Assault' (docs/17-keyart-neon-analysis.md). Jangan menulis hex di kode; baca dari sini."),
        ("playerCyan", "#2BE8FF"),
        ("playerSteel", "#DCE6F2"),
        ("playerDeep", "#2E5BD8"),
        ("bumperMagenta", "#FF2BD6"),
        ("bumperCore", "#FF9BEE"),
        ("tracerRed", "#FF2A2A"),
        ("enemyRed", "#E03A2F"),
        ("enemyOrange", "#FF7A18"),
        ("blastOrange", "#FF9A2E"),
        ("blastCore", "#FFE3A0"),
        ("chainViolet", "#A64BFF"),
        ("vortexPurple", "#6B2FA8"),
        ("nightBase", "#070A14"),
        ("comboChrome", "#9BF2FF"),
        ("comboOutline", "#0A2A33"),
        ("brassBullet", "#D9A441"),
        (
            "postfx",
            collections.OrderedDict(
                [
                    ("glowIntensity", 1.15),
                    ("glowBloom", 0.28),
                    ("glowThreshold", 0.60),
                    ("fogColor", "#2A1340"),
                    ("fogStartZ", 28.0),
                    ("fogDensity", 0.022),
                    ("vignette", 0.35),
                    ("grain", 0.03),
                    ("exposure", 1.10),
                    ("tonemapWhite", 6.0),
                ]
            ),
        ),
    ]
)

# --- Five neon rooms. ids unchanged so existing saves keep their unlocks. ---
VARIANT_SKIN = {
    "classic_pit": (
        "Neon Dock",
        "Dok bongkar-muat. Empat bumper simetris mengajarkan sudut pantul 45 derajat.",
        {
            "primary": "#2BE8FF",
            "enemy": "#E03A2F",
            "bumper": "#FF2BD6",
            "bgTop": "#131B38",
            "bgBottom": "#070A14",
            "grid": "#1E8FA8",
            "player": "#DCE6F2",
            "tracer": "#FF2A2A",
            "chain": "#A64BFF",
            "bumperGlow": "#FF9BEE",
            "wallPanel": "#2A1B3D",
            "fog": "#2A1340",
            "vortex": "#6B2FA8",
        },
    ),
    "twin_towers": (
        "Data Spires",
        "Dua menara data membelah lorong jadi tiga jalur sempit. Zig-zag bernilai tinggi.",
        {
            "primary": "#36D9FF",
            "enemy": "#E8452E",
            "bumper": "#C62BFF",
            "bgTop": "#1A1440",
            "bgBottom": "#06060F",
            "grid": "#2C6FD8",
            "player": "#DCE6F2",
            "tracer": "#FF3A1F",
            "chain": "#B45CFF",
            "bumperGlow": "#E59BFF",
            "wallPanel": "#241a46",
            "fog": "#2B1A52",
            "vortex": "#7A3AC4",
        },
    ),
    "gravity_chamber": (
        "Singularity Bay",
        "Dua sumur gravitasi melengkungkan peluru. Lintasan non-linear, imbalan tinggi.",
        {
            "primary": "#2BFFE0",
            "enemy": "#FF4D4D",
            "bumper": "#FF2BD6",
            "bgTop": "#0D2338",
            "bgBottom": "#04080F",
            "grid": "#1E9E9E",
            "player": "#E4F3FF",
            "tracer": "#FF2A2A",
            "chain": "#9B5CFF",
            "bumperGlow": "#FFA8F0",
            "wallPanel": "#17304a",
            "fog": "#1C2A5C",
            "vortex": "#5C32C4",
        },
    ),
    "explosive_yard": (
        "Fuel Yard",
        "Ladang drum bahan bakar. Satu pantulan tepat memicu ledakan berantai sepanjang arena.",
        {
            "primary": "#FFB02E",
            "enemy": "#FF5A1F",
            "bumper": "#FF3DA6",
            "bgTop": "#331026",
            "bgBottom": "#0B0408",
            "grid": "#C2561F",
            "player": "#DCE6F2",
            "tracer": "#FF2A2A",
            "chain": "#FF6AD5",
            "bumperGlow": "#FFB0E6",
            "wallPanel": "#3A1A20",
            "fog": "#3A1430",
            "vortex": "#8A2F6B",
        },
    ),
    "moving_maze": (
        "Shift Grid",
        "Pelat lantai bergeser terus. Celah tembak berubah tiap detik.",
        {
            "primary": "#7CFF4D",
            "enemy": "#E03A2F",
            "bumper": "#FF2BD6",
            "bgTop": "#10202A",
            "bgBottom": "#050A0C",
            "grid": "#39A86B",
            "player": "#DCE6F2",
            "tracer": "#FF2A2A",
            "chain": "#A64BFF",
            "bumperGlow": "#FF9BEE",
            "wallPanel": "#1C2E2A",
            "fog": "#1E2A44",
            "vortex": "#6B2FA8",
        },
    ),
}

# --- Crowd: one red-orange family. Difference reads from value and
# saturation, never from hue, so 200 of them still parse as one army. ------
ENEMY_SKIN = {
    "grunt": ("#E03A2F", "Infanteri dasar, mati 1 hit."),
    "runner": ("#FF7A18", "Penyerbu cepat, memecah formasi."),
    "brute": ("#B32015", "Lapis berat, butuh bounce ber-stack."),
    "shielder": ("#FF9A5E", "Pembawa perisai energi, hanya rusak dari samping/belakang."),
    "splitter": ("#FF4D7A", "Pecah jadi 3 infanteri saat mati."),
    "bomber": ("#FFC247", "Pembawa muatan, meledak saat mati, radius 2.5, chain kill."),
}

# --- Phase 2: camera framing, solved not guessed ----------------------------
#
# Three measurements were taken off the key art (docs/17 §17.2): the player's
# body centre sits at 87% of screen height, the player is 18.5% of screen
# height tall, and the horizon lands at 14%. Those are three equations; camera
# height, camera depth and pitch are three unknowns. tools/solve_framing.py
# searches them. The answer is a LOW pitch with a wide lens, not the steep
# top-down the eye first reports — the floor looks steep near the player
# because the bottom of a 60 degree frame already points 52 degrees down.
CAMERA = collections.OrderedDict(
    [
        ("pitchDegrees", 22.5),
        ("yawDegrees", 0.0),
        ("heightOffset", 15.95),
        ("backOffsetZ", 11.1),
        ("lookTargetZ", 27.4),
        ("followLerp", 8.0),
        ("followFactorX", 0.75),
        ("bulletFollowLerp", 14.0),
        ("playerScreenAnchor", 0.87),
        ("playerMinScreenHeight", 0.15),
        ("wallVisibleFromZ", 9.0),
        ("fovMaxDeg", 62.0),
        ("comboDollyIn", 0.5),
        ("comboDollyAt", 20),
        ("dollyRate", 1.5),
        (
            "framingNote",
            "Diselesaikan dari tiga ukuran key art (anchor 0.87, tinggi pemain 0.185, horizon 0.14) lewat tools/solve_framing.py. Angka lama (pitch 40, distance 18, heightOffset 12) membingkai arena isometrik datar dengan pemain sebesar ibu jari.",
        ),
        # distance/lookAheadZ are kept so older tools that read them do not
        # crash; the Godot camera no longer uses either.
        ("distance", 11.5),
        ("lookAheadZ", 9.0),
    ]
)

# Lebar lorong dipersempit 20 -> 12. Dua alasan, keduanya terukur:
# pada framing baru, dinding di x=+-10 baru masuk layar di z~20, artinya
# separuh arena memantulkan peluru di luar layar; dan key art memperlihatkan
# lorong sempit yang padat, bukan lapangan. Dengan x=+-6 dinding terbaca
# mulai z~9, tepat di awal zona tempur.
ARENA_WIDTH = 12.0


# Card names carried the fantasy fiction in player-facing text.
CARD_RENAME = {
    "extra_troops": ("Overclock Inti", "+4 daya tembak awal"),
    "fire_rate": ("Siklus Cepat", "+15% laju tembak otomatis"),
    "auto_damage": ("Muatan Terfokus", "+20% damage tembak otomatis"),
    "chain_bounces": ("Lapis Pantul", "+5 pantulan chain shot"),
    "chain_damage": ("Inti Plasma", "+25% damage chain shot"),
    "charge_speed": ("Kapasitor Kilat", "Chain shot terisi 20% lebih cepat"),
    "move_speed": ("Servo Ringan", "+12% kecepatan geser"),
    "gate_luck": ("Prediksi Gerbang", "Gerbang negatif 25% lebih jarang"),
}


def main() -> int:
    data = json.loads(SRC.read_text(), object_pairs_hook=collections.OrderedDict)

    data["version"] = "3.0.0-neon"
    data["notes"] = (
        "Single source of truth untuk arena CHAIN RIDER (arah visual NEON, basis "
        "key art docs/17-keyart-neon-analysis.md). Dipakai tools/blueprint_gen.py, "
        "prototipe web, dan Godot. Koordinat dunia: X = -10..+10 (lebar 20), "
        "Z = 0..40 (panjang 40), Y = up. Origin (0,0,0) = tengah dinding bawah."
    )

    # artDirection sits right after the notes so it reads as the headline.
    rebuilt = collections.OrderedDict()
    for key, value in data.items():
        rebuilt[key] = value
        if key == "notes":
            rebuilt["artDirection"] = ART
    data = rebuilt

    data["camera"] = merge_keep_extra(CAMERA, data["camera"])
    narrow_lane(data)

    for variant in data["variants"]:
        name, desc, theme = VARIANT_SKIN[variant["id"]]
        variant["name"] = name
        variant["description"] = desc
        variant["theme"] = collections.OrderedDict(theme.items())

    for enemy in data["enemyTypes"]:
        colour, note = ENEMY_SKIN[enemy["id"]]
        enemy["color"] = colour
        enemy["note"] = note

    for card in data["meta"]["cards"]:
        if card["id"] in CARD_RENAME:
            card["name"], card["desc"] = CARD_RENAME[card["id"]]

    # The squad is now one soldier. The rules are untouched: `troops` keeps
    # driving fire rate and leak punishment, it is simply read as the weapon's
    # power level instead of a head count. See docs/18 Phase 4.
    data["squad"]["presentation"] = "solo"
    data["squad"]["note"] = (
        "Satu prajurit, bukan peleton (keputusan NEON, docs/18 Fase 4). "
        "Nilai `troops` tetap mengemudikan laju tembak dan hukuman kebobolan, "
        "tapi dibaca sebagai POWER senjata. Aturan sim tidak berubah, jadi "
        "replay lama tetap cocok."
    )
    data["squad"]["powerLabel"] = "POWER"

    SRC.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"rewrote {SRC.relative_to(ROOT)}")
    return 0


def narrow_lane(data: dict) -> None:
    """Squeeze the lane to ARENA_WIDTH and drag the furniture in with it.

    Guarded by a marker so re-running the migration does not shrink the arena
    a second time.
    """
    arena = data["arena"]
    old_width = float(arena["width"])
    if "widthScaledFrom" in arena or abs(old_width - ARENA_WIDTH) < 0.001:
        return
    ratio = ARENA_WIDTH / old_width
    arena["widthScaledFrom"] = old_width
    arena["width"] = ARENA_WIDTH
    arena["xMin"] = -ARENA_WIDTH / 2.0
    arena["xMax"] = ARENA_WIDTH / 2.0
    arena["walls"]["left"]["x"] = -ARENA_WIDTH / 2.0
    arena["walls"]["right"]["x"] = ARENA_WIDTH / 2.0
    for variant in data["variants"]:
        for obstacle in variant.get("obstacles", []):
            if "x" in obstacle:
                obstacle["x"] = round(float(obstacle["x"]) * ratio, 2)
            # Big footprints scale with the lane too. Two 2.4 radius pillars
            # in a 12 wide lane leave no centre channel at all, which turns
            # Data Spires from three lanes into a wall.
            if obstacle.get("type") in ("pillar", "gravityWell") and "radius" in obstacle:
                obstacle["radius"] = round(float(obstacle["radius"]) * ratio, 2)
            if "width" in obstacle:
                obstacle["width"] = round(float(obstacle["width"]) * ratio, 2)
    # Formation spacing follows the lane, otherwise a 12-column wave is wider
    # than the arena it spawns into.
    data["spawn"]["spacing"] = round(float(data["spawn"]["spacing"]) * ratio, 3)
    data["spawn"]["separationRadius"] = round(
        float(data["spawn"]["separationRadius"]) * ratio, 3
    )
    data["gates"]["halfWidth"] = round(float(data["gates"]["halfWidth"]) * ratio, 2)


def merge_keep_extra(new: collections.OrderedDict, old: dict) -> collections.OrderedDict:
    """New values win; keys only present in the old block survive (shake etc.)."""
    out = collections.OrderedDict(new)
    for key, value in old.items():
        if key not in out:
            out[key] = value
    return out


if __name__ == "__main__":
    raise SystemExit(main())
