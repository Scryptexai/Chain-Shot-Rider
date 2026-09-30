class_name MusicDirector
extends Node
## Layered music playback, per docs/07 section 7.3.
##
## Three players run at once on the Music bus: the base synth, the layer that
## belongs to the current arena variant, and the boss-wave drum fill. They are
## all 60 s loops rendered from the same 120 BPM grid by tools/gen_music.py, so
## they stay phase-locked as long as they start together - which is why they
## start in one call rather than fading in on demand. Arranging by volume
## instead of by playback position is what keeps the layers in sync.
##
## Volume, filtering and pitch respond to game state; the stems never change.

const MUSIC_DIR := "res://audio/music/"
const BASE_STEM := "base_synth"
const FILL_STEM := "drums_fill"

# Variant index -> extra layer. docs/07 7.3: Classic Pit runs on base alone.
const VARIANT_LAYERS := ["", "arp", "pad", "percussion", "glitch"]

const BASE_DB := -4.0
const LAYER_DB := -6.0
const LAYER_BOOST_DB := 3.0  # waves 3-4 lift the arrangement
const FILL_DB := -5.0
const SILENT_DB := -60.0
const FADE_RATE_DB := 40.0

const SLOWMO_PITCH := 0.85
const SLOWMO_CUTOFF := 1200.0
const OPEN_CUTOFF := 20000.0
const BOSS_WAVE_INDEX := 4
const LAYER_WAVE_INDEX := 2
const CUTOFF_RATE := 26000.0

## Exposed for the smoke test: a music system that silently fails to load is
## indistinguishable from one that is merely quiet.
var layers_loaded: int = 0
var active_variant: int = -1

var _base: AudioStreamPlayer = null
var _layer: AudioStreamPlayer = null
var _fill: AudioStreamPlayer = null
var _stingers: Dictionary = {}
var _target_db: Dictionary = {}
var _cutoff: float = OPEN_CUTOFF
var _target_cutoff: float = OPEN_CUTOFF
var _lpf: AudioEffectLowPassFilter = null
var _playing: bool = false
var _muted: bool = false


func _ready() -> void:
	_base = _make_player()
	_layer = _make_player()
	_fill = _make_player()
	for name in ["stinger_victory", "stinger_defeat"]:
		var path := "%s%s.ogg" % [MUSIC_DIR, name]
		if ResourceLoader.exists(path):
			var player := _make_player()
			player.stream = load(path)
			_stingers[name] = player
	_bind_filter()


## Loads the stems for one arena variant and starts them together.
func start(variant: int) -> void:
	if _muted:
		return
	active_variant = variant
	layers_loaded = 0
	_assign(_base, BASE_STEM)
	var layer_name: String = ""
	if variant >= 0 and variant < VARIANT_LAYERS.size():
		layer_name = str(VARIANT_LAYERS[variant])
	if layer_name.is_empty():
		_layer.stream = null
	else:
		_assign(_layer, layer_name)
	_assign(_fill, FILL_STEM)

	# Everything starts silent and is mixed up by _apply_state, so a run never
	# opens with the boss drums already audible.
	for player in [_base, _layer, _fill]:
		player.volume_db = SILENT_DB
		if player.stream != null:
			player.play()
	_target_db[_base] = BASE_DB
	_target_db[_layer] = SILENT_DB
	_target_db[_fill] = SILENT_DB
	_playing = true


func stop() -> void:
	_playing = false
	for player in [_base, _layer, _fill]:
		if player != null and player.playing:
			player.stop()


## Fades the loop out and fires the end-of-run sting. docs/07 7.3 asks for a
## 1.5 s fade; the fade is driven by the same envelope as every other level
## move here, so it cannot fight the wave mixing on the way out.
func finish(victory: bool) -> void:
	for player in [_base, _layer, _fill]:
		_target_db[player] = SILENT_DB
	var key := "stinger_victory" if victory else "stinger_defeat"
	if _stingers.has(key) and not _muted:
		var sting: AudioStreamPlayer = _stingers[key]
		sting.volume_db = -3.0
		sting.play()


func set_muted(value: bool) -> void:
	_muted = value
	if value:
		stop()


## Drives layer levels, filter and pitch from game state. `unscaled_delta`
## keeps the fades wall-clock steady while slow motion stretches frame time.
func update(sim: SimWorld, feel: GameFeel, unscaled_delta: float) -> void:
	if not _playing or sim == null:
		return
	_apply_state(sim, feel)
	for player in [_base, _layer, _fill]:
		if player == null or player.stream == null:
			continue
		var want: float = float(_target_db.get(player, SILENT_DB))
		player.volume_db = move_toward(player.volume_db, want, FADE_RATE_DB * unscaled_delta)
	_cutoff = move_toward(_cutoff, _target_cutoff, CUTOFF_RATE * unscaled_delta)
	if _lpf != null:
		_lpf.cutoff_hz = _cutoff


func _apply_state(sim: SimWorld, feel: GameFeel) -> void:
	var wave: int = sim.wave_index
	var boss_wave: bool = wave >= BOSS_WAVE_INDEX
	var lifted: bool = wave >= LAYER_WAVE_INDEX

	_target_db[_base] = BASE_DB + (LAYER_BOOST_DB if lifted else 0.0)
	if _layer.stream != null:
		_target_db[_layer] = (
			LAYER_DB + (LAYER_BOOST_DB if lifted else 0.0) if lifted else SILENT_DB
		)
	_target_db[_fill] = FILL_DB if boss_wave else SILENT_DB

	# Slow motion drops pitch and closes the filter; the -6 dB duck that the
	# sheet also asks for is applied by AudioDirector on the Music bus, so it
	# is deliberately not repeated here.
	var slow: bool = feel != null and feel.time_scale < 0.9
	var pitch: float = SLOWMO_PITCH if slow else 1.0
	for player in [_base, _layer, _fill]:
		if player != null:
			player.pitch_scale = pitch
	if slow:
		_target_cutoff = SLOWMO_CUTOFF
	elif boss_wave:
		_target_cutoff = OPEN_CUTOFF
	else:
		_target_cutoff = 9000.0


func _assign(player: AudioStreamPlayer, stem: String) -> void:
	var path := "%s%s.ogg" % [MUSIC_DIR, stem]
	if not ResourceLoader.exists(path):
		push_warning("MusicDirector: stem hilang: %s" % path)
		player.stream = null
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	layers_loaded += 1


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Music"
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _bind_filter() -> void:
	# AudioDirector installs the low-pass on the Music bus; grab the instance
	# so the sweep can be driven here rather than duplicating the effect.
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var effect := AudioServer.get_bus_effect(bus, i)
		if effect is AudioEffectLowPassFilter:
			_lpf = effect as AudioEffectLowPassFilter
			return
