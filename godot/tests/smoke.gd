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
	await _run_card_draft(packed)
	await _run_stage_map(packed)
	_finish()


## Drives the fifteen stage ladder: open it, measure every rung, and press one.
##
## A ladder screen fails in ways a screenshot would not show. Rows can collapse
## to a few pixels, locked stages can stay pressable, and the scroll can sit at
## the top so the stage you are actually on is off screen. All three are
## checked here against real geometry from the layout pass.
func _run_stage_map(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	var screens: Object = root.get("_screens")
	if screens == null or not screens.has_method("show_stage_map"):
		_fail("peta: layar peta stage tidak ada")
		root.queue_free()
		return

	var rows := await _open_map(root, screens)
	var total := int(Cfg.num(GameConfig.dict("meta"), "stageCount", 15.0))
	if rows.size() != total:
		_fail("peta: %d baris, meta.stageCount minta %d" % [rows.size(), total])
	if rows.is_empty():
		root.queue_free()
		return

	_check_map_layout(rows, screens)
	var row_h: float = (rows[0] as Button).get_global_rect().size.y
	var row_count: int = rows.size()

	# Fresh profile: only the first stage may be pressable.
	var pressable := 0
	for row in rows:
		if not (row as Button).disabled:
			pressable += 1
	if pressable != 1:
		_fail("peta: %d stage bisa ditekan pada profil baru, harusnya 1" % pressable)

	# Reopen part way up the ladder and confirm the scroll follows progress.
	SaveGame.unlocked_stage = 7
	var later := await _open_map(root, screens)
	if later.size() == total:
		var scroll_rect: Rect2 = (screens.get("_map_scroll") as Control).get_global_rect()
		var current: Rect2 = (later[7] as Button).get_global_rect()
		if not scroll_rect.intersects(current):
			_fail("peta: stage 8 di luar viewport setelah auto-scroll")
		var cleared := 0
		for i in range(7):
			if not (later[i] as Button).disabled:
				cleared += 1
		if cleared != 7:
			_fail("peta: %d dari 7 stage yang sudah lewat terbuka" % cleared)

	# Pressing a rung has to actually launch that stage.
	SaveGame.reset_progress()
	var again := await _open_map(root, screens)
	(again[0] as Button).pressed.emit()
	if root.get("_sim") == null:
		_fail("peta: menekan stage tidak memulai simulasi")
	else:
		print(
			(
				"  peta stage: %d baris, tinggi %d px, stage 8 terlihat, tekan stage 1 jalan"
				% [row_count, int(row_h)]
			)
		)
	root.queue_free()


## Opens the map and waits for the layout pass before handing back the rows.
func _open_map(root: Node, screens: Object) -> Array:
	root.call("_show_stage_map")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var list: Object = screens.get("_map_list")
	var rows: Array = []
	for child in (list as Node).get_children():
		if child is Button:
			rows.append(child)
	return rows


## Measured geometry, not assumptions: tap height, width, and no overlap.
func _check_map_layout(rows: Array, screens: Object) -> void:
	var viewport: Vector2 = (screens as CanvasLayer).get_viewport().get_visible_rect().size
	var previous_bottom := -1.0
	for i in range(rows.size()):
		var rect: Rect2 = (rows[i] as Button).get_global_rect()
		if rect.size.y < 100.0:
			_fail("peta: baris %d tinggi %d px, di bawah lantai 100 px" % [i + 1, rect.size.y])
			break
		if rect.size.x < 200.0:
			_fail("peta: baris %d lebar %d px" % [i + 1, rect.size.x])
			break
		if rect.position.x < 0.0 or rect.position.x + rect.size.x > viewport.x + 1.0:
			_fail("peta: baris %d keluar layar mendatar" % [i + 1])
			break
		if previous_bottom >= 0.0 and rect.position.y < previous_bottom - 0.5:
			_fail("peta: baris %d tumpang tindih dengan baris sebelumnya" % [i + 1])
			break
		previous_bottom = rect.position.y + rect.size.y
	_dump_map_layout(rows, screens, viewport)


func _dump_map_layout(rows: Array, screens: Object, viewport: Vector2) -> void:
	var clip: Rect2 = (screens.get("_map_scroll") as Control).get_global_rect()
	var entries: Array = []
	for i in range(rows.size()):
		var rect: Rect2 = (rows[i] as Button).get_global_rect()
		if not clip.intersects(rect):
			continue
		(
			entries
			. append(
				{
					"label": "STAGE %02d" % (i + 1),
					"x": rect.position.x,
					"y": rect.position.y,
					"w": rect.size.x,
					"h": rect.size.y,
				}
			)
		)
	var payload := {
		"screen": "stage map",
		"viewport": {"w": viewport.x, "h": viewport.y},
		"rects": entries,
	}
	var file := FileAccess.open("res://../screenshots/layout-stagemap.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()


## Drives the between-stage upgrade draft end to end: open it, press a card,
## and confirm the pick actually reaches the simulation.
##
## The draft is the whole of the meta layer, and every part of it can fail
## quietly. An empty offer list still renders a screen. A card that is granted
## but never folded into SimWorld leaves a run that plays identically while
## the save file fills up with upgrades the player can never feel.
func _run_card_draft(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	root.call("_on_play")

	var screens: Object = root.get("_screens")
	if screens == null or not screens.has_method("show_cards"):
		_fail("draft: layar kartu tidak ada")
		root.queue_free()
		return

	root.call("_on_continue")
	# Container geometry is resolved during the layout pass, not when the
	# children are added. Reading rects in the same frame reported 36 px wide
	# cards stacked on top of each other - stale values, not a broken screen.
	await get_tree().process_frame
	await get_tree().process_frame
	var list: Object = screens.get("_card_list")
	var buttons: Array = []
	for child in (list as Node).get_children():
		if child is Button:
			buttons.append(child)
	var want: int = int(Cfg.num(GameConfig.dict("meta"), "cardsOffered", 3.0))
	if buttons.size() != want:
		_fail("draft: %d kartu ditawarkan, meta.cardsOffered minta %d" % [buttons.size(), want])
	if buttons.is_empty():
		root.queue_free()
		return

	_check_card_layout(buttons)

	var before: int = SaveGame.owned_cards.size()
	(buttons[0] as Button).pressed.emit()

	if SaveGame.owned_cards.size() != before + 1:
		_fail("draft: kartu ditekan tapi tidak tersimpan")
	var upgrades: Dictionary = SaveGame.active_upgrades()
	if upgrades.is_empty():
		_fail("draft: kartu dimiliki tapi active_upgrades() kosong")
	# Taking the card ends the stage and hands control back to the ladder, so
	# launch from there to confirm the upgrade actually reaches SimWorld.
	root.call("_on_stage_chosen", 0)
	var sim: Object = root.get("_sim")
	if sim == null:
		_fail("draft: stage tidak bisa dimulai dari peta setelah memilih kartu")
	elif upgrades.has("startTroops"):
		# The one upgrade whose effect is readable straight off the sim, so
		# when it is the card drawn, check the number rather than trusting the
		# plumbing.
		var base: float = Cfg.num(GameConfig.dict("squad"), "startTroops", 5.0)
		var expected: int = int(base) + int(upgrades["startTroops"])
		if int(sim.get("troops")) != expected:
			_fail(
				"draft: troop %d, kartu seharusnya memberi %d" % [int(sim.get("troops")), expected]
			)
	print(
		(
			"  draft: %d kartu ditawarkan, '%s' dipilih, upgrade aktif %s"
			% [buttons.size(), SaveGame.owned_cards[0], str(upgrades)]
		)
	)
	SaveGame.reset_progress()
	root.queue_free()


## Measures the drafted cards after a layout pass.
##
## Nothing here can be seen - there is no GPU in this sandbox - but Godot's
## layout engine runs headless all the same, so the geometry is real even
## though the pixels are not. That is enough to catch the failures that
## actually ship on a phone: a tap target too small for a thumb, cards
## overlapping each other, or a column running off the bottom of a 19.5:9
## screen.
func _check_card_layout(buttons: Array) -> void:
	var viewport: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	)
	var previous := Rect2()
	for i in range(buttons.size()):
		var rect: Rect2 = (buttons[i] as Button).get_global_rect()
		if rect.size.y < 120.0:
			_fail(
				"draft: kartu %d tinggi %.0f px, docs/06 6.3a minta minimal 120" % [i, rect.size.y]
			)
		if rect.size.x < 200.0:
			_fail("draft: kartu %d lebar cuma %.0f px" % [i, rect.size.x])
		if rect.position.x < 0.0 or rect.end.x > viewport.x + 1.0:
			_fail(
				(
					"draft: kartu %d keluar layar mendatar (%.0f..%.0f dari %.0f)"
					% [i, rect.position.x, rect.end.x, viewport.x]
				)
			)
		if rect.end.y > viewport.y + 1.0:
			_fail(
				"draft: kartu %d jatuh di bawah layar (%.0f > %.0f)" % [i, rect.end.y, viewport.y]
			)
		if i > 0 and rect.position.y < previous.end.y - 1.0:
			_fail("draft: kartu %d tumpang tindih dengan kartu %d" % [i, i - 1])
		previous = rect
	_dump_layout(buttons, viewport)
	print(
		(
			"  draft layout: %d kartu, tinggi %.0f px, lebar %.0f px, dasar %.0f/%.0f"
			% [
				buttons.size(),
				(buttons[0] as Button).get_global_rect().size.y,
				(buttons[0] as Button).get_global_rect().size.x,
				previous.end.y,
				viewport.y,
			]
		)
	)


## Writes the measured rects to JSON so tools/draw_layout.py can turn them
## into a picture. The numbers are real measurements from Godot's layout
## engine; the picture is a diagram of them, not a screenshot. Nothing in this
## sandbox can render the actual screen.
func _dump_layout(buttons: Array, viewport: Vector2) -> void:
	var entries: Array = []
	for i in range(buttons.size()):
		var button := buttons[i] as Button
		var rect: Rect2 = button.get_global_rect()
		var caption := ""
		for child in button.get_children():
			for leaf in (child as Node).get_children():
				if leaf is Label and caption.is_empty():
					caption = (leaf as Label).text
		(
			entries
			. append(
				{
					"label": caption if not caption.is_empty() else "card %d" % i,
					"x": rect.position.x,
					"y": rect.position.y,
					"w": rect.size.x,
					"h": rect.size.y,
				}
			)
		)
	var payload := {
		"screen": "upgrade draft",
		"viewport": {"w": viewport.x, "h": viewport.y},
		"rects": entries,
	}
	var file := FileAccess.open("res://../screenshots/layout-cards.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()


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
	# Goes through the map's launch handler rather than start_stage directly,
	# so the screen wiring is exercised too. _on_play opens the stage ladder
	# now and no longer starts a run by itself; pressing a rung is covered by
	# _run_stage_map.
	root.call("_on_stage_chosen", stage)

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
	var cues := _check_audio(root, stage)
	_check_music(root, stage)

	print(
		(
			(
				"  varian %d: skor %d, troop %d, musuh %d, obstacle %d,"
				+ " slow-mo %.2f, shake %s, cue %d"
			)
			% [
				stage + 1,
				int(sim.get("score")),
				int(sim.get("troops")),
				int(sim.get("enemy_count")),
				(sim.get("field") as ObstacleField).obstacles.size(),
				slowest,
				"ya" if shook else "tidak",
				cues,
			]
		)
	)
	root.queue_free()


## Audio is the newest layer and the easiest to leave silently disconnected:
## nothing in this sandbox can hear it, and a director that never plays sounds
## exactly like one that does. So assert the cues that a played run must fire.
func _check_audio(root: Node, stage: int) -> int:
	var audio: Object = root.get("_audio")
	if audio == null:
		_fail("varian %d: AudioDirector tidak dibuat" % stage)
		return 0
	var counts: Dictionary = audio.get("play_counts")
	var total := 0
	for cue in counts:
		total += int(counts[cue])
	# shot and kill are unconditional in a run that taps and scores; if either
	# is missing the event wiring is broken, not the balance.
	for required in ["shot", "kill"]:
		if int(counts.get(required, 0)) == 0:
			_fail("varian %d: cue '%s' tidak pernah berbunyi" % [stage, required])
	# The kill cooldown is the load-bearing mix decision in docs/07 7.4.
	var seconds := float(FRAMES_PER_STAGE) / 60.0
	var kill_cap := int(seconds / 0.04) + 2
	if int(counts.get("kill", 0)) > kill_cap:
		_fail(
			(
				"varian %d: cue 'kill' berbunyi %d kali, cooldown 0.04 s membatasi %d"
				% [stage, int(counts.get("kill", 0)), kill_cap]
			)
		)
	# Bus tree from docs/07 7.4 must exist or every volume trim is a no-op.
	for bus_name in ["Music", "SFX", "Impact", "Crowd", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			_fail("varian %d: bus '%s' tidak dibuat" % [stage, bus_name])
	return total


## Music loads from disk and mixes by volume, so both halves can fail quietly:
## a missing stem leaves a silent player, and a stuck fade leaves it inaudible.
func _check_music(root: Node, stage: int) -> void:
	var music: Object = root.get("_music")
	if music == null:
		_fail("varian %d: MusicDirector tidak dibuat" % stage)
		return
	# Variant 0 runs on base alone (docs/07 7.3), so base + fill is the floor;
	# every other variant adds its own layer on top.
	var expected := 2 if stage == 0 else 3
	var loaded := int(music.get("layers_loaded"))
	if loaded < expected:
		_fail("varian %d: %d stem musik dimuat, diharapkan %d" % [stage, loaded, expected])
	if int(music.get("active_variant")) != stage:
		_fail(
			"varian %d: MusicDirector memutar varian %d" % [stage, int(music.get("active_variant"))]
		)
	# The base loop must have faded up from its silent start.
	var base: Node = music.get_child(0)
	if base is AudioStreamPlayer:
		var player := base as AudioStreamPlayer
		if not player.playing:
			_fail("varian %d: loop musik dasar tidak berjalan" % stage)
		elif player.volume_db <= -59.0:
			_fail("varian %d: musik dasar masih senyap (%.1f dB)" % [stage, player.volume_db])


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
