extends CanvasLayer
## HUD portrait, dibangun ulang mengikuti bahasa UI game squad-runner mobile
## (Last War, Top War, Survivor.io) dan diskin oleh UiTheme.
##
## Kerangka acuannya 1080 px lebar (project memakai stretch "canvas_items" +
## match-width), jadi satu angka di file ini = satu piksel acuan di perangkat
## apa pun. Tinggi TIDAK pernah diasumsikan 1920: ponsel modern 19,5:9 sampai
## 20:9, dan ruang ekstra itu memang sengaja jatuh ke dek atas/bawah. Semua
## elemen bawah karena itu di-anchor ke tepi bawah, bukan ke koordinat tetap.
##
## Aturan tata letak yang menentukan bentuknya:
##   · 88 px teratas tidak dipakai — itu wilayah notch dan punch-hole.
##   · Aksi hidup di sepertiga bawah, dalam jangkauan jempol: tombol chain shot
##     bundar 230 px di kanan bawah, nyawa di kiri bawah.
##   · Yang boleh dibaca saat bermain cuma empat: skor, progres wave, jumlah
##     pasukan, dan kesiapan chain shot. Sisanya (FPS, tick, damage mult)
##     bukan HUD game — itu panel alat, dan tempatnya di layar SETUP.
##   · Warna ikut varian arena, supaya HUD tidak terbaca seperti aplikasi lain
##     yang ditempel di atas permainan.

## Jeda. HUD punya tombolnya karena sebelumnya tidak ada jalan keluar dari run
## selain kalah — layar pause sudah ada di screens.gd tapi tak pernah terpanggil.
signal pause_pressed
## Tombol aksi: menembak tanpa jempol harus menutupi arena.
signal fire_pressed

# --- kerangka acuan ---------------------------------------------------------
const REF_W := 1080.0
const SAFE_TOP := 88.0
const SIDE_MARGIN := 44.0
# 128 px, bukan 112: gaya tombol tebal punya radius sudut 34 px dan kaki 16 px
# yang ikut masuk hitungan ukuran minimum, dan kotak yang lebih kecil dari itu
# akan dipanjangkan sendiri oleh layout jadi persegi panjang.
const PAUSE_SIZE := 128.0
const FIRE_SIZE := 230.0
const HEART_SIZE := 62.0

const FLOAT_POOL := 32
const FLOAT_RISE := 90.0
const FLOAT_LIFE := 0.8


## Hujan confetti. Dipakai sekali per ambang kill (50/100/200) — langka, dan
## karena itu boleh berlebihan. Digambar sendiri, bukan GPUParticles2D: tiga
## puluh persegi yang jatuh tidak butuh sistem partikel, dan versi gambar
## berperilaku sama di web export tanpa perlu shader.
class Confetti:
	extends Control

	const PIECES := 36
	const LIFE := 1.6
	const GRAVITY := 900.0

	var _pos: PackedVector2Array = PackedVector2Array()
	var _vel: PackedVector2Array = PackedVector2Array()
	var _spin: PackedFloat32Array = PackedFloat32Array()
	var _tint: PackedColorArray = PackedColorArray()
	var _life := 0.0
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	## Satu letusan dari atas layar. Warnanya diambil dari palet varian supaya
	## perayaan tetap terasa milik arena ini, bukan tempelan generik.
	func burst(width: float, palette: Array[Color]) -> void:
		_pos.clear()
		_vel.clear()
		_spin.clear()
		_tint.clear()
		for i in range(PIECES):
			_pos.append(Vector2(_rng.randf() * width, _rng.randf_range(-120.0, 40.0)))
			_vel.append(Vector2(_rng.randf_range(-160.0, 160.0), _rng.randf_range(80.0, 420.0)))
			_spin.append(_rng.randf_range(-9.0, 9.0))
			_tint.append(palette[i % palette.size()])
		_life = LIFE
		visible = true
		queue_redraw()

	func advance(delta: float) -> void:
		if _life <= 0.0:
			return
		_life -= delta
		if _life <= 0.0:
			visible = false
			return
		for i in range(_pos.size()):
			var velocity := _vel[i] + Vector2(0.0, GRAVITY * delta)
			_vel[i] = velocity
			_pos[i] = _pos[i] + velocity * delta
		queue_redraw()

	func is_falling() -> bool:
		return _life > 0.0

	func _draw() -> void:
		if _life <= 0.0:
			return
		var fade := clampf(_life / LIFE, 0.0, 1.0)
		for i in range(_pos.size()):
			var tint := _tint[i]
			tint.a = fade
			var angle := _spin[i] * (LIFE - _life)
			var axis := Vector2(cos(angle), sin(angle)) * 13.0
			var side := Vector2(-axis.y, axis.x) * 0.45
			draw_colored_polygon(
				PackedVector2Array(
					[
						_pos[i] - axis - side,
						_pos[i] + axis - side,
						_pos[i] + axis + side,
						_pos[i] - axis + side,
					]
				),
				tint
			)


