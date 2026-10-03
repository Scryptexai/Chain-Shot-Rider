extends CanvasLayer
## Markas, jeda, hasil, dan draft kartu — disusun ulang sebagai layar game
## mobile, bukan daftar pengaturan.
##
## Yang berubah dari versi sebelumnya dan alasannya:
##   · Menu dan peta stage digabung jadi satu layar MARKAS. Dua layar untuk
##     satu pertanyaan ("stage mana berikutnya?") memaksa satu ketukan ekstra
##     sebelum game dimulai, dan membuat layar pertama cuma berisi satu tombol.
##   · Peta stage jadi rel mendatar berisi kartu bergambar, bukan daftar 15
##     baris teks. Daftar panjang bergulir vertikal dengan label status di
##     kanan adalah pola aplikasi; chapter select di game mobile selalu rel
##     kartu yang bisa digeser jempol.
##   · Tombol memakai gaya tebal berbevel dengan "kaki" gelap, dan aksi utama
##     berwarna hijau. Tombol datar berpinggir tipis terbaca seperti dialog
##     sistem, bukan tombol game.
##
## Aturan sentuh yang tetap dipegang:
##   · Target tap >= 120 px tinggi, jarak antar tombol >= 20 px.
##   · 88 px teratas tidak dipakai (notch).
##   · Aksi utama di bagian bawah layar, dalam jangkauan jempol.
##   · Semua layar meredupkan permainan di belakangnya.

signal play_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal continue_pressed
signal card_chosen(card_id: String)
signal stage_chosen(stage: int)

const REF_W := 1080.0
const SAFE_TOP := 88.0
const SIDE := 60.0
const BUTTON_H := 150.0
const CARD_H := 190.0
const STAGE_CARD_W := 240.0
const STAGE_CARD_H := 300.0
const STAGE_CARD_GAP := 22.0

var _pal: Dictionary = {}
var _theme: Theme
var _scrim: ColorRect
var _home: Control
var _pause: Control
var _result: Control
var _cards: Control

var _result_title: Label
var _result_rows: VBoxContainer
var _card_list: VBoxContainer
var _result_advance: Button
var _result_subtitle: Label

var _profile_level: Label
var _pill_best: Label
var _pill_cards: Label
var _chapter_kicker: Label
var _chapter_name: Label
var _chapter_boss: Label
var _chapter_desc: Label
var _chapter_stars: HBoxContainer
var _chapter_panel: PanelContainer
var _chapter_lane: ColorRect
var _play_button: Button
var _play_caption: Label
var _map_list: HBoxContainer
var _map_scroll: ScrollContainer
var _map_subtitle: Label


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_theme = UiTheme.build(_pal)
	_build_scrim()
	_home = _build_home()
	_pause = _build_pause()
	_result = _build_result()
	_cards = _build_cards()
	show_menu()


## Markas. Dipanggil saat boot dan setiap kali pemain kembali dari run.
func show_menu() -> void:
	_refresh_home()
	_swap(_home)


## Pause overlay.
func show_pause() -> void:
	_swap(_pause)


## Result screen. Rows are built from the run, not from a fixed template,
## so adding a stat later does not mean re-laying out the screen.
func show_result(won: bool, rows: Array) -> void:
	_result_title.text = "MENANG" if won else "KALAH"
	_result_title.add_theme_color_override("font_color", _pal["primary"] if won else UiTheme.DANGER)
	_result_subtitle.text = (
		"STAGE %02d  ·  %s" % [SaveGame.unlocked_stage + 1, _variant_name(SaveGame.unlocked_stage)]
	)
	for child in _result_rows.get_children():
		child.queue_free()
	# Angka dihitung naik, satu baris demi satu baris. Hasil run yang muncul
	# jadi sekali tempel terbaca seperti tabel laporan; angka yang berlari naik
	# terbaca sebagai hadiah — itu yang dilakukan Last War dan sejenisnya di
	# layar akhir ronde.
	var index := 0
	for entry in rows:
		var row: Dictionary = entry
		_result_rows.add_child(
			_stat_row(String(row.get("label", "")), String(row.get("value", "")), index)
		)
		index += 1
	# A win leads into the upgrade draft rather than straight back to the
	# menu, which is what makes the stage ladder feel like progress instead of
	# a series of unrelated runs.
	_result_advance.text = "LANJUT" if won else "COBA LAGI"
	UiTheme.apply_chunky(
		_result_advance,
		_pal["primary"] if won else UiTheme.GO,
		Color(_pal["primary"].darkened(0.5)) if won else UiTheme.GO_DARK
	)
	_swap(_result)


