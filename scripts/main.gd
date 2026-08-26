extends Node2D
## Gloom Bastion: first visual sandbox.
## This intentionally uses procedural pixel-like shapes until authored sprites are added.

const MAP_RECT := Rect2(40, 92, 1200, 570)
# PackedVector2Array is initialized at runtime because Godot does not accept
# its constructor as a constant expression in every 4.x version.
var path_points := PackedVector2Array([
	Vector2(40, 505), Vector2(220, 505), Vector2(220, 260),
	Vector2(510, 260), Vector2(510, 535), Vector2(820, 535),
	Vector2(820, 205), Vector2(1240, 205)
])
var towers: Array[Vector2] = []
var enemies: Array[Dictionary] = []
var gold := 250
var wave := 0
var running_wave := false
var spawn_timer := 0.0
var selected_position := Vector2.ZERO
var elapsed := 0.0
var projectiles: Array[Dictionary] = []
const TOWER_RANGE: float = 150.0
const TOWER_FIRE_RATE: float = 0.7
const MONSTER_TEXTURE: Texture2D = preload("res://assets/art/monster_crawler.png")
const TOWER_TEXTURE: Texture2D = preload("res://assets/art/tower_blood_crystal.png")

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if running_wave:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and enemies.size() < 14:
			spawn_timer = 0.8
			_enemies_spawn()
		for enemy in enemies:
			_move_enemy(enemy, delta)
		_update_towers(delta)
	_update_projectiles(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_position = event.position
		if MAP_RECT.has_point(event.position) and _is_buildable(event.position) and gold >= 50:
			towers.append(event.position)
			gold -= 50
			queue_redraw()
	if event.is_action_pressed("start_wave") and not running_wave:
		wave += 1
		running_wave = true
		spawn_timer = 0.0
		queue_redraw()

func _enemies_spawn() -> void:
	var enemy := {
		"position": path_points[0],
		"path_index": 1,
		"speed": 34.0 + wave * 2.0,
		"hp": 3,
		"fire_cooldown": 0.0
	}
	enemies.append(enemy)

func _move_enemy(enemy: Dictionary, delta: float) -> void:
	var path_index: int = enemy.path_index
	if path_index >= path_points.size():
		return
	var target: Vector2 = path_points[path_index]
	var current_position: Vector2 = enemy["position"]
	var speed: float = float(enemy["speed"])
	var distance: float = current_position.distance_to(target)
	var travel: float = speed * delta
	if distance <= travel:
		enemy["position"] = target
		enemy["path_index"] = path_index + 1
	else:
		enemy["position"] = current_position + current_position.direction_to(target) * travel


func _update_towers(delta: float) -> void:
	for tower_position in towers:
		var best: Dictionary = {}
		var best_distance := TOWER_RANGE
		for enemy in enemies:
			var distance: float = tower_position.distance_to(enemy["position"])
			if distance < best_distance:
				best = enemy
				best_distance = distance
		if not best.is_empty():
			var cooldown: float = float(best["fire_cooldown"]) - delta
			if cooldown <= 0.0:
				projectiles.append({"position": tower_position, "target": best, "speed": 420.0, "damage": 1})
				best["fire_cooldown"] = TOWER_FIRE_RATE

func _update_projectiles(delta: float) -> void:
	for projectile in projectiles.duplicate():
		var target: Dictionary = projectile["target"]
		if not enemies.has(target):
			projectiles.erase(projectile)
			continue
		var position: Vector2 = projectile["position"]
		var target_position: Vector2 = target["position"]
		var travel: float = float(projectile["speed"]) * delta
		if position.distance_to(target_position) <= travel:
			target["hp"] = int(target["hp"]) - int(projectile["damage"])
			projectiles.erase(projectile)
			if int(target["hp"]) <= 0:
				enemies.erase(target)
				gold += 15
		else:
			projectile["position"] = position + position.direction_to(target_position) * travel

func _is_buildable(point: Vector2) -> bool:
	for path_point in path_points:
		if point.distance_to(path_point) < 65.0:
			return false
	return true

func _draw() -> void:
	# Deep gothic parchment and subtle grid.
	draw_rect(Rect2(0, 0, 1280, 720), Color("120f18"))
	draw_rect(MAP_RECT, Color("241d29"), true)
	for x in range(40, 1240, 32):
		draw_line(Vector2(x, 92), Vector2(x, 662), Color(0.18, 0.14, 0.2, 0.35), 1)
	for y in range(92, 663, 32):
		draw_line(Vector2(40, y), Vector2(1240, y), Color(0.18, 0.14, 0.2, 0.35), 1)
	# Blood-dark road with a pale worn center.
	draw_polyline(path_points, Color("0c0b11"), 76.0, true)
	draw_polyline(path_points, Color("4b3034"), 64.0, true)
	draw_polyline(path_points, Color("68444a"), 3.0, true)
	for point in path_points:
		draw_circle(point, 5.0, Color("a86a67"))
	# Towers with range rings and authored pixel sprites.
	for point in towers:
		draw_circle(point, TOWER_RANGE, Color(0.55, 0.1, 0.13, 0.06))
		draw_arc(point, TOWER_RANGE, 0.0, TAU, 64, Color(0.65, 0.24, 0.28, 0.22), 2.0)
		draw_texture_rect(TOWER_TEXTURE, Rect2(point - Vector2(42, 50), Vector2(84, 100)), false)
	# Animated authored monster sprites and crimson projectiles.
	for enemy in enemies:
		var p: Vector2 = enemy["position"]
		var bob := sin(elapsed * 8.0 + p.x * 0.03) * 2.0
		var path_index: int = enemy["path_index"]
		var facing := Vector2.RIGHT
		if path_index < path_points.size():
			facing = p.direction_to(path_points[path_index])
		draw_set_transform(p + Vector2(0, bob), facing.angle(), Vector2(1, 1))
		draw_texture_rect(MONSTER_TEXTURE, Rect2(-28, -30, Vector2(56, 60)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var hp_ratio: float = float(enemy["hp"]) / 3.0
		draw_rect(Rect2(p + Vector2(-22, -40), Vector2(44, 4)), Color("1a1219"), true)
		draw_rect(Rect2(p + Vector2(-22, -40), Vector2(44 * hp_ratio, 4)), Color("b8454d"), true)
	for projectile in projectiles:
		draw_circle(projectile["position"], 6.0, Color("ff6b55"))
		draw_circle(projectile["position"], 13.0, Color(0.9, 0.15, 0.12, 0.18))
	# UI.
	draw_rect(Rect2(0, 0, 1280, 72), Color("0c0a10"), true)
	draw_line(Vector2(0, 71), Vector2(1280, 71), Color("71343e"), 2)
	draw_string(ThemeDB.fallback_font, Vector2(36, 34), "GLOOM BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("dfb6a1"))
	draw_string(ThemeDB.fallback_font, Vector2(36, 57), "THE NIGHT REMEMBERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("80636c"))
	draw_string(ThemeDB.fallback_font, Vector2(890, 34), "GOLD  %03d" % gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d9b477"))
	draw_string(ThemeDB.fallback_font, Vector2(1060, 34), "WAVE  %02d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c87879"))
	draw_string(ThemeDB.fallback_font, Vector2(36, 696), "CLICK TO BUILD  •  T TO SELECT  •  SPACE TO SUMMON THE NEXT WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("8c7480"))
