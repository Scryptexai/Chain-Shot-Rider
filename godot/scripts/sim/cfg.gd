class_name Cfg
extends RefCounted
## Type-safe reads out of the config dictionary.
##
## This exists because of a real failure. `spawnInterval` changed from a
## scalar to a per-wave array, `float()` threw on it, and the rest of
## `_read_config` never ran — silently restoring bossHpScale to 1.0 instead
## of the measured 0.4, zeroing the difficulty ramp, and emptying the combo
## milestones. Three of five stages stalled, and nothing in the logs pointed
## at the config.
##
## A key of the wrong type should cost one value, not every value after it.


## Reads one number, falling back rather than throwing.
static func num(source: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = source.get(key, fallback)
	if value is float or value is int:
		return float(value)
	push_warning(
		"config '%s' is %s, not a number; using %s" % [key, type_string(typeof(value)), fallback]
	)
	return fallback


## Same guard, for a numeric entry inside an array.
static func num_at(source: Array, index: int, fallback: float) -> float:
	if index < 0 or index >= source.size():
		return fallback
	var value: Variant = source[index]
	if value is float or value is int:
		return float(value)
	return fallback
