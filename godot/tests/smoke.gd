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
	await _run_hud_layout(packed)
	_finish()


## Mengukur HUD saat sebuah run benar-benar berjalan.
##
## HUD adalah satu-satunya layar yang tidak pernah bisa dilihat di sandbox ini
## (tidak ada GPU), tapi mesin layout Godot tetap jalan headless, jadi semua
## angka di bawah ini nyata. Yang diperiksa adalah hal-hal yang membuat sebuah
## HUD gagal di ponsel sungguhan dan tidak pernah terlihat di kode:
##   · tombol aksi terlalu kecil untuk ibu jari, atau berada di luar
##     jangkauannya (bagian atas layar),
##   · tombol jeda masuk ke wilayah notch,
##   · pod informasi menindih tombol aksi,
##   · dan tombol yang terpasang tapi tidak tersambung ke apa pun.
func _run_hud_layout(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	root.call("_on_stage_chosen", 0)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud: Object = root.get("_hud")
	var screens: Object = root.get("_screens")
	var fire := hud.get("_fire_button") as Button
	var pause := hud.get("_pause_button") as Button
	if fire == null or pause == null:
		_fail("hud: tombol chain shot / jeda tidak ada")
		root.queue_free()
		return

	var viewport: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	)
	var fire_rect: Rect2 = fire.get_global_rect()
	var pause_rect: Rect2 = pause.get_global_rect()

	if fire_rect.size.x < 200.0 or fire_rect.size.y < 200.0:
		_fail("hud: tombol chain shot %.0fx%.0f px, terlalu kecil untuk ibu jari" % [fire_rect.size.x, fire_rect.size.y])
	# Zona ibu jari: aksi utama harus duduk di sepertiga bawah layar.
	if fire_rect.get_center().y < viewport.y * 0.62:
		_fail("hud: tombol chain shot di luar zona ibu jari (y %.0f dari %.0f)" % [fire_rect.get_center().y, viewport.y])
	if fire_rect.end.x > viewport.x + 1.0 or fire_rect.end.y > viewport.y + 1.0:
		_fail("hud: tombol chain shot keluar layar")
	if absf(pause_rect.size.x - pause_rect.size.y) > 8.0:
		_fail("hud: tombol jeda tidak persegi (%.0fx%.0f)" % [pause_rect.size.x, pause_rect.size.y])
	if pause_rect.size.x < 100.0 or pause_rect.size.y < 100.0:
		_fail("hud: tombol jeda %.0fx%.0f px, di bawah lantai 100 px" % [pause_rect.size.x, pause_rect.size.y])
	if pause_rect.position.y < 80.0:
		_fail("hud: tombol jeda masuk wilayah notch (y %.0f)" % pause_rect.position.y)
	if pause_rect.end.x > viewport.x + 1.0:
		_fail("hud: tombol jeda keluar layar")

	_check_hud_overlap(hud, viewport)

	# Tombol jeda harus benar-benar menjeda: sebelum ini tidak ada satu pun
	# jalan keluar dari run selain kalah.
	pause.pressed.emit()
	if root.call("is_physics_processing"):
		_fail("hud: tombol jeda tidak menghentikan simulasi")
	var pause_screen := screens.get("_pause") as Control
	if pause_screen == null or not pause_screen.visible:
		_fail("hud: layar jeda tidak muncul")
	root.call("_on_resume")

	# Dan tombol chain shot harus memicu tembakan yang sama dengan tap arena.
	root.set("_pending_tap", false)
	fire.pressed.emit()
	if not bool(root.get("_pending_tap")):
		_fail("hud: tombol chain shot tidak memicu tembakan")

	_dump_hud_layout(hud, viewport)
	print(
		(
			"  hud: chain shot %.0fx%.0f px @ y %.0f/%.0f, jeda %.0f px, jeda+tembak tersambung"
			% [fire_rect.size.x, fire_rect.size.y, fire_rect.position.y, viewport.y, pause_rect.size.y]
		)
	)
	Engine.time_scale = 1.0
	root.queue_free()