## Hides every screen and hands control back to the game.
func hide_all() -> void:
	_swap(null)


## Rel stage. Dibangun ulang tiap kali dibuka karena unlock berubah di
## belakangnya, dan peta yang masih menunjukkan kunci kemarin lebih buruk
## daripada tidak ada peta.
##
## Menunggu layout pass sebelum menggulir: ScrollContainer melaporkan viewport
## nol sampai anaknya diukur, jadi offset yang dihitung di frame yang sama
## akan selalu mendarat di awal rel.
func show_stage_map() -> void:
	_refresh_home()
	_swap(_home)

	await get_tree().process_frame
	await get_tree().process_frame
	var total := _stage_count()
	var current: int = clampi(SaveGame.unlocked_stage, 0, total - 1)
	var pitch := STAGE_CARD_W + STAGE_CARD_GAP
	var target := float(current) * pitch - (_map_scroll.size.x - STAGE_CARD_W) * 0.5
	_map_scroll.scroll_horizontal = int(maxf(target, 0.0))


func _swap(target: Control) -> void:
	for screen in [_home, _pause, _result, _cards]:
		if screen != null:
			screen.visible = screen == target
	_scrim.visible = target != null
	# Screens must keep receiving input while the game is paused.
	visible = true


func _build_scrim() -> void:
	_scrim = ColorRect.new()
	var bottom: Color = _pal["bg_bottom"]
	_scrim.color = Color(bottom.r, bottom.g, bottom.b, 0.82)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)


