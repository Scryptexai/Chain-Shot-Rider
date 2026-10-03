class_name SquadScreen
extends Control

## Layar SQUAD — apa yang sebenarnya dibawa pemain ke arena.
##
## Sebelum ini Godot hanya menunjukkan ANGKA kartu di markas ("KARTU 3"), jadi
## satu-satunya cara tahu upgrade apa yang aktif adalah mengingatnya sendiri.
## Prototipe web sudah punya daftarnya; layar ini menutup celah itu sekaligus
## menjawab pertanyaan yang lebih penting daripada "kartu apa saja": berapa
## kuat squad-nya sekarang. Karena itu lembar statistik datang lebih dulu,
## kartunya menyusul di bawah.

signal closed

const SIDE := 48.0
const SAFE_TOP := 96.0
const BUTTON_H := 150.0

## Urutan pod statistik. Ditulis tangan, bukan hasil iterasi Dictionary, supaya
## posisinya tidak pernah berpindah-pindah di antara dua kali buka layar.
const STAT_ROWS: Array[Array] = [
	["autoDamageMul", "DAMAGE AUTO", "x"],
	["fireRateMul", "RATE TEMBAK", "x"],
	["chainDamageMul", "DAMAGE CHAIN", "x"],
	["bounceBudget", "PANTULAN", "+"],
	["chargeRateMul", "ISI ULANG", "x"],
	["moveSpeedMul", "GERAK", "x"],
	["startTroops", "PASUKAN AWAL", "+"],
	["negativeSideChance", "GATE BURUK", "x"],
]

var _pal: Dictionary = {}
var _theme: Theme
var _back_button: Button
var _card_list: VBoxContainer
var _empty_note: Control
var _stat_values: Dictionary = {}
var _count_label: Label


func build(pal: Dictionary, theme: Theme) -> void:
	_pal = pal
	_theme = theme
	# anchors_and_offsets, bukan set_anchors_preset: layar ini sudah berada di
	# dalam CanvasLayer, dan preset tanpa offset mempertahankan ukuran nol.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_screen()
	refresh()


## Mengisi ulang dari SaveGame. Dipanggil tiap kali layar dibuka, karena kartu
## bisa bertambah di antara dua kunjungan.
func refresh() -> void:
	var upgrades: Dictionary = SaveGame.active_upgrades()
	for row in STAT_ROWS:
		var stat: String = row[0]
		var sign: String = row[2]
		var label: Label = _stat_values[stat]
		var neutral: float = 1.0 if sign == "x" else 0.0
		var value: float = float(upgrades.get(stat, neutral))
		var owned: bool = not is_equal_approx(value, neutral)
		if sign == "x":
			label.text = "x%.2f" % value
		else:
			label.text = "+%d" % int(round(value))
		# Yang belum diubah kartu dibiarkan redup: lembar statistik harus bisa
		# dibaca sekilas sebagai "ini yang sudah kamu naikkan".
		UiTheme.style_label(label, 32, _pal["primary"] if owned else UiTheme.INK_DIM, 0)

	for child in _card_list.get_children():
		child.queue_free()
		_card_list.remove_child(child)
	var cards: Array = GameConfig.list("meta.cards")
	for card_id in SaveGame.owned_cards:
		_card_list.add_child(_card_row(String(card_id), cards))
	_empty_note.visible = SaveGame.owned_cards.is_empty()
	_count_label.text = "%d KARTU" % SaveGame.owned_cards.size()


func _build_screen() -> void:
	var box := _fill_column()

	var head := HBoxContainer.new()
	box.add_child(head)
	_text(head, "SQUAD", 56, UiTheme.INK)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(push)

	box.add_child(_grow(0.2))

	# --- lembar statistik ----------------------------------------------------
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 34, 0.85))
	box.add_child(sheet)
	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 12)
	sheet.add_child(sheet_box)
	var sheet_head := HBoxContainer.new()
	sheet_box.add_child(sheet_head)
	_text(sheet_head, "KEKUATAN", 32, UiTheme.INK)
	var sheet_push := Control.new()
	sheet_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_head.add_child(sheet_push)
	_text(sheet_head, "DARI KARTU", 22, UiTheme.INK_DIM)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sheet_box.add_child(grid)
	for row in STAT_ROWS:
		grid.add_child(_stat_pod(String(row[0]), String(row[1])))

	box.add_child(_spacer(22.0))

	# --- kartu yang dimiliki -------------------------------------------------
	var list_head := HBoxContainer.new()
	box.add_child(list_head)
	_text(list_head, "KARTU AKTIF", 30, UiTheme.INK)
	var list_push := Control.new()
	list_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(list_push)
	# Hitungannya, bukan ajakan "GULIR": layar yang menyuruh menggulir padahal
	# tidak ada yang bisa digulir adalah kebohongan kecil yang mahal.
	_count_label = _text(list_head, "0 KARTU", 22, UiTheme.INK_DIM)

	# Daftar digulir, bukan dipaksa muat: delapan kartu adalah batas atas dan
	# memaksanya masuk satu layar akan mengecilkan teksnya sampai tidak terbaca.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)

	_card_list = VBoxContainer.new()
	_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_list.add_theme_constant_override("separation", 12)
	inner.add_child(_card_list)
	_empty_note = _empty_state()
	inner.add_child(_empty_note)

	box.add_child(_spacer(22.0))

	_back_button = Button.new()
	_back_button.theme = _theme
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.text = "KEMBALI"
	_back_button.custom_minimum_size = Vector2(0.0, BUTTON_H * 0.72)
	_back_button.add_theme_font_size_override("font_size", 40)
	UiTheme.apply_chunky(_back_button, Color(0.12, 0.17, 0.3), Color(0.03, 0.05, 0.12))
	_back_button.pressed.connect(func() -> void: closed.emit())
	box.add_child(_back_button)


func _stat_pod(stat: String, key: String) -> PanelContainer:
	var pod := PanelContainer.new()
	pod.add_theme_stylebox_override("panel", UiTheme.pod(Color(0.04, 0.08, 0.18), 22, 0.9))
	pod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	pod.add_child(col)
	_text(col, key, 18, UiTheme.INK_DIM)
	_stat_values[stat] = _text(col, "x1.00", 32, UiTheme.INK_DIM)
	return pod


## Satu kartu milik pemain. Bentuknya mengikuti kartu draft supaya benda yang
## sama tidak berganti rupa setelah dipungut.
func _card_row(card_id: String, cards: Array) -> PanelContainer:
	var name_text := card_id
	var desc_text := ""
	for entry in cards:
		var card: Dictionary = entry
		if String(card.get("id", "")) == card_id:
			name_text = String(card.get("name", card_id))
			desc_text = String(card.get("desc", ""))
			break

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 26, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiTheme.blob(_pal["primary"], 18))
	badge.custom_minimum_size = Vector2(72.0, 72.0)
	row.add_child(badge)
	var mark := _text(badge, "LV", 26, Color(0.02, 0.07, 0.12))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_text(col, name_text.to_upper(), 28, UiTheme.INK)
	var desc := _text(col, desc_text, 22, UiTheme.INK_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return panel


func _empty_state() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.pod(UiTheme.INK_DIM, 26, 0.45))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := _text(col, "BELUM ADA UPGRADE", 28, UiTheme.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _text(col, "Menangkan satu stage untuk menarik kartu pertama.", 22, UiTheme.INK_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return panel


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
