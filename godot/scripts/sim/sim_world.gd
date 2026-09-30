class_name SimWorld
extends RefCounted
## The whole game rule set, with no engine dependencies.
##
## Nothing in this file touches Node, Input, delta time from the engine, or
## rendering. It advances on a fixed step it is handed, reads input from a
## plain struct, and keeps its state in flat arrays. Three things fall out of
## that: the same seed always replays identically, the rules can be tested
## headlessly without opening a window, and the renderer can be rewritten or
## replaced without touching a single rule.
##
## Squad control and gates are adapted from the Last War / Top War lane
## shooter: the squad slides horizontally, auto-fire is constant chip damage,
## and math gates descend toward the player. The modification is the chain
## shot — an aimed ricochet bullet the player can ride, which is the skill
## ceiling the reference games do not have. Gates apply to whoever passes
## through them, squad or bullet.

enum State { PLAYING, VICTORY, DEFEAT }

const TICKS_PER_SECOND := 60
const FIXED_DELTA := 1.0 / float(TICKS_PER_SECOND)
const MAX_ENEMIES := 256
const MAX_AUTO_BULLETS := 96
const MAX_SUBSTEPS := 4
const SQUAD_Z := 2.0
const CHAIN_MAX_LIFE := 12.0
# NOT Vector2.UP. This vector lives on the arena's (x, z) plane, where z grows
# away from the player; Vector2.UP is (0, -1) because screen Y points down.
# Using it aimed every chain shot backwards, out of the arena within a few
# ticks: twenty-eight shots, zero kills, and the game's signature weapon did
# nothing at all.
const FORWARD := Vector2(0.0, 1.0)

# --- run state -------------------------------------------------------------
var state: int = State.PLAYING
var elapsed: float = 0.0
var tick_index: int = 0
var score: int = 0
var combo: int = 0
var lives: int = 3
var troops: int = 5
var wave_index: int = 0
var stage_index: int = 0

# --- squad -----------------------------------------------------------------
var squad_x: float = 0.0
var squad_target_x: float = 0.0
var chain_charge: float = 0.0
var chain_charges: int = 0

# --- chain shot ------------------------------------------------------------
var chain_active: bool = false
var chain_pos: Vector2 = Vector2.ZERO
var chain_dir: Vector2 = FORWARD
var chain_speed: float = 25.0
var chain_bounces_left: int = 15
var chain_damage_mul: float = 1.0
var chain_riding: bool = false
var chain_life: float = 0.0
var chain_steer_meter: float = 0.0

# --- crowd (flat arrays, swap-removed) -------------------------------------
var enemy_count: int = 0
var enemy_x := PackedFloat32Array()
var enemy_z := PackedFloat32Array()
var enemy_hp := PackedFloat32Array()
var enemy_type := PackedInt32Array()

# --- auto-fire projectiles --------------------------------------------------
var auto_count: int = 0
var auto_x := PackedFloat32Array()
var auto_z := PackedFloat32Array()
var auto_vx := PackedFloat32Array()

# --- gates and pickups ------------------------------------------------------
var gates: Array[Dictionary] = []
var barrels: Array[Dictionary] = []

# --- boss -------------------------------------------------------------------
var boss_active: bool = false
var boss_pos: Vector2 = Vector2.ZERO
var boss_hp: float = 0.0
var boss_hp_max: float = 1.0

# --- events drained by the presentation layer -------------------------------
var events: Array[Dictionary] = []

var _rng: DetRng
var _cfg: Dictionary = {}
var _upgrades: Dictionary = {}

var _x_min := -10.0
var _x_max := 10.0
var _z_max := 40.0
var _defense_z := 5.0

var _move_speed := 14.0
var _move_smoothing := 18.0
var _body_radius := 0.30
var _max_troops := 60
var _troop_loss_per_leak := 3
var _respawn_troops := 3

var _auto_rate_base := 2.4
var _auto_rate_per_troop := 0.12
var _auto_rate_max := 9.0
var _auto_damage := 4.0
var _auto_speed := 34.0
var _auto_radius := 0.12
var _auto_spread := 2.5
var _auto_cooldown := 0.0

var _chain_charge_seconds := 4.0
var _chain_charge_per_kill := 0.12
var _chain_max_charges := 2
var _chain_base_speed := 25.0
var _chain_radius := 0.26
var _chain_base_bounces := 15
var _chain_damage_base := 10.0
var _chain_damage_per_bounce := 1.15
var _chain_speed_per_bounce := 1.02
var _chain_speed_cap := 1.5
var _chain_steer_per_swipe := 15.0
var _chain_steer_max_rate := 90.0
var _chain_steer_duration := 3.0

