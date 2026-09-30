extends Node
## Canonical game numbers, loaded from JSON at boot.
##
## Config/arena_config.json at the repo root is the single source of truth: the
## web prototype and the headless balance harness read that exact file. Godot
## can only read res://, so tools/sync_config.py copies it into the project.
##
## Every accessor fails loudly. A key renamed in the JSON must surface as an
## error at boot, not as a silent 0.0 that shows up two weeks later looking
## like a balance bug. Returning a quiet default is the expensive option.

const CONFIG_PATH := "res://config/arena_config.json"

var loaded: bool = false

var _root: Dictionary = {}


func _ready() -> void:
	load_config()


## Reads and parses the config. Safe to call again after an external edit.
func load_config() -> bool:
	loaded = false
	_root = {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("GameConfig: cannot open %s — run tools/sync_config.py" % CONFIG_PATH)
		return false
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameConfig: %s did not parse as a JSON object" % CONFIG_PATH)
		return false
	_root = parsed as Dictionary
	loaded = true
	return true


## Float at a dotted path, e.g. "bullet.baseSpeed" or "variants.0.theme.primary".
func num(path: String) -> float:
	var value: Variant = _resolve(path)
	if value == null:
		push_error("GameConfig: missing key '%s'" % path)
		return 0.0
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		push_error("GameConfig: key '%s' is not a number" % path)
		return 0.0
	return float(value)


## Integer at a dotted path.
func integer(path: String) -> int:
	return int(round(num(path)))


## Boolean at a dotted path.
func flag(path: String) -> bool:
	var value: Variant = _resolve(path)
	if typeof(value) != TYPE_BOOL:
		push_error("GameConfig: missing or non-bool key '%s'" % path)
		return false
	return value


## String at a dotted path.
func text(path: String) -> String:
	var value: Variant = _resolve(path)
	if typeof(value) != TYPE_STRING:
		push_error("GameConfig: missing or non-string key '%s'" % path)
		return ""
	return value


## Dictionary at a dotted path. An empty path returns the whole config.
func dict(path: String) -> Dictionary:
	var value: Variant = _resolve(path)
	if typeof(value) != TYPE_DICTIONARY:
		push_error("GameConfig: missing or non-object key '%s'" % path)
		return {}
	return value


## Array at a dotted path.
func list(path: String) -> Array:
	var value: Variant = _resolve(path)
	if typeof(value) != TYPE_ARRAY:
		push_error("GameConfig: missing or non-array key '%s'" % path)
		return []
	return value


## Colour parsed from a "#RRGGBB" theme entry.
func color(path: String) -> Color:
	var hex := text(path)
	if hex.is_empty() or not hex.begins_with("#"):
		return Color.MAGENTA
	return Color.from_string(hex, Color.MAGENTA)


## True when a key exists — for genuinely optional settings only.
func has(path: String) -> bool:
	return _resolve(path) != null


func _resolve(path: String) -> Variant:
	if path.is_empty():
		return _root
	var node: Variant = _root
	for part in path.split("."):
		var kind := typeof(node)
		if kind == TYPE_DICTIONARY:
			var as_dict := node as Dictionary
			if not as_dict.has(part):
				return null
			node = as_dict[part]
		elif kind == TYPE_ARRAY and part.is_valid_int():
			var as_array := node as Array
			var index := part.to_int()
			if index < 0 or index >= as_array.size():
				return null
			node = as_array[index]
		else:
			return null
	return node