## Cincin progres chain shot. Digambar, bukan disusun dari node: busur yang
## tumbuh adalah satu-satunya cara membaca "berapa lama lagi" tanpa angka.
class ChargeRing:
	extends Control

	var progress := 0.0
	var tint := Color("#7CFFEA")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(value: float, color: Color) -> void:
		var clamped := clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, progress) and color == tint:
			return
		progress = clamped
		tint = color
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 7.0
		if radius <= 1.0:
			return
		draw_arc(center, radius, 0.0, TAU, 72, Color(1, 1, 1, 0.10), 13.0, true)
		if progress > 0.002:
			draw_arc(
				center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 72, tint, 13.0, true
			)


var _sim: SimWorld
var _camera: Camera3D
var _pal: Dictionary = {}

var _score_pod: PanelContainer
var _chip_column: VBoxContainer
var _score_value: Label
var _combo: Label
var _wave: Label
var _stage_tag: Label
var _wave_dots: HBoxContainer
var _squad: Label
var _squad_pod: PanelContainer
var _squad_glyph: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _steer_bar: ProgressBar
var _steer_secs: Label
var _steer_label: Label
var _charge_row: HBoxContainer
var _hp_row: HBoxContainer
var _fire_button: Button
var _fire_ring: ChargeRing
var _fire_caption: Label
var _pause_button: Button
var _flash: ColorRect
var _vignette: ColorRect
var _confetti: Confetti
var _banner: Label
var _popup: Label
var _hint: PanelContainer
var _hint_label: RichTextLabel

var _floats: Array[Label] = []
var _float_state: Array[Dictionary] = []

var _shown_score := 0.0
var _combo_pulse := 0.0
var _popup_time := 0.0
var _banner_time := 0.0
var _flash_time := 0.0
var _hint_time := 0.0
var _fire_pulse := 0.0
var _last_msec := 0
var _stage_index := 0


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_last_msec = Time.get_ticks_msec()
	_build_overlays()
	_build_top_bar()
	_build_boss_bar()
	_build_bottom_deck()
	_build_hint()
	_build_float_pool()


## Called by Game once a run starts.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim
	_shown_score = 0.0
	_hint_time = 6.0
	if _hint != null:
		_hint.visible = true
		_hint.modulate.a = 1.0


