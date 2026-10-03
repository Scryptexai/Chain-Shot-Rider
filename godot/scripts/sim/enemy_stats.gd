class_name EnemyStats
extends RefCounted

## Pembaca tabel statistik musuh dari config.
##
## Dipisah dari SimWorld karena isinya murni: tidak ada state, tidak ada RNG,
## tidak ada efek samping — hanya "baris ke-N tabel punya hp berapa". Memberinya
## berkas sendiri menjaga sim_world.gd tetap berisi aturan main saja, dan
## membuat nilai bawaannya bisa ditemukan dalam satu tempat ketika sebuah tipe
## musuh baru lupa mencantumkan salah satu field.


static func field(types: Array, type_index: int, key: String, fallback: float) -> float:
	if type_index < 0 or type_index >= types.size():
		return fallback
	var entry: Dictionary = types[type_index]
	return float(entry.get(key, fallback))


static func hp(types: Array, type_index: int) -> float:
	return field(types, type_index, "hp", 10.0)


static func speed(types: Array, type_index: int) -> float:
	return field(types, type_index, "speed", 0.6)


static func radius(types: Array, type_index: int) -> float:
	return field(types, type_index, "radius", 0.35)


static func score(types: Array, type_index: int) -> int:
	return int(field(types, type_index, "score", 10.0))