## Tidak ada dua elemen HUD tetap yang boleh saling menindih, dan tidak satu
## pun boleh keluar layar.
##
## Ini satu-satunya pemeriksaan yang menangkap kegagalan paling umum di HUD
## yang ditaruh pada koordinat tetap: teks pada font perangkat ternyata lebih
## tinggi dari dugaan, kotaknya memuai, dan dua pod saling tumpuk. Tanpa GPU
## tidak ada cara lain melihatnya selain mengukurnya.
func _check_hud_overlap(hud: Object, viewport: Vector2) -> void:
	var names: Array = [
		"_score_pod",
		"_chip_column",
		"_pause_button",
		"_squad_pod",
		"_steer_bar",
		"_hp_row",
		"_fire_button",
	]
	var rects: Array = []
	var labels: Array = []
	for field in names:
		var control := hud.get(String(field)) as Control
		if control == null:
			_fail("hud: %s hilang" % field)
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < -1.0 or rect.end.x > viewport.x + 1.0:
			_fail("hud: %s keluar layar mendatar (%.0f..%.0f)" % [field, rect.position.x, rect.end.x])
		if rect.position.y < -1.0 or rect.end.y > viewport.y + 1.0:
			_fail("hud: %s keluar layar tegak (%.0f..%.0f)" % [field, rect.position.y, rect.end.y])
		rects.append(rect)
		labels.append(String(field))
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[j]
			# Kempiskan 1 px: tepi yang bersentuhan tepat bukan tumpang tindih.
			if a.grow(-1.0).intersects(b.grow(-1.0)):
				_fail("hud: %s menindih %s" % [labels[i], labels[j]])


## Menulis rect HUD ke JSON supaya tools/draw_layout.py bisa menggambarnya.
func _dump_hud_layout(hud: Object, viewport: Vector2) -> void:
	var entries: Array = []
	for pair in [
		["_score_pod", "SCORE"],
		["_chip_column", "STAGE + WAVE"],
		["_pause_button", "JEDA"],
		["_squad_pod", "PASUKAN"],
		["_steer_bar", "STEER"],
		["_hp_row", "NYAWA"],
		["_fire_button", "CHAIN SHOT"],
		["_hint", "HINT"],
	]:
		var control := hud.get(String(pair[0])) as Control
		if control == null:
			continue
		var rect: Rect2 = control.get_global_rect()
		entries.append(
			{
				"label": String(pair[1]),
				"x": rect.position.x,
				"y": rect.position.y,
				"w": rect.size.x,
				"h": rect.size.y,
			}
		)
	var payload := {
		"screen": "hud",
		"viewport": {"w": viewport.x, "h": viewport.y},
		"rects": entries,
	}
	var file := FileAccess.open("res://../screenshots/layout-hud.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()


## Menggiring tangga 15 stage: buka, ukur tiap kartu, tekan satu.
##
## Sejak peta jadi rel kartu mendatar di layar markas, pemeriksaannya ikut
## mendatar — tapi jaminannya sama: kartu tidak boleh menciut di bawah ukuran
## target sentuh, tidak boleh saling tumpang tindih, harus berada di dalam rel,
## dan stage yang sedang dimainkan harus tergulir ke dalam pandangan. Tidak
## satu pun dari itu terlihat di screenshot.
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
	_check_home_layout(screens)
	_check_glyphs(screens as Node, "peta + markas")
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
				"  rel stage: %d kartu, tinggi %d px, stage 8 tergulir ke pandangan, tekan stage 1 jalan"
				% [row_count, int(row_h)]
			)
		)
	root.queue_free()


## Markas harus muat di layar acuan dan menaruh aksi utamanya di bawah.
##
## Kolom markas disusun dari spacer yang memuai, jadi satu elemen yang terlalu
## tinggi mendorong tombol MAIN keluar layar tanpa suara — headless maupun di
## perangkat.
func _check_home_layout(screens: Object) -> void:
	var viewport: Vector2 = (screens as CanvasLayer).get_viewport().get_visible_rect().size
	var play := screens.get("_play_button") as Button
	if play == null:
		_fail("markas: tombol MAIN tidak ada")
		return
	var rect: Rect2 = play.get_global_rect()
	if rect.size.y < 120.0:
		_fail("markas: tombol MAIN tinggi %.0f px" % rect.size.y)
	if rect.end.y > viewport.y + 1.0:
		_fail("markas: tombol MAIN jatuh di bawah layar (%.0f > %.0f)" % [rect.end.y, viewport.y])
	if rect.position.y < viewport.y * 0.6:
		_fail("markas: tombol MAIN di luar zona ibu jari (y %.0f)" % rect.position.y)
	var rail := screens.get("_map_scroll") as Control
	if rail != null and rail.get_global_rect().intersects(rect):
		_fail("markas: rel stage menindih tombol MAIN")
	print(
		(
			"  markas: tombol MAIN %.0fx%.0f px @ y %.0f/%.0f, rel stage terpisah"
			% [rect.size.x, rect.size.y, rect.position.y, viewport.y]
		)
	)


