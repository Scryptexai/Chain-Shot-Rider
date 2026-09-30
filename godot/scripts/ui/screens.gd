extends CanvasLayer
## Menu, pause and result screens from docs/06.3, skinned by UiTheme.
##
## One CanvasLayer holds all three because they are mutually exclusive and
## share a skin; three scenes would mean three places to update when the
## palette changes. Only one root is ever visible.
##
## Touch-first rules applied throughout:
##   · Buttons are 120px tall with 24px gaps. Below roughly 90px, thumbs miss.
##   · Nothing important sits in the top 88px safe area.
##   · Every screen dims the game behind it, so it is always obvious whether
##     the simulation is running or waiting for you.

signal play_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed

const REF_W := 1080.0
const SAFE_TOP := 88.0
const BUTTON_H := 120.0

var _pal: Dictionary = {}
var _theme: Theme
var _scrim: ColorRect
var _menu: Control
var _pause: Control
var _result: Control
var _result_title: Label
var _result_rows: VBoxContainer
var _menu_best: Label


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_theme = UiTheme.build(_pal)
	_build_scrim()
	_menu = _build_menu()
	_pause = _build_pause()
	_result = _build_result()
	show_menu()


## Main menu, shown on boot.
func show_menu() -> void:
	_menu_best.text = "BEST  %d        COINS  %d" % [SaveGame.best_score, SaveGame.coins]
	_swap(_menu)


## Pause overlay.
func show_pause() -> void:
	_swap(_pause)


## Result screen. Rows are built from the run, not from a fixed template,
## so adding a stat later does not mean re-laying out the screen.
func show_result(won: bool, rows: Array) -> void:
	_result_title.text = "VICTORY" if won else "DEFEAT"
	_result_title.add_theme_color_override("font_color", _pal["primary"] if won else UiTheme.DANGER)
	for child in _result_rows.get_children():
		child.queue_free()
	for entry in rows:
		var row: Dictionary = entry
		_result_rows.add_child(
			_stat_row(String(row.get("label", "")), String(row.get("value", "")))
		)
	_swap(_result)


## Hides every screen and hands control back to the game.
func hide_all() -> void:
	_swap(null)


func _swap(target: Control) -> void:
	for screen in [_menu, _pause, _result]:
		if screen != null:
			screen.visible = screen == target
	_scrim.visible = target != null
	# Screens must keep receiving input while the game is paused.
	visible = true


func _build_scrim() -> void:
	_scrim = ColorRect.new()
	var bottom: Color = _pal["bg_bottom"]
	_scrim.color = Color(bottom.r, bottom.g, bottom.b, 0.78)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)


func _build_menu() -> Control:
	var root := _screen_root()
	var box := _column(root, 260.0, 900.0)

	var title := Label.new()
	title.text = "CHAIN RIDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(title, 104, _pal["primary"], 12)
	box.add_child(title)

	var tagline := Label.new()
	tagline.text = "RIDE THE RICOCHET"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(tagline, 32, UiTheme.INK_DIM)
	box.add_child(tagline)

	box.add_child(_spacer(80.0))
	box.add_child(_button("PLAY", play_pressed))
	box.add_child(_spacer(24.0))

	_menu_best = Label.new()
	_menu_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(_menu_best, 30, UiTheme.INK_DIM)
	box.add_child(_menu_best)
	return root


func _build_pause() -> Control:
	var root := _screen_root()
	var box := _column(root, 420.0, 760.0)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(title, 72, UiTheme.INK)
	box.add_child(title)

	box.add_child(_spacer(60.0))
	box.add_child(_button("RESUME", resume_pressed))
	box.add_child(_spacer(24.0))
	box.add_child(_button("RESTART", restart_pressed))
	box.add_child(_spacer(24.0))
	box.add_child(_button("MENU", menu_pressed))
	return root


func _build_result() -> Control:
	var root := _screen_root()
	var box := _column(root, 360.0, 880.0)

	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_label(_result_title, 88, _pal["primary"], 12)
	box.add_child(_result_title)

	box.add_child(_spacer(40.0))

	var slab := PanelContainer.new()
	slab.add_theme_stylebox_override("panel", UiTheme.slab(_pal))
	box.add_child(slab)
	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 18)
	slab.add_child(_result_rows)

	box.add_child(_spacer(48.0))
	box.add_child(_button("RETRY", restart_pressed))
	box.add_child(_spacer(24.0))
	box.add_child(_button("MENU", menu_pressed))
	return root


func _stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_label(name_label, 34, UiTheme.INK_DIM, 0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_label(value_label, 40, UiTheme.INK, 0)
	row.add_child(value_label)
	return row


func _screen_root() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	return root


func _column(parent: Control, top: float, height: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_left = 90.0
	box.offset_right = -90.0
	box.offset_top = maxf(top, SAFE_TOP)
	box.offset_bottom = top + height
	parent.add_child(box)
	return box


func _button(text: String, target: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.theme = _theme
	button.custom_minimum_size = Vector2(0.0, BUTTON_H)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: target.emit())
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
