extends CanvasLayer
## Portrait HUD, built to docs/06-ui-wireframe.md and skinned by UiTheme.
##
## Coordinates here are literal numbers from that document. The project
## stretches with "canvas_items" at 1080x1920 and match-width, so one unit in
## this file is one reference pixel no matter the device. Width is the
## critical dimension in portrait; height varies from 18:9 to 21:9, which is
## why nothing is positioned by assuming a 1920 tall screen.
##
## Two layout rules from the spec are load-bearing:
##   · The top 88px is never used. That is where notches and punch-holes live,
##     and a score hidden under a cutout is a bug report, not a style choice.
##   · The bottom third stays clear of anything the player must read, because
##     that is where the thumb sits during play.
##
## Colours come from the active variant, so the HUD changes with the arena
## instead of sitting on top of it like a different application.

# --- reference frame (docs/06) ---------------------------------------------
const REF_W := 1080.0
const SAFE_TOP := 88.0
const TOP_BAR_H := 140.0
const BOTTOM_BAR_TOP := -270.0
const SIDE_MARGIN := 48.0

const FLOAT_POOL := 32
const FLOAT_RISE := 90.0
const FLOAT_LIFE := 0.8

var _sim: SimWorld
var _camera: Camera3D
var _pal: Dictionary = {}

var _score_value: Label
var _score_caption: Label
var _combo: Label
var _wave: Label
var _squad: Label
var _squad_chip: PanelContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _steer_bar: ProgressBar
var _steer_secs: Label
var _charge_row: HBoxContainer
var _hp_row: HBoxContainer
var _flash: ColorRect
var _vignette: ColorRect
var _banner: Label
var _popup: Label

var _floats: Array[Label] = []
var _float_state: Array[Dictionary] = []

var _shown_score := 0.0
var _combo_pulse := 0.0
var _popup_time := 0.0
var _banner_time := 0.0
var _flash_time := 0.0
var _last_msec := 0


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_last_msec = Time.get_ticks_msec()
	_build_overlays()
	_build_top_bar()
	_build_boss_bar()
	_build_bottom_bar()
	_build_float_pool()


## Called by Game once a run starts.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim
	_shown_score = 0.0


## The HUD needs the camera to place floating text over world positions.
func bind_camera(camera: Camera3D) -> void:
	_camera = camera


