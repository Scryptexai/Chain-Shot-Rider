class_name SetupScreen
extends Control

## Layar pengaturan — satu-satunya layar yang paling gampang berubah jadi
## formulir.
##
## Aturan yang dijaga di sini: tidak ada slider, tidak ada daftar baris polos,
## tidak ada tombol merah sekali tekan. Volume adalah meteran balok yang bisa
## ditekan tanpa melihat, dan menghapus progres harus ditahan selama 1,2 detik.
## Itu bahasa game; sisanya bahasa aplikasi, dan aplikasi bukan yang sedang
## dibangun.

signal closed
signal progress_wiped

const SIDE := 48.0
const SAFE_TOP := 96.0
const BUTTON_H := 150.0

var _pal: Dictionary = {}
var _theme: Theme
var _volume_cells: Array[Button] = []
var _volume_caption: Label
var _hold_fill: ColorRect
var _hold_tween: Tween
var _hold_caption: Label
var _back_button: Button
var _pods: Dictionary = {}


func build(pal: Dictionary, theme: Theme) -> void:
	_pal = pal
	_theme = theme
	# HARUS anchors_and_offsets: layar ini sudah berada di dalam CanvasLayer saat
	# build() dipanggil, dan set_anchors_preset() sendirian mempertahankan ukuran
	# lama (nol) dengan cara menulis offset negatif — hasilnya kolom gepeng di
	# pojok kiri atas.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_screen()
	# Volume tersimpan harus berlaku sejak nada pertama, bukan setelah pemain
	# membuka layar ini.
	_apply_volume()
	refresh()


## Kolom yang mengisi layar penuh dengan margin aman, sama seperti layar lain.
func _fill_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = SIDE
	box.offset_right = -SIDE
	box.offset_top = SAFE_TOP
	box.offset_bottom = -72.0
	add_child(box)
	return box


func _grow(ratio: float) -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = ratio
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


## Layar pengaturan. Bahasa visualnya tetap bahasa game: tidak ada slider,
## tidak ada baris formulir, tidak ada tombol merah polos.
func _build_screen() -> void:
	var box := _fill_column()

	var head := HBoxContainer.new()
	box.add_child(head)
	_text(head, "SETUP", 56, UiTheme.INK)
	var head_push := Control.new()
	head_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_push)

	box.add_child(_grow(0.2))

	# --- VOLUME sebagai lima balok, bukan slider -----------------------------
	#
	# Slider adalah kontrol aplikasi: butuh presisi jempol pada garis setebal
	# empat piksel, dan nilainya tidak berarti apa-apa bagi pemain. Lima balok
	# bertingkat bisa ditekan tanpa melihat, besar di layar, dan terbaca
	# seperti meteran — bahasa yang sama dengan bar nyawa di HUD.
	var audio_panel := PanelContainer.new()
	audio_panel.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 34, 0.85))
	box.add_child(audio_panel)
	var audio_box := VBoxContainer.new()
	audio_box.add_theme_constant_override("separation", 14)
	audio_panel.add_child(audio_box)
	var audio_head := HBoxContainer.new()
	audio_box.add_child(audio_head)
	_text(audio_head, "VOLUME", 32, UiTheme.INK)
	var audio_push := Control.new()
	audio_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_head.add_child(audio_push)
	_volume_caption = _text(audio_head, "4 / 5", 28, UiTheme.INK_DIM)

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 10)
	audio_box.add_child(cells)
	_volume_cells.clear()
	for level in range(6):
		var cell := Button.new()
		cell.theme = _theme
		cell.focus_mode = Control.FOCUS_NONE
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Tinggi menanjak: meteran yang bentuknya saja sudah memberi tahu arah
		# "lebih keras", bahkan tanpa warna.
		cell.custom_minimum_size = Vector2(0.0, 72.0 + float(level) * 14.0)
		cell.text = "OFF" if level == 0 else "%d" % level
		cell.add_theme_font_size_override("font_size", 24)
		cell.pressed.connect(func() -> void: _set_volume(float(level) / 5.0))
		cells.add_child(cell)
		_volume_cells.append(cell)

	box.add_child(_grow(0.2))

	# --- kontrol -------------------------------------------------------------
	var keys := PanelContainer.new()
	keys.add_theme_stylebox_override("panel", UiTheme.pod(UiTheme.INK_DIM, 34, 0.5))
	box.add_child(keys)
	var keys_box := VBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 6)
	keys.add_child(keys_box)
	_text(keys_box, "KONTROL", 28, UiTheme.INK)
	_text(keys_box, "GESER  ·  gerakkan squad, belokkan peluru", 24, UiTheme.INK_DIM)
	_text(keys_box, "TAP  ·  chain shot", 24, UiTheme.INK_DIM)
	_text(keys_box, "ESC  ·  jeda", 24, UiTheme.INK_DIM)

	box.add_child(_grow(0.25))

	# --- status: angka progres sebagai pod, bukan tabel -----------------------
	#
	# Sisi web menaruh diagnostiknya di layar yang sama; paritasnya dijaga di
	# sini, dengan bentuk yang sama pula: pod angka besar, karena tabel
	# kunci-nilai adalah bahasa panel admin.
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UiTheme.pod(UiTheme.INK_DIM, 34, 0.5))
	box.add_child(status)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 12)
	status.add_child(status_box)
	_text(status_box, "STATUS", 28, UiTheme.INK)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	status_box.add_child(grid)
	for key in ["STAGE TERBUKA", "SKOR TERBAIK", "KARTU", "KOIN"]:
		grid.add_child(_pod(key))

	box.add_child(_grow(0.75))

	# --- hapus progres: ditahan, bukan diklik --------------------------------
	#
	# Tombol merah sekali tekan adalah cara tercepat seorang pemain kehilangan
	# lima belas stage karena jempol yang meleset. Menahan selama 1,2 detik
	# memberi jalan keluar, dan batang yang terisi adalah umpan baliknya.
	var danger := PanelContainer.new()
	danger.add_theme_stylebox_override("panel", UiTheme.pod(UiTheme.DANGER, 30, 0.7))
	box.add_child(danger)
	var danger_box := VBoxContainer.new()
	danger_box.add_theme_constant_override("separation", 10)
	danger.add_child(danger_box)
	_hold_caption = _text(danger_box, "TAHAN UNTUK HAPUS PROGRES", 26, UiTheme.DANGER)

	var hold_button := Button.new()
	hold_button.theme = _theme
	hold_button.focus_mode = Control.FOCUS_NONE
	hold_button.custom_minimum_size = Vector2(0.0, 110.0)
	hold_button.add_theme_font_size_override("font_size", 30)
	hold_button.text = "HAPUS"
	UiTheme.apply_chunky(hold_button, Color(0.35, 0.09, 0.14), Color(0.16, 0.03, 0.06), 30)
	danger_box.add_child(hold_button)

	var track := Control.new()
	track.custom_minimum_size = Vector2(0.0, 12.0)
	danger_box.add_child(track)
	_hold_fill = ColorRect.new()
	_hold_fill.color = UiTheme.DANGER
	_hold_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_hold_fill.anchor_right = 0.0
	_hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_hold_fill)

	hold_button.button_down.connect(_start_hold)
	hold_button.button_up.connect(_cancel_hold)

	_back_button = Button.new()
	var back := _back_button
	back.theme = _theme
	back.focus_mode = Control.FOCUS_NONE
	back.text = "KEMBALI"
	back.custom_minimum_size = Vector2(0.0, BUTTON_H * 0.72)
	back.add_theme_font_size_override("font_size", 40)
	UiTheme.apply_chunky(back, Color(0.12, 0.17, 0.3), Color(0.03, 0.05, 0.12))
	back.pressed.connect(
		func() -> void:
			_cancel_hold()
			closed.emit()
	)
	box.add_child(back)


