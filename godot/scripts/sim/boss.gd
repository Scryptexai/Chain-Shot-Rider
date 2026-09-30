class_name Boss
extends RefCounted
## The end-of-stage boss: five of them, one per arena variant.
##
## Before this there was one generic boss with 1200 HP and a single sine
## wobble, used by all five stages — so the climax of every arena was the
## same fight in a different colour, even though the config had five bosses
## with distinct HP and movement patterns all along.
##
## Movement is a pure function of elapsed time rather than an integrated
## velocity. That keeps replays exact and means a boss cannot drift out of
## the arena after a long fight.
##
## Vulnerability rules deliberately do NOT gate all damage. Auto-fire always
## travels up the arena, so a rule like shifter's "weak from behind" would be
## unsatisfiable and the run would stall — and a stalled run is worse than a
## lost one. Facing instead scales the multiplier, so progress is always
## possible and the correct angle is simply far better.

const FIXED_DELTA := 1.0 / 60.0

var id: String = "colossus"
var pattern: String = "slow_descend_slam"
var shield_facing: String = "front"
var hp: float = 1200.0
var hp_max: float = 1200.0
var position: Vector2 = Vector2(0.0, 34.0)

var _spawn_z: float = 34.0
var _descend: float = 0.35
var _phase: float = 0.0


func _init(config: Dictionary, variant_index: int, hp_scale: float, difficulty: float) -> void:
	var entry := _lookup(config, variant_index)
	id = String(entry.get("id", "colossus"))
	pattern = String(entry.get("pattern", "slow_descend_slam"))
	shield_facing = String(entry.get("shieldFacing", "front"))
	hp_max = float(entry.get("hp", 1200.0)) * difficulty * hp_scale
	hp = hp_max
	var arena: Dictionary = config.get("arena", {})
	_spawn_z = float(arena.get("zMax", 40.0)) - 6.0
	position = Vector2(0.0, _spawn_z)


## Finds this variant's boss, by the variant's own `boss` id.
func _lookup(config: Dictionary, variant_index: int) -> Dictionary:
	var variants: Array = config.get("variants", [])
	if variant_index < 0 or variant_index >= variants.size():
		return {}
	var variant: Dictionary = variants[variant_index]
	var wanted := String(variant.get("boss", ""))
	for candidate in config.get("bosses", []):
		var boss: Dictionary = candidate
		if String(boss.get("id", "")) == wanted:
			return boss
	return {}


## Advances the fight. `health_fraction` drives the second-phase speed-up that
## every pattern shares: a wounded boss presses harder.
func tick(elapsed: float) -> void:
	_phase += FIXED_DELTA
	var urgency := 1.0 + (1.0 - clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)) * 0.8
	match pattern:
		"mirror_pair_sidestep":
			# Twin warden: wide, fast lateral sweeps that punish standing still.
			position.x = sin(elapsed * 1.6 * urgency) * 7.5
			position.y -= _descend * 0.9 * urgency * FIXED_DELTA
		"orbit_pull_pulse":
			# Singularity: circles its own centre, so the opening rotates.
			position.x = sin(elapsed * 1.1 * urgency) * 5.0
			position.y = _spawn_z - _phase * _descend * 0.8 + cos(elapsed * 1.1) * 1.8
		"barrel_drop_charge":
			# Pyro baron: holds, then lunges. Stepwise rather than smooth.
			var cycle := fposmod(elapsed * 0.45 * urgency, 1.0)
			position.x = sin(elapsed * 0.6) * 4.0
			position.y -= (_descend * 2.6 if cycle > 0.75 else _descend * 0.15) * FIXED_DELTA
		"teleport_lane_swap":
			# Shifter: snaps between three lanes instead of sliding.
			var lane := int(fposmod(elapsed * 0.5 * urgency, 3.0))
			position.x = [-6.0, 0.0, 6.0][lane]
			position.y -= _descend * urgency * FIXED_DELTA
		_:
			# Colossus: the plain one, and deliberately so — it teaches the
			# fight before the other four complicate it.
			position.x = sin(elapsed * 0.8) * 6.0
			position.y -= _descend * urgency * FIXED_DELTA


## Damage multiplier for a hit arriving along `direction`.
##
## Never returns zero: see the note at the top of this file. The worst angle
## still chips, it just takes far longer than the right one.
func facing_multiplier(direction: Vector2) -> float:
	match shield_facing:
		"front":
			# Shielded from the player's side; a shot coming back down the
			# arena has gone around it, and pays accordingly.
			return 1.0 if direction.y < 0.0 else 0.45
		"back_weak":
			return 2.0 if direction.y < 0.0 else 0.6
		"rotating":
			# The opening turns with the boss, so timing replaces position.
			var open := sin(_phase * 1.4) > 0.0
			return 1.6 if open else 0.5
	return 1.0


func is_dead() -> bool:
	return hp <= 0.0
