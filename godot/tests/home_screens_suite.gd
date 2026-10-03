class_name HomeScreensSuite
extends Node

## Penjaga untuk dua layar markas yang isinya murni UI: pemilih medan dan
## setup.
##
## Keduanya "lulus diam-diam" kalau hanya dilihat sekali — kartu yang selalu
## hidup, tombol hapus yang langsung jalan, volume yang tersimpan tapi tidak
## pernah sampai ke bus audio. Jadi setiap perilaku di sini diuji lewat dua
## keadaan yang berlawanan.

signal failed(message: String)

## Dipinjam dari smoke.gd: pemeriksa "tanpa emoji / tanpa glyph aneh".
var glyph_check: Callable = func(_node: Node, _label: String) -> void: pass


## Pemilih medan: lima kartu arena di markas.
##
## Dua keadaan yang berlawanan, karena kartu yang SELALU bisa ditekan dan kartu
## yang SELALU mati sama-sama lolos kalau hanya satu keadaan yang diperiksa.
## Yang dijaga juga perilakunya: menekan medan harus memulai stage TERBARU yang
## memakai medan itu, bukan stage pertamanya — kalau salah, pemain stage 14
## dilempar balik ke tutorial.
func run(packed: PackedScene) -> void:
	await _run_arena_picker(packed)
	await _run_setup_screen(packed)


