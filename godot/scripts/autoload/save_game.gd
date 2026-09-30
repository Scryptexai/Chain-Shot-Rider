extends Node
## Meta progression: stage ladder, coins, and the upgrade cards a player owns.
##
## Deliberately small. Last War's retention comes from a full 4X base layer,
## which is months of work and a different game; what carries over here is a
## stage ladder and one card choice between stages. That is enough to make a
## run feel like it belongs to a campaign without committing to an economy
## that would need live balancing.
##
## Saved as JSON rather than a binary resource so a broken save can be read
## and fixed by hand instead of silently refusing to load.

signal progress_changed

const SAVE_PATH := "user://chainrider_save.json"
const SAVE_VERSION := 1

var unlocked_stage: int = 0
var coins: int = 0
var best_score: int = 0
var owned_cards: Array[String] = []


func _ready() -> void:
	load_progress()


## Reads the save file, falling back to a fresh profile.
func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveGame: save exists but could not be opened; starting fresh")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame: save file is corrupt; starting fresh")
		return
	var data := parsed as Dictionary
	unlocked_stage = int(data.get("unlocked_stage", 0))
	coins = int(data.get("coins", 0))
	best_score = int(data.get("best_score", 0))
	owned_cards.clear()
	for entry in data.get("owned_cards", []):
		owned_cards.append(String(entry))
	progress_changed.emit()


## Writes the save file.
func save_progress() -> void:
	var data := {
		"version": SAVE_VERSION,
		"unlocked_stage": unlocked_stage,
		"coins": coins,
		"best_score": best_score,
		"owned_cards": owned_cards,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()


## Records the outcome of a finished run.
func record_run(stage: int, won: bool, run_score: int, earned_coins: int) -> void:
	coins += earned_coins
	best_score = maxi(best_score, run_score)
	if won and stage >= unlocked_stage:
		unlocked_stage = stage + 1
	save_progress()
	progress_changed.emit()


## Adds a card to the permanent collection.
func grant_card(card_id: String) -> void:
	owned_cards.append(card_id)
	save_progress()
	progress_changed.emit()


## Folds owned cards into the stat multipliers SimWorld reads.
##
## Cards stack multiplicatively for percentage stats and additively for flat
## ones, which is why the card table stores "mul" and "add" separately rather
## than a single ambiguous "value".
func active_upgrades() -> Dictionary:
	var result: Dictionary = {}
	var cards: Array = GameConfig.list("meta.cards")
	for card_id in owned_cards:
		for entry in cards:
			var card: Dictionary = entry
			if String(card.get("id", "")) != card_id:
				continue
			var stat := String(card.get("stat", ""))
			if stat.is_empty():
				continue
			if card.has("mul"):
				result[stat] = float(result.get(stat, 1.0)) * float(card["mul"])
			elif card.has("add"):
				result[stat] = float(result.get(stat, 0.0)) + float(card["add"])
	return result


## Wipes progress. Used by the debug menu and by tests.
func reset_progress() -> void:
	unlocked_stage = 0
	coins = 0
	best_score = 0
	owned_cards.clear()
	save_progress()
	progress_changed.emit()