## Opens the map and waits for the layout pass before handing back the rows.
func _open_map(root: Node, screens: Object) -> Array:
	root.call("_show_stage_map")
	# show_stage_map() menggulir sendiri setelah dua layout pass; tunggu lebih
	# lama dari itu supaya yang terbaca adalah posisi akhir, bukan posisi awal.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var list: Object = screens.get("_map_list")
	var rows: Array = []
	for child in (list as Node).get_children():
		if child is Button:
			rows.append(child)
	return rows


## Geometri terukur, bukan asumsi: ukuran target sentuh, tanpa tumpang tindih,
## dan rel yang benar-benar memperlihatkan lebih dari satu kartu.
func _check_map_layout(rows: Array, screens: Object) -> void:
	var viewport: Vector2 = (screens as CanvasLayer).get_viewport().get_visible_rect().size
	var rail: Rect2 = (screens.get("_map_scroll") as Control).get_global_rect()
	var previous_right := -1.0
	var visible_cards := 0
	for i in range(rows.size()):
		var rect: Rect2 = (rows[i] as Button).get_global_rect()
		if rect.size.y < 200.0:
			_fail("peta: kartu %d tinggi %d px, di bawah lantai 200 px" % [i + 1, rect.size.y])
			break
		if rect.size.x < 200.0:
			_fail("peta: kartu %d lebar %d px, di bawah lantai 200 px" % [i + 1, rect.size.x])
			break
		# Rel mendatar: kartu boleh keluar layar ke kanan (itu gunanya bisa
		# digeser), tapi tidak boleh keluar dari rel secara vertikal.
		if rect.position.y < rail.position.y - 2.0 or rect.end.y > rail.end.y + 2.0:
			_fail("peta: kartu %d keluar dari rel secara vertikal" % [i + 1])
			break
		if previous_right >= 0.0 and rect.position.x < previous_right - 0.5:
			_fail("peta: kartu %d tumpang tindih dengan kartu sebelumnya" % [i + 1])
			break
		previous_right = rect.end.x
		if rail.intersects(rect):
			visible_cards += 1
	if visible_cards < 2:
		_fail("peta: hanya %d kartu terlihat di rel, harusnya bisa dibandingkan" % visible_cards)
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
	_check_glyphs(screens as Node, "draft kartu")
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

	# HUD adalah milik run. Kalau ia terlihat sebelum run dimulai, markas dan
	# peta stage tertimpa nyawa, pod pasukan, dan teks gelombang. Kegagalan ini
	# tidak pernah muncul di sandbox tanpa GPU dan baru terlihat di build web,
	# jadi sekarang dijaga di sini.
	var hud_layer: CanvasLayer = root.get_node_or_null(NodePath("HUD"))
	if hud_layer != null and hud_layer.visible:
		_fail("varian %d: HUD terlihat sebelum run dimulai" % (stage + 1))

	root.set("_stage", stage)
	# Goes through the map's launch handler rather than start_stage directly,
	# so the screen wiring is exercised too. _on_play opens the stage ladder
	# now and no longer starts a run by itself; pressing a rung is covered by
	# _run_stage_map.
	root.call("_on_stage_chosen", stage)

	if hud_layer != null and not hud_layer.visible:
		_fail("varian %d: HUD tidak muncul saat run berjalan" % (stage + 1))
	if hud_layer != null:
		_check_glyphs(hud_layer, "varian %d HUD" % (stage + 1))

	var sim: Object = root.get("_sim")
	if sim == null:
		_fail("varian %d: simulasi tidak dibuat" % stage)
		root.queue_free()
		return

	# The feel layer is easy to wire up and leave dead, so watch it work:
	# a ridden bullet must slow the engine, and something must shake.
	var slowest := 1.0
	var shook := false
	# Karakter ber-tulang: dummy renderer tidak menggambar apa pun, tapi
	# skeleton, AnimationPlayer dan kolamnya tetap dieksekusi. Yang diukur
	# adalah hal-hal yang diam-diam mati: model tidak termuat, aktor tidak
	# pernah dipinjam, anggaran LOD jebol di gelombang besar, atau mayat
	# tidak pernah roboh.
	var view: Object = root.get_node_or_null(NodePath("ArenaView"))
	var chars: Object = view.get("_chars") if view != null else null
	var peak_actors := 0
	var peak_corpses := 0
	var clips_seen: Dictionary = {}
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
		if chars != null:
			peak_actors = maxi(peak_actors, int(chars.call("active_count")))
			peak_corpses = maxi(peak_corpses, int(chars.call("corpse_count")))
			for name in _clips_playing(chars):
				clips_seen[name] = true
	Engine.time_scale = 1.0
	if slowest >= 0.999:
		_fail("varian %d: slow-mo tidak pernah aktif" % stage)
	if not shook:
		_fail("varian %d: camera shake tidak pernah aktif" % stage)
	_check_characters(stage, chars, peak_actors, peak_corpses, clips_seen)
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


