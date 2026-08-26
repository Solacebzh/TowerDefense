extends Node
## Autoload singleton (name: Save). Stores meta-progression between runs:
## Blood Shards currency + purchased meta-upgrade levels.

const SAVE_PATH := "user://gloom_bastion.save"

var shards := 0
var meta_levels := {}          # {"start_gold": 2, ...}
var best_wave := 0
var runs := 0

func _ready() -> void:
	load_game()

func meta_level(id: String) -> int:
	return int(meta_levels.get(id, 0))

func meta_cost(id: String) -> int:
	var def: Dictionary = GameData.META[id]
	var lvl := meta_level(id)
	return int(round(def.cost * pow(def.cost_growth, lvl)))

func can_buy_meta(id: String) -> bool:
	var def: Dictionary = GameData.META[id]
	return meta_level(id) < def.max_level and shards >= meta_cost(id)

func buy_meta(id: String) -> bool:
	if not can_buy_meta(id):
		return false
	shards -= meta_cost(id)
	meta_levels[id] = meta_level(id) + 1
	save_game()
	return true

# --- Aggregated meta bonuses used by a run -----------------------------------
func bonus_start_gold() -> int:
	return meta_level("start_gold") * 40

func bonus_base_hp() -> int:
	return meta_level("base_hp") * 25

func bonus_tower_damage_mult() -> float:
	return 1.0 + meta_level("tower_power") * 0.06

func bonus_gold_mult() -> float:
	return 1.0 + meta_level("greed") * 0.08

func register_run_result(wave_reached: int, shards_earned: int) -> void:
	runs += 1
	best_wave = max(best_wave, wave_reached)
	shards += shards_earned
	save_game()

func save_game() -> void:
	var data := {
		"shards": shards,
		"meta_levels": meta_levels,
		"best_wave": best_wave,
		"runs": runs,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		shards = int(parsed.get("shards", 0))
		meta_levels = parsed.get("meta_levels", {})
		best_wave = int(parsed.get("best_wave", 0))
		runs = int(parsed.get("runs", 0))