# ---------------------------------------------------------------------------
# MARKAS
# ---------------------------------------------------------------------------
func _build_home() -> Control:
	var root := _screen_root()
	var box := _fill_column(root)

	# --- baris profil + sumber daya ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.custom_minimum_size = Vector2(0.0, 110.0)
	box.add_child(top)

	var profile := PanelContainer.new()
	profile.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 56))
	top.add_child(profile)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 18)
	profile.add_child(profile_row)
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(88.0, 88.0)
	avatar.add_theme_stylebox_override(
		"panel", UiTheme.blob(_pal["primary"], 28, _pal["primary"].darkened(0.5))
	)
	profile_row.add_child(avatar)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	profile_row.add_child(who)
	_text(who, "COMMANDER", 30, UiTheme.INK)
	_profile_level = _text(who, "LV 1", 24, UiTheme.INK_DIM)

	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(push)

	# Label kata, bukan simbol: font bawaan Godot tidak punya ★ dan ✦, dan
	# "BEST" lebih jelas daripada bintang yang harus ditebak artinya.
	_pill_best = _pill(top, "BEST 0", UiTheme.GOLD)
	_pill_cards = _pill(top, "KARTU 0", UiTheme.INK)

	box.add_child(_grow(0.5))

	# --- logo ---
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -10)
	box.add_child(logo)
	_text(logo, "CHAIN", 112, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_text(logo, "RIDER", 112, _pal["primary"], HORIZONTAL_ALIGNMENT_CENTER)
	var tagline := _text(logo, "RIDE THE RICOCHET", 26, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	tagline.custom_minimum_size = Vector2(0.0, 60.0)

	box.add_child(_grow(0.35))

	# --- kartu chapter: fokus layar, menjawab "aku main apa sekarang" ---
	_chapter_panel = PanelContainer.new()
	_chapter_panel.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 40, 0.9))
	box.add_child(_chapter_panel)
	var chapter := VBoxContainer.new()
	chapter.add_theme_constant_override("separation", 10)
	_chapter_panel.add_child(chapter)

	# Pratinjau lorong: satu batang warna tema. Murah, tapi cukup untuk
	# membedakan lima arena tanpa aset gambar.
	_chapter_lane = ColorRect.new()
	_chapter_lane.color = _pal["primary"]
	_chapter_lane.custom_minimum_size = Vector2(0.0, 12.0)
	chapter.add_child(_chapter_lane)

	_chapter_kicker = _text(chapter, "STAGE 01 / 15", 24, _pal["primary"])
	_chapter_name = _text(chapter, "CLASSIC PIT", 64, UiTheme.INK)
	_chapter_boss = _text(chapter, "BOSS · COLOSSUS", 26, Color("#FFB3B3"))
	_chapter_stars = UiTheme.pips(3, 3, UiTheme.GOLD, UiTheme.INK_DIM.darkened(0.3), 20)
	chapter.add_child(_chapter_stars)
	_chapter_desc = _text(chapter, "", 26, Color("#C3D3EA"))
	_chapter_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chapter_desc.custom_minimum_size = Vector2(0.0, 80.0)

	box.add_child(_grow(0.2))

	# --- rel stage ---
	var rail_head := HBoxContainer.new()
	rail_head.add_theme_constant_override("separation", 12)
	box.add_child(rail_head)
	_text(rail_head, "PILIH STAGE", 30, UiTheme.INK)
	var head_push := Control.new()
	head_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_head.add_child(head_push)
	_map_subtitle = _text(rail_head, "0 / 15 CLEARED", 24, UiTheme.INK_DIM)

	_map_scroll = ScrollContainer.new()
	_map_scroll.custom_minimum_size = Vector2(0.0, STAGE_CARD_H + 24.0)
	_map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_map_scroll)

	_map_list = HBoxContainer.new()
	_map_list.add_theme_constant_override("separation", int(STAGE_CARD_GAP))
	_map_scroll.add_child(_map_list)

	box.add_child(_grow(0.5))

	# --- aksi utama di zona jempol ---
	_play_button = Button.new()
	_play_button.text = "MAIN"
	_play_button.theme = _theme
	_play_button.focus_mode = Control.FOCUS_NONE
	_play_button.custom_minimum_size = Vector2(0.0, BUTTON_H)
	_play_button.add_theme_font_size_override("font_size", 56)
	UiTheme.apply_chunky(_play_button, UiTheme.GO, UiTheme.GO_DARK)
	_play_button.pressed.connect(
		func() -> void:
			var total := _stage_count()
			stage_chosen.emit(clampi(SaveGame.unlocked_stage, 0, total - 1))
	)
	box.add_child(_play_button)

	_play_caption = _text(box, "", 24, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_play_caption.custom_minimum_size = Vector2(0.0, 48.0)
	return root


## Mengisi ulang markas dari SaveGame. Dipisah dari _build_home supaya layar
## dibangun sekali dan hanya datanya yang berubah.
func _refresh_home() -> void:
	var total := _stage_count()
	var cleared: int = mini(SaveGame.unlocked_stage, total)
	var current: int = clampi(SaveGame.unlocked_stage, 0, total - 1)
	var variant: Dictionary = GameConfig.dict("variants.%d" % _variant_for_stage(current))

	_profile_level.text = "LV %d" % (cleared + 1)
	_pill_best.text = "BEST %d" % SaveGame.best_score
	_pill_cards.text = "KARTU %d" % SaveGame.owned_cards.size()
	_map_subtitle.text = "%d / %d CLEARED" % [cleared, total]

	_chapter_kicker.text = "STAGE %02d / %d" % [current + 1, total]
	_chapter_name.text = String(variant.get("name", "?")).to_upper()
	_chapter_boss.text = "BOSS · %s" % String(variant.get("boss", "-")).replace("_", " ").to_upper()
	_chapter_desc.text = String(variant.get("description", ""))
	_set_pips(_chapter_stars, _rank(_difficulty_for_stage(current)))
	var theme_block: Dictionary = variant.get("theme", {})
	var accent: Color = UiTheme.palette(theme_block)["primary"]
	_chapter_lane.color = accent
	_chapter_panel.add_theme_stylebox_override("panel", UiTheme.pod(accent, 40, 0.9))
	_play_caption.text = "STAGE %02d · %s" % [current + 1, String(variant.get("name", "?")).to_upper()]

	for child in _map_list.get_children():
		child.queue_free()
		_map_list.remove_child(child)
	for stage in range(total):
		_map_list.add_child(_stage_card(stage, current))


## Satu kartu di rel. Stage terkunci tetap ditampilkan: melihat apa yang ada di
## depan adalah satu-satunya alasan layar pemilih stage ada.
func _stage_card(stage: int, unlocked: int) -> Button:
	var variant: Dictionary = GameConfig.dict("variants.%d" % _variant_for_stage(stage))
	var cleared := stage < SaveGame.unlocked_stage
	var locked := stage > unlocked
	var theme_block: Dictionary = variant.get("theme", {})
	var accent: Color = UiTheme.palette(theme_block)["primary"]
	if cleared:
		accent = UiTheme.GOLD
	if locked:
		accent = UiTheme.INK_DIM

	var button := Button.new()
	button.theme = _theme
	button.custom_minimum_size = Vector2(STAGE_CARD_W, STAGE_CARD_H)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = locked
	UiTheme.apply_chunky(button, Color(0.055, 0.09, 0.19), Color(0.01, 0.03, 0.07), 30)
	button.add_theme_stylebox_override(
		"normal", _card_face(accent, 0.10, stage == unlocked)
	)
	button.add_theme_stylebox_override("hover", _card_face(accent, 0.2, stage == unlocked))
	button.add_theme_stylebox_override("pressed", _card_face(accent, 0.3, stage == unlocked))
	button.add_theme_stylebox_override("disabled", _card_face(accent, 0.05, false))

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 16.0
	stack.offset_right = -16.0
	stack.offset_top = 18.0
	stack.offset_bottom = -18.0
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)

	var state := Label.new()
	state.text = "CLEARED" if cleared else ("LOCKED" if locked else "PLAY")
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(state, 22, accent, 0)
	stack.add_child(state)

	var art := ColorRect.new()
	art.color = Color(accent.r, accent.g, accent.b, 0.35)
	art.custom_minimum_size = Vector2(0.0, 70.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)

	var number := Label.new()
	number.text = "%02d" % (stage + 1)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(number, 52, UiTheme.INK_DIM if locked else UiTheme.INK, 0)
	stack.add_child(number)

	var name_label := Label.new()
	name_label.text = String(variant.get("name", "?"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(name_label, 24, UiTheme.INK_DIM if locked else UiTheme.INK, 0)
	stack.add_child(name_label)

	var sub := Label.new()
	sub.text = "x%.2f" % _difficulty_for_stage(stage)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(sub, 20, UiTheme.INK_DIM, 0)
	stack.add_child(sub)

	button.pressed.connect(func() -> void: stage_chosen.emit(stage))
	return button


func _card_face(accent: Color, fill: float, current: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.35 + fill)
	style.set_corner_radius_all(30)
	style.border_color = accent if current else Color(accent.r, accent.g, accent.b, 0.45)
	style.set_border_width_all(4 if current else 2)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 8)
	return style


# ---------------------------------------------------------------------------
# JEDA / HASIL / KARTU
# ---------------------------------------------------------------------------
func _build_pause() -> Control:
	var root := _screen_root()
	var box := _fill_column(root)
	box.add_child(_grow(1.0))
	_text(box, "JEDA", 84, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_spacer(60.0))
	box.add_child(_action("LANJUT", resume_pressed, UiTheme.GO, UiTheme.GO_DARK))
	box.add_child(_spacer(24.0))
	box.add_child(_action("ULANGI STAGE", restart_pressed))
	box.add_child(_spacer(24.0))
	box.add_child(_action("KELUAR KE MARKAS", menu_pressed))
	box.add_child(_grow(1.0))
	return root


func _build_result() -> Control:
	var root := _screen_root()
	var box := _fill_column(root)
	box.add_child(_grow(0.6))

	_result_title = _text(box, "MENANG", 96, _pal["primary"], HORIZONTAL_ALIGNMENT_CENTER)
	_result_subtitle = _text(box, "", 26, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_spacer(40.0))

	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 16)
	box.add_child(_result_rows)

	box.add_child(_spacer(48.0))
	_result_advance = Button.new()
	_result_advance.text = "COBA LAGI"
	_result_advance.theme = _theme
	_result_advance.custom_minimum_size = Vector2(0.0, BUTTON_H)
	_result_advance.focus_mode = Control.FOCUS_NONE
	_result_advance.add_theme_font_size_override("font_size", 50)
	UiTheme.apply_chunky(_result_advance, UiTheme.GO, UiTheme.GO_DARK)
	# One button, two meanings, so the win path does not need a second layout.
	_result_advance.pressed.connect(
		func() -> void:
			if _result_advance.text == "LANJUT":
				continue_pressed.emit()
			else:
				restart_pressed.emit()
	)
	box.add_child(_result_advance)
	box.add_child(_spacer(24.0))
	box.add_child(_action("KEMBALI KE MARKAS", menu_pressed))
	box.add_child(_grow(0.6))
	return root


