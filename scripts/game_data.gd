extends RefCounted
class_name GameData
## Static, data-driven definitions for Gloom Bastion.
## Everything the designer tunes lives here: towers, enemies, city buildings,
## wave pacing and meta-progression. Keeping it in one place makes balancing easy.

# --- Towers (defenses) -------------------------------------------------------
# type: "single" fires one bolt, "splash" damages an area, "beam" hits instantly.
const TOWERS := {
	"blood_crystal": {
		"name": "Cristal de Sang",
		"desc": "Éclat arcanique équilibré. Cible unique.",
		"texture": "res://assets/art/tower_blood_crystal.png",
		"cost": 55,
		"range": 168.0,
		"fire_rate": 0.75,          # seconds between shots
		"damage": 3.0,
		"projectile_speed": 460.0,
		"attack": "single",
		"splash": 0.0,
		"slow": 0.0,
		"color": "ff5545",
		"draw_w": 60.0,
	},
	"bone_ballista": {
		"name": "Baliste d'Os",
		"desc": "Harpon lourd, lent mais dévastateur. Transperce.",
		"texture": "res://assets/art/tower_bone_ballista.png",
		"cost": 90,
		"range": 240.0,
		"fire_rate": 1.6,
		"damage": 9.0,
		"projectile_speed": 620.0,
		"attack": "pierce",
		"splash": 0.0,
		"slow": 0.0,
		"color": "e8d9b0",
		"draw_w": 58.0,
	},
	"plague_cauldron": {
		"name": "Chaudron de Peste",
		"desc": "Vapeurs toxiques. Dégâts de zone + ralentissement.",
		"texture": "res://assets/art/tower_plague_cauldron.png",
		"cost": 120,
		"range": 150.0,
		"fire_rate": 1.1,
		"damage": 2.5,
		"projectile_speed": 340.0,
		"attack": "splash",
		"splash": 74.0,
		"slow": 0.45,               # slows enemies to 55% for a short time
		"color": "8fd14a",
		"draw_w": 66.0,
	},
}

# Order shown in the build bar.
const TOWER_ORDER := ["blood_crystal", "bone_ballista", "plague_cauldron"]

# --- Enemies -----------------------------------------------------------------
const ENEMIES := {
	"crawler": {
		"name": "Rampant",
		"texture": "res://assets/art/monster_crawler.png",
		"hp": 8.0,
		"speed": 62.0,
		"reward": 6,
		"damage": 6,                # damage to base if it reaches the keep
		"draw_w": 52.0,
		"gib_scale": 1.0,
	},
	"wraith": {
		"name": "Spectre",
		"texture": "res://assets/art/monster_wraith.png",
		"hp": 14.0,
		"speed": 96.0,
		"reward": 9,
		"damage": 8,
		"draw_w": 62.0,
		"gib_scale": 0.9,
	},
	"brute": {
		"name": "Charnier",
		"texture": "res://assets/art/monster_brute.png",
		"hp": 55.0,
		"speed": 34.0,
		"reward": 22,
		"damage": 25,
		"draw_w": 76.0,
		"gib_scale": 1.7,
	},
}

# --- City buildings (permanent within a run) ---------------------------------
# effect is applied globally; buildings can be levelled up (cost scales).
const BUILDINGS := {
	"forge": {
		"name": "Forge Sanglante",
		"desc": "+18% dégâts de toutes les tours par niveau.",
		"base_cost": 80,
		"cost_growth": 1.6,
		"max_level": 6,
		"color": "ff7a55",
		"glyph": "\u2692",           # crossed hammers
	},
	"treasury": {
		"name": "Trésorerie",
		"desc": "+30% d'or par ennemi tué, par niveau.",
		"base_cost": 70,
		"cost_growth": 1.55,
		"max_level": 6,
		"color": "d9b477",
		"glyph": "\u25C8",
	},
	"sanctum": {
		"name": "Sanctuaire",
		"desc": "+35 PV max au donjon et régénère entre les vagues.",
		"base_cost": 90,
		"cost_growth": 1.6,
		"max_level": 6,
		"color": "9ad1ff",
		"glyph": "\u271A",
	},
	"altar": {
		"name": "Autel de Guerre",
		"desc": "+12% cadence de tir de toutes les tours, par niveau.",
		"base_cost": 100,
		"cost_growth": 1.65,
		"max_level": 6,
		"color": "c87879",
		"glyph": "\u2666",
	},
}

const BUILDING_ORDER := ["forge", "treasury", "sanctum", "altar"]

# --- Meta upgrades (persist across runs, bought with Blood Shards) ------------
const META := {
	"start_gold": {
		"name": "Coffres Ancestraux",
		"desc": "+40 or de départ par niveau.",
		"cost": 3,
		"cost_growth": 1.5,
		"max_level": 8,
	},
	"base_hp": {
		"name": "Fondations Damnées",
		"desc": "+25 PV max du donjon par niveau.",
		"cost": 3,
		"cost_growth": 1.5,
		"max_level": 8,
	},
	"tower_power": {
		"name": "Runes de Carnage",
		"desc": "+6% dégâts de base des tours par niveau.",
		"cost": 4,
		"cost_growth": 1.6,
		"max_level": 6,
	},
	"greed": {
		"name": "Pacte de Cupidité",
		"desc": "+8% d'or gagné par niveau.",
		"cost": 4,
		"cost_growth": 1.6,
		"max_level": 6,
	},
}

const META_ORDER := ["start_gold", "base_hp", "tower_power", "greed"]

## Build a wave definition procedurally so difficulty scales forever.
## Returns an Array of spawn entries {type, delay} to feed the spawner.
static func build_wave(wave: int) -> Array:
	var spawns: Array = []
	var budget := 6 + wave * 4              # total "threat" points to spend
	var t := 0.0
	var base_gap: float = maxf(0.35, 0.95 - wave * 0.03)
	while budget > 0:
		var roll := randf()
		var type := "crawler"
		var cost := 1
		# Brutes appear from wave 3, wraiths from wave 2.
		if wave >= 3 and roll > 0.85:
			type = "brute"; cost = 6
		elif wave >= 2 and roll > 0.55:
			type = "wraith"; cost = 2
		else:
			type = "crawler"; cost = 1
		if cost > budget:
			type = "crawler"; cost = 1
		spawns.append({"type": type, "delay": t})
		budget -= cost
		t += base_gap * randf_range(0.7, 1.25)
	# A mini-boss brute every 5 waves.
	if wave % 5 == 0:
		spawns.append({"type": "brute", "delay": t + 1.0, "boss": true})
	return spawns

## HP/speed multipliers that ramp with wave number.
static func enemy_hp_mult(wave: int) -> float:
	return 1.0 + (wave - 1) * 0.14

static func enemy_speed_mult(wave: int) -> float:
	return minf(1.9, 1.0 + (wave - 1) * 0.025)
