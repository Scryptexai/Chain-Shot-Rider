class_name ObstacleField
extends RefCounted
## The arena furniture for one variant: bumpers, pillars, wells, walls,
## platforms and barrels.
##
## Until this existed the five arenas were a palette swap — same empty box,
## different colour. The shapes were already in the config and already proven
## in the web prototype; this is the version that ships.
##
## Like the rest of the sim it holds no nodes, uses no physics engine, and
## advances only on the fixed step it is handed, so the arena is replayable.
## Explosions return their effect instead of reaching back into SimWorld,
## which keeps damage rules in one place.

const FIXED_DELTA := 1.0 / 60.0

var obstacles: Array[Dictionary] = []

var _cfg: Dictionary = {}
var _defaults: Dictionary = {}


func _init(config: Dictionary, variant_index: int) -> void:
	_cfg = config
	_defaults = config.get("obstacleDefaults", {})
	var variants: Array = config.get("variants", [])
	if variant_index < 0 or variant_index >= variants.size():
		return
	var variant: Dictionary = variants[variant_index]
	for entry in variant.get("obstacles", []):
		obstacles.append(_make(entry))


func _make(entry: Variant) -> Dictionary:
	var source: Dictionary = entry
	var kind := String(source.get("type", "bumper"))
	var preset: Dictionary = _defaults.get(kind, {})
	var x := Cfg.num(source, "x", 0.0)
	return {
		"kind": kind,
		"x": x,
		"base_x": x,
		"z": Cfg.num(source, "z", 20.0),
		"radius": Cfg.num(source, "radius", Cfg.num(preset, "radius", 0.9)),
		"force": Cfg.num(source, "force", Cfg.num(preset, "force", 5.0)),
		"width": Cfg.num(source, "width", Cfg.num(preset, "width", 4.0)),
		"travel": Cfg.num(source, "travel", 6.0),
		"speed": Cfg.num(source, "speed", Cfg.num(preset, "speed", 2.0)),
		"phase": Cfg.num(source, "phase", 0.0),
		"hp": _starting_hp(kind, preset),
		"alive": true,
	}


func _starting_hp(kind: String, preset: Dictionary) -> float:
	match kind:
		"barrel":
			return Cfg.num(preset, "hp", 1.0)
		"shieldWall":
			return Cfg.num(preset, "hp", 3.0)
	return -1.0


## Moving platforms slide on a sine of elapsed time rather than an integrated
## velocity, so there is no accumulated drift and a replay lands them in
## exactly the same place.
func tick(elapsed: float) -> void:
	for entry in obstacles:
		var obstacle: Dictionary = entry
		if String(obstacle["kind"]) != "movingPlatform":
			continue
		var phase := float(obstacle["phase"]) + elapsed * float(obstacle["speed"])
		obstacle["x"] = float(obstacle["base_x"]) + sin(phase) * float(obstacle["travel"]) * 0.5


## Gravity wells bend the chain bullet instead of stopping it, which is what
## makes that arena read as a different game rather than a different colour.
## Returns the new heading.
func gravity_turn(position: Vector2, direction: Vector2) -> Vector2:
	var heading := direction
	var max_turn := (
		Cfg.num(_defaults.get("gravityWell", {}), "maxCurveDegPerSec", 120.0) * FIXED_DELTA
	)
	for entry in obstacles:
		var obstacle: Dictionary = entry
		if String(obstacle["kind"]) != "gravityWell" or not bool(obstacle["alive"]):
			continue
		var to_well := Vector2(float(obstacle["x"]), float(obstacle["z"])) - position
		var distance := to_well.length()
		var radius := float(obstacle["radius"])
		if distance > radius or distance < 0.001:
			continue
		# Falls off toward the rim: grazing the edge nudges, a centre pass
		# swings hard.
		var strength := (1.0 - distance / radius) * float(obstacle["force"])
		var desired := to_well / distance
		var cross := heading.x * desired.y - heading.y * desired.x
		var turn := clampf(
			rad_to_deg(asin(clampf(cross, -1.0, 1.0))) * strength * FIXED_DELTA, -max_turn, max_turn
		)
		heading = Ricochet.rotate_xz(heading, -turn)
	return heading


