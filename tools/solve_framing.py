#!/usr/bin/env python3
"""Solve the camera placement that reproduces the key art framing.

Three things were measured off docs/17-keyart-neon-analysis.md §17.2:

    anchor   body centre of the player at 87% of screen height
    size     player occupies 18.5% of screen height
    horizon  the horizon line lands at 14% of screen height

Those are three constraints; camera height, camera depth and pitch are three
unknowns, so the framing is determined, not a matter of taste. This brute
force search is deliberately dumb and slow: it runs once per art change and a
grid search cannot land in a local minimum the way a gradient solver can.

Run: python3 tools/solve_framing.py
"""
import math

FOV = 60.0           # vertical FOV at the 9:16 reference aspect
PLAYER_H = 4.86      # 1.8 m model x CHAR_SCALE 2.0 x PLAYER_SCALE 1.35
PLAYER_Z = -2.0      # world z of SimWorld.SQUAD_Z = 2.0
ASPECT = 9.0 / 16.0

TARGET_ANCHOR = 0.87
TARGET_SIZE = 0.185
TARGET_HORIZON = 0.14


def projector(cam_y: float, cam_z: float, pitch: float):
    """Returns screen_y(py, pz) in 0..1 (0 = top) plus view depth."""
    t = math.tan(math.radians(FOV) / 2.0)
    fwd = (-math.sin(pitch), -math.cos(pitch))
    up = (math.cos(pitch), -math.sin(pitch))

    def project(py: float, pz: float):
        dy, dz = py - cam_y, pz - cam_z
        depth = dy * fwd[0] + dz * fwd[1]
        if depth <= 0.01:
            return None, depth
        return 0.5 - 0.5 * ((dy * up[0] + dz * up[1]) / (depth * t)), depth

    return project, t


def horizon_y(pitch: float) -> float:
    t = math.tan(math.radians(FOV) / 2.0)
    return 0.5 - 0.5 * (math.sin(pitch) / (math.cos(pitch) * t))


def solve():
    best = None
    for cam_y in (x * 0.05 for x in range(60, 400)):
        for cam_z in (x * 0.05 for x in range(0, 300)):
            for pitch_deg in (x * 0.5 for x in range(15, 150)):
                pitch = math.radians(pitch_deg)
                project, _ = projector(cam_y, cam_z, pitch)
                foot, _ = project(0.0, PLAYER_Z)
                head, _ = project(PLAYER_H, PLAYER_Z)
                if foot is None or head is None:
                    continue
                err = (
                    (((foot + head) / 2 - TARGET_ANCHOR) / 0.02) ** 2
                    + ((foot - head - TARGET_SIZE) / 0.02) ** 2
                    + ((horizon_y(pitch) - TARGET_HORIZON) / 0.02) ** 2
                )
                if best is None or err < best[0]:
                    best = (err, cam_y, cam_z, pitch_deg)
    return best


def main() -> int:
    err, cam_y, cam_z, pitch_deg = solve()
    pitch = math.radians(pitch_deg)
    project, t = projector(cam_y, cam_z, pitch)
    look_z = cam_z - cam_y / math.tan(pitch)
    print(f"residual        {err:.3f}")
    print(f"heightOffset    {cam_y:.2f}")
    print(f"backOffsetZ     {cam_z:.2f}")
    print(f"pitchDegrees    {pitch_deg:.1f}")
    print(f"lookTargetZ     {-look_z:.1f}  (arena space)")
    print("\n lane z | screen y | visible half-width")
    for z in (2, 5, 9, 14, 20, 30, 40, 120):
        screen, depth = project(0.0, -float(z))
        print(f" {z:6} | {screen:8.3f} | {depth * t * ASPECT:6.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