## Upgrade draft between stages. `offers` is a list of card dictionaries from
## meta.cards; picking one emits card_chosen and the caller grants it.
func show_cards(offers: Array) -> void:
	for child in _card_list.get_children():
		child.queue_free()
		_card_list.remove_child(child)
	for entry in offers:
		var card: Dictionary = entry
		_card_list.add_child(_card_button(card))
	_swap(_cards)


func _build_cards() -> Control:
	var root := _screen_root()
	var box := _fill_column(root)
	box.add_child(_grow(0.8))
	_text(box, "PILIH UPGRADE", 76, _pal["primary"], HORIZONTAL_ALIGNMENT_CENTER)
	_text(box, "DIBAWA SAMPAI AKHIR KAMPANYE", 26, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_spacer(44.0))
	_card_list = VBoxContainer.new()
	_card_list.add_theme_constant_override("separation", 24)
	box.add_child(_card_list)
	box.add_child(_grow(1.0))
	return root


## One card as a single tap target. The labels sit inside the button with
## input ignored, so the whole slab is pressable rather than just the text.
func _card_button(card: Dictionary) -> Button:
	var button := Button.new()
	button.theme = _theme
	button.custom_minimum_size = Vector2(0.0, CARD_H)
	button.focus_mode = Control.FOCUS_NONE
	UiTheme.apply_chunky(button, Color(0.07, 0.13, 0.26), Color(0.01, 0.04, 0.09), 34)

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 40.0
	stack.offset_right = -40.0
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)

	var name_label := Label.new()
	name_label.text = String(card.get("name", "?"))
	UiTheme.style_label(name_label, 48, _pal["primary"], 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = String(card.get("desc", ""))
	UiTheme.style_label(desc_label, 30, UiTheme.INK_DIM, 0)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(desc_label)

	var card_id := String(card.get("id", ""))
	button.pressed.connect(func() -> void: card_chosen.emit(card_id))
	return button


func _stat_row(label_text: String, value_text: String, order: int = -1) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 24, 0.7))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	row.add_child(line)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(name_label, 30, UiTheme.INK_DIM, 0)
	line.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_label(value_label, 46, _pal["primary"], 0)
	line.add_child(value_label)
	if order >= 0:
		_count_up(value_label, value_text, order)
	return row