func _run_arena_picker(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	var screens: Object = root.get("_screens")
	if screens == null:
		failed.emit("medan: layar tidak terbentuk")
		root.queue_free()
		return

	# 1. Profil baru: hanya medan stage pertama yang hidup.
	var fresh := await _arena_cards(root, screens)
	var arena_count := GameConfig.list("variants").size()
	if fresh.size() != arena_count:
		failed.emit("medan: %d kartu, config punya %d varian" % [fresh.size(), arena_count])
	if fresh.is_empty():
		root.queue_free()
		return
	var open_fresh := 0
	for card in fresh:
		if not (card as Button).disabled:
			open_fresh += 1
	if open_fresh != 1:
		failed.emit("medan: %d kartu hidup pada profil baru, harusnya 1" % open_fresh)

	# 2. Progres penuh: semua medan terbuka.
	var total := int(Cfg.num(GameConfig.dict("meta"), "stageCount", 15.0))
	SaveGame.unlocked_stage = total - 1
	var later := await _arena_cards(root, screens)
	var open_late := 0
	for card in later:
		if not (card as Button).disabled:
			open_late += 1
	if open_late != arena_count:
		failed.emit(
			"medan: hanya %d dari %d kartu terbuka di akhir game" % [open_late, arena_count]
		)

	# 3. Menekan medan pertama memulai stage terbaru yang memakai medan itu.
	var wanted := -1
	for stage in range(total):
		if screens.call("_variant_for_stage", stage) == 0:
			wanted = stage
	(later[0] as Button).pressed.emit()
	await get_tree().process_frame
	var sim: Object = root.get("_sim")
	if sim == null:
		failed.emit("medan: menekan kartu tidak memulai run")
	else:
		var started := int(root.get("_stage"))
		if started != wanted:
			failed.emit(
				"medan: kartu 1 memulai stage %d, harusnya %d (terbaru)" % [started, wanted]
			)
		else:
			print(
				(
					"  medan: %d kartu, 1 terbuka di awal, %d di akhir, kartu 1 -> stage %d"
					% [fresh.size(), open_late, started + 1]
				)
			)
	root.queue_free()


## Layar setup: volume balok dan hapus-progres yang harus ditahan.
##
## Keduanya diuji lewat keadaan yang berlawanan: senyap vs penuh, lepas cepat
## vs tahan penuh. Tombol hapus yang langsung jalan saat ditekan adalah bug
## paling mahal di layar ini, jadi justru pelepasan cepat yang diperiksa lebih
## dulu.
func _run_setup_screen(packed: PackedScene) -> void:
	SaveGame.reset_progress()
	var root := packed.instantiate()
	add_child(root)
	var screens: Object = root.get("_screens")
	var setup: Object = screens.get("_setup") if screens != null else null
	if setup == null:
		failed.emit("setup: layar setup tidak ada")
		root.queue_free()
		return
	# Layar dibuka sungguhan dulu: Godot menunda sebagian layout untuk node yang
	# tersembunyi, jadi mengukur layar yang belum pernah tampil akan membaca
	# posisi yang tidak pernah dilihat pemain.
	screens.call("_swap", setup)
	await get_tree().process_frame
	await get_tree().process_frame
	glyph_check.call(setup as Node, "setup")

	# Layar yang "ada" tapi gepeng di pojok kiri atas tetap lolos semua uji
	# fungsional di bawah ini, jadi geometrinya diperiksa lebih dulu: kolom
	# harus benar-benar mengisi layar 9:16, dan KEMBALI harus berada di zona
	# jempol bawah.
	var viewport: Vector2 = (setup as Control).get_viewport().get_visible_rect().size
	var rect: Rect2 = (setup as Control).get_global_rect()
	if rect.size.x < viewport.x - 1.0 or rect.size.y < viewport.y - 1.0:
		failed.emit(
			(
				"setup: layar %.0fx%.0f px, layar acuan %.0fx%.0f"
				% [rect.size.x, rect.size.y, viewport.x, viewport.y]
			)
		)
	var back := setup.get("_back_button") as Button
	if back == null:
		failed.emit("setup: tombol KEMBALI tidak ada")
	elif back.get_global_rect().position.y < viewport.y * 0.6:
		failed.emit("setup: KEMBALI di luar zona ibu jari (y %.0f)" % back.get_global_rect().position.y)

	var cells: Array = setup.get("_volume_cells")
	if cells.size() < 2:
		failed.emit("setup: kontrol volume bukan deret balok (%d sel)" % cells.size())
		root.queue_free()
		return
	for cell in cells:
		var size: Vector2 = (cell as Control).custom_minimum_size
		if size.y < 56.0:
			failed.emit("setup: sel volume tinggi %.0f px, target sentuh minimal 56" % size.y)
			break
	for node in (setup as Node).find_children("*", "", true, false):
		if node is Slider:
			failed.emit("setup: masih ada slider di layar setup")
			break

	# Catatan: uji ini meng-emit "pressed" langsung. Mengirim InputEventMouse
	# lewat Input.parse_input_event() TIDAK bekerja headless — tanpa jendela,
	# server tampilan dummy tidak pernah menjalankan pick GUI, jadi tombol yang
	# sehat pun tampak mati. Bukti bahwa jempol benar-benar mengenai tombol
	# diambil di browser sungguhan (tools/web_build_test.js + tangkapan layar).
	var master := AudioServer.get_bus_index("Master")

	# 1. Senyap: bus Master benar-benar dimatikan, bukan sekadar pelan.
	(cells[0] as Button).pressed.emit()
	if SaveGame.volume > 0.001:
		failed.emit("setup: balok OFF menyisakan volume %.2f" % SaveGame.volume)
	if master >= 0 and not AudioServer.is_bus_mute(master):
		failed.emit("setup: senyap tidak mematikan bus Master")

	# 2. Penuh: hidup lagi dan nilainya ikut tersimpan.
	(cells[cells.size() - 1] as Button).pressed.emit()
	if SaveGame.volume < 0.99:
		failed.emit("setup: balok teratas hanya memberi volume %.2f" % SaveGame.volume)
	if master >= 0 and AudioServer.is_bus_mute(master):
		failed.emit("setup: volume penuh tapi bus Master masih mute")
	var loud := AudioServer.get_bus_volume_db(master) if master >= 0 else -99.0

	# 3. Hapus progres dilepas cepat: progres harus selamat.
	SaveGame.unlocked_stage = 6
	setup.call("_start_hold")
	await get_tree().create_timer(0.2).timeout
	setup.call("_cancel_hold")
	await get_tree().process_frame
	if SaveGame.unlocked_stage != 6:
		failed.emit("setup: tahan 0,2 detik sudah menghapus progres")

	# 4. Ditahan penuh: baru progresnya hilang.
	setup.call("_start_hold")
	await get_tree().create_timer(1.5).timeout
	if SaveGame.unlocked_stage != 0:
		failed.emit("setup: tahan penuh tidak menghapus progres")
	if SaveGame.volume < 0.99:
		failed.emit("setup: hapus progres ikut mereset volume perangkat")
	print(
		(
			"  setup: %d balok volume, senyap mute bus, penuh %.1f dB, hapus butuh tahan penuh"
			% [cells.size(), loud]
		)
	)
	root.queue_free()


## Kartu medan dari markas, setelah layout settle.
func _arena_cards(root: Node, screens: Object) -> Array:
	root.call("_show_stage_map")
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Object = screens.get("_arena_row")
	var cards: Array = []
	if row != null:
		for child in (row as Node).get_children():
			if child is Button:
				cards.append(child)
	return cards
