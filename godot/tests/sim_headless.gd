extends SceneTree
## Headless test harness for the Godot rule set.
##
##   godot --headless --path godot/ --script res://tests/sim_headless.gd
##   godot --headless --path godot/ --script res://tests/sim_headless.gd -- --determinism
##
## This is the Godot-side counterpart of tools/sim_test.js. The JS harness
## tests the prototype; this one tests the code that ships. They are separate
## on purpose — the two tick orders differ, so a replay does not cross engines,
## and a bug fixed in one is not automatically fixed in the other.
##
## The config is read straight from JSON rather than through the GameConfig
## autoload, because a --script run has no autoloads. That also keeps the test
## honest: it exercises the rules, not the plumbing around them.
##
## Exit code is 1 if any check fails, so CI can gate on it.

const CONFIG_PATH := "res://config/arena_config.json"
const TICKS_PER_SECOND := 60
const MAX_SECONDS := 300.0
const DETERMINISM_TICKS := 7200
const THUMB_LATENCY := 0.20

var _cfg: Dictionary = {}
var _failures: Array[String] = []


func _init() -> void:
	_cfg = _load_config()
	if _cfg.is_empty():
		push_error("cannot read %s" % CONFIG_PATH)
		quit(1)
		return

	var args := OS.get_cmdline_user_args()
	if args.has("--trace"):
		_run_trace(0)
	elif args.has("--determinism"):
		_run_determinism()
	else:
		_run_balance()
		_run_determinism()

	print("")
	if _failures.is_empty():
		print("SEMUA UJI LULUS")
		quit(0)
	else:
		for line in _failures:
			print("GAGAL: %s" % line)
		quit(1)


func _load_config() -> Dictionary:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


# --- balance ---------------------------------------------------------------


func _run_balance() -> void:
	print("")
	print("CHAIN RIDER — simulasi headless Godot  (bot: skilled)")
	print("".lpad(96, "="))
	print(
		(
			"%-18s %-9s %8s %6s %6s %7s %7s %7s"
			% ["arena", "hasil", "durasi", "wave", "troop", "skor", "nyawa", "tick"]
		)
	)
	print("".lpad(96, "-"))

	var names := _variant_names()
	var wins := 0
	var total_time := 0.0
	var stalls := 0

	for stage in range(names.size()):
		var result := _play_one(stage)
		var outcome := String(result["outcome"])
		if outcome == "victory":
			wins += 1
		if outcome == "timeout":
			stalls += 1
			_failures.append("stage %d buntu — tidak menang/kalah dalam %ds" % [stage, MAX_SECONDS])
		total_time += float(result["elapsed"])
		print(
			(
				"%-18s %-9s %7.1fs %6s %6d %7d %7d %7d"
				% [
					"%d. %s" % [stage + 1, names[stage]],
					outcome,
					float(result["elapsed"]),
					"%d/%d" % [int(result["wave"]) + 1, _wave_count()],
					int(result["troops"]),
					int(result["score"]),
					int(result["lives"]),
					int(result["ticks"]),
				]
			)
		)
		for problem in result["problems"]:
			_failures.append("stage %d: %s" % [stage, problem])

	print("".lpad(96, "-"))
	print(
		(
			"menang %d/%d   durasi rata-rata %.1fs (target sesi: 60–180 s)   buntu %d"
			% [wins, names.size(), total_time / float(names.size()), stalls]
		)
	)


## Plays one stage with a bot that reads the same state a thumb would see.
func _play_one(stage: int) -> Dictionary:
	var seed_value := _seed() + stage * 7919
	var sim := SimWorld.new(_cfg, seed_value, stage)
	var max_ticks := int(MAX_SECONDS * TICKS_PER_SECOND)
	var problems: Array[String] = []
	var latency_ticks := int(THUMB_LATENCY * TICKS_PER_SECOND)
	var held_target := 0.0
	var ticks := 0

	while ticks < max_ticks and sim.state == SimWorld.State.PLAYING:
		# The thumb reacts late. Refreshing the target on every tick would
		# give the bot reflexes no player has, and would hide gate timing bugs.
		if ticks % latency_ticks == 0:
			held_target = _bot_target_x(sim)
		var tap := not sim.chain_riding and sim.chain_charges > 0 and sim.enemy_count > 0
		sim.set_input(held_target, true, tap, _bot_steer(sim))
		sim.tick()
		ticks += 1
		var problem := _check_invariants(sim)
		if problem != "" and not problems.has(problem):
			problems.append(problem)

	var outcome := "timeout"
	if sim.state == SimWorld.State.VICTORY:
		outcome = "victory"
	elif sim.state == SimWorld.State.DEFEAT:
		outcome = "defeat"

	return {
		"outcome": outcome,
		"elapsed": sim.elapsed,
		"wave": sim.wave_index,
		"troops": sim.troops,
		"score": sim.score,
		"lives": sim.lives,
		"ticks": ticks,
		"problems": problems,
	}