## Nearest solid contact along a swept motion. Wells and platforms are skipped:
## one curves the bullet, the other only blocks the crowd.
func sweep(position: Vector2, motion: Vector2, bullet_radius: float) -> Dictionary:
	var best := {"hit": false}
	var best_t := 2.0
	for i in range(obstacles.size()):
		var obstacle: Dictionary = obstacles[i]
		if not bool(obstacle["alive"]):
			continue
		var kind := String(obstacle["kind"])
		if kind == "gravityWell" or kind == "movingPlatform":
			continue
		var radius := float(obstacle["radius"])
		if kind == "shieldWall":
			radius = float(obstacle["width"]) * 0.5
		var center := Vector2(float(obstacle["x"]), float(obstacle["z"]))
		var hit: Dictionary = Ricochet.sweep_circle(position, motion, bullet_radius, center, radius)
		if hit.get("hit", false) and float(hit["t"]) < best_t:
			best_t = float(hit["t"])
			best = {"hit": true, "t": best_t, "index": i, "normal": hit["normal"]}
	return best


## Applies a chain hit. Returns a description of what the sim must still do:
## `damage_bonus` for the bullet, and `blasts` for area damage it must deal.
func resolve_hit(index: int) -> Dictionary:
	var obstacle: Dictionary = obstacles[index]
	var kind := String(obstacle["kind"])
	var result := {"kind": kind, "damage_bonus": 0.0, "blasts": []}
	match kind:
		"barrel":
			result["blasts"] = detonate(index)
		"shieldWall":
			obstacle["hp"] = float(obstacle["hp"]) - 1.0
			if float(obstacle["hp"]) <= 0.0:
				obstacle["alive"] = false
		"bumper":
			# A bumper should reward the bank shot, not merely permit it.
			result["damage_bonus"] = Cfg.num(_defaults.get("bumper", {}), "bounceBonusDamage", 0.05)
	return result


## Detonates a barrel and everything within its blast, returning one entry per
## explosion so the caller can apply damage and spawn effects.
func detonate(index: int) -> Array:
	var blasts: Array = []
	var pending: Array[int] = [index]
	# Iterative rather than recursive: a dense yard could nest deeply, and
	# each barrel can only die once so the queue always drains.
	while not pending.is_empty():
		var at: int = pending.pop_back()
		var obstacle: Dictionary = obstacles[at]
		if not bool(obstacle["alive"]) or String(obstacle["kind"]) != "barrel":
			continue
		obstacle["alive"] = false
		var preset: Dictionary = _defaults.get("barrel", {})
		var center := Vector2(float(obstacle["x"]), float(obstacle["z"]))
		var radius := Cfg.num(preset, "explosionRadius", 3.0)
		blasts.append(
			{
				"x": center.x,
				"z": center.y,
				"radius": radius,
				"damage": Cfg.num(preset, "explosionDamage", 50.0)
			}
		)
		for other in range(obstacles.size()):
			var neighbour: Dictionary = obstacles[other]
			if not bool(neighbour["alive"]) or String(neighbour["kind"]) != "barrel":
				continue
			var to_other := center.distance_to(
				Vector2(float(neighbour["x"]), float(neighbour["z"]))
			)
			if to_other <= radius:
				pending.append(other)
	return blasts


## Platforms shove the crowd back instead of letting it walk through.
## Returns the corrected z, or the original if nothing is in the way.
func block_enemy(x: float, z: float) -> float:
	for entry in obstacles:
		var obstacle: Dictionary = entry
		if String(obstacle["kind"]) != "movingPlatform" or not bool(obstacle["alive"]):
			continue
		var half := float(obstacle["width"]) * 0.5
		if absf(x - float(obstacle["x"])) < half and absf(z - float(obstacle["z"])) < 0.6:
			return float(obstacle["z"]) + 0.6
	return z
