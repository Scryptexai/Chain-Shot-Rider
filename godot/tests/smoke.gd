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

const FRAMES_PER_STAGE := 900

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

	root.set("_stage", stage)
	# Goes through the menu button rather than start_stage directly, so the
	# screen wiring is exercised too.
	root.call("_on_play")

	var sim: Object = root.get("_sim")
	if sim == null:
		_fail("varian %d: simulasi tidak dibuat" % stage)
		root.queue_free()
		return

	for frame in range(FRAMES_PER_STAGE):
		root.call("_physics_process", 1.0 / 60.0)
		root.call("_process", 1.0 / 60.0)

	print(
		(
			"  varian %d: skor %d, troop %d, musuh %d, obstacle %d"
			% [
				stage + 1,
				int(sim.get("score")),
				int(sim.get("troops")),
				int(sim.get("enemy_count")),
				(sim.get("field") as ObstacleField).obstacles.size(),
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
