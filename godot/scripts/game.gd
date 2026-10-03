extends Node3D
## Wires input, the simulation, and the presentation layer together.
##
## The split this file enforces: SimWorld owns the rules and advances on a
## fixed 60 Hz step inside _physics_process; everything visual reads that
## state in _process and is allowed to lag, smooth, or exaggerate it. Nothing
## visual is ever allowed to write back into the simulation, which is what
## keeps replays honest.

const STAGE_SEED_BASE := 20260929

var _sim: SimWorld
var _stage: int = 0
var _pointer_down := false
var _pointer_arena_x := 0.0
var _pointer_last_x := 0.0
var _press_position := Vector2.ZERO
var _press_time := 0.0
var _pending_tap := false
var _pending_drag := 0.0
var _feel: GameFeel = null
var _audio: AudioDirector = null
var _music: MusicDirector = null
var _fov_scale: float = 1.0
var _camera_home := Vector3.ZERO

@onready var _view: Node3D = $ArenaView
@onready var _hud: CanvasLayer = $HUD
@onready var _screens: CanvasLayer = $Screens
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	if not GameConfig.loaded:
		push_error("Game: config failed to load; nothing to run")
		return
	_stage = SaveGame.unlocked_stage
	_place_camera()
	# Layar web bisa berubah ukuran kapan saja (rotasi, bilah alamat ponsel).
	get_viewport().size_changed.connect(_update_fov_scale)
	# Everything visual is themed from the variant this stage runs in, so the
	# palette has to be resolved before anything is built.
	var variant := _variant_for_stage(_stage)
	if _view.has_method("build"):
		_view.call("build", variant)
	if _hud.has_method("build"):
		_hud.call("build", variant)
	# HUD dibangun sekali di sini, tapi ia milik RUN, bukan milik aplikasi.
	# Sebelum ini ia ikut tampil di markas dan di peta stage: nyawa, pod
	# pasukan, dan teks "WAVE 1/5" menumpuk di atas layar menu. Tidak pernah
	# terlihat selama proyek hanya diuji headless — dummy renderer tidak
	# menggambar apa pun — dan baru ketahuan pada build web pertama.
	_hud.visible = false
	if _screens.has_method("build"):
		_screens.call("build", variant)
	_connect_screens()
	_connect_hud()
	_apply_aspect_guard()
	# Satu-satunya tempat framing portrait bisa rusak adalah jendela yang
	# berubah bentuk, jadi penjaganya dipasang di sana dan bukan dipanggil
	# tiap frame.
	get_window().size_changed.connect(_apply_aspect_guard)
	_feel = GameFeel.new(GameConfig.dict(""))
	_audio = AudioDirector.new(GameConfig.dict(""))
	add_child(_audio)
	# Music is built after AudioDirector so the Music bus and its low-pass
	# already exist when MusicDirector goes looking for the filter to drive.
	_music = MusicDirector.new()
	add_child(_music)
	set_physics_process(false)


## Begins a stage, seeded so the same stage always plays the same way.
func start_stage(stage: int) -> void:
	_stage = stage
	_hud.visible = true
	var seed_value := STAGE_SEED_BASE + stage * 7919
	_sim = SimWorld.new(GameConfig.dict(""), seed_value, stage, SaveGame.active_upgrades())
	if _view.has_method("bind_sim"):
		_view.call("bind_sim", _sim)
	if _hud.has_method("bind_sim"):
		_hud.call("bind_sim", _sim)
	if _hud.has_method("bind_camera"):
		_hud.call("bind_camera", _camera)
	if _hud.has_method("set_stage"):
		_hud.call("set_stage", stage)
	if _music != null:
		_music.start(_variant_for_stage(stage))


## Maps a stage index onto one of the five arena variants.
func _variant_for_stage(stage: int) -> int:
	var cycle: Array = GameConfig.list("meta.variantCycle")
	if cycle.is_empty():
		return 0
	return int(cycle[stage % cycle.size()])


## Project settings lock the game to 1080x1920 match-width, yang benar untuk
## ponsel: layar lebih jangkung dari 9:16 hanya menambah ruang vertikal.
## Tapi aturan yang sama di jendela lanskap atau desktop melebarkan dunia
## sampai lorongnya terpotong di atas dan bawah, dan UI yang di-anchor ke
## tepi bawah terlempar keluar layar. Di sana portrait dipertahankan dengan
## pillarbox, bukan dengan merusak bingkainya.
func _apply_aspect_guard() -> void:
	var window := get_window()
	var size := window.size
	if size.x <= 0 or size.y <= 0:
		return
	var aspect := float(size.x) / float(size.y)
	# 9/16 = 0.5625 (portrait acuan), 9/21 ≈ 0.4286 (ponsel paling jangkung).
	if aspect > 0.5625 or aspect < 9.0 / 21.0:
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	else:
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH


