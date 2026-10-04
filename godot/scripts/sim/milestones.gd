class_name Milestones
extends RefCounted

## Buku prestasi kecil sebuah run: kelipatan combo, ambang kill, tangga
## pantulan, perfect clear, dan pita near-miss.
##
## Semua ini hidup di sisi simulasi, bukan tampilan. Alasannya satu: bonusnya
## nyata — skor dan koin. Kalau hitungannya ditaruh di HUD, dua build bisa
## memberi angka berbeda untuk permainan yang sama, dan pemain yang menutup
## HUD kehilangan koinnya. Yang ditinggalkan di tampilan hanya kilat, denyut
## slow motion, dan confetti-nya.
##
## Angkanya datang dari Config/arena_config.json ("scoring" dan "arena"),
## sehingga web dan Godot menimbang prestasi yang persis sama.

## Jarak di atas garis pertahanan yang sudah dihitung "nyaris kebobolan".
var near_miss_band: float = 0.5

var _combo_steps: Array = []
var _kill_steps: Array = []
var _kill_bonus: int = 500
var _bounce_every: int = 5
var _perfect_coins: int = 50


func _init(cfg: Dictionary) -> void:
	var scoring: Dictionary = cfg.get("scoring", {})
	_combo_steps = scoring.get("comboMilestones", [10, 20, 50, 100])
	_kill_steps = scoring.get("killMilestones", [50, 100, 200])
	_kill_bonus = int(Cfg.num(scoring, "killMilestoneBonus", 500.0))
	_bounce_every = maxi(int(Cfg.num(scoring, "bounceMilestoneEvery", 5.0)), 1)
	_perfect_coins = int(Cfg.num(scoring, "perfectClearBonusCoins", 50.0))
	near_miss_band = Cfg.num(cfg.get("arena", {}), "nearMissBandZ", 0.5)


## Dipanggil tepat setelah combo naik. Perbandingannya sama-dengan, bukan
## lebih-besar: milestone berbunyi sekali saat dilewati.
func on_combo(combo: int, events: Array) -> void:
	for step in _combo_steps:
		if combo == int(step):
			events.append({"type": "combo_milestone", "combo": combo})


## Dipanggil setelah pencacah kill naik. Mengembalikan bonus skor yang harus
## ditambahkan pemanggil — nol untuk kill biasa.
func on_kill(kills: int, events: Array) -> int:
	for step in _kill_steps:
		if kills == int(step):
			events.append({"type": "kill_milestone", "kills": kills, "bonus": _kill_bonus})
			return _kill_bonus
	return 0


## Tangga pantulan: tiap kelipatan kelima layak kilat, bunyi, dan denyut.
func on_bounce(count: int, pos: Vector2, events: Array) -> void:
	if count % _bounce_every != 0:
		return
	events.append({"type": "bounce_milestone", "count": count, "x": pos.x, "z": pos.y})


## Gelombang selesai. Tanpa satu pun kebocoran, bonusnya koin — bukan skor —
## supaya hadiahnya ikut keluar dari run dan terasa di meta.
func on_wave_cleared(wave: int, leaked: int, events: Array) -> int:
	if leaked > 0:
		return 0
	events.append({"type": "perfect_clear", "wave": wave, "coins": _perfect_coins})
	return _perfect_coins
