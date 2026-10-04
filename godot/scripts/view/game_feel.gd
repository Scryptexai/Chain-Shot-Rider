class_name GameFeel
extends RefCounted
## Slow motion, camera shake and field-of-view punch.
##
## These are the three effects that separate "the rules are running" from
## "the game feels good", and all three were designed in docs 02 and 08 and
## then never built. Riding a ricochet through a crowd is the moment the
## whole design exists for; at a flat 1.0 time scale it goes by too fast to
## read, let alone steer.
##
## Everything here is presentation only. The simulation still advances on its
## own fixed step — slow motion changes how many ticks a wall-clock second
## buys, never the size of a tick, so a slowed run and a normal run produce
## the same replay. That is why `Engine.time_scale` is the lever rather than
## a variable delta.
##
## Shake is generated from a decaying sine rather than random noise: noise
## makes a 60 Hz frame and a 30 Hz frame disagree about where the camera is,
## and the cheap version reads the same on both.

## Time scales come from config; these are the fallbacks if a key is missing.
const DEFAULT_CROWD_SCALE := 0.3
const DEFAULT_FINAL_SCALE := 0.15
const DEFAULT_TRANSITION := 0.2

var time_scale: float = 1.0
var fov: float = 60.0

var _target_scale: float = 1.0
var _target_fov: float = 60.0
var _transition: float = DEFAULT_TRANSITION
var _crowd_scale: float = DEFAULT_CROWD_SCALE
var _final_scale: float = DEFAULT_FINAL_SCALE
var _final_threshold: int = 3
var _fov_normal: float = 60.0
var _fov_slow: float = 40.0
var _shake_presets: Dictionary = {}

## Dua waktu pinjaman: denyut pendek tiap kelipatan lima pantulan, dan
## potongan sinematik saat peluru terakhir menutup sebuah gelombang. Keduanya
## memaksa slow motion dari luar — bukan dari keadaan sim — jadi mereka perlu
## sisa waktunya sendiri.
var _pulse_remaining: float = 0.0
var _pulse_scale: float = 0.45
var _pulse_duration: float = 0.18
var _cinema_remaining: float = 0.0
var _cinema_duration: float = 1.2
var _fov_last_bullet: float = 32.0

var _shake_amplitude: float = 0.0
var _shake_frequency: float = 20.0
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_phase: float = 0.0


func _init(config: Dictionary) -> void:
	var slow: Dictionary = config.get("slowMo", {})
	_crowd_scale = Cfg.num(slow, "crowdTimeScale", DEFAULT_CROWD_SCALE)
	_final_scale = Cfg.num(slow, "finalBounceTimeScale", DEFAULT_FINAL_SCALE)
	_final_threshold = int(Cfg.num(slow, "finalBounceThreshold", 3.0))
	_transition = maxf(Cfg.num(slow, "transitionDuration", DEFAULT_TRANSITION), 0.01)
	_fov_normal = Cfg.num(slow, "fovNormal", 60.0)
	_fov_slow = Cfg.num(slow, "fovBulletTime", 40.0)
	_pulse_scale = Cfg.num(slow, "bouncePulseTimeScale", 0.45)
	_pulse_duration = maxf(Cfg.num(slow, "bouncePulseDuration", 0.18), 0.01)
	_fov_last_bullet = Cfg.num(slow, "fovLastBullet", 32.0)
	var scoring: Dictionary = config.get("scoring", {})
	_cinema_duration = maxf(Cfg.num(scoring, "lastBulletZoomDuration", 1.2), 0.01)
	fov = _fov_normal
	_target_fov = _fov_normal
	var camera: Dictionary = config.get("camera", {})
	_shake_presets = camera.get("shake", {})