## Where the bot wants the squad. Gates outrank crowd: a bad door costs more
## than a few missed shots, which is the lesson the reference game teaches.
func _bot_target_x(sim: SimWorld) -> float:
	var aim := _crowd_aim_x(sim)
	var gate := _imminent_gate(sim)
	if gate.is_empty():
		return aim
	# Pick the door, then keep hunting inside the half it commits to. Parking
	# on a fixed x while a gate descends costs every shot in between, and a
	# gate is on screen most of the time — measured headlessly, the fixed-x
	# version stopped killing anything for forty-five seconds at a stretch.
	var left_gain := _op_gain(sim.troops, gate["left"])
	var right_gain := _op_gain(sim.troops, gate["right"])
	if right_gain >= left_gain:
		return clampf(aim, 0.5, 9.0)
	return clampf(aim, -9.0, -0.5)


## Where the crowd is, weighted toward whatever is closest to the line.
func _crowd_aim_x(sim: SimWorld) -> float:
	if sim.enemy_count == 0:
		return sim.squad_x
	var weight_sum := 0.0
	var weighted_x := 0.0
	for i in range(sim.enemy_count):
		var weight := 1.0 / maxf(sim.enemy_z[i], 1.0)
		weighted_x += sim.enemy_x[i] * weight
		weight_sum += weight
	return weighted_x / maxf(weight_sum, 0.001)


## Steering while riding is the whole skill of the game, so a bot that never
## steers measures a game nobody plays. A chain shot leaves the squad straight
## up: without input it climbs, bounces off the ceiling, comes straight back
## down and exits, spending two of its fifteen bounces. This bot aims the
## bullet at the nearest enemy ahead of it, which is what a thumb is for.
func _bot_steer(sim: SimWorld) -> float:
	if not sim.chain_riding or sim.chain_steer_meter <= 0.0:
		return 0.0
	var target_index := -1
	var best := 1e9
	for i in range(sim.enemy_count):
		var to_enemy := Vector2(sim.enemy_x[i], sim.enemy_z[i]) - sim.chain_pos
		# Only chase what the bullet is already heading toward; turning back
		# on itself wastes the meter and usually ends in the floor.
		if to_enemy.normalized().dot(sim.chain_dir) < 0.2:
			continue
		var d := to_enemy.length()
		if d < best:
			best = d
			target_index = i
	if target_index < 0:
		return 0.0
	var desired := (
		(Vector2(sim.enemy_x[target_index], sim.enemy_z[target_index]) - sim.chain_pos).normalized()
	)
	# Signed angle between heading and desired, mapped onto a drag.
	var cross := sim.chain_dir.x * desired.y - sim.chain_dir.y * desired.x
	return clampf(-cross * 2.0, -1.0, 1.0)


## The nearest gate the squad can still steer into.
func _imminent_gate(sim: SimWorld) -> Dictionary:
	var best: Dictionary = {}
	var best_z := 999.0
	for entry in sim.gates:
		var gate: Dictionary = entry
		if bool(gate["squad_done"]):
			continue
		var z := float(gate["z"])
		if z < best_z:
			best_z = z
			best = gate
	return best if best_z < 22.0 else {}


## Troops gained (or lost) by taking one door.
func _op_gain(troops: int, side: Variant) -> float:
	var entry: Dictionary = side
	var value := float(entry.get("value", 0.0))
	match String(entry.get("op", "add")):
		"mul":
			return float(troops) * value - float(troops)
		"add":
			return value
		"sub":
			return -value
		"div":
			return float(troops) / maxf(value, 1.0) - float(troops)
	return 0.0


## Catches the failures a linter cannot see: things leaving the arena, values
## going non-finite, and the speed cap quietly drifting.
func _check_invariants(sim: SimWorld) -> String:
	var problem := ""
	if not is_finite(sim.squad_x):
		problem = "squad_x bukan angka berhingga"
	elif sim.squad_x < -10.5 or sim.squad_x > 10.5:
		problem = "squad keluar dinding: x=%.2f" % sim.squad_x
	elif sim.troops < 0:
		problem = "troop negatif: %d" % sim.troops
	elif sim.chain_active:
		problem = _check_chain(sim)
	if problem == "":
		for i in range(sim.enemy_count):
			if sim.enemy_x[i] < -10.6 or sim.enemy_x[i] > 10.6:
				problem = "musuh keluar dinding: x=%.2f" % sim.enemy_x[i]
				break
	return problem