## Labels the stage chip. The HUD cannot derive it: stage is campaign state.
func set_stage(stage: int) -> void:
	_stage_index = stage
	if _stage_tag != null:
		_stage_tag.text = "ST %02d" % (stage + 1)


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
	_update_charges(delta)
	_update_hearts()
	_update_floats(delta)
	_update_overlays(delta)
	if _confetti != null:
		_confetti.advance(delta)


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
			"bounce_milestone":
				_show_popup("BOUNCE x%d" % int(event.get("count", 0)))
			"kill_milestone":
				_show_popup("%d KILLS" % int(event.get("kills", 0)))
				_burst_confetti()
			"perfect_clear":
				_show_banner("PERFECT CLEAR +%d" % int(event.get("coins", 0)), UiTheme.GOLD)
			"life_lost":
				_flash_time = 0.4
			"boss_hit":
				_show_popup("CRITICAL")
			"victory":
				_show_banner("STAGE CLEAR", _pal["primary"])
			"defeat":
				_show_banner("OVERRUN", UiTheme.DANGER)
			"chain_fired":
				_hide_hint()


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
	var current := mini(_sim.wave_index + 1, waves)
	_wave.text = "WAVE %d/%d" % [maxi(current, 1), waves]
	# Lima titik bisa dibaca dengan lirikan setengah detik; "WAVE 3/5" tidak.
	var dots := _wave_dots.get_children()
	for i in range(dots.size()):
		var dot := dots[i] as Panel
		var lit: bool = i < maxi(current, 1)
		var fill: Color = _pal["primary"] if lit else Color(1, 1, 1, 0.14)
		dot.add_theme_stylebox_override("panel", UiTheme.blob(fill, 6))

	_squad.text = "%d" % _sim.troops
	# Squad count is health and damage at once, so it gets an early warning
	# state rather than only being noticed when the run is already lost.
	var low: bool = _sim.troops <= 5
	_squad.add_theme_color_override("font_color", UiTheme.DANGER if low else UiTheme.INK)
	_squad_pod.add_theme_stylebox_override(
		"panel", UiTheme.pod(UiTheme.DANGER if low else _pal["primary"], 28)
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
	var alpha := 1.0 if riding else 0.0
	_steer_bar.modulate.a = alpha
	_steer_secs.modulate.a = alpha
	_steer_label.modulate.a = alpha
	_steer_secs.text = "%.1fs" % maxf(meter, 0.0)
	# Warning white in the last half second, before steering simply stops.
	var fill := _steer_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = UiTheme.INK if (riding and meter < 0.5) else _pal["primary"]


func _update_charges(delta: float) -> void:
	var children := _charge_row.get_children()
	for i in range(children.size()):
		var pip := children[i] as Panel
		var ready_pip: bool = i < _sim.chain_charges
		var fill: Color = _pal["primary"] if ready_pip else Color(1, 1, 1, 0.16)
		pip.add_theme_stylebox_override("panel", UiTheme.blob(fill, 11))

	# Cincin penuh = siap. Di bawah itu cincin menunjukkan isi menuju muatan
	# berikutnya, jadi tombol selalu menjawab "kapan saya bisa menembak lagi".
	var ready_now: bool = _sim.chain_charges > 0
	var ring: float = 1.0 if ready_now else clampf(_sim.chain_charge, 0.0, 1.0)
	_fire_ring.set_progress(ring, _pal["primary"] if ready_now else Color(1, 1, 1, 0.35))
	_fire_caption.add_theme_color_override(
		"font_color", _pal["primary"] if ready_now else UiTheme.INK_DIM
	)
	# Denyut halus saat siap: tombol yang hidup menarik jempol ke sana.
	if ready_now:
		_fire_pulse = fmod(_fire_pulse + delta * 2.4, TAU)
		var pulse := 1.0 + 0.035 * sin(_fire_pulse)
		_fire_button.pivot_offset = _fire_button.size * 0.5
		_fire_button.scale = Vector2(pulse, pulse)
	else:
		_fire_pulse = 0.0
		_fire_button.scale = Vector2.ONE


func _update_hearts() -> void:
	var children := _hp_row.get_children()
	for i in range(children.size()):
		var heart := children[i] as Panel
		var alive: bool = i < _sim.lives
		heart.add_theme_stylebox_override(
			"panel",
			(
				UiTheme.blob(UiTheme.DANGER, 20, Color(0.35, 0.03, 0.09))
				if alive
				else UiTheme.blob(Color(0.13, 0.18, 0.29, 0.85), 20)
			)
		)


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

	# Petunjuk kontrol pergi sendiri. Teks permanen di layar main adalah
	# dokumentasi, bukan desain.
	if _hint_time > 0.0:
		_hint_time -= delta
		if _hint != null:
			_hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
			if _hint_time <= 0.0:
				_hint.visible = false


func _hide_hint() -> void:
	_hint_time = minf(_hint_time, 0.35)


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


## Confetti memakai tiga warna palet arena, jadi letusannya ikut berganti
## rupa antar varian tanpa aset tambahan.
func _burst_confetti() -> void:
	if _confetti == null:
		return
	var palette: Array[Color] = [_pal["primary"], UiTheme.GOLD, _pal["bumper"]]
	_confetti.burst(maxf(_confetti.size.x, REF_W), palette)


func _show_popup(text: String) -> void:
	_popup.text = text
	_popup.visible = true
	_popup_time = 0.97


func _show_banner(text: String, tint: Color) -> void:
	_banner.text = text
	_banner.modulate = tint
	_banner.visible = true
	_banner_time = 2.0


# ---------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------
func _build_top_bar() -> void:
	# Satu baris, tiga blok: skor di kiri, chip stage di tengah, jeda di kanan.
	# Disusun sebagai container supaya tiga blok itu tidak pernah bisa saling
	# menindih betapapun tinggi atau lebar teksnya pada font perangkat.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_right = 1.0
	top.offset_left = SIDE_MARGIN
	top.offset_right = -SIDE_MARGIN
	top.offset_top = SAFE_TOP
	top.offset_bottom = SAFE_TOP + 128.0
	add_child(top)

	# Skor di kiri: arah baca pertama, dan jauh dari jempol kanan.
	_score_pod = PanelContainer.new()
	_score_pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_pod.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_score_pod.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 30))
	top.add_child(_score_pod)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", -2)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_pod.add_child(score_box)
	_label("SCORE", 22, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, score_box)
	_score_value = _label("0", 58, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, score_box)

	var left_push := Control.new()
	left_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(left_push)

	# Chip stage + wave di tengah atas, dengan titik progres di bawahnya.
	_chip_column = VBoxContainer.new()
	_chip_column.add_theme_constant_override("separation", 12)
	_chip_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_chip_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_chip_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_chip_column)

	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 38))
	_chip_column.add_child(chip)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", 16)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_row)
	_stage_tag = _label("ST 01", 30, _pal["primary"], HORIZONTAL_ALIGNMENT_CENTER, chip_row)
	_wave = _label("WAVE 1/5", 28, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, chip_row)

	# Lima titik bisa dibaca dengan lirikan setengah detik.
	_wave_dots = HBoxContainer.new()
	_wave_dots.add_theme_constant_override("separation", 9)
	_wave_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_wave_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_column.add_child(_wave_dots)
	for _i in range(maxi(GameConfig.integer("spawn.waveCount"), 1)):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(44.0, 12.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", UiTheme.blob(Color(1, 1, 1, 0.14), 6))
		_wave_dots.add_child(dot)

	var right_push := Control.new()
	right_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right_push)

	# Jeda di kanan atas: jauh dari jempol yang sedang bermain, tetap terjangkau.
	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.custom_minimum_size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	_pause_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pause_button.add_theme_font_size_override("font_size", 38)
	UiTheme.apply_chunky(_pause_button, Color(0.09, 0.14, 0.26), Color(0.02, 0.04, 0.09), 34)
	# Margin isi bawaan gaya tombol tebal dipakai untuk tombol selebar layar;
	# di tombol ikon persegi margin itu memanjangkannya jadi persegi panjang,
	# jadi dikosongkan supaya kotaknya tetap kotak.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := _pause_button.get_theme_stylebox(state) as StyleBoxFlat
		if box == null:
			continue
		box.content_margin_left = 6.0
		box.content_margin_right = 6.0
		box.content_margin_top = 6.0
		box.content_margin_bottom = 6.0
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	top.add_child(_pause_button)

	_combo = _label("", 86, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_combo, Vector2(REF_W * 0.5 - 300.0, 470.0), Vector2(600.0, 110.0))