## Menghitung naik angka di satu baris hasil, tanpa merusak teks di sekitarnya.
##
## Nilainya datang sebagai string yang sudah diformat ("1240", "x4", "+35",
## "3/5"), jadi yang dianimasikan hanya bilangan bulat PERTAMA; awalan dan
## akhiran dibiarkan apa adanya. Baris tanpa angka — misalnya "—" ketika sebuah
## statistik tidak berlaku — dilewati, bukan dipaksa jadi nol.
func _count_up(label: Label, text: String, order: int) -> void:
	var digits := ""
	var start := -1
	for i in range(text.length()):
		if text[i] >= "0" and text[i] <= "9":
			if start < 0:
				start = i
			digits += text[i]
		elif start >= 0:
			break
	if start < 0 or digits.length() > 9:
		return
	var target := int(digits)
	if target <= 0:
		return
	var prefix := text.substr(0, start)
	var suffix := text.substr(start + digits.length())
	label.text = prefix + "0" + suffix
	var tween := create_tween()
	# Berurutan dari atas: tiap baris menunggu giliran, supaya mata punya
	# sesuatu untuk diikuti alih-alih lima angka yang berkedut bersamaan.
	tween.tween_interval(0.12 + float(order) * 0.14)
	tween.tween_method(
		func(value: float) -> void:
			if is_instance_valid(label):
				label.text = prefix + str(int(round(value))) + suffix,
		0.0,
		float(target),
		0.45
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
func _stage_count() -> int:
	return maxi(int(Cfg.num(GameConfig.dict("meta"), "stageCount", 15.0)), 1)


## Mirrors Game._variant_for_stage so the map names the arena the run will
## actually load.
func _variant_for_stage(stage: int) -> int:
	var cycle: Array = GameConfig.list("meta.variantCycle")
	if cycle.is_empty():
		return 0
	return int(cycle[stage % cycle.size()])


func _variant_name(stage: int) -> String:
	var variant: Dictionary = GameConfig.dict("variants.%d" % _variant_for_stage(stage))
	return String(variant.get("name", "?")).to_upper()


func _difficulty_for_stage(stage: int) -> float:
	var per: float = Cfg.num(GameConfig.dict("meta"), "difficultyPerStage", 0.12)
	return 1.0 + per * float(stage)


## Tiga tingkat kesulitan, dibaca sekilas lewat pip yang menyala.
func _rank(difficulty: float) -> int:
	if difficulty >= 1.9:
		return 3
	if difficulty >= 1.3:
		return 2
	return 1


## Menyalakan sejumlah pip pada deretan yang sudah dibangun.
func _set_pips(row: HBoxContainer, filled: int) -> void:
	if row == null:
		return
	var children := row.get_children()
	for i in range(children.size()):
		var pip := children[i] as Panel
		if pip == null:
			continue
		var tint: Color = UiTheme.GOLD if i < filled else UiTheme.INK_DIM.darkened(0.3)
		pip.add_theme_stylebox_override("panel", UiTheme.blob(tint, 10))


func _screen_root() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	return root


## Kolom yang mengisi layar penuh dengan margin aman. Tinggi tidak pernah
## diasumsikan: ruang ekstra pada layar jangkung dibagikan oleh _grow().
func _fill_column(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = SIDE
	box.offset_right = -SIDE
	box.offset_top = SAFE_TOP
	box.offset_bottom = -72.0
	parent.add_child(box)
	return box


func _grow(ratio: float) -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = ratio
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _text(
	parent: Node,
	value: String,
	size: int,
	tint: Color,
	alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(label, size, tint, 6)
	parent.add_child(label)
	return label


func _pill(parent: Node, value: String, tint: Color) -> Label:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.pod(tint, 34, 0.75))
	parent.add_child(pill)
	return _text(pill, value, 30, tint)


## Tombol sekunder bergaya game: tetap tebal, warnanya saja yang meredup.
func _action(
	text: String,
	target: Signal,
	face: Color = Color(0.1, 0.15, 0.27),
	foot: Color = Color(0.02, 0.04, 0.1)
) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = _theme
	button.custom_minimum_size = Vector2(0.0, BUTTON_H)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 44)
	UiTheme.apply_chunky(button, face, foot)
	button.pressed.connect(func() -> void: target.emit())
	return button