var _gate_enabled := true
var _gate_spawn_z := 38.0
var _gate_speed := 2.4
var _gate_half_width := 4.7
var _gate_center_gap := 0.6
var _gate_height := 0.9
var _gate_next_at := 6.0
var _gate_interval := 11.0
var _gate_jitter := 2.0
var _gate_negative_chance := 0.45
var _gate_ops: Array = []
var _gate_bounce_cap := 50
var _gate_damage_cap := 4.0
var _gate_sub_loss := 4
var _gate_div_damage := 0.6

var _boss_chip_factor := 0.35
var _boss_hp_scale := 1.0

var _enemy_types: Array = []
var _wave_sizes: Array = []
var _spawn_interval := 0.5
# Seconds each wave has to fully deploy. Divided across that wave's enemy
# count to get the trickle rate, so later waves arrive faster, not just in
# greater number. The prototype spawns a wave in one burst instead; that is
# why a replay does not carry across the two implementations.
var _spawn_windows: Array = []
var _formation_kinds: Array = []
var _formation_columns := Vector2(5.0, 12.0)
var _formation_spacing := 0.8
var _formation_slots := PackedVector2Array()
var _formation_index := 0
var _formation_anchor_x := 0.0
var _wave_timer := 0.0
var _spawn_timer := 0.0
var _wave_remaining := 0
var _wave_cooldown := 0.0
var _difficulty := 1.0
var _combo_milestones: Array = []

var _input_pointer_x := 0.0
var _input_pointer_down := false
var _input_tap := false
var _input_drag_dx := 0.0


func _init(config: Dictionary, seed_value: int, stage: int, upgrades: Dictionary = {}) -> void:
	_cfg = config
	_upgrades = upgrades
	stage_index = stage
	_rng = DetRng.new(seed_value)
	_read_config()
	_reserve_arrays()
	_start_wave()


## Queues this frame's input. Consumed inside the next tick, never applied
## directly, so that a replayed input log produces an identical run.
func set_input(pointer_x: float, pointer_down: bool, tap: bool, drag_dx: float) -> void:
	_input_pointer_x = pointer_x
	_input_pointer_down = pointer_down
	_input_tap = _input_tap or tap
	_input_drag_dx += drag_dx


## Advances one fixed step. The order here is part of the save format: change
## it and old replays stop matching.
func tick() -> void:
	if state != State.PLAYING:
		return
	# Events describe the tick that just ran, so the sim clears them itself.
	# Leaving that to the consumer cost us twice: a reader that ran late saw an
	# empty list, and a reader that never ran let the array grow for the whole
	# session. Now a slow frame simply accumulates several ticks' events, which
	# is what a renderer wants anyway.
	events.clear()
	_consume_input()
	_tick_squad()
	_tick_gates()
	_tick_auto_fire()
	_tick_auto_bullets()
	_tick_chain_bullet()
	_tick_crowd()
	_tick_boss()
	_tick_waves()
	elapsed += FIXED_DELTA
	tick_index += 1


## Cheap state fingerprint for replay assertions in tests.
func snapshot_hash() -> int:
	var acc := tick_index * 31 + enemy_count * 17 + troops * 7 + score
	acc = acc * 33 + int(squad_x * 1000.0)
	acc = acc * 33 + int(chain_pos.x * 1000.0)
	acc = acc * 33 + int(chain_pos.y * 1000.0)
	for i in range(enemy_count):
		acc = (acc * 31 + int(enemy_x[i] * 100.0) + int(enemy_z[i] * 100.0)) & 0x7FFFFFFF
	return acc & 0x7FFFFFFF