func _build_boss_bar() -> void:
	_boss_name = _label("BOSS", 28, Color("#FF8A8A"), HORIZONTAL_ALIGNMENT_CENTER)
	_place(_boss_name, Vector2(120.0, 370.0), Vector2(REF_W - 240.0, 40.0))
	_boss_bar = _bar(UiTheme.DANGER)
	_place(_boss_bar, Vector2(120.0, 414.0), Vector2(REF_W - 240.0, 28.0))
	_boss_bar.visible = false
	_boss_name.visible = false


## Dek bawah: semua yang disentuh dan semua yang harus dibaca saat panik.
## Di-anchor ke tepi bawah supaya layar 20:9 memberi ruang ekstra ke arena,
## bukan menggeser tombol ke tempat yang tidak terjangkau jempol.
func _build_bottom_deck() -> void:
	# Kolom kiri-bawah: pasukan, meter steer, nyawa — satu container, bukan
	# tiga kotak pada koordinat tetap. Dengan grow ke atas, elemen yang
	# ternyata lebih tinggi dari dugaan memakan ruang arena di atasnya dan
	# tidak pernah menindih tetangganya atau jatuh ke luar layar.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 20)
	left.alignment = BoxContainer.ALIGNMENT_END
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_anchor_bottom(left, Vector2(SIDE_MARGIN, -360.0), Vector2(REF_W - 420.0, 288.0))
	add_child(left)

	# Pasukan: angka terpenting dalam loop ini (sekaligus HP dan DPS).
	_squad_pod = PanelContainer.new()
	_squad_pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_pod.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_squad_pod.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 28))
	left.add_child(_squad_pod)
	var squad_row := HBoxContainer.new()
	squad_row.add_theme_constant_override("separation", 14)
	squad_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_pod.add_child(squad_row)
	# Belah ketupat yang digambar, bukan karakter ▲: font bawaan Godot tidak
	# memilikinya dan hasilnya kotak tofu di build sungguhan.
	_squad_glyph = UiTheme.diamond(_pal["primary"], 20)
	squad_row.add_child(_squad_glyph)
	var squad_box := VBoxContainer.new()
	squad_box.add_theme_constant_override("separation", -4)
	squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_row.add_child(squad_box)
	_squad = _label("5", 52, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, squad_box)
	_label("PASUKAN", 20, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, squad_box)

	# Meter steer hanya hidup saat menunggangi peluru.
	var steer_row := HBoxContainer.new()
	steer_row.add_theme_constant_override("separation", 16)
	steer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(steer_row)
	_steer_label = _label("STEER", 24, _pal["primary"], HORIZONTAL_ALIGNMENT_LEFT, steer_row)
	_steer_bar = _bar(_pal["primary"], steer_row)
	_steer_bar.custom_minimum_size = Vector2(320.0, 26.0)
	_steer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_steer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_steer_secs = _label("0.0s", 26, _pal["primary"], HORIZONTAL_ALIGNMENT_RIGHT, steer_row)
	_steer_bar.modulate.a = 0.0
	_steer_secs.modulate.a = 0.0
	_steer_label.modulate.a = 0.0

	# Nyawa: kotak tebal, bukan karakter teks. Teks "♥" mengecil jadi noda
	# merah di layar kecil dan tidak punya keadaan "kosong" yang jelas.
	_hp_row = HBoxContainer.new()
	_hp_row.add_theme_constant_override("separation", 12)
	_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_hp_row)
	for _i in range(GameConfig.integer("player.lives")):
		var heart := Panel.new()
		heart.custom_minimum_size = Vector2(HEART_SIZE, HEART_SIZE)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.add_theme_stylebox_override(
			"panel", UiTheme.blob(UiTheme.DANGER, 20, Color(0.35, 0.03, 0.09))
		)
		_hp_row.add_child(heart)

	# Tombol aksi utama: bundar, 230 px, pojok kanan bawah.
	_fire_button = Button.new()
	_fire_button.focus_mode = Control.FOCUS_NONE
	UiTheme.apply_chunky(
		_fire_button, Color(0.055, 0.105, 0.21), Color(0.01, 0.03, 0.07), int(FIRE_SIZE * 0.5)
	)
	_anchor_bottom(
		_fire_button,
		Vector2(REF_W - SIDE_MARGIN - FIRE_SIZE, -(FIRE_SIZE + 72.0)),
		Vector2(FIRE_SIZE, FIRE_SIZE)
	)
	_fire_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fire_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fire_button.pressed.connect(func() -> void: fire_pressed.emit())
	add_child(_fire_button)

	_fire_ring = ChargeRing.new()
	_fire_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fire_button.add_child(_fire_ring)

	var fire_box := VBoxContainer.new()
	fire_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	fire_box.alignment = BoxContainer.ALIGNMENT_CENTER
	fire_box.add_theme_constant_override("separation", 2)
	fire_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire_button.add_child(fire_box)
	# Cincin digambar dari StyleBoxFlat; ◎ tidak ada di font bawaan.
	var ring_row := HBoxContainer.new()
	ring_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ring_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire_box.add_child(ring_row)
	ring_row.add_child(UiTheme.ring(UiTheme.INK, 54, 6))
	_fire_caption = _label("CHAIN", 24, UiTheme.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, fire_box)

	_charge_row = HBoxContainer.new()
	_charge_row.add_theme_constant_override("separation", 10)
	_charge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_charge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire_box.add_child(_charge_row)
	for _i in range(GameConfig.integer("squad.chainShot.maxCharges")):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(22.0, 22.0)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", UiTheme.blob(Color(1, 1, 1, 0.16), 11))
		_charge_row.add_child(pip)