## Klip yang sedang berjalan pada aktor yang dipinjam frame ini.
func _clips_playing(chars: Object) -> Array:
	var names: Array = []
	for child in (chars as Node).get_children():
		var player: AnimationPlayer = child.find_child("AnimationPlayer", true, false)
		if player != null and player.is_playing():
			names.append(player.current_animation)
	return names


## Bukti bahwa lapisan karakter v1.0 benar-benar hidup di dalam run, bukan
## sekadar berkas yang ada di folder.
func _check_characters(
	stage: int, chars: Object, peak_actors: int, peak_corpses: int, clips: Dictionary
) -> void:
	if chars == null:
		_fail("varian %d: ArenaView tidak punya kolam karakter" % (stage + 1))
		return
	var loaded := int(chars.call("loaded_count"))
	var budget: int = (
		int(CharacterPool.BUDGET["troops"]) + int(CharacterPool.BUDGET["enemies"]) + 1
	)
	if loaded < 8:
		_fail("varian %d: hanya %d model ber-tulang termuat, harus 8" % [stage + 1, loaded])
	if peak_actors <= 0:
		_fail("varian %d: tidak ada karakter ber-tulang yang pernah tampil" % (stage + 1))
	if peak_actors > budget:
		_fail(
			(
				"varian %d: anggaran LOD jebol — %d aktor sekaligus, batas %d"
				% [stage + 1, peak_actors, budget]
			)
		)
	if clips.size() < 2:
		_fail("varian %d: hanya satu klip animasi yang pernah jalan" % (stage + 1))
	if peak_corpses <= 0:
		_fail("varian %d: musuh mati tanpa pernah roboh" % (stage + 1))
	if peak_corpses > int(CharacterPool.BUDGET["corpses"]):
		_fail("varian %d: mayat melewati anggaran (%d)" % [stage + 1, peak_corpses])
	print(
		(
			"    karakter: %d model, puncak %d aktor (batas %d), %d mayat, klip %s"
			% [loaded, peak_actors, budget, peak_corpses, str(clips.keys())]
		)
	)


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


## Setiap karakter yang tampil harus benar-benar ada di font.
##
## Font bawaan Godot (Open Sans SemiBold) tidak punya ★ ☆ ✦ ▲ ◎ →, dan
## yang muncul di layar adalah kotak tofu. Renderer dummy tidak menggambar
## huruf, jadi hal ini lolos semua tes sampai ada yang melihat build web.
## Pemeriksaan ini menelusuri pohon UI dan membandingkan tiap karakter dengan
## cakupan font yang benar-benar dipakai label itu.
func _check_glyphs(node: Node, where: String) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	elif node is RichTextLabel:
		text = (node as RichTextLabel).get_parsed_text()
	if text != "":
		var font: Font = null
		if node is Control:
			font = (node as Control).get_theme_font("font")
		if font == null:
			font = ThemeDB.fallback_font
		var missing := ""
		for i in range(text.length()):
			var code := text.unicode_at(i)
			# Karakter kontrol dan spasi tidak punya glyph dan memang tidak perlu.
			if code <= 32:
				continue
			if not font.has_char(code):
				var ch := String.chr(code)
				if not missing.contains(ch):
					missing += ch
		if missing != "":
			_fail("%s: font tidak punya glyph untuk \"%s\" (teks: %s)" % [where, missing, text])
	for child in node.get_children():
		_check_glyphs(child, where)


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
