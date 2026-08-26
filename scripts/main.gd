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

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	if running_wave:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and enemies.size() < 14:
			spawn_timer = 0.8
			_enemies_spawn()
		for enemy in enemies:
			_move_enemy(enemy, delta)
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
		"speed": 34.0 + wave * 2.0
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
	# Towers: black stone silhouette, crimson core.
	for point in towers:
		draw_circle(point, 43.0, Color(0.55, 0.1, 0.13, 0.12))
		draw_circle(point, 24.0, Color("17141c"))
		draw_circle(point, 15.0, Color("792b38"))
		draw_circle(point, 7.0, Color("d06b61"))
		draw_line(point + Vector2(-17, -17), point + Vector2(17, 17), Color("302735"), 5)
	# Enemies as readable crimson silhouettes for the prototype.
	for enemy in enemies:
		var p: Vector2 = enemy.position
		draw_circle(p, 14.0, Color("0b090d"))
		draw_circle(p, 9.0, Color("943d46"))
		draw_circle(p + Vector2(-3, -2), 2.0, Color("f0b06b"))
	# UI.
	draw_rect(Rect2(0, 0, 1280, 72), Color("0c0a10"), true)
	draw_line(Vector2(0, 71), Vector2(1280, 71), Color("71343e"), 2)
	draw_string(ThemeDB.fallback_font, Vector2(36, 34), "GLOOM BASTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("dfb6a1"))
	draw_string(ThemeDB.fallback_font, Vector2(36, 57), "THE NIGHT REMEMBERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("80636c"))
	draw_string(ThemeDB.fallback_font, Vector2(890, 34), "GOLD  %03d" % gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d9b477"))
	draw_string(ThemeDB.fallback_font, Vector2(1060, 34), "WAVE  %02d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c87879"))
	draw_string(ThemeDB.fallback_font, Vector2(36, 696), "CLICK TO BUILD  •  T TO SELECT  •  SPACE TO SUMMON THE NEXT WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("8c7480"))