func _check_chain(sim: SimWorld) -> String:
	if not is_finite(sim.chain_pos.x) or not is_finite(sim.chain_pos.y):
		return "posisi chain bukan angka berhingga"
	if sim.chain_pos.x < -10.6 or sim.chain_pos.x > 10.6:
		return "chain tembus dinding: x=%.2f" % sim.chain_pos.x
	if sim.chain_speed > 25.0 * 1.5 + 0.01:
		return "speed cap chain terlampaui: %.2f" % sim.chain_speed
	return ""


# --- trace -----------------------------------------------------------------


## Plays one stage and reports what actually happened every five seconds.
## A results table tells you a run was lost; this tells you why.
func _run_trace(stage: int) -> void:
	print("")
	print("TRACE stage %d — %s" % [stage, _variant_names()[stage]])
	print(
		(
			"%6s %7s %7s %7s %7s %7s %7s %7s"
			% ["t", "troops", "musuh", "kill", "bocor", "gate+", "gate-", "chain"]
		)
	)
	var sim := SimWorld.new(_cfg, _seed() + stage * 7919, stage)
	var latency_ticks := int(THUMB_LATENCY * TICKS_PER_SECOND)
	var held_target := 0.0
	var kills := 0
	var leaks := 0
	var gates_good := 0
	var gates_bad := 0
	var chains := 0
	var ticks := 0

	while ticks < int(MAX_SECONDS * TICKS_PER_SECOND) and sim.state == SimWorld.State.PLAYING:
		if ticks % latency_ticks == 0:
			held_target = _bot_target_x(sim)
		var tap := not sim.chain_riding and sim.chain_charges > 0 and sim.enemy_count > 0
		if tap:
			chains += 1
		sim.set_input(held_target, true, tap, _bot_steer(sim))
		sim.tick()
		for entry in sim.events:
			var event: Dictionary = entry
			match String(event.get("type", "")):
				"kill":
					kills += 1
				"life_lost":
					leaks += 1
				"gate_squad":
					if int(event.get("delta", 0)) >= 0:
						gates_good += 1
					else:
						gates_bad += 1
		ticks += 1
		if ticks % (TICKS_PER_SECOND * 5) == 0:
			print(
				(
					"%5.0fs %7d %7d %7d %7d %7d %7d %7d"
					% [
						sim.elapsed,
						sim.troops,
						sim.enemy_count,
						kills,
						leaks,
						gates_good,
						gates_bad,
						chains
					]
				)
			)

	print(
		(
			"akhir: %s pada %.1fs — wave %d, nyawa %d"
			% [
				"victory" if sim.state == SimWorld.State.VICTORY else "defeat",
				sim.elapsed,
				sim.wave_index + 1,
				sim.lives,
			]
		)
	)


# --- determinism -----------------------------------------------------------


## Two runs, same seed, same scripted input: every sampled hash must match.
## A short horizon passes even when the run is not deterministic, so this
## checks two hours of ticks at 60 Hz across every variant.
func _run_determinism() -> void:
	print("")
	print("DETERMINISME (%d tick × %d varian)" % [DETERMINISM_TICKS, _variant_names().size()])
	var all_match := true
	for stage in range(_variant_names().size()):
		var first := _hash_run(stage)
		var second := _hash_run(stage)
		if first == second:
			print("  varian %d: IDENTIK (%d sampel)" % [stage + 1, first.size()])
		else:
			all_match = false
			var at := _first_divergence(first, second)
			print("  varian %d: BERBEDA pada sampel %d" % [stage + 1, at])
			_failures.append("determinisme varian %d menyimpang di sampel %d" % [stage, at])
	if all_match:
		print("  hasil: SEMUA VARIAN IDENTIK")


## Runs a fixed, scripted input sequence and samples the state hash.
func _hash_run(stage: int) -> PackedInt64Array:
	var sim := SimWorld.new(_cfg, _seed() + stage * 7919, stage)
	var hashes := PackedInt64Array()
	for tick in range(DETERMINISM_TICKS):
		# Scripted rather than bot-driven: the bot reads state, so a bot run
		# would mask a divergence by steering both runs back together.
		var target := sin(float(tick) * 0.013) * 7.0
		sim.set_input(target, true, tick % 137 == 0, 0.0)
		sim.tick()
		if tick % 60 == 0:
			hashes.append(sim.snapshot_hash())
	return hashes


func _first_divergence(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return i
	return mini(a.size(), b.size())


# --- config helpers --------------------------------------------------------


func _variant_names() -> Array:
	var names: Array = []
	for entry in _cfg.get("variants", []):
		var variant: Dictionary = entry
		names.append(String(variant.get("name", "variant")))
	return names


func _wave_count() -> int:
	var spawn: Dictionary = _cfg.get("spawn", {})
	return int(spawn.get("waveCount", 5))


func _seed() -> int:
	var determinism: Dictionary = _cfg.get("determinism", {})
	return int(determinism.get("defaultSeed", 20260929))