## Pulls one frame of state. Reads only; the HUD never writes to the sim.
func render_frame() -> void:
	if _sim == null:
		return
	# Unscaled: slow-motion must not turn popups into slideshows.
	var now := Time.get_ticks_msec()
	var delta := clampf(float(now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now

	_drain_events()
	_update_score(delta)
	_update_combo(delta)
	_update_wave_and_squad()
	_update_boss()
	_update_steer()
	_update_charges()
	_update_hearts()
	_update_floats(delta)
	_update_overlays(delta)


func _drain_events() -> void:
	for event in _sim.events:
		match String(event.get("type", "")):
			"kill":
				_spawn_float(
					Vector2(float(event.get("x", 0.0)), float(event.get("z", 0.0))),
					"+%d" % int(event.get("score", 10)),
					UiTheme.GOLD
				)
			"gate_squad":
				var delta_troops := int(event.get("delta", 0))
				_spawn_float(
					Vector2(_sim.squad_x, SimWorld.SQUAD_Z + 1.5),
					"%+d" % delta_troops,
					_pal["primary"] if delta_troops >= 0 else UiTheme.DANGER
				)
			"combo_milestone":
				_show_popup("x%d COMBO" % int(event.get("combo", 0)))
			"life_lost":
				_flash_time = 0.4
			"boss_hit":
				_show_popup("CRITICAL")
			"victory":
				_show_banner("STAGE CLEAR", _pal["primary"])
			"defeat":
				_show_banner("OVERRUN", UiTheme.DANGER)


func _update_score(delta: float) -> void:
	# Count-up tween: the number climbing is the reward, not the final value.
	_shown_score = move_toward(
		_shown_score,
		float(_sim.score),
		maxf(absf(float(_sim.score) - _shown_score) * 8.0 * delta, 60.0 * delta)
	)
	_score_value.text = "%s" % int(round(_shown_score))


func _update_combo(delta: float) -> void:
	# Hidden below x2: showing "x1" is noise before the player has built
	# anything, and it trains them to ignore the spot where x30 will appear.
	var active: bool = _sim.combo > 1
	_combo.visible = active
	if not active:
		_combo_pulse = 0.0
		return
	_combo.text = "x%d" % _sim.combo
	_combo_pulse = maxf(_combo_pulse - delta * 4.0, 0.0)
	var scale := 1.0 + 0.15 * _combo_pulse
	_combo.pivot_offset = _combo.size * 0.5
	_combo.scale = Vector2(scale, scale)


func _update_wave_and_squad() -> void:
	var waves := GameConfig.integer("spawn.waveCount")
	_wave.text = "WAVE %d/%d" % [mini(_sim.wave_index + 1, waves), waves]
	_squad.text = "SQUAD  x%d" % _sim.troops
	# Squad count is health and damage at once, so it gets an early warning
	# state rather than only being noticed when the run is already lost.
	var low: bool = _sim.troops <= 5
	_squad.add_theme_color_override("font_color", UiTheme.DANGER if low else UiTheme.INK)
	_squad_chip.add_theme_stylebox_override(
		"panel", UiTheme.panel(UiTheme.DANGER if low else _pal["primary"], 16)
	)


func _update_boss() -> void:
	_boss_bar.visible = _sim.boss_active
	_boss_name.visible = _sim.boss_active
	if _sim.boss_active:
		_boss_bar.value = _sim.boss_hp / maxf(_sim.boss_hp_max, 1.0) * 100.0


func _update_steer() -> void:
	var riding: bool = _sim.chain_active and _sim.chain_riding
	var meter := _sim.chain_steer_meter
	var total := maxf(GameConfig.num("bullet.steerMeterDuration"), 0.01)
	_steer_bar.value = clampf(meter / total, 0.0, 1.0) * 100.0
	_steer_bar.modulate.a = 1.0 if riding else 0.25
	_steer_secs.modulate.a = _steer_bar.modulate.a
	_steer_secs.text = "%.1fs" % maxf(meter, 0.0)
	# Warning white in the last half second, before steering simply stops.
	var fill := _steer_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = UiTheme.INK if (riding and meter < 0.5) else _pal["primary"]


func _update_charges() -> void:
	var children := _charge_row.get_children()
	for i in range(children.size()):
		var pip := children[i] as Panel
		var style := pip.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		var ready: bool = i < _sim.chain_charges
		style.bg_color = _pal["primary"] if ready else Color(0, 0, 0, 0.25)
		style.border_color = _pal["primary"] if ready else Color(1, 1, 1, 0.18)


func _update_hearts() -> void:
	var children := _hp_row.get_children()
	for i in range(children.size()):
		var heart := children[i] as Label
		var alive: bool = i < _sim.lives
		heart.text = "♥" if alive else "♡"
		heart.modulate = UiTheme.DANGER if alive else Color(1, 1, 1, 0.22)


func _update_floats(delta: float) -> void:
	for i in range(_floats.size()):
		var state := _float_state[i]
		if not bool(state.get("active", false)):
			continue
		state["time"] = float(state["time"]) - delta
		if float(state["time"]) <= 0.0:
			state["active"] = false
			_floats[i].visible = false
			continue
		var age := 1.0 - float(state["time"]) / FLOAT_LIFE
		var label := _floats[i]
		label.position = Vector2(state["origin"]) - Vector2(0.0, FLOAT_RISE * age)
		# Quadratic fade: a linear fade reads as a stutter at the very end.
		label.modulate.a = 1.0 - age * age


func _update_overlays(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.color = Color(
			UiTheme.DANGER.r, UiTheme.DANGER.g, UiTheme.DANGER.b, _flash_time / 0.4 * 0.6
		)
	else:
		_flash.color = Color(UiTheme.DANGER.r, UiTheme.DANGER.g, UiTheme.DANGER.b, 0.0)

	# Slow-motion vignette rides the same state the simulation uses, so the
	# visual and the mechanic can never disagree about how slow things are.
	var slow := 1.0 if _sim.chain_riding else 0.0
	_vignette.modulate.a = lerpf(_vignette.modulate.a, slow * 0.42, delta * 5.0)

	if _popup_time > 0.0:
		_popup_time -= delta
		var scale := 1.25 if _popup_time > 0.85 else 1.0
		_popup.pivot_offset = _popup.size * 0.5
		_popup.scale = Vector2(scale, scale)
		_popup.modulate.a = clampf(_popup_time / 0.25, 0.0, 1.0)
	else:
		_popup.visible = false

	if _banner_time > 0.0:
		_banner_time -= delta


func _spawn_float(world_xz: Vector2, text: String, tint: Color) -> void:
	if _camera == null:
		return
	var screen := _camera.unproject_position(Vector3(world_xz.x, 0.8, -world_xz.y))
	for i in range(_floats.size()):
		if bool(_float_state[i].get("active", false)):
			continue
		_float_state[i] = {"active": true, "time": FLOAT_LIFE, "origin": screen}
		var label := _floats[i]
		label.text = text
		label.modulate = tint
		label.position = screen
		label.visible = true
		return
	# Pool exhausted: aggregate instead of allocating. One readable number
	# beats thirty overlapping ones, and it costs nothing extra.
	_show_popup(text)


func _show_popup(text: String) -> void:
	_popup.text = text
	_popup.visible = true
	_popup_time = 0.97


func _show_banner(text: String, tint: Color) -> void:
	_banner.text = text
	_banner.modulate = tint
	_banner.visible = true
	_banner_time = 2.0


func _build_top_bar() -> void:
	var score_chip := _chip(Vector2(SIDE_MARGIN, SAFE_TOP), Vector2(380.0, 122.0), 20)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", -6)
	score_chip.add_child(score_box)
	_score_value = _label("0", 68, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, score_box)
	_score_caption = _label("SCORE", 26, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, score_box)

	_combo = _label("", 84, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_combo, Vector2(REF_W * 0.5 - 220.0, SAFE_TOP + 10.0), Vector2(440.0, 100.0))

	var wave_chip := _chip(Vector2(REF_W - SIDE_MARGIN - 340.0, SAFE_TOP), Vector2(340.0, 56.0), 16)
	_wave = _label("WAVE 1/5", 38, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, wave_chip)

	_squad_chip = _chip(
		Vector2(REF_W - SIDE_MARGIN - 340.0, SAFE_TOP + 66.0), Vector2(340.0, 56.0), 16
	)
	_squad = _label("SQUAD  x5", 36, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, _squad_chip)


func _build_boss_bar() -> void:
	_boss_name = _label("BOSS", 32, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_place(
		_boss_name,
		Vector2(SIDE_MARGIN, SAFE_TOP + TOP_BAR_H + 12.0),
		Vector2(REF_W - SIDE_MARGIN * 2.0, 40.0)
	)
	_boss_bar = _bar(UiTheme.DANGER)
	_place(
		_boss_bar,
		Vector2(SIDE_MARGIN, SAFE_TOP + TOP_BAR_H + 56.0),
		Vector2(REF_W - SIDE_MARGIN * 2.0, 22.0)
	)
	_boss_bar.visible = false
	_boss_name.visible = false


func _build_bottom_bar() -> void:
	_steer_bar = _bar(_pal["primary"])
	_anchor_bottom(
		_steer_bar,
		Vector2(SIDE_MARGIN, BOTTOM_BAR_TOP),
		Vector2(REF_W - SIDE_MARGIN * 2.0 - 120.0, 24.0)
	)
	_steer_secs = _label("0.0s", 32, _pal["primary"], HORIZONTAL_ALIGNMENT_RIGHT)
	_anchor_bottom(
		_steer_secs,
		Vector2(REF_W - SIDE_MARGIN - 110.0, BOTTOM_BAR_TOP - 8.0),
		Vector2(110.0, 40.0)
	)

	_charge_row = HBoxContainer.new()
	_charge_row.add_theme_constant_override("separation", 12)
	_charge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom(_charge_row, Vector2(SIDE_MARGIN, BOTTOM_BAR_TOP + 90.0), Vector2(400.0, 44.0))
	add_child(_charge_row)
	for _i in range(GameConfig.integer("squad.chainShot.maxCharges")):
		_charge_row.add_child(_charge_pip())

	_hp_row = HBoxContainer.new()
	_hp_row.add_theme_constant_override("separation", 10)
	_hp_row.alignment = BoxContainer.ALIGNMENT_END
	_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom(
		_hp_row, Vector2(REF_W - SIDE_MARGIN - 230.0, BOTTOM_BAR_TOP + 78.0), Vector2(230.0, 64.0)
	)
	add_child(_hp_row)
	for _i in range(GameConfig.integer("player.lives")):
		var heart := Label.new()
		heart.text = "♥"
		heart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heart.custom_minimum_size = Vector2(64.0, 64.0)
		UiTheme.style_label(heart, 56, UiTheme.DANGER)
		_hp_row.add_child(heart)


func _build_overlays() -> void:
	_vignette = ColorRect.new()
	_vignette.color = Color("#00344D")
	_vignette.modulate.a = 0.0
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)

	_flash = ColorRect.new()
	_flash.color = Color(UiTheme.DANGER.r, UiTheme.DANGER.g, UiTheme.DANGER.b, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_popup = _label("", 88, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.offset_left = -REF_W * 0.5
	_popup.offset_right = REF_W * 0.5
	_popup.offset_top = -240.0
	_popup.offset_bottom = -140.0
	_popup.visible = false

	_banner = _label("", 96, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -REF_W * 0.5
	_banner.offset_right = REF_W * 0.5
	_banner.offset_top = -60.0
	_banner.offset_bottom = 60.0
	_banner.visible = false


func _build_float_pool() -> void:
	for _i in range(FLOAT_POOL):
		var label := _label("", 40, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		label.size = Vector2(200.0, 48.0)
		label.pivot_offset = Vector2(100.0, 24.0)
		label.visible = false
		_floats.append(label)
		_float_state.append({"active": false, "time": 0.0, "origin": Vector2.ZERO})


func _chip(at: Vector2, size: Vector2, radius: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UiTheme.panel(_pal["primary"], radius))
	_place(chip, at, size)
	add_child(chip)
	return chip


func _label(text: String, size: int, tint: Color, alignment: int, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_label(label, size, tint)
	if parent == null:
		add_child(label)
	else:
		parent.add_child(label)
	return label


func _bar(tint: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(tint))
	bar.add_theme_stylebox_override("background", UiTheme.bar_track(_pal))
	add_child(bar)
	return bar


func _charge_pip() -> Panel:
	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(44.0, 44.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.25)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	pip.add_theme_stylebox_override("panel", style)
	return pip


func _place(control: Control, at: Vector2, size: Vector2) -> void:
	control.offset_left = at.x
	control.offset_top = at.y
	control.offset_right = at.x + size.x
	control.offset_bottom = at.y + size.y


func _anchor_bottom(control: Control, at: Vector2, size: Vector2) -> void:
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = at.x
	control.offset_top = at.y
	control.offset_right = at.x + size.x
	control.offset_bottom = at.y + size.y
