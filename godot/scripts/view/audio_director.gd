class_name AudioDirector
extends Node
## Turns simulation events into sound, per docs/07.
##
## The director is a view-layer consumer: it reads SimWorld events and state
## and never writes back. In particular the pitch jitter below draws from its
## own RandomNumberGenerator, never the sim's. Pulling a single number from the
## sim RNG to vary a kill pop would shift every later draw and break replay
## determinism - the kind of failure that looks like nothing until two runs of
## the same seed diverge.
##
## Mixing follows docs/07 section 7.4: eight voices, a bus tree with the stated
## trims, music ducked under slow-mo, crowd ducked under explosions.

const VOICE_COUNT := 8
const BOUNCE_LADDER_CAP := 14
const SEMITONE := 1.0594630943592953
const SFX_DIR := "res://audio/sfx/"

# Bus name -> [send target, volume dB]. Mirrors the tree drawn in docs/07 7.4.
const BUS_TREE := {
	"Music": ["Master", -6.0],
	"SFX": ["Master", 0.0],
	"Impact": ["SFX", 0.0],
	"Crowd": ["SFX", -4.0],
	"Ambient": ["SFX", -12.0],
	"UI": ["Master", -3.0],
}

# Cue table, transcribed from the sheet in docs/07 section 7.1.
#   variants   how many timbre renders exist on disk
#   volume     linear 0-1 from the sheet, converted to dB at load
#   cooldown   seconds; the Kill value of 0.04 is what keeps 200 deaths from
#              sounding like sand (see docs/07, "Kenapa cooldown 0.04 s")
#   priority   0 is most important and may steal a voice from anything higher
#   jitter     +/- pitch spread, 0 for cues that must sound identical
const CUES := {
	"shot":
	{
		"variants": 3,
		"volume": 0.85,
		"cooldown": 0.05,
		"priority": 0,
		"bus": "Impact",
		"jitter": 0.0
	},
	"bounce":
	{
		"variants": 4,
		"volume": 0.70,
		"cooldown": 0.02,
		"priority": 0,
		"bus": "Impact",
		"jitter": 0.0
	},
	"kill":
	{
		"variants": 5,
		"volume": 0.45,
		"cooldown": 0.04,
		"priority": 3,
		"bus": "Crowd",
		"jitter": 0.05
	},
	"combo_milestone":
	{"variants": 4, "volume": 0.90, "cooldown": 0.30, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"explosion":
	{
		"variants": 3,
		"volume": 1.00,
		"cooldown": 0.08,
		"priority": 0,
		"bus": "Impact",
		"jitter": 0.08
	},
	"chain_spark":
	{"variants": 2, "volume": 0.55, "cooldown": 0.06, "priority": 2, "bus": "SFX", "jitter": 0.0},
	"slowmo_enter":
	{"variants": 1, "volume": 0.80, "cooldown": 0.50, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"slowmo_exit":
	{"variants": 1, "volume": 0.70, "cooldown": 0.50, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"heartbeat":
	{"variants": 1, "volume": 0.65, "cooldown": 0.90, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"breach":
	{
		"variants": 2,
		"volume": 0.95,
		"cooldown": 0.35,
		"priority": 0,
		"bus": "Impact",
		"jitter": 0.0
	},
	"perfect_clear":
	{"variants": 1, "volume": 0.85, "cooldown": 0.0, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"kill_milestone":
	{"variants": 3, "volume": 0.85, "cooldown": 0.0, "priority": 1, "bus": "SFX", "jitter": 0.0},
	"bullet_expire":
	{"variants": 2, "volume": 0.50, "cooldown": 0.10, "priority": 2, "bus": "SFX", "jitter": 0.0},
	"steer_warn":
	{"variants": 1, "volume": 0.40, "cooldown": 0.25, "priority": 2, "bus": "UI", "jitter": 0.0},
	"ui_tap":
	{"variants": 2, "volume": 0.55, "cooldown": 0.05, "priority": 3, "bus": "UI", "jitter": 0.0},
	"boss_roar":
	{"variants": 1, "volume": 1.00, "cooldown": 0.0, "priority": 0, "bus": "Impact", "jitter": 0.0},
}

const MUSIC_DUCK_DB := -6.0
const MUSIC_DUCK_ATTACK := 0.15
const MUSIC_DUCK_RELEASE := 0.4
const CROWD_DUCK_DB := -5.0
const CROWD_DUCK_TIME := 0.3
const SLOWMO_ENTER_THRESHOLD := 0.9
const STEER_WARN_SECONDS := 0.5

## Cue name -> number of times it has played. Read by the smoke test; a cue
## that never fires is indistinguishable from a cue that does not exist.
var play_counts: Dictionary = {}
var bounce_ladder: int = 0

var _voices: Array[AudioStreamPlayer] = []
var _voice_priority: Array[int] = []
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()
var _music_duck: float = 0.0
var _crowd_duck_remaining: float = 0.0
var _was_slow: bool = false
var _muted: bool = false


## Config masih diterima walau isinya tidak lagi dibaca: ambang near-miss
## sekarang milik simulasi, yang mengirim event "near_miss" sendiri.
func _init(_config: Dictionary = {}) -> void:
	_rng.seed = 987654321


func _ready() -> void:
	_ensure_buses()
	_load_streams()
	for i in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_voices.append(player)
		_voice_priority.append(99)


## Plays a cue if its cooldown has elapsed and a voice can be found.
## Returns true when a voice actually started, so callers and tests can tell
## "suppressed by cooldown" apart from "played".
func play(cue: String, pitch_override: float = -1.0) -> bool:
	if _muted or not CUES.has(cue):
		return false
	var spec: Dictionary = CUES[cue]
	var last: float = _last_played.get(cue, -999.0)
	if _clock - last < float(spec["cooldown"]):
		return false
	var bank: Array = _streams.get(cue, [])
	if bank.is_empty():
		return false
	var voice := _acquire_voice(int(spec["priority"]))
	if voice < 0:
		return false

	var player: AudioStreamPlayer = _voices[voice]
	player.stream = bank[_rng.randi_range(0, bank.size() - 1)]
	player.bus = str(spec["bus"])
	player.volume_db = linear_to_db(float(spec["volume"]))
	var jitter: float = float(spec["jitter"])
	if pitch_override > 0.0:
		player.pitch_scale = pitch_override
	elif jitter > 0.0:
		player.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	else:
		player.pitch_scale = 1.0
	player.play()

	_voice_priority[voice] = int(spec["priority"])
	_last_played[cue] = _clock
	play_counts[cue] = int(play_counts.get(cue, 0)) + 1
	return true


## Maps one simulation event onto a cue. Mirrors GameFeel.react_to so the two
## view-layer consumers stay symmetrical.
func react_to(event: Dictionary) -> void:
	var kind: String = str(event.get("type", ""))
	match kind:
		"chain_fired":
			play("shot")
			bounce_ladder = 0
		"bounce":
			_play_bounce()
		"obstacle_hit":
			_play_bounce()
		"kill":
			play("kill")
		"kill_milestone":
			play("kill_milestone")
		"bounce_milestone":
			play("chain_spark")
		"near_miss":
			play("heartbeat")
		"perfect_clear":
			play("perfect_clear")
		"explosion":
			play("explosion")
			_crowd_duck_remaining = CROWD_DUCK_TIME
		"combo_milestone":
			play("combo_milestone")
		"chain_end":
			play("bullet_expire")
			bounce_ladder = 0
		"ride_start":
			play("chain_spark")
		"leak":
			play("breach")
		"life_lost":
			play("breach")
		"boss_start":
			play("boss_roar")
		"victory":
			play("perfect_clear")


## Polled cues and ducking. `unscaled_delta` must ignore Engine.time_scale:
## audio cooldowns are wall-clock contracts, and slow-mo would otherwise
## stretch the 0.04 s kill cooldown into a quarter of a second.
func update(sim: SimWorld, feel: GameFeel, unscaled_delta: float) -> void:
	_clock += unscaled_delta
	_update_slowmo(feel)
	_update_proximity(sim)
	_update_ducking(unscaled_delta)
	for i in range(_voices.size()):
		if not _voices[i].playing:
			_voice_priority[i] = 99


## Silences the director. Used by the headless sim harness, which has no audio
## device and no interest in one.
func set_muted(value: bool) -> void:
	_muted = value


func _play_bounce() -> void:
	# docs/07 7.2: one semitone per bounce, capped at 14. Above that it stops
	# reading as a climbing ladder and starts sounding like vermin.
	bounce_ladder = mini(bounce_ladder + 1, BOUNCE_LADDER_CAP)
	play("bounce", pow(SEMITONE, float(bounce_ladder)))


func _update_slowmo(feel: GameFeel) -> void:
	if feel == null:
		return
	var slow: bool = feel.time_scale < SLOWMO_ENTER_THRESHOLD
	if slow and not _was_slow:
		play("slowmo_enter")
	elif not slow and _was_slow:
		play("slowmo_exit")
	_was_slow = slow


func _update_proximity(sim: SimWorld) -> void:
	if sim == null:
		return
	if sim.chain_active and sim.chain_steer_meter > 0.0:
		if sim.chain_steer_meter < STEER_WARN_SECONDS:
			play("steer_warn")


func _update_ducking(delta: float) -> void:
	# Music duck follows an attack/release envelope rather than snapping, so
	# entering slow-mo sounds like the mix leaning back instead of a dropout.
	var target: float = MUSIC_DUCK_DB if _was_slow else 0.0
	var rate: float = MUSIC_DUCK_ATTACK if _was_slow else MUSIC_DUCK_RELEASE
	_music_duck = move_toward(_music_duck, target, abs(MUSIC_DUCK_DB) * delta / maxf(rate, 0.01))
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, float(BUS_TREE["Music"][1]) + _music_duck)

	if _crowd_duck_remaining > 0.0:
		_crowd_duck_remaining -= delta
	var crowd_bus := AudioServer.get_bus_index("Crowd")
	if crowd_bus >= 0:
		var duck: float = CROWD_DUCK_DB if _crowd_duck_remaining > 0.0 else 0.0
		AudioServer.set_bus_volume_db(crowd_bus, float(BUS_TREE["Crowd"][1]) + duck)


## Finds a free voice, or steals one from a less important cue. Returns -1 when
## everything playing outranks the request, in which case the cue is dropped -
## which is correct: with eight voices, a kill pop must never evict a boss roar.
func _acquire_voice(priority: int) -> int:
	for i in range(_voices.size()):
		if not _voices[i].playing:
			return i
	var worst := -1
	var worst_priority := priority
	for i in range(_voices.size()):
		if _voice_priority[i] > worst_priority:
			worst_priority = _voice_priority[i]
			worst = i
	return worst


func _ensure_buses() -> void:
	for bus_name in BUS_TREE:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_volume_db(idx, float(BUS_TREE[bus_name][1]))
	# Sends are set in a second pass: a child bus cannot route to a parent that
	# does not exist yet, and dictionary order is not a dependency order.
	for bus_name in BUS_TREE:
		var idx := AudioServer.get_bus_index(bus_name)
		var target: String = str(BUS_TREE[bus_name][0])
		if idx >= 0 and AudioServer.get_bus_index(target) >= 0:
			AudioServer.set_bus_send(idx, target)
	_ensure_effects()


func _ensure_effects() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, limiter)
	var music := AudioServer.get_bus_index("Music")
	if music >= 0 and AudioServer.get_bus_effect_count(music) == 0:
		# Parked wide open; the music layer system will sweep it to 1200 Hz
		# under slow-mo as docs/07 7.3 describes.
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(music, lpf)


func _load_streams() -> void:
	for cue in CUES:
		var bank: Array = []
		var count: int = int(CUES[cue]["variants"])
		for v in range(1, count + 1):
			var path := "%s%s_%d.wav" % [SFX_DIR, cue, v]
			if ResourceLoader.exists(path):
				bank.append(load(path))
			else:
				push_warning("AudioDirector: cue file hilang: %s" % path)
		_streams[cue] = bank
