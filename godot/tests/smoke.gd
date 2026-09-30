extends Node
## Boots the real scene and drives frames through it, with autoloads live.
##
## Everything in sim_headless.gd tests rules; nothing tested the renderer. A
## view can pass gdparse, gdlint, gdformat and the cross-reference validator
## and still die on its first frame — reading a property that moved, indexing
## an empty pool, sizing a bar against a crowd of zero. The headless dummy
## renderer draws nothing, but it executes every line that would.
##
## This has to be a scene rather than a `--script` run: `--script` does not
## register autoloads, so anything touching GameConfig fails to compile.
##
##   godot --headless --path godot/ res://tests/smoke.tscn

## Thirty seconds: long enough for every variant to land a ridden chain
## shot, which is what slow motion and the ricochet effects hang on.
const FRAMES_PER_STAGE := 1800

var _failures: Array[String] = []


func _ready() -> void:
	print("")
	print("SMOKE: scene sungguhan, %d frame per varian" % FRAMES_PER_STAGE)
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn tidak bisa dimuat")
		_finish()
		return

	var stages := GameConfig.list("meta.variantCycle").size()
	for stage in range(maxi(stages, 1)):
		_run_stage(packed, stage)
	_finish()


func _run_stage(packed: PackedScene, stage: int) -> void:
	var root := packed.instantiate()
	add_child(root)
	if not root.has_method("start_stage"):
		_fail("Game tidak punya start_stage()")
		root.queue_free()
		return

	# Game skips rendering for any child whose script failed to compile, so a
	# broken view would let this test pass while drawing nothing. Check that
	# the scripts are actually there before trusting anything below.
	for child_name in ["ArenaView", "HUD", "Screens"]:
		var child := root.get_node_or_null(NodePath(child_name))
		if child == null:
			_fail("node %s hilang dari main.tscn" % child_name)
		elif child.get_script() == null:
			_fail("skrip %s gagal dikompilasi" % child_name)
	for pair in [["ArenaView", "render_frame"], ["HUD", "render_frame"], ["Screens", "build"]]:
		var child := root.get_node_or_null(NodePath(String(pair[0])))
		if child != null and not child.has_method(String(pair[1])):
			_fail("%s tidak punya %s()" % [pair[0], pair[1]])

	root.set("_stage", stage)
	# Goes through the menu button rather than start_stage directly, so the
	# screen wiring is exercised too.
	root.call("_on_play")

	var sim: Object = root.get("_sim")
	if sim == null:
		_fail("varian %d: simulasi tidak dibuat" % stage)
		root.queue_free()
		return

	# The feel layer is easy to wire up and leave dead, so watch it work:
	# a ridden bullet must slow the engine, and something must shake.
	var slowest := 1.0
	var shook := false
	for frame in range(FRAMES_PER_STAGE):
		# Drive it like a thumb. Watching an idle game proves nothing: with
		# no taps the chain shot never fires, so slow motion, bullet riding
		# and every ricochet effect stay dead code.
		root.set("_pointer_down", true)
		root.set("_pointer_arena_x", sin(float(frame) * 0.02) * 6.0)
		if frame % 45 == 0:
			root.set("_pending_tap", true)
		root.call("_physics_process", 1.0 / 60.0)
		root.call("_process", 1.0 / 60.0)
		slowest = minf(slowest, Engine.time_scale)
		var feel: Object = root.get("_feel")
		if feel != null and float(feel.call("current_shake_strength")) > 0.0:
			shook = true
	Engine.time_scale = 1.0
	if slowest >= 0.999:
		_fail("varian %d: slow-mo tidak pernah aktif" % stage)
	if not shook:
		_fail("varian %d: camera shake tidak pernah aktif" % stage)

	print(
		(
			"  varian %d: skor %d, troop %d, musuh %d, obstacle %d, slow-mo %.2f, shake %s"
			% [
				stage + 1,
				int(sim.get("score")),
				int(sim.get("troops")),
				int(sim.get("enemy_count")),
				(sim.get("field") as ObstacleField).obstacles.size(),
				slowest,
				"ya" if shook else "tidak",
			]
		)
	)
	root.queue_free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("SMOKE LULUS — renderer berjalan di semua varian")
		get_tree().quit(0)
	else:
		for line in _failures:
			print("GAGAL: %s" % line)
		get_tree().quit(1)
