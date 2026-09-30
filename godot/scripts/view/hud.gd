extends CanvasLayer
## Portrait HUD. Built in code so the layout rules stay readable as rules.
##
## The safe area matters more than it looks: on a notched portrait phone the
## top 12% is where the score would naturally sit and also where the cutout
## is. Anchors here keep every readable element inside the safe rect, and the
## bottom third is left clear because that is where the thumb lives.

const TOP_MARGIN := 120.0
const SIDE_MARGIN := 48.0

var _sim: SimWorld
var _score_label: Label
var _troops_label: Label
var _wave_label: Label
var _charge_bar: ProgressBar
var _boss_bar: ProgressBar
var _banner: Label


func _ready() -> void:
	_score_label = _make_label(Vector2(SIDE_MARGIN, TOP_MARGIN), HORIZONTAL_ALIGNMENT_LEFT, 56)
	_wave_label = _make_label(
		Vector2(SIDE_MARGIN, TOP_MARGIN + 70.0), HORIZONTAL_ALIGNMENT_LEFT, 40
	)
	_troops_label = _make_label(
		Vector2(-SIDE_MARGIN - 300.0, TOP_MARGIN), HORIZONTAL_ALIGNMENT_RIGHT, 56
	)
	_troops_label.anchor_left = 1.0
	_troops_label.anchor_right = 1.0
	_charge_bar = _make_bar(Vector2(SIDE_MARGIN, -220.0), Color(1.0, 0.55, 0.2))
	_boss_bar = _make_bar(Vector2(SIDE_MARGIN, TOP_MARGIN + 130.0), Color(0.9, 0.25, 0.3))
	_boss_bar.visible = false
	_banner = _make_label(Vector2(-300.0, -600.0), HORIZONTAL_ALIGNMENT_CENTER, 72)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.visible = false


## Called by Game once a run starts.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim


## Pulls one frame of state. Reads only; the HUD never writes to the sim.
func render_frame() -> void:
	if _sim == null:
		return
	_score_label.text = "%d" % _sim.score
	_troops_label.text = "x%d" % _sim.troops
	_wave_label.text = "WAVE %d  ·  LIVES %d" % [_sim.wave_index + 1, _sim.lives]
	_charge_bar.value = _charge_fraction() * 100.0
	_boss_bar.visible = _sim.boss_active
	if _sim.boss_active:
		_boss_bar.value = _sim.boss_hp / maxf(_sim.boss_hp_max, 1.0) * 100.0
	_update_banner()


func _charge_fraction() -> float:
	if _sim.chain_charges > 0:
		return 1.0
	return clampf(_sim.chain_charge, 0.0, 1.0)


func _update_banner() -> void:
	if _sim.state == SimWorld.State.VICTORY:
		_banner.text = "STAGE CLEAR"
		_banner.visible = true
	elif _sim.state == SimWorld.State.DEFEAT:
		_banner.text = "OVERRUN"
		_banner.visible = true


func _make_label(offset: Vector2, alignment: int, size: int) -> Label:
	var label := Label.new()
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x + 600.0
	label.offset_bottom = offset.y + float(size) + 12.0
	if offset.y < 0.0:
		label.anchor_top = 1.0
		label.anchor_bottom = 1.0
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label


func _make_bar(offset: Vector2, tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.offset_left = offset.x
	bar.offset_top = offset.y
	bar.offset_right = -SIDE_MARGIN
	bar.offset_bottom = offset.y + 28.0
	bar.anchor_right = 1.0
	if offset.y < 0.0:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.corner_radius_top_left = 6
	fill.corner_radius_top_right = 6
	fill.corner_radius_bottom_left = 6
	fill.corner_radius_bottom_right = 6
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.08, 0.09, 0.13, 0.75)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	add_child(bar)
	return bar