## Menyalakan balok volume sampai level yang aktif.
func refresh() -> void:
	var level := int(round(SaveGame.volume * 5.0))
	for i in range(_volume_cells.size()):
		# Balok OFF hanya menyala saat benar-benar senyap; kalau ikut menyala
		# bersama yang lain, meteran malah membaca "mati DAN keras".
		var on: bool = i > 0 and i <= level
		var face: Color = _pal["primary"].darkened(0.35) if on else Color(0.11, 0.15, 0.26)
		if i == 0 and level == 0:
			face = UiTheme.DANGER.darkened(0.45)
		UiTheme.apply_chunky(_volume_cells[i], face, face.darkened(0.5), 20)
	_volume_caption.text = "SENYAP" if level == 0 else "%d / 5" % level

	var total := int(Cfg.num(GameConfig.dict("meta"), "stageCount", 15.0))
	_pods["STAGE TERBUKA"].text = "%d / %d" % [mini(SaveGame.unlocked_stage + 1, total), total]
	_pods["SKOR TERBAIK"].text = "%d" % SaveGame.best_score
	_pods["KARTU"].text = "%d" % SaveGame.owned_cards.size()
	_pods["KOIN"].text = "%d" % SaveGame.coins


## Satu pod angka. Nilainya diisi oleh refresh(), bukan saat dibangun.
func _pod(key: String) -> PanelContainer:
	var pod := PanelContainer.new()
	pod.add_theme_stylebox_override("panel", UiTheme.pod(Color(0.04, 0.08, 0.18), 22, 0.9))
	pod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	pod.add_child(col)
	_text(col, key, 18, UiTheme.INK_DIM)
	_pods[key] = _text(col, "0", 34, _pal["primary"])
	return pod


func _set_volume(value: float) -> void:
	SaveGame.volume = clampf(value, 0.0, 1.0)
	SaveGame.save_progress()
	_apply_volume()
	refresh()


## Satu-satunya tempat yang menyentuh bus Master, supaya "senyap" berarti
## senyap dan bukan "hampir senyap tapi masih bocor dari satu bus".
func _apply_volume() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	AudioServer.set_bus_mute(master, SaveGame.volume <= 0.001)
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(SaveGame.volume, 0.0001)))


func _start_hold() -> void:
	_cancel_hold()
	_hold_caption.text = "TAHAN TERUS…"
	_hold_tween = create_tween()
	_hold_tween.tween_property(_hold_fill, "anchor_right", 1.0, 1.2)
	_hold_tween.tween_callback(
		func() -> void:
			SaveGame.reset_progress()
			_hold_caption.text = "PROGRES DIHAPUS"
			_hold_fill.anchor_right = 0.0
			progress_wiped.emit()
	)


func _cancel_hold() -> void:
	if _hold_tween != null and _hold_tween.is_valid():
		_hold_tween.kill()
	_hold_tween = null
	if _hold_fill != null:
		_hold_fill.anchor_right = 0.0
	if _hold_caption != null and _hold_caption.text == "TAHAN TERUS…":
		_hold_caption.text = "TAHAN UNTUK HAPUS PROGRES"