## HUD baru memegang dua aksi: jeda dan chain shot. Keduanya dialirkan lewat
## sinyal supaya HUD tetap read-only terhadap simulasi.
func _connect_hud() -> void:
	if _hud.has_signal("pause_pressed"):
		_hud.connect("pause_pressed", _on_pause)
	if _hud.has_signal("fire_pressed"):
		_hud.connect("fire_pressed", _on_hud_fire)


## Tombol chain shot melewati jalur yang sama dengan tap di arena, jadi tidak
## ada aturan tembak kedua yang bisa berbeda perilakunya.
func _on_hud_fire() -> void:
	if _sim != null and is_physics_processing():
		_pending_tap = true


func _on_pause() -> void:
	if _sim == null or not is_physics_processing():
		return
	Engine.time_scale = 1.0
	set_physics_process(false)
	_screens.call("show_pause")


func _connect_screens() -> void:
	_screens.connect("play_pressed", _on_play)
	_screens.connect("resume_pressed", _on_resume)
	_screens.connect("restart_pressed", _on_restart)
	_screens.connect("menu_pressed", _on_menu)
	_screens.connect("continue_pressed", _on_continue)
	_screens.connect("card_chosen", _on_card_chosen)
	_screens.connect("stage_chosen", _on_stage_chosen)


## Play opens the ladder instead of dropping straight into a stage. The
## campaign is fifteen stages long, so "where am I" is a question the player
## has to be able to answer before a run starts, not after it.
func _on_play() -> void:
	_show_stage_map()


func _show_stage_map() -> void:
	Engine.time_scale = 1.0
	set_physics_process(false)
	_hud.visible = false
	_screens.call("show_stage_map")


func _on_stage_chosen(stage: int) -> void:
	_stage = stage
	_screens.call("hide_all")
	start_stage(stage)
	set_physics_process(true)


## A win leads into the upgrade draft. The offer is drawn with a generator
## seeded from the stage, never the sim RNG: pulling from the sim to pick cards
## would shift every later draw and break replay determinism.
func _on_continue() -> void:
	_screens.call("show_cards", _draw_offers())


## Picks the cards to offer. Cards already owned are filtered out while there
## are enough left to fill the hand; once the pool runs low they come back, so
## the screen never shows fewer options than meta.cardsOffered.
func _draw_offers() -> Array:
	var all: Array = GameConfig.list("meta.cards")
	# GameConfig.num() takes no fallback and logs an error on a missing key,
	# so read the meta block and let Cfg supply the default instead.
	var want: int = int(Cfg.num(GameConfig.dict("meta"), "cardsOffered", 3.0))
	var pool: Array = []
	for entry in all:
		var card: Dictionary = entry
		if not SaveGame.owned_cards.has(String(card.get("id", ""))):
			pool.append(card)
	if pool.size() < want:
		pool = all.duplicate()

	var rng := RandomNumberGenerator.new()
	rng.seed = STAGE_SEED_BASE + _stage * 104729
	var offers: Array = []
	for i in range(mini(want, pool.size())):
		offers.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return offers


## Taking the card ends the stage, it does not start the next one.
##
## This used to call start_stage(_stage), which replayed the stage that had
## just been won: _stage is only read from SaveGame at boot, so the ladder
## never advanced inside a session no matter how many runs were cleared.
## Handing control back to the map makes the unlock visible and lets the
## player choose where to go next.
func _on_card_chosen(card_id: String) -> void:
	if not card_id.is_empty():
		SaveGame.grant_card(card_id)
	_stage = SaveGame.unlocked_stage
	_show_stage_map()


func _on_resume() -> void:
	_screens.call("hide_all")
	set_physics_process(true)


func _on_restart() -> void:
	_screens.call("hide_all")
	start_stage(_stage)
	set_physics_process(true)


func _on_menu() -> void:
	Engine.time_scale = 1.0
	set_physics_process(false)
	_hud.visible = false
	_screens.call("show_menu")
	if _music != null:
		_music.stop()


func _physics_process(_delta: float) -> void:
	if _sim == null:
		return
	_sim.set_input(_pointer_arena_x, _pointer_down, _pending_tap, _pending_drag)
	_pending_tap = false
	_pending_drag = 0.0
	_sim.tick()
	if _sim.state != SimWorld.State.PLAYING:
		_finish_run()


func _process(_delta: float) -> void:
	if _sim == null:
		return
	# Order is free here: SimWorld.tick() owns the event buffer, so both
	# readers see the same list no matter which one runs first, and a frame
	# that spans several ticks sees all of their events.
	if _hud.has_method("render_frame"):
		_hud.call("render_frame")
	if _view.has_method("render_frame"):
		_view.call("render_frame")
	_update_feel(_delta)


## Slow motion, shake and FOV. Driven from unscaled time so the easing takes
## the same wall-clock duration however slow the world currently is.
func _update_feel(delta: float) -> void:
	if _feel == null:
		return
	var unscaled := delta / maxf(Engine.time_scale, 0.01)
	for entry in _sim.events:
		_feel.react_to(entry)
		if _audio != null:
			_audio.react_to(entry)
	_feel.update(_sim, unscaled)
	# Audio updates after feel so slow-mo enter/exit cues read this frame's
	# time_scale rather than the previous one's.
	if _audio != null:
		_audio.update(_sim, _feel, unscaled)
	if _music != null:
		_music.update(_sim, _feel, unscaled)
	# The sim keeps its fixed step; this only changes how many steps a real
	# second buys, so a slowed run still replays identically.
	Engine.time_scale = _feel.time_scale
	_camera.fov = _feel.fov * _fov_scale
	_camera.position = _camera_home + _feel.shake_offset()


