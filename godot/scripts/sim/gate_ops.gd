class_name GateOps
extends RefCounted

## Aritmetika gerbang: memilih sisi mana yang muncul, dan apa artinya "x2",
## "+8", "-6", atau ":2" bagi pasukan maupun bagi peluru chain.
##
## Dipisah dari SimWorld karena ini tabel dan rumus, bukan aturan arena:
## isinya hanya membaca blok "gates" di config lalu berhitung. SimWorld tetap
## memegang kapan gerbang turun dan siapa yang menyentuhnya.
##
## Urutan pengambilan acak dijaga persis seperti versi sebelumnya — satu
## panggilan `weighted_index` per sisi — supaya seed yang sama tetap
## menghasilkan run yang sama.

var enabled := true
var spawn_z := 38.0
var speed := 2.4
var half_width := 4.7
var center_gap := 0.6
var height := 0.9
var next_at := 6.0
var interval := 11.0
var jitter := 2.0
var negative_chance := 0.45

var _ops: Array = []
var _bounce_cap := 50
var _damage_cap := 4.0
var _sub_loss := 4
var _div_damage := 0.6


func _init(cfg: Dictionary, negative_chance_mul: float) -> void:
	var gate_cfg: Dictionary = cfg.get("gates", {})
	enabled = bool(gate_cfg.get("enabled", true))
	spawn_z = Cfg.num(gate_cfg, "spawnZ", 38.0)
	speed = Cfg.num(gate_cfg, "descendSpeed", 2.4)
	half_width = Cfg.num(gate_cfg, "halfWidth", 4.7)
	center_gap = Cfg.num(gate_cfg, "centerGapX", 0.6)
	height = Cfg.num(gate_cfg, "height", 0.9)
	next_at = Cfg.num(gate_cfg, "firstAtSeconds", 6.0)
	interval = Cfg.num(gate_cfg, "intervalSeconds", 11.0)
	jitter = Cfg.num(gate_cfg, "intervalJitter", 2.0)
	negative_chance = Cfg.num(gate_cfg, "negativeSideChance", 0.45) * negative_chance_mul
	_ops = gate_cfg.get("squadOps", [])
	var effects: Dictionary = gate_cfg.get("bulletEffects", {})
	_bounce_cap = int(effects.get("bounceBudgetCap", 50))
	_damage_cap = Cfg.num(effects, "damageMulCap", 4.0)
	_sub_loss = int(effects.get("subBounceLoss", 4))
	_div_damage = Cfg.num(effects, "divDamageMul", 0.6)


func pick(rng: DetRng, want_negative: bool) -> Dictionary:
	var pool: Array = []
	var weights := PackedFloat32Array()
	for op in _ops:
		var entry: Dictionary = op
		if bool(entry.get("positive", true)) != want_negative:
			pool.append(entry)
			weights.append(float(entry.get("weight", 1.0)))
	if pool.is_empty():
		return {"op": "add", "value": 1.0, "positive": true}
	return pool[rng.weighted_index(weights)]


## Pasukan: hasilnya sudah dijepit ke rentang yang sah.
func apply_to_troops(value: int, side: Dictionary, max_troops: int) -> int:
	var amount := float(side.get("value", 1.0))
	var result := value
	match String(side.get("op", "add")):
		"mul":
			result = int(float(value) * amount)
		"add":
			result = value + int(amount)
		"sub":
			result = value - int(amount)
		"div":
			result = int(float(value) / maxf(amount, 1.0))
	return clampi(result, 0, max_troops)


## Peluru: mengembalikan anggaran pantulan dan pengali damage yang baru,
## beserta nama operasinya untuk event tampilan.
func apply_to_bullet(side: Dictionary, bounces: int, damage_mul: float) -> Dictionary:
	var op := String(side.get("op", "add"))
	var value := float(side.get("value", 1.0))
	match op:
		"mul":
			bounces = mini(int(float(bounces) * value), _bounce_cap)
			damage_mul = minf(damage_mul * 1.1, _damage_cap)
		"add":
			bounces = mini(bounces + int(value * 0.5), _bounce_cap)
		"sub":
			bounces = maxi(bounces - _sub_loss, 1)
		"div":
			damage_mul = maxf(damage_mul * _div_damage, 0.25)
	return {"bounces": bounces, "damage_mul": damage_mul, "op": op}