## Toast petunjuk di tengah lapangan: ruang itu kosong di detik-detik pertama,
## jadi tidak ada yang tertutup justru ketika pemain paling perlu melihat.
func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], 26, 0.86))
	_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hint.anchor_top = 0.44
	_hint.anchor_bottom = 0.44
	_hint.offset_left = 110.0
	_hint.offset_right = REF_W - 110.0
	_hint.offset_top = -90.0
	_hint.offset_bottom = 90.0
	add_child(_hint)

	_hint_label = RichTextLabel.new()
	_hint_label.bbcode_enabled = true
	_hint_label.fit_content = true
	_hint_label.scroll_active = false
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("normal_font_size", 28)
	_hint_label.add_theme_font_size_override("bold_font_size", 28)
	_hint_label.text = (
		"[center][b]GESER[/b] untuk menggerakkan squad — posisinya adalah bidikanmu.\n"
		+ "[b]TAP[/b] untuk chain shot, lalu [b]GESER[/b] membelokkan peluru.[/center]"
	)
	_hint.add_child(_hint_label)
	_hint.visible = false


func _build_overlays() -> void:
	_vignette = ColorRect.new()
	_vignette.color = Color("#00344D")
	_vignette.modulate.a = 0.0
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)

	_confetti = Confetti.new()
	_confetti.visible = false
	add_child(_confetti)

	_flash = ColorRect.new()
	_flash.color = Color(UiTheme.DANGER.r, UiTheme.DANGER.g, UiTheme.DANGER.b, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_popup = _label("", 96, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.offset_left = -REF_W * 0.5
	_popup.offset_right = REF_W * 0.5
	_popup.offset_top = -240.0
	_popup.offset_bottom = -140.0
	_popup.visible = false

	_banner = _label("", 104, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -REF_W * 0.5
	_banner.offset_right = REF_W * 0.5
	_banner.offset_top = -70.0
	_banner.offset_bottom = 70.0
	_banner.visible = false


func _build_float_pool() -> void:
	for _i in range(FLOAT_POOL):
		var label := _label("", 40, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		label.size = Vector2(200.0, 48.0)
		label.pivot_offset = Vector2(100.0, 24.0)
		label.visible = false
		_floats.append(label)
		_float_state.append({"active": false, "time": 0.0, "origin": Vector2.ZERO})


func _pod(at: Vector2, size: Vector2, radius: int) -> PanelContainer:
	var pod := PanelContainer.new()
	pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pod.add_theme_stylebox_override("panel", UiTheme.pod(_pal["primary"], radius))
	_place(pod, at, size)
	add_child(pod)
	return pod


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


func _bar(tint: Color, parent: Node = null) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UiTheme.bar_fill(tint))
	bar.add_theme_stylebox_override("background", UiTheme.bar_track(_pal))
	if parent == null:
		add_child(bar)
	else:
		parent.add_child(bar)
	return bar


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