func _unhandled_input(event: InputEvent) -> void:
	# Esc/back menjeda, bukan menutup game: di Android tombol back memetakan ke
	# ui_cancel, dan keluar dari run tanpa peringatan adalah cara tercepat
	# membuang progres pemain.
	if event.is_action_pressed("ui_cancel"):
		if is_physics_processing():
			_on_pause()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_pointer_down = true
		_press_position = event.position
		_press_time = Time.get_ticks_msec() / 1000.0
		_pointer_arena_x = _screen_to_arena_x(event.position.x)
		_pointer_last_x = _pointer_arena_x
		return
	_pointer_down = false
	var held := Time.get_ticks_msec() / 1000.0 - _press_time
	var moved := event.position.distance_to(_press_position)
	# A tap is a press that neither lingered nor travelled. Everything else was
	# the player moving the squad, and firing on that would feel like a misfire.
	if held <= 0.25 and moved <= 24.0:
		_pending_tap = true


func _handle_drag(event: InputEventScreenDrag) -> void:
	_pointer_down = true
	_pointer_arena_x = _screen_to_arena_x(event.position.x)
	_pending_drag += _pointer_arena_x - _pointer_last_x
	_pointer_last_x = _pointer_arena_x


func _screen_to_arena_x(screen_x: float) -> float:
	var width := float(get_viewport().get_visible_rect().size.x)
	if width <= 0.0:
		return 0.0
	var t := clampf(screen_x / width, 0.0, 1.0)
	var x_min := GameConfig.num("arena.xMin")
	var x_max := GameConfig.num("arena.xMax")
	return lerpf(x_min, x_max, t)


func _place_camera() -> void:
	# Positioned in code rather than baked into the scene file: the framing is
	# derived from arena numbers, so a config change must move the camera too.
	var defense_z := GameConfig.num("arena.defenseLineZ")
	var height := GameConfig.num("camera.heightOffset")
	var distance := GameConfig.num("camera.distance")
	var look_ahead := GameConfig.num("camera.lookAheadZ")
	var origin := Vector3(0.0, maxf(height, 8.0), distance)
	_camera.look_at_from_position(origin, Vector3(0.0, 0.0, -(defense_z + look_ahead)), Vector3.UP)
	_update_fov_scale()
	_camera.fov = GameConfig.num("slowMo.fovNormal") * _fov_scale
	# Remembered so shake can be an offset from it rather than an integration
	# that slowly walks the camera away from its framing.
	_camera_home = _camera.position


## Bukaan horizontal dikunci, bukan vertikal — persis seperti widthMatchedFov()
## di js/render3d.js.
##
## Godot memakai FOV vertikal. Pada ponsel 9:19.5 itu berarti lorong terlihat
## jauh lebih panjang daripada di 9:16: lantai berakhir di tengah layar dan
## sisanya hitam. Yang harus tetap sama antar layar adalah LEBAR arena, jadi
## FOV vertikal dihitung ulang dari lebar 9:16 lalu dibatasi supaya musuh jauh
## tidak menyusut jadi beberapa piksel.
func _update_fov_scale() -> void:
	var base := GameConfig.num("slowMo.fovNormal")
	if base <= 0.0:
		_fov_scale = 1.0
		return
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var half_width := tan(deg_to_rad(base) * 0.5) * (9.0 / 16.0)
	var matched := rad_to_deg(2.0 * atan(half_width / maxf(aspect, 0.0001)))
	_fov_scale = clampf(matched, base * 0.85, 58.0) / base


func _finish_run() -> void:
	# Never leave the engine slowed on the results screen.
	Engine.time_scale = 1.0
	# Layar hasil adalah layar penuh; HUD run yang masih menyala di belakangnya
	# hanya menumpuk angka di atas angka.
	_hud.visible = false
	var won: bool = _sim.state == SimWorld.State.VICTORY
	if _music != null:
		_music.finish(won)
	var earned := _sim.score / 10
	SaveGame.record_run(_stage, won, _sim.score, earned)
	set_physics_process(false)
	if won:
		_stage = SaveGame.unlocked_stage
	(
		_screens
		. call(
			"show_result",
			won,
			[
				{"label": "SCORE", "value": "%d" % _sim.score},
				{
					"label": "WAVE",
					"value": "%d/%d" % [_sim.wave_index + 1, GameConfig.integer("spawn.waveCount")]
				},
				{"label": "SQUAD", "value": "x%d" % _sim.troops},
				{"label": "COINS", "value": "+%d" % earned},
				{"label": "BEST", "value": "%d" % SaveGame.best_score},
			]
		)
	)
