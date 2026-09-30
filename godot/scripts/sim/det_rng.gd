class_name DetRng
extends RefCounted
## Deterministic xorshift128 — the same algorithm the web prototype runs.
##
## The engine RNG is deliberately avoided. Godot's RandomNumberGenerator is
## fine, but it is not the generator the balance harness measured with, and a
## replay that diverges between the prototype and the build is worse than no
## replay at all. Same algorithm, same seeding, same call order means a seed
## can be compared across both.
##
## Every draw inside a simulation tick must come from this object. A single
## call to randf() anywhere in the sim path silently breaks determinism.

const MASK32 := 0xFFFFFFFF

var _x: int = 0
var _y: int = 0
var _z: int = 0
var _w: int = 0


func _init(seed_value: int = 20260929) -> void:
	seed_with(seed_value)


## Reseeds the stream. Constants match the prototype's splitting of one seed.
func seed_with(seed_value: int) -> void:
	var s := seed_value & MASK32
	if s == 0:
		s = 0x9E3779B9
	_x = s
	_y = (s ^ 0x9E3779B9) & MASK32
	_z = (s ^ 0x85EBCA6B) & MASK32
	_w = (s ^ 0xC2B2AE35) & MASK32
	for _i in range(8):
		next_u32()


## Next raw 32-bit value.
func next_u32() -> int:
	var t := (_x ^ ((_x << 11) & MASK32)) & MASK32
	_x = _y
	_y = _z
	_z = _w
	_w = ((_w ^ (_w >> 19)) ^ (t ^ (t >> 8))) & MASK32
	return _w


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Uniform float in [low, high).
func range_float(low: float, high: float) -> float:
	return low + (high - low) * next_float()


## Uniform integer in [low, high) — low inclusive, high exclusive.
func range_int(low: int, high: int) -> int:
	if high <= low:
		return low
	return low + int(next_float() * float(high - low))


## True with the given probability.
func chance(probability: float) -> bool:
	return next_float() < probability


## Index into a weight table, proportional to the weights.
func weighted_index(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var roll := next_float() * total
	var running := 0.0
	for i in range(weights.size()):
		running += weights[i]
		if roll < running:
			return i
	return weights.size() - 1


## Snapshot of internal state, for replay assertions in tests.
func state() -> PackedInt32Array:
	return PackedInt32Array([_x, _y, _z, _w])
