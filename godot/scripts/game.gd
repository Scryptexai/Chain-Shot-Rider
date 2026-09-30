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
	# Everything visual is themed from the variant this stage runs in, so the
	# palette has to be resolved before anything is built.
	var variant := _variant_for_stage(_stage)
	if _view.has_method("build"):
		_view.call("build", variant)
	if _hud.has_method("build"):
		_hud.call("build", variant)
	if _screens.has_method("build"):
		_screens.call("build", variant)
	_connect_screens()
	_feel = GameFeel.new(GameConfig.dict(""))
	_audio = AudioDirector.new(GameConfig.dict(""))
	add_child(_audio)
	set_physics_process(false)


## Begins a stage, seeded so the same stage always plays the same way.
func start_stage(stage: int) -> void:
	_stage = stage
	var seed_value := STAGE_SEED_BASE + stage * 7919
	_sim = SimWorld.new(GameConfig.dict(""), seed_value, stage, SaveGame.active_upgrades())
	if _view.has_method("bind_sim"):
		_view.call("bind_sim", _sim)
	if _hud.has_method("bind_sim"):
		_hud.call("bind_sim", _sim)
	if _hud.has_method("bind_camera"):
		_hud.call("bind_camera", _camera)


## Maps a stage index onto one of the five arena variants.
func _variant_for_stage(stage: int) -> int:
	var cycle: Array = GameConfig.list("meta.variantCycle")
	if cycle.is_empty():
		return 0
	return int(cycle[stage % cycle.size()])


func _connect_screens() -> void:
	_screens.connect("play_pressed", _on_play)
	_screens.connect("resume_pressed", _on_resume)
	_screens.connect("restart_pressed", _on_restart)
	_screens.connect("menu_pressed", _on_menu)


func _on_play() -> void:
	_screens.call("hide_all")
	start_stage(_stage)
	set_physics_process(true)


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
	_screens.call("show_menu")


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
	# The sim keeps its fixed step; this only changes how many steps a real
	# second buys, so a slowed run still replays identically.
	Engine.time_scale = _feel.time_scale
	_camera.fov = _feel.fov
	_camera.position = _camera_home + _feel.shake_offset()


func _unhandled_input(event: InputEvent) -> void:
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
	_camera.fov = GameConfig.num("slowMo.fovNormal")
	# Remembered so shake can be an offset from it rather than an integration
	# that slowly walks the camera away from its framing.
	_camera_home = _camera.position


func _finish_run() -> void:
	# Never leave the engine slowed on the results screen.
	Engine.time_scale = 1.0
	var won: bool = _sim.state == SimWorld.State.VICTORY
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