## Reads one number from a config dictionary without trusting its type.
##
## This exists because of a real failure: `spawnInterval` changed from a scalar
## to a per-wave array, `float()` threw, and the rest of _read_config never
## ran — silently restoring bossHpScale to 1.0 and stalling three of five
## stages. A bad key should cost one value, not every value after it.
func _num(source: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = source.get(key, fallback)
	if value is float or value is int:
		return float(value)
	push_warning(
		"config '%s' is %s, not a number; using %s" % [key, type_string(typeof(value)), fallback]
	)
	return fallback


## Same guard, for a numeric entry inside an array.
func _num_at(source: Array, index: int, fallback: float) -> float:
	if index < 0 or index >= source.size():
		return fallback
	var value: Variant = source[index]
	if value is float or value is int:
		return float(value)
	return fallback


func _read_config() -> void:
	var arena: Dictionary = _cfg.get("arena", {})
	_x_min = _num(arena, "xMin", -10.0)
	_x_max = _num(arena, "xMax", 10.0)
	_z_max = _num(arena, "zMax", 40.0)
	_defense_z = _num(arena, "defenseLineZ", 5.0)

	var squad: Dictionary = _cfg.get("squad", {})
	troops = int(squad.get("startTroops", 5)) + int(_upgrade("startTroops", 0.0))
	_max_troops = int(squad.get("maxTroops", 60))
	_move_speed = _num(squad, "moveSpeedMax", 14.0) * _upgrade_mul("moveSpeedMul")
	_move_smoothing = _num(squad, "moveSmoothing", 18.0)
	_body_radius = _num(squad, "bodyRadius", 0.30)
	_troop_loss_per_leak = int(squad.get("troopLossPerLeak", 3))
	_respawn_troops = int(squad.get("respawnTroops", 3))

	var auto: Dictionary = squad.get("autoFire", {})
	_auto_rate_base = _num(auto, "baseRatePerSec", 2.4)
	_auto_rate_per_troop = _num(auto, "ratePerTroop", 0.12)
	_auto_rate_max = _num(auto, "maxRatePerSec", 9.0)
	_auto_damage = _num(auto, "damage", 4.0) * _upgrade_mul("autoDamageMul")
	_auto_speed = _num(auto, "projectileSpeed", 34.0)
	_auto_radius = _num(auto, "projectileRadius", 0.12)
	_auto_spread = _num(auto, "spreadDeg", 2.5)
	# Auto-fire always travels up, so it can never satisfy a boss vulnerability
	# rule like "only from behind". Without chip damage that is a stalemate,
	# and a stalemate wastes the player's time worse than a loss does.
	_boss_chip_factor = _num(auto, "bossChipFactor", 0.35)

	var chain: Dictionary = squad.get("chainShot", {})
	_chain_charge_seconds = _num(chain, "chargeSeconds", 4.0)
	_chain_charge_per_kill = _num(chain, "chargePerKill", 0.12)
	_chain_max_charges = int(chain.get("maxCharges", 2))

	var bullet: Dictionary = _cfg.get("bullet", {})
	_chain_base_speed = _num(bullet, "baseSpeed", 25.0)
	_chain_radius = _num(bullet, "radius", 0.26)
	_chain_base_bounces = int(bullet.get("maxBounce", 15)) + int(_upgrade("bounceBudget", 0.0))
	_chain_damage_base = _num(bullet, "damageBase", 10.0)
	_chain_damage_per_bounce = _num(bullet, "damagePerBounce", 1.15)
	_chain_speed_per_bounce = _num(bullet, "speedPerBounce", 1.02)
	_chain_speed_cap = _num(bullet, "speedMultiplierCap", 1.5)
	_chain_steer_per_swipe = _num(bullet, "steerAnglePerSwipe", 15.0)
	_chain_steer_max_rate = _num(bullet, "steerMaxAnglePerSecond", 90.0)
	_chain_steer_duration = _num(bullet, "steerMeterDuration", 3.0)

	_read_gate_config()

	_enemy_types = _cfg.get("enemyTypes", [])
	var spawn: Dictionary = _cfg.get("spawn", {})
	_wave_sizes = spawn.get("enemiesPerWave", [30, 50, 80, 120, 200])
	_spawn_windows = spawn.get("spawnInterval", [10.0, 12.0, 15.0, 18.0, 20.0])
	_formation_kinds = spawn.get("formation", ["rect"])
	var columns: Array = spawn.get("columnsRange", [5, 12])
	if columns.size() >= 2:
		_formation_columns = Vector2(_num_at(columns, 0, 5.0), _num_at(columns, 1, 12.0))
	_formation_spacing = _num(spawn, "spacing", 0.8)

	var balance: Dictionary = _cfg.get("balance", {})
	# The damage model changed when auto-fire became the primary DPS, so boss
	# HP is scaled by one measured lever instead of being re-tuned per boss.
	_boss_hp_scale = _num(balance, "bossHpScale", 1.0)

	var meta: Dictionary = _cfg.get("meta", {})
	_difficulty = 1.0 + _num(meta, "difficultyPerStage", 0.12) * float(stage_index)

	var scoring: Dictionary = _cfg.get("scoring", {})
	_combo_milestones = scoring.get("comboMilestones", [10, 20, 50, 100])

	var player: Dictionary = _cfg.get("player", {})
	lives = int(player.get("lives", 3))


func _read_gate_config() -> void:
	var gate_cfg: Dictionary = _cfg.get("gates", {})
	_gate_enabled = bool(gate_cfg.get("enabled", true))
	_gate_spawn_z = _num(gate_cfg, "spawnZ", 38.0)
	_gate_speed = _num(gate_cfg, "descendSpeed", 2.4)
	_gate_half_width = _num(gate_cfg, "halfWidth", 4.7)
	_gate_center_gap = _num(gate_cfg, "centerGapX", 0.6)
	_gate_height = _num(gate_cfg, "height", 0.9)
	_gate_next_at = _num(gate_cfg, "firstAtSeconds", 6.0)
	_gate_interval = _num(gate_cfg, "intervalSeconds", 11.0)
	_gate_jitter = _num(gate_cfg, "intervalJitter", 2.0)
	_gate_negative_chance = _num(gate_cfg, "negativeSideChance", 0.45)
	_gate_negative_chance *= _upgrade_mul("negativeSideChance")
	_gate_ops = gate_cfg.get("squadOps", [])
	var effects: Dictionary = gate_cfg.get("bulletEffects", {})
	_gate_bounce_cap = int(effects.get("bounceBudgetCap", 50))
	_gate_damage_cap = _num(effects, "damageMulCap", 4.0)
	_gate_sub_loss = int(effects.get("subBounceLoss", 4))
	_gate_div_damage = _num(effects, "divDamageMul", 0.6)


func _reserve_arrays() -> void:
	enemy_x.resize(MAX_ENEMIES)
	enemy_z.resize(MAX_ENEMIES)
	enemy_hp.resize(MAX_ENEMIES)
	enemy_type.resize(MAX_ENEMIES)
	auto_x.resize(MAX_AUTO_BULLETS)
	auto_z.resize(MAX_AUTO_BULLETS)
	auto_vx.resize(MAX_AUTO_BULLETS)


func _upgrade(key: String, fallback: float) -> float:
	return float(_upgrades.get(key, fallback))


func _upgrade_mul(key: String) -> float:
	return float(_upgrades.get(key, 1.0))


func _consume_input() -> void:
	if _input_pointer_down and not chain_riding:
		squad_target_x = clampf(_input_pointer_x, _x_min + _body_radius, _x_max - _body_radius)
	if chain_riding and absf(_input_drag_dx) > 0.001:
		_steer_chain(_input_drag_dx)
	if _input_tap:
		if chain_riding:
			_end_chain("brake")
		else:
			_try_fire_chain()
	_input_tap = false
	_input_drag_dx = 0.0


func _tick_squad() -> void:
	var to_target := squad_target_x - squad_x
	var step := clampf(
		to_target * _move_smoothing * FIXED_DELTA,
		-_move_speed * FIXED_DELTA,
		_move_speed * FIXED_DELTA
	)
	squad_x += step
	if chain_charges < _chain_max_charges:
		var rate := _upgrade_mul("chargeRateMul") / maxf(_chain_charge_seconds, 0.01)
		chain_charge += rate * FIXED_DELTA
		if chain_charge >= 1.0:
			chain_charge -= 1.0
			chain_charges += 1


func _try_fire_chain() -> void:
	if chain_active or chain_charges <= 0:
		return
	chain_charges -= 1
	chain_active = true
	chain_riding = false
	chain_life = 0.0
	chain_pos = Vector2(squad_x, SQUAD_Z + 0.8)
	chain_dir = FORWARD
	chain_speed = _chain_base_speed
	chain_bounces_left = _chain_base_bounces
	chain_damage_mul = _upgrade_mul("chainDamageMul")
	chain_steer_meter = _chain_steer_duration
	events.append({"type": "chain_fired", "x": squad_x})


func _steer_chain(drag_dx: float) -> void:
	if chain_steer_meter <= 0.0:
		return
	var per_tick := _chain_steer_max_rate * FIXED_DELTA
	var degrees := clampf(drag_dx * _chain_steer_per_swipe, -per_tick, per_tick)
	chain_dir = Ricochet.rotate_xz(chain_dir, -degrees)
	chain_steer_meter -= FIXED_DELTA


func _tick_auto_fire() -> void:
	if troops <= 0:
		return
	var rate := _auto_rate_base + _auto_rate_per_troop * float(troops)
	rate = minf(rate, _auto_rate_max) * _upgrade_mul("fireRateMul")
	_auto_cooldown -= FIXED_DELTA
	if _auto_cooldown > 0.0:
		return
	_auto_cooldown = 1.0 / maxf(rate, 0.01)
	if auto_count >= MAX_AUTO_BULLETS:
		return
	var spread := deg_to_rad(_rng.range_float(-_auto_spread, _auto_spread))
	auto_x[auto_count] = squad_x
	auto_z[auto_count] = SQUAD_Z + 0.8
	auto_vx[auto_count] = sin(spread) * _auto_speed
	auto_count += 1
	events.append({"type": "auto_fired"})


func _tick_auto_bullets() -> void:
	var i := 0
	while i < auto_count:
		auto_z[i] += _auto_speed * FIXED_DELTA
		auto_x[i] += auto_vx[i] * FIXED_DELTA
		var consumed := _auto_bullet_hits(i)
		if consumed or auto_z[i] > _z_max or auto_x[i] < _x_min or auto_x[i] > _x_max:
			_swap_remove_auto(i)
		else:
			i += 1


func _auto_bullet_hits(index: int) -> bool:
	var pos := Vector2(auto_x[index], auto_z[index])
	for e in range(enemy_count):
		var radius := _enemy_radius(enemy_type[e])
		if (
			pos.distance_squared_to(Vector2(enemy_x[e], enemy_z[e]))
			<= pow(radius + _auto_radius, 2.0)
		):
			_damage_enemy(e, _auto_damage)
			return true
	for b in range(barrels.size()):
		var barrel: Dictionary = barrels[b]
		if (
			pos.distance_squared_to(Vector2(barrel["x"], barrel["z"]))
			<= pow(0.55 + _auto_radius, 2.0)
		):
			barrel["hp"] = float(barrel["hp"]) - _auto_damage
			return true
	if boss_active and pos.distance_squared_to(boss_pos) <= pow(1.8 + _auto_radius, 2.0):
		boss_hp -= _auto_damage * _boss_chip_factor
		return true
	return false


func _swap_remove_auto(index: int) -> void:
	var last := auto_count - 1
	auto_x[index] = auto_x[last]
	auto_z[index] = auto_z[last]
	auto_vx[index] = auto_vx[last]
	auto_count -= 1


func _tick_chain_bullet() -> void:
	if not chain_active:
		return
	chain_life += FIXED_DELTA
	if chain_life > CHAIN_MAX_LIFE:
		_end_chain("timeout")
		return
	var travel := chain_speed * FIXED_DELTA
	var steps := clampi(int(ceil(travel / 0.5)), 1, MAX_SUBSTEPS)
	var step_delta := travel / float(steps)
	for _s in range(steps):
		if not chain_active:
			return
		_advance_chain(step_delta)


## Moves the chain bullet, resolving every contact inside the step.
##
## The earlier version returned after the first contact, throwing away the
## unused part of the step. In a crowd that meant the bullet barely advanced:
## it spent its twelve-second life grinding forward instead of ricocheting,
## and a fifteen-bounce budget was never spent. Now the leftover distance is
## carried into the next iteration, so one tick can pass through several
## enemies and still bounce off the wall behind them.
func _advance_chain(distance: float) -> void:
	var remaining := distance
	# Bounded so a bullet wedged in a corner cannot spin here forever; the
	# rest of its travel is dropped that tick, which is survivable.
	var guard := 0
	while remaining > 0.0001 and chain_active and guard < 8:
		guard += 1
		var motion := chain_dir * remaining
		var wall: Dictionary = Ricochet.sweep_side_walls(
			chain_pos, motion, _chain_radius, _x_min, _x_max
		)
		var top: Dictionary = Ricochet.sweep_top_wall(chain_pos, motion, _chain_radius, _z_max)
		var enemy_hit := _sweep_chain_enemies(motion)
		var boss_hit := _sweep_chain_boss(motion)

		var best_t := 2.0
		var kind := ""
		if wall.get("hit", false):
			best_t = float(wall["t"])
			kind = "wall"
		if top.get("hit", false) and float(top["t"]) < best_t:
			best_t = float(top["t"])
			kind = "top"
		if enemy_hit.get("hit", false) and float(enemy_hit["t"]) < best_t:
			best_t = float(enemy_hit["t"])
			kind = "enemy"
		if boss_hit.get("hit", false) and float(boss_hit["t"]) < best_t:
			best_t = float(boss_hit["t"])
			kind = "boss"

		if kind == "":
			chain_pos += motion
			_chain_gate_and_bounds()
			return

		chain_pos += motion * best_t
		remaining -= remaining * best_t

		if kind == "enemy":
			_resolve_chain_enemy(int(enemy_hit["index"]))
			# The nudge past the body is travel too, so charge it to the step.
			remaining = maxf(remaining - (_chain_radius + 0.05), 0.0)
			continue
		if kind == "boss":
			# Full damage, unlike auto-fire chip: landing a ricochet on the
			# boss is the skill play, so it has to be worth far more than
			# holding still.
			boss_hp -= _chain_damage_base * chain_damage_mul * 3.0
			events.append({"type": "boss_hit", "x": chain_pos.x, "z": chain_pos.y})
			_bounce_chain(boss_hit["normal"])
			continue
		var normal: Vector2 = top["normal"] if kind == "top" else wall["normal"]
		_bounce_chain(normal)


func _sweep_chain_enemies(motion: Vector2) -> Dictionary:
	var best := {"hit": false}
	var best_t := 2.0
	for e in range(enemy_count):
		var center := Vector2(enemy_x[e], enemy_z[e])
		var hit: Dictionary = Ricochet.sweep_circle(
			chain_pos, motion, _chain_radius, center, _enemy_radius(enemy_type[e])
		)
		if hit.get("hit", false) and float(hit["t"]) < best_t:
			best_t = float(hit["t"])
			best = {"hit": true, "t": best_t, "index": e, "normal": hit["normal"]}
	return best


func _sweep_chain_boss(motion: Vector2) -> Dictionary:
	if not boss_active:
		return {"hit": false}
	return Ricochet.sweep_circle(chain_pos, motion, _chain_radius, boss_pos, 1.8)


func _resolve_chain_enemy(index: int) -> void:
	var damage := _chain_damage_base * chain_damage_mul
	damage *= pow(_chain_damage_per_bounce, float(_chain_base_bounces - chain_bounces_left))
	_damage_enemy(index, damage, "chain")
	if not chain_riding:
		chain_riding = true
		events.append({"type": "ride_start"})
	chain_pos += chain_dir * (_chain_radius + 0.05)


func _bounce_chain(normal: Vector2) -> void:
	chain_bounces_left -= 1
	chain_dir = Ricochet.reflect_safe(chain_dir, normal)
	chain_pos += chain_dir * 0.02
	chain_speed = minf(chain_speed * _chain_speed_per_bounce, _chain_base_speed * _chain_speed_cap)
	events.append({"type": "bounce", "x": chain_pos.x, "z": chain_pos.y})
	if chain_bounces_left <= 0:
		_end_chain("exhausted")


func _chain_gate_and_bounds() -> void:
	if chain_pos.y < 0.0 or chain_pos.y > _z_max + 1.0:
		_end_chain("left_arena")


func _end_chain(reason: String) -> void:
	chain_active = false
	chain_riding = false
	combo = 0
	events.append({"type": "chain_end", "reason": reason})


func _tick_gates() -> void:
	if not _gate_enabled:
		return
	if elapsed >= _gate_next_at:
		_spawn_gate()
		_gate_next_at = elapsed + _gate_interval + _rng.range_float(-_gate_jitter, _gate_jitter)
	var i := 0
	while i < gates.size():
		var gate: Dictionary = gates[i]
		gate["z"] = float(gate["z"]) - _gate_speed * _difficulty * FIXED_DELTA
		var z := float(gate["z"])
		if not bool(gate["squad_done"]) and z <= SQUAD_Z + _gate_height:
			_apply_gate_to_squad(gate)
			gate["squad_done"] = true
		if chain_active and not bool(gate["bullet_done"]):
			if absf(chain_pos.y - z) <= _gate_height:
				_apply_gate_to_bullet(gate)
				gate["bullet_done"] = true
		if z < -2.0:
			gates.remove_at(i)
		else:
			i += 1


func _spawn_gate() -> void:
	var left := _pick_gate_op(_rng.chance(_gate_negative_chance))
	# The right side takes the opposite polarity of the left: a gate where both
	# doors punish is not a decision, it is a toll.
	var right := _pick_gate_op(bool(left["positive"]))
	(
		gates
		. append(
			{
				"z": _gate_spawn_z,
				"left": left,
				"right": right,
				"squad_done": false,
				"bullet_done": false,
			}
		)
	)


func _pick_gate_op(want_negative: bool) -> Dictionary:
	var pool: Array = []
	var weights := PackedFloat32Array()
	for op in _gate_ops:
		var entry: Dictionary = op
		if bool(entry.get("positive", true)) != want_negative:
			pool.append(entry)
			weights.append(float(entry.get("weight", 1.0)))
	if pool.is_empty():
		return {"op": "add", "value": 1.0, "positive": true}
	return pool[_rng.weighted_index(weights)]


func _apply_gate_to_squad(gate: Dictionary) -> void:
	var side: Dictionary = gate["right"] if squad_x >= 0.0 else gate["left"]
	var before := troops
	troops = _apply_op(troops, side)
	troops = clampi(troops, 0, _max_troops)
	(
		events
		. append(
			{
				"type": "gate_squad",
				"delta": troops - before,
				"positive": troops >= before,
			}
		)
	)
	if troops <= 0:
		_lose_life()


func _apply_gate_to_bullet(gate: Dictionary) -> void:
	var side: Dictionary = gate["right"] if chain_pos.x >= 0.0 else gate["left"]
	var op := String(side.get("op", "add"))
	var value := float(side.get("value", 1.0))
	match op:
		"mul":
			chain_bounces_left = mini(int(float(chain_bounces_left) * value), _gate_bounce_cap)
			chain_damage_mul = minf(chain_damage_mul * 1.1, _gate_damage_cap)
		"add":
			chain_bounces_left = mini(chain_bounces_left + int(value * 0.5), _gate_bounce_cap)
		"sub":
			chain_bounces_left = maxi(chain_bounces_left - _gate_sub_loss, 1)
		"div":
			chain_damage_mul = maxf(chain_damage_mul * _gate_div_damage, 0.25)
	events.append({"type": "gate_bullet", "op": op})


func _apply_op(value: int, side: Dictionary) -> int:
	var amount := float(side.get("value", 1.0))
	match String(side.get("op", "add")):
		"mul":
			return int(float(value) * amount)
		"add":
			return value + int(amount)
		"sub":
			return value - int(amount)
		"div":
			return int(float(value) / maxf(amount, 1.0))
	return value


func _tick_crowd() -> void:
	var i := 0
	while i < enemy_count:
		var type_index := enemy_type[i]
		var speed := _enemy_speed(type_index) * _difficulty
		enemy_z[i] -= speed * FIXED_DELTA
		if enemy_z[i] <= _defense_z:
			_leak_enemy(i)
		else:
			i += 1


func _leak_enemy(index: int) -> void:
	troops -= _troop_loss_per_leak
	events.append({"type": "leak"})
	_swap_remove_enemy(index)
	if troops <= 0:
		_lose_life()


func _damage_enemy(index: int, amount: float, source: String = "auto") -> void:
	enemy_hp[index] -= amount
	if enemy_hp[index] > 0.0:
		return
	combo += 1
	score += int(float(_enemy_score(enemy_type[index])) * (1.0 + float(combo) * 0.15))
	chain_charge += _chain_charge_per_kill
	(
		events
		. append(
			{
				"type": "kill",
				"x": enemy_x[index],
				"z": enemy_z[index],
				"score": _enemy_score(enemy_type[index]),
				# Which weapon landed it. Tests use this to attribute damage
				# throughput; the view uses it to pick the hit effect.
				"source": source,
			}
		)
	)
	for milestone in _combo_milestones:
		if combo == int(milestone):
			events.append({"type": "combo_milestone", "combo": combo})
	_swap_remove_enemy(index)


func _swap_remove_enemy(index: int) -> void:
	var last := enemy_count - 1
	enemy_x[index] = enemy_x[last]
	enemy_z[index] = enemy_z[last]
	enemy_hp[index] = enemy_hp[last]
	enemy_type[index] = enemy_type[last]
	enemy_count -= 1


func _lose_life() -> void:
	lives -= 1
	troops = _respawn_troops
	events.append({"type": "life_lost", "lives": lives})
	if lives <= 0:
		state = State.DEFEAT
		events.append({"type": "defeat"})


## Waves run on a clock, not on a clear.
##
## Waiting for an empty arena was the original rule, and headless runs sat at
## wave four for five minutes: auto-fire caps at nine shots a second, so a
## hundred-and-twenty enemy wave simply outlasts it. The tuned prototype
## advances on spawnInterval regardless of what is left alive, which is also
## what makes the pressure curve rise. Clearing early is still rewarded — it
## cuts the remainder of the timer short.
func _tick_waves() -> void:
	if boss_active:
		return
	if _wave_remaining > 0:
		_spawn_timer -= FIXED_DELTA
		if _spawn_timer <= 0.0:
			_spawn_timer = _spawn_interval
			_spawn_enemy()
	_wave_timer -= FIXED_DELTA
	# A wave fully spawned and fully killed hands the time back to the player.
	if _wave_remaining <= 0 and enemy_count == 0:
		_wave_timer = minf(_wave_timer, 1.6)
	if _wave_timer > 0.0:
		return
	wave_index += 1
	if wave_index >= _wave_sizes.size():
		_start_boss()
	else:
		_start_wave()


func _start_wave() -> void:
	if wave_index >= _wave_sizes.size():
		return
	_wave_remaining = int(_wave_sizes[wave_index])
	var window := 12.0
	if not _spawn_windows.is_empty():
		window = _num_at(_spawn_windows, mini(wave_index, _spawn_windows.size() - 1), 12.0)
	_spawn_interval = window / maxf(float(_wave_remaining), 1.0)
	_wave_timer = window
	_build_formation(_wave_remaining)
	_spawn_timer = 0.0
	_wave_cooldown = 2.0
	events.append({"type": "wave_start", "wave": wave_index + 1})


func _spawn_enemy() -> void:
	if enemy_count >= MAX_ENEMIES or _wave_remaining <= 0:
		return
	var type_index := _pick_enemy_type()
	var slot := _next_formation_slot()
	var margin := 1.0
	enemy_x[enemy_count] = clampf(_formation_anchor_x + slot.x, _x_min + margin, _x_max - margin)
	enemy_z[enemy_count] = _z_max + slot.y
	enemy_hp[enemy_count] = _enemy_hp(type_index) * _difficulty
	enemy_type[enemy_count] = type_index
	enemy_count += 1
	_wave_remaining -= 1


## Lays out one wave in a shape, instead of scattering it across the arena.
##
## This matters more than it looks. The squad fires straight up, so a crowd
## spread evenly over eighteen units can never be engaged: measured headlessly,
## random placement produced twelve kills in sixty seconds and lost every
## stage in wave one. A formation concentrates the crowd into columns the
## squad can actually meet, and turns "where do I stand" into a real decision.
## Shapes and counts come from spawn.formation / columnsRange / spacing, the
## same keys the web prototype uses.
func _build_formation(count: int) -> void:
	_formation_slots = PackedVector2Array()
	_formation_index = 0
	var kind := "rect"
	if not _formation_kinds.is_empty():
		var at := mini(wave_index, _formation_kinds.size() - 1)
		kind = String(_formation_kinds[at])
	var columns := _rng.range_int(int(_formation_columns.x), int(_formation_columns.y) + 1)
	var spacing := _formation_spacing
	var half_w := (_x_max - _x_min) * 0.5 - 1.5

	match kind:
		"vshape":
			_formation_v(count, spacing, half_w)
		"diamond":
			_formation_diamond(count, spacing, half_w)
		"circle":
			_formation_circle(count, spacing, half_w)
		_:
			_formation_rect(count, columns, spacing)

	# Anchor the shape somewhere the whole crowd still fits inside the walls.
	var widest := 0.0
	for slot in _formation_slots:
		widest = maxf(widest, absf(slot.x))
	var limit := maxf(half_w - widest, 0.0)
	_formation_anchor_x = _rng.range_float(-limit, limit)


func _formation_rect(count: int, columns: int, spacing: float) -> void:
	var half := float(columns - 1) * spacing * 0.5
	for i in range(count):
		_formation_slots.append(
			Vector2(float(i % columns) * spacing - half, float(i / columns) * spacing)
		)


func _formation_v(count: int, spacing: float, half_w: float) -> void:
	var row := 0
	while _formation_slots.size() < count and row < 400:
		var x := minf(float(row) * spacing * 0.6, half_w)
		var z := float(row) * spacing * 0.8
		_formation_slots.append(Vector2(-x, z))
		if x > 0.01 and _formation_slots.size() < count:
			_formation_slots.append(Vector2(x, z))
		row += 1


func _formation_diamond(count: int, spacing: float, half_w: float) -> void:
	var widest := int(sqrt(float(count)))
	var total := widest * 2
	var row := 0
	while _formation_slots.size() < count and row <= total:
		var n := maxi(1, (row + 1) if row <= widest else (total - row + 1))
		var half := minf(float(n - 1) * spacing * 0.5, half_w)
		for c in range(n):
			if _formation_slots.size() >= count:
				break
			var x := 0.0 if n == 1 else -half + 2.0 * half * float(c) / float(n - 1)
			_formation_slots.append(Vector2(x, float(row) * spacing * 0.9))
		row += 1
	while _formation_slots.size() < count:
		var c := _formation_slots.size() % 6
		_formation_slots.append(Vector2((float(c) - 2.5) * spacing, float(row) * spacing * 0.9))


func _formation_circle(count: int, spacing: float, half_w: float) -> void:
	var ring := 1
	while _formation_slots.size() < count and ring <= 60:
		var r := minf(float(ring) * spacing * 1.1, half_w)
		var per := maxi(6, int(TAU * r / spacing))
		for i in range(per):
			if _formation_slots.size() >= count:
				break
			var a := float(i) / float(per) * TAU
			_formation_slots.append(Vector2(cos(a) * r, sin(a) * r + r))
		ring += 1


## Slots are consumed in order so a wave keeps its shape while it trickles in.
func _next_formation_slot() -> Vector2:
	if _formation_slots.is_empty():
		return Vector2(_rng.range_float(-6.0, 6.0), _rng.range_float(0.0, 6.0))
	var slot := _formation_slots[_formation_index % _formation_slots.size()]
	_formation_index += 1
	return slot


func _pick_enemy_type() -> int:
	if _enemy_types.is_empty():
		return 0
	var unlocked := mini(1 + wave_index, _enemy_types.size())
	return _rng.range_int(0, unlocked)


func _start_boss() -> void:
	boss_active = true
	boss_hp_max = 1200.0 * _difficulty * _boss_hp_scale
	boss_hp = boss_hp_max
	boss_pos = Vector2(0.0, _z_max - 6.0)
	events.append({"type": "boss_start"})


func _tick_boss() -> void:
	if not boss_active:
		return
	boss_pos.y -= 0.35 * FIXED_DELTA
	boss_pos.x = sin(elapsed * 0.8) * 6.0
	if boss_hp <= 0.0:
		boss_active = false
		score += 2000
		state = State.VICTORY
		events.append({"type": "victory"})
	elif boss_pos.y <= _defense_z + 1.0:
		state = State.DEFEAT
		events.append({"type": "defeat"})


func _enemy_field(type_index: int, key: String, fallback: float) -> float:
	if type_index < 0 or type_index >= _enemy_types.size():
		return fallback
	var entry: Dictionary = _enemy_types[type_index]
	return float(entry.get(key, fallback))


func _enemy_hp(type_index: int) -> float:
	return _enemy_field(type_index, "hp", 10.0)


func _enemy_speed(type_index: int) -> float:
	return _enemy_field(type_index, "speed", 0.6)


func _enemy_radius(type_index: int) -> float:
	return _enemy_field(type_index, "radius", 0.35)


func _enemy_score(type_index: int) -> int:
	return int(_enemy_field(type_index, "score", 10.0))