## Decides this frame's time scale and FOV from the run state, then eases
## toward them. Called with unscaled delta so the transition takes the same
## wall-clock time no matter how slow the world currently is.
func update(sim: SimWorld, unscaled_delta: float) -> void:
	_target_scale = 1.0
	_target_fov = _fov_normal
	if sim != null and sim.chain_riding:
		# The last few bounces are the payoff, so they get the deepest slow.
		var final_stretch := sim.chain_bounces_left <= _final_threshold
		_target_scale = _final_scale if final_stretch else _crowd_scale
		_target_fov = _fov_slow

	# Peluru terakhir menang atas segalanya: gelombang sudah habis, jadi tidak
	# ada lagi yang perlu dibaca cepat. Denyut pantulan hanya menekan sedikit,
	# dan tidak pernah membatalkan slow motion yang sudah lebih dalam.
	if _cinema_remaining > 0.0:
		_cinema_remaining -= unscaled_delta
		_target_scale = minf(_target_scale, _final_scale)
		_target_fov = minf(_target_fov, _fov_last_bullet)
	elif _pulse_remaining > 0.0:
		_pulse_remaining -= unscaled_delta
		_target_scale = minf(_target_scale, _pulse_scale)

	var step := clampf(unscaled_delta / _transition, 0.0, 1.0)
	time_scale = lerpf(time_scale, _target_scale, step)
	fov = lerpf(fov, _target_fov, step)
	if absf(time_scale - _target_scale) < 0.002:
		time_scale = _target_scale

	if _shake_remaining > 0.0:
		_shake_remaining -= unscaled_delta
		_shake_phase += unscaled_delta * _shake_frequency


## Starts a shake by name, matching the presets in config `camera.shake`.
## A stronger shake overrides a weaker one; a weaker one never cuts a
## stronger one short, which would read as the camera giving up.
func shake(preset_name: String) -> void:
	var preset: Dictionary = _shake_presets.get(preset_name, {})
	var amplitude := Cfg.num(preset, "amplitude", 0.1)
	if amplitude < current_shake_strength():
		return
	_shake_amplitude = amplitude
	_shake_frequency = Cfg.num(preset, "frequency", 20.0)
	_shake_duration = maxf(Cfg.num(preset, "duration", 0.15), 0.01)
	_shake_remaining = _shake_duration
	_shake_phase = 0.0


## Current camera offset. Two axes at different rates so it does not read as
## a single straight line of motion.
func shake_offset() -> Vector3:
	if _shake_remaining <= 0.0:
		return Vector3.ZERO
	var decay := _shake_remaining / _shake_duration
	var strength := _shake_amplitude * decay * decay
	return Vector3(
		sin(_shake_phase * TAU) * strength, cos(_shake_phase * TAU * 0.7) * strength * 0.6, 0.0
	)


func current_shake_strength() -> float:
	if _shake_remaining <= 0.0:
		return 0.0
	return _shake_amplitude * (_shake_remaining / _shake_duration)


## Maps a simulation event onto a shake. Kept here rather than in Game so the
## whole feel vocabulary lives in one file.
func react_to(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"explosion":
			shake("explosion")
		"bounce_milestone":
			shake("comboMilestone")
			pulse()
		"kill_milestone":
			shake("comboMilestone")
		"last_bullet":
			cinematic()
		"combo_milestone":
			shake("comboMilestone")
		"boss_hit":
			shake("bounceBig")
		"bounce":
			shake("bounceSmall")
		"life_lost":
			shake("explosion")


## Denyut pendek: dunia melambat sekejap lalu kembali. Dipakai tangga
## pantulan, yang terlalu sering untuk mendapat slow motion penuh.
func pulse() -> void:
	_pulse_remaining = _pulse_duration


## Potongan sinematik peluru terakhir: slow motion terdalam plus satu langkah
## zoom lagi, selama durasi yang ditulis config.
func cinematic() -> void:
	_cinema_remaining = _cinema_duration


func cinematic_remaining() -> float:
	return maxf(_cinema_remaining, 0.0)


func pulse_remaining() -> float:
	return maxf(_pulse_remaining, 0.0)
