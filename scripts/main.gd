extends Node2D
## GLOOM BASTION — roguelite tower defense core loop.
##
## Loop:  Build phase  ->  summon wave  ->  survive  ->  earn gold
##        -> spend on TOWERS (defense) or CITY BUILDINGS (permanent buffs)
##        -> harder wave -> ... -> keep destroyed = run ends -> Blood Shards
##        feed meta-progression that persists to the next run.
##
## Rendered in immediate mode (_draw) with manual, reliable UI hit-testing so
## the whole game lives in code and needs no editor wiring.

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const SCREEN := Vector2(1280, 720)
const TOP_BAR := 64.0
const BOTTOM_BAR := 132.0
const TILE := 40.0
const MAP_RECT := Rect2(0, TOP_BAR, 1280, 720 - TOP_BAR - BOTTOM_BAR)

# Enemy path (waypoints). Enemies walk these toward the keep.
var path_points := PackedVector2Array([
	Vector2(-30, 150), Vector2(300, 150), Vector2(300, 330),
	Vector2(120, 330), Vector2(120, 470), Vector2(560, 470),
	Vector2(560, 250), Vector2(820, 250), Vector2(820, 430),
	Vector2(1060, 430),
])
const KEEP_POS := Vector2(1128, 430)
const KEEP_DRAW_W := 300.0

# City building plots (placed near the keep).
var building_plots := [
	{"id": "", "pos": Vector2(1010, 300), "type_index": 0},
	{"id": "", "pos": Vector2(1130, 300), "type_index": 1},
	{"id": "", "pos": Vector2(1010, 540), "type_index": 2},
	{"id": "", "pos": Vector2(1130, 540), "type_index": 3},
]

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------
enum Phase { MENU, BUILD, COMBAT, GAMEOVER }
var phase: int = Phase.MENU

# ---------------------------------------------------------------------------
# Run state
# ---------------------------------------------------------------------------
var gold := 0
var wave := 0
var base_hp := 0
var base_hp_max := 0
var shards_this_run := 0

var towers: Array = []          # each: Tower (inner class)
var enemies: Array = []         # each: Enemy
var projectiles: Array = []     # each: Projectile
var gibs: Array = []            # gore chunks
var blood_decals: Array = []    # persistent ground splatter {pos, r, col, a}
var floaters: Array = []        # floating combat text {pos, text, col, life}

# Building levels for the current run: {"forge": 2, ...}
var building_levels := {}

# ---------------------------------------------------------------------------
# Wave spawner
# ---------------------------------------------------------------------------
var wave_queue: Array = []       # pending spawns for the active wave
var wave_timer := 0.0
var spawned_this_wave := 0
var total_this_wave := 0

# ---------------------------------------------------------------------------
# Input / selection
# ---------------------------------------------------------------------------
var selected_tower_type := "blood_crystal"
var hover_cell := Vector2i(-999, -999)
var mouse_pos := Vector2.ZERO
var elapsed := 0.0
var shake := 0.0
var buttons: Array = []          # rebuilt each frame: {rect, action, arg}

# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------
var tex := {}

# Fonts
var font: Font
var font_big: Font

# ===========================================================================
# Inner data classes
# ===========================================================================
class Tower:
	var type: String
	var pos: Vector2
	var cooldown := 0.0
	func _init(t: String, p: Vector2) -> void:
		type = t
		pos = p

class Enemy:
	var type: String
	var pos: Vector2
	var path_index := 1
	var hp: float
	var hp_max: float
	var speed: float
	var base_speed: float
	var reward: int
	var damage: int
	var slow_timer := 0.0
	var boss := false
	var bob := 0.0
	var hit_flash := 0.0
	var facing := Vector2.RIGHT

class Projectile:
	var pos: Vector2
	var target                   # Enemy or null
	var speed: float
	var damage: float
	var attack: String
	var splash: float
	var slow: float
	var color: Color
	var vel := Vector2.ZERO       # for pierce shots that keep flying
	var life := 2.0
	var already_hit := []          # enemies a pierce shot has already damaged

class Gib:
	var pos: Vector2
	var vel: Vector2
	var rot: float
	var spin: float
	var size: float
	var life: float
	var col: Color

# ===========================================================================
# Lifecycle
# ===========================================================================
func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	font_big = ThemeDB.fallback_font
	_load_textures()
	set_process(true)
	queue_redraw()

func _load_textures() -> void:
	tex["keep"] = load("res://assets/art/keep_blood.png")
	for id in GameData.TOWERS:
		tex[id] = load(GameData.TOWERS[id].texture)
	for id in GameData.ENEMIES:
		tex[id] = load(GameData.ENEMIES[id].texture)

# ===========================================================================
# Run management
# ===========================================================================
func start_run() -> void:
	gold = 200 + Save.bonus_start_gold()
	wave = 0
	base_hp_max = 200 + Save.bonus_base_hp()
	base_hp = base_hp_max
	shards_this_run = 0
	towers.clear()
	enemies.clear()
	projectiles.clear()
	gibs.clear()
	blood_decals.clear()
	floaters.clear()
	building_levels.clear()
	for plot in building_plots:
		plot.id = ""
	wave_queue.clear()
	phase = Phase.BUILD

func begin_wave() -> void:
	if phase != Phase.BUILD:
		return
	wave += 1
	wave_queue = GameData.build_wave(wave)
	total_this_wave = wave_queue.size()
	spawned_this_wave = 0
	wave_timer = 0.0
	phase = Phase.COMBAT

func end_wave() -> void:
	# Reward + sanctum regen, back to build.
	var sanctum_lvl := int(building_levels.get("sanctum", 0))
	if sanctum_lvl > 0:
		base_hp = min(base_hp_max, base_hp + sanctum_lvl * 12)
	gold += 30 + wave * 6         # wave clear bonus
	_add_floater(KEEP_POS + Vector2(0, -120), "VAGUE %d SURVÉCUE" % wave, Color("d9b477"))
	phase = Phase.BUILD

func game_over() -> void:
	phase = Phase.GAMEOVER
	shards_this_run = 3 + wave / 2
	Save.register_run_result(wave, shards_this_run)

# ===========================================================================
# Process
# ===========================================================================
func _process(delta: float) -> void:
	elapsed += delta
	shake = max(0.0, shake - delta * 3.0)
	_update_floaters(delta)
	_update_gibs(delta)
	if phase == Phase.COMBAT:
		_update_spawner(delta)
		for e in enemies.duplicate():
			_update_enemy(e, delta)
		_update_towers(delta)
		_update_projectiles(delta)
		# Wave finished?
		if spawned_this_wave >= total_this_wave and enemies.is_empty():
			end_wave()
		if base_hp <= 0:
			game_over()
	queue_redraw()

func _update_spawner(delta: float) -> void:
	wave_timer += delta
	while spawned_this_wave < wave_queue.size() and wave_queue[spawned_this_wave].delay <= wave_timer:
		_spawn_enemy(wave_queue[spawned_this_wave])
		spawned_this_wave += 1

func _spawn_enemy(entry: Dictionary) -> void:
	var def: Dictionary = GameData.ENEMIES[entry.type]
	var e := Enemy.new()
	e.type = entry.type
	e.pos = path_points[0]
	e.path_index = 1
	e.hp_max = def.hp * GameData.enemy_hp_mult(wave)
	e.speed = def.speed * GameData.enemy_speed_mult(wave)
	if entry.get("boss", false):
		e.hp_max *= 4.0
		e.speed *= 0.8
		e.boss = true
	e.hp = e.hp_max
	e.base_speed = e.speed
	e.reward = def.reward
	e.damage = def.damage
	enemies.append(e)

func _update_enemy(e: Enemy, delta: float) -> void:
	e.bob += delta
	e.hit_flash = max(0.0, e.hit_flash - delta * 4.0)
	if e.slow_timer > 0.0:
		e.slow_timer -= delta
		e.speed = e.base_speed * 0.5
	else:
		e.speed = e.base_speed
	if e.path_index >= path_points.size():
		# Reached the keep: damage base, die.
		_damage_base(e.damage)
		_spawn_blood(e.pos, 10, e)
		enemies.erase(e)
		return
	var target: Vector2 = path_points[e.path_index]
	var to := target - e.pos
	var dist := to.length()
	var travel := e.speed * delta
	if dist > 0.001:
		e.facing = to / dist
	if dist <= travel:
		e.pos = target
		e.path_index += 1
	else:
		e.pos += e.facing * travel

func _damage_base(amount: int) -> void:
	base_hp = max(0, base_hp - amount)
	shake = 1.0
	_add_floater(KEEP_POS + Vector2(0, -110), "-%d" % amount, Color("ff4a4a"))

# ---------------------------------------------------------------------------
# Towers firing
# ---------------------------------------------------------------------------
func _tower_damage_mult() -> float:
	var forge := int(building_levels.get("forge", 0))
	return Save.bonus_tower_damage_mult() * (1.0 + forge * 0.18)

func _tower_rate_mult() -> float:
	var altar := int(building_levels.get("altar", 0))
	return 1.0 / (1.0 + altar * 0.12)   # lower cooldown = faster

func _update_towers(delta: float) -> void:
	var dmg_mult := _tower_damage_mult()
	var rate_mult := _tower_rate_mult()
	for t in towers:
		t.cooldown -= delta
		if t.cooldown > 0.0:
			continue
		var def: Dictionary = GameData.TOWERS[t.type]
		var best: Enemy = null
		var best_progress := -1.0
		for e in enemies:
			var d := t.pos.distance_to(e.pos)
			if d <= def.range:
				# Prefer the enemy furthest along the path (closest to keep).
				var progress := float(e.path_index) + (1.0 - e.pos.distance_to(path_points[min(e.path_index, path_points.size()-1)]) * 0.001)
				if progress > best_progress:
					best_progress = progress
					best = e
		if best != null:
			_fire(t, def, best, dmg_mult)
			t.cooldown = def.fire_rate * rate_mult

func _fire(t: Tower, def: Dictionary, target: Enemy, dmg_mult: float) -> void:
	var p := Projectile.new()
	p.pos = t.pos + Vector2(0, -24)
	p.target = target
	p.speed = def.projectile_speed
	p.damage = def.damage * dmg_mult
	p.attack = def.attack
	p.splash = def.splash
	p.slow = def.slow
	p.color = Color(def.color)
	if def.attack == "pierce":
		p.vel = (target.pos - p.pos).normalized() * def.projectile_speed
	projectiles.append(p)

func _update_projectiles(delta: float) -> void:
	for p in projectiles.duplicate():
		p.life -= delta
		if p.life <= 0.0:
			projectiles.erase(p)
			continue
		if p.attack == "pierce":
			var prev := p.pos
			p.pos += p.vel * delta
			# hit any enemy passed through (once each)
			for e in enemies.duplicate():
				if not p.already_hit.has(e) and _seg_hits(prev, p.pos, e.pos, 26.0):
					p.already_hit.append(e)
					_deal_damage(e, p.damage, p)
			if not MAP_RECT.grow(80).has_point(p.pos):
				projectiles.erase(p)
			continue
		# homing single / splash
		if p.target == null or not enemies.has(p.target):
			# retarget nearest or die
			projectiles.erase(p)
			continue
		var tpos: Vector2 = p.target.pos
		var travel := p.speed * delta
		if p.pos.distance_to(tpos) <= travel:
			p.pos = tpos
			_impact(p)
			projectiles.erase(p)
		else:
			p.pos += p.pos.direction_to(tpos) * travel

func _impact(p: Projectile) -> void:
	if p.attack == "splash":
		for e in enemies.duplicate():
			if e.pos.distance_to(p.pos) <= p.splash:
				_deal_damage(e, p.damage, p)
		_add_floater(p.pos, "", Color("8fd14a"))
	else:
		if enemies.has(p.target):
			_deal_damage(p.target, p.damage, p)

func _deal_damage(e: Enemy, amount: float, p: Projectile) -> void:
	e.hp -= amount
	e.hit_flash = 1.0
	if p.slow > 0.0:
		e.slow_timer = 2.2
	_spawn_blood(e.pos, 4, e)
	if e.hp <= 0.0:
		_kill_enemy(e)

func _kill_enemy(e: Enemy) -> void:
	var greed := Save.bonus_gold_mult()
	var treasury := int(building_levels.get("treasury", 0))
	var reward := int(round(e.reward * greed * (1.0 + treasury * 0.30)))
	gold += reward
	_add_floater(e.pos + Vector2(0, -30), "+%d" % reward, Color("d9b477"))
	_spawn_gibs(e)
	_spawn_blood(e.pos, 16, e)
	enemies.erase(e)

# ---------------------------------------------------------------------------
# Gore
# ---------------------------------------------------------------------------
func _spawn_blood(pos: Vector2, count: int, e) -> void:
	var gib_scale := 1.0
	if e != null:
		gib_scale = GameData.ENEMIES[e.type].gib_scale
	for i in count:
		var g := Gib.new()
		g.pos = pos
		var ang := randf() * TAU
		var spd := randf_range(30, 220) * gib_scale
		g.vel = Vector2(cos(ang), sin(ang)) * spd
		g.rot = randf() * TAU
		g.spin = randf_range(-8, 8)
		g.size = randf_range(2, 5) * gib_scale
		g.life = randf_range(0.25, 0.6)
		g.col = Color("8f1d1d").lerp(Color("d43a3a"), randf())
		gibs.append(g)

func _spawn_gibs(e: Enemy) -> void:
	var gib_scale: float = GameData.ENEMIES[e.type].gib_scale
	var n := int(4 + gib_scale * 3)
	for i in n:
		var g := Gib.new()
		g.pos = e.pos
		var ang := randf() * TAU
		g.vel = Vector2(cos(ang), sin(ang)) * randf_range(60, 260) * gib_scale
		g.rot = randf() * TAU
		g.spin = randf_range(-12, 12)
		g.size = randf_range(4, 9) * gib_scale
		g.life = randf_range(0.5, 1.1)
		g.col = Color("5a1414").lerp(Color("b83232"), randf())
		gibs.append(g)
	# permanent splatter decal
	blood_decals.append({
		"pos": e.pos + Vector2(randf_range(-6,6), randf_range(-4,8)),
		"r": randf_range(10, 20) * gib_scale,
		"col": Color(0.35, 0.05, 0.06, 0.5),
	})
	if blood_decals.size() > 120:
		blood_decals.pop_front()

func _update_gibs(delta: float) -> void:
	for g in gibs.duplicate():
		g.life -= delta
		if g.life <= 0.0:
			gibs.erase(g)
			continue
		g.vel *= 0.90
		g.vel.y += 180 * delta      # gravity
		g.pos += g.vel * delta
		g.rot += g.spin * delta

func _add_floater(pos: Vector2, text: String, col: Color) -> void:
	if text == "":
		return
	floaters.append({"pos": pos, "text": text, "col": col, "life": 1.0})

func _update_floaters(delta: float) -> void:
	for f in floaters.duplicate():
		f.life -= delta * 0.9
		f.pos.y -= 26 * delta
		if f.life <= 0.0:
			floaters.erase(f)

# ===========================================================================
# City buildings
# ===========================================================================
func building_cost(id: String) -> int:
	var def: Dictionary = GameData.BUILDINGS[id]
	var lvl := int(building_levels.get(id, 0))
	return int(round(def.base_cost * pow(def.cost_growth, lvl)))

func can_build(id: String) -> bool:
	var def: Dictionary = GameData.BUILDINGS[id]
	return int(building_levels.get(id, 0)) < def.max_level and gold >= building_cost(id)

func build_or_upgrade(id: String) -> void:
	if not can_build(id):
		return
	gold -= building_cost(id)
	building_levels[id] = int(building_levels.get(id, 0)) + 1
	# sanctum raises max hp immediately
	if id == "sanctum":
		base_hp_max += 35
		base_hp += 35

# ===========================================================================
# Tower placement helpers
# ===========================================================================
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor((p.y) / TILE)))

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)

func is_buildable_cell(c: Vector2i) -> bool:
	var center := cell_center(c)
	if not MAP_RECT.has_point(center):
		return false
	# not on the path
	for i in range(path_points.size() - 1):
		if _point_seg_dist(center, path_points[i], path_points[i+1]) < 44.0:
			return false
	# not on the keep
	if center.distance_to(KEEP_POS) < 130.0:
		return false
	# not on a building plot
	for plot in building_plots:
		if center.distance_to(plot.pos) < 60.0:
			return false
	# not on an existing tower
	for t in towers:
		if cell_of(t.pos) == c:
			return false
	return true

func try_place_tower(p: Vector2) -> void:
	var c := cell_of(p)
	if not is_buildable_cell(c):
		return
	var def: Dictionary = GameData.TOWERS[selected_tower_type]
	if gold < def.cost:
		return
	gold -= def.cost
	towers.append(Tower.new(selected_tower_type, cell_center(c)))

# ===========================================================================
# Geometry helpers
# ===========================================================================
func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _seg_hits(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	return _point_seg_dist(center, a, b) <= radius

# ===========================================================================
# Input
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_pos = event.position
		hover_cell = cell_of(mouse_pos)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE:
			if phase == Phase.BUILD:
				begin_wave()
		KEY_1:
			selected_tower_type = "blood_crystal"
		KEY_2:
			selected_tower_type = "bone_ballista"
		KEY_3:
			selected_tower_type = "plague_cauldron"

func _handle_click(pos: Vector2) -> void:
	# UI buttons first (they were rebuilt during _draw).
	for b in buttons:
		if b.rect.has_point(pos):
			_do_action(b.action, b.get("arg", null))
			return
	# City plots
	if phase == Phase.BUILD or phase == Phase.COMBAT:
		for plot in building_plots:
			if pos.distance_to(plot.pos) < 46.0:
				var id: String = GameData.BUILDING_ORDER[plot.type_index]
				if plot.id == "":
					plot.id = id
				build_or_upgrade(id)
				return
	# Place tower on map
	if phase == Phase.BUILD or phase == Phase.COMBAT:
		if MAP_RECT.has_point(pos):
			try_place_tower(pos)

func _do_action(action: String, arg) -> void:
	match action:
		"start_run":
			start_run()
		"begin_wave":
			begin_wave()
		"select_tower":
			selected_tower_type = arg
		"buy_meta":
			Save.buy_meta(arg)
		"restart":
			start_run()
		"to_menu":
			phase = Phase.MENU

# ===========================================================================
# Small drawing helpers
# ===========================================================================
func _ui_text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, size, col)

func _button(rect: Rect2, label: String, action: String, arg = null, enabled := true, accent := Color("71343e")) -> void:
	var mouse_in := rect.has_point(mouse_pos)
	var bg := Color("1a151f")
	if not enabled:
		bg = Color("15121a")
	elif mouse_in:
		bg = Color("2a2030")
	draw_rect(rect, bg, true)
	draw_rect(rect, accent, false, 2.0)
	var col := Color("e7d5c6") if enabled else Color("5b4f57")
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_ui_text(rect.position + Vector2((rect.size.x - tw) * 0.5, rect.size.y * 0.5 + 6), label, 16, col)
	if enabled:
		buttons.append({"rect": rect, "action": action, "arg": arg})

func _draw_sprite(tex_key: String, center: Vector2, target_w: float) -> void:
	var t: Texture2D = tex.get(tex_key)
	if t == null:
		return
	var s := target_w / float(t.get_width())
	var sz := Vector2(t.get_width(), t.get_height()) * s
	# anchor bottom-center so things "stand" on their spot
	var origin := center - Vector2(sz.x * 0.5, sz.y * 0.86)
	draw_texture_rect(t, Rect2(origin, sz), false)

# ===========================================================================
# Main draw
# ===========================================================================
func _draw() -> void:
	buttons.clear()
	var shake_off := Vector2.ZERO
	if shake > 0.0:
		shake_off = Vector2(randf_range(-1,1), randf_range(-1,1)) * shake * 6.0
	draw_set_transform(shake_off, 0.0, Vector2.ONE)

	match phase:
		Phase.MENU:
			_draw_menu()
		Phase.GAMEOVER:
			_draw_world()
			_draw_gameover()
		_:
			_draw_world()
			_draw_hud()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------------------
func _draw_world() -> void:
	# Background
	draw_rect(Rect2(0, 0, SCREEN.x, SCREEN.y), Color("0c0a12"), true)
	draw_rect(MAP_RECT, Color("1a1520"), true)
	# subtle grid
	var gx := int(MAP_RECT.position.x)
	while gx < MAP_RECT.end.x:
		draw_line(Vector2(gx, MAP_RECT.position.y), Vector2(gx, MAP_RECT.end.y), Color(0.16,0.12,0.18,0.5), 1.0)
		gx += int(TILE)
	var gy := int(MAP_RECT.position.y)
	while gy < MAP_RECT.end.y:
		draw_line(Vector2(MAP_RECT.position.x, gy), Vector2(MAP_RECT.end.x, gy), Color(0.16,0.12,0.18,0.5), 1.0)
		gy += int(TILE)

	# Blood decals under everything
	for d in blood_decals:
		draw_circle(d.pos, d.r, d.col)
		draw_circle(d.pos + Vector2(d.r*0.5, d.r*0.3), d.r*0.4, d.col)

	# Path
	draw_polyline(path_points, Color("0a0810"), 52.0, true)
	draw_polyline(path_points, Color("3a252b"), 42.0, true)
	draw_polyline(path_points, Color("512f35"), 3.0, true)
	# Spawn portal marker
	var spawn := path_points[0]
	var pulse: float = 0.5 + 0.5 * sin(elapsed * 3.0)
	draw_circle(spawn + Vector2(30, 0), 26.0, Color(0.7, 0.1, 0.12, 0.25 + 0.2 * pulse))
	draw_arc(spawn + Vector2(30, 0), 26.0, 0, TAU, 24, Color("b83240"), 2.0)

	# Build hover preview
	if (phase == Phase.BUILD or phase == Phase.COMBAT) and MAP_RECT.has_point(mouse_pos):
		var c := hover_cell
		var center := cell_center(c)
		var ok := is_buildable_cell(c)
		var def: Dictionary = GameData.TOWERS[selected_tower_type]
		var col := Color(0.4, 0.9, 0.4, 0.25) if (ok and gold >= def.cost) else Color(0.9, 0.2, 0.2, 0.22)
		draw_rect(Rect2(Vector2(c.x*TILE, c.y*TILE), Vector2(TILE, TILE)), col, true)
		if ok:
			draw_circle(center, def.range, Color(0.7, 0.2, 0.2, 0.05))
			draw_arc(center, def.range, 0, TAU, 48, Color(0.8, 0.3, 0.3, 0.25), 1.5)

	# City building plots
	for plot in building_plots:
		_draw_building_plot(plot)

	# The keep (base)
	_draw_keep()

	# Towers (sorted by y for depth)
	var sorted_towers := towers.duplicate()
	sorted_towers.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for t in sorted_towers:
		var def: Dictionary = GameData.TOWERS[t.type]
		if phase == Phase.BUILD:
			draw_arc(t.pos, def.range, 0, TAU, 40, Color(0.7, 0.25, 0.28, 0.10), 1.0)
		# shadow
		draw_circle(t.pos + Vector2(0, 4), def.draw_w * 0.28, Color(0,0,0,0.35))
		_draw_sprite(t.type, t.pos, def.draw_w)

	# Enemies (sorted by y)
	var sorted_enemies := enemies.duplicate()
	sorted_enemies.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for e in sorted_enemies:
		_draw_enemy(e)

	# Gibs
	for g in gibs:
		draw_set_transform(g.pos, g.rot, Vector2.ONE)
		draw_rect(Rect2(-g.size*0.5, -g.size*0.5, g.size, g.size), g.col, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Projectiles
	for p in projectiles:
		draw_circle(p.pos, 12.0, Color(p.color.r, p.color.g, p.color.b, 0.15))
		draw_circle(p.pos, 5.0, p.color)

	# Floaters
	for f in floaters:
		var a: float = clamp(f.life, 0.0, 1.0)
		_ui_text(f.pos, f.text, 16, Color(f.col.r, f.col.g, f.col.b, a))

	# Vignette-ish darkening at map edges
	draw_rect(Rect2(0, MAP_RECT.position.y, SCREEN.x, 8), Color(0,0,0,0.35))

func _draw_keep() -> void:
	draw_circle(KEEP_POS + Vector2(0, 20), 120.0, Color(0,0,0,0.4))
	_draw_sprite("keep", KEEP_POS, KEEP_DRAW_W)
	# HP bar above keep
	var w := 180.0
	var top := KEEP_POS + Vector2(-w*0.5, -150)
	draw_rect(Rect2(top, Vector2(w, 12)), Color("120d12"), true)
	var ratio: float = clamp(float(base_hp) / float(base_hp_max), 0.0, 1.0)
	var hpcol := Color("b83240").lerp(Color("3fae54"), ratio)
	draw_rect(Rect2(top, Vector2(w * ratio, 12)), hpcol, true)
	draw_rect(Rect2(top, Vector2(w, 12)), Color("71343e"), false, 1.5)
	_ui_text(top + Vector2(0, -6), "DONJON  %d / %d" % [base_hp, base_hp_max], 13, Color("cbb0a0"))

func _draw_building_plot(plot: Dictionary) -> void:
	var id: String = GameData.BUILDING_ORDER[plot.type_index]
	var def: Dictionary = GameData.BUILDINGS[id]
	var lvl := int(building_levels.get(id, 0))
	var pos: Vector2 = plot.pos
	var hovered := mouse_pos.distance_to(pos) < 46.0
	# base pad
	draw_circle(pos + Vector2(0, 6), 40.0, Color(0,0,0,0.3))
	var pad := Color("241c26")
	if plot.id == "":
		pad = Color("1c1620")
	draw_rect(Rect2(pos - Vector2(34, 30), Vector2(68, 62)), pad, true)
	draw_rect(Rect2(pos - Vector2(34, 30), Vector2(68, 62)), Color(def.color), false, 2.0)
	if plot.id == "":
		_ui_text(pos + Vector2(-14, 6), "+", 30, Color(def.color, 0.7))
		_ui_text(pos + Vector2(-30, 30), def.name, 10, Color("8a7680"))
	else:
		# a little tower of level pips + glyph
		_ui_text(pos + Vector2(-10, 2), def.glyph, 26, Color(def.color))
		for i in lvl:
			draw_rect(Rect2(pos + Vector2(-30 + i*11, 16), Vector2(8, 6)), Color(def.color), true)
		_ui_text(pos + Vector2(-30, -34), "%s Nv.%d" % [def.name, lvl], 10, Color("cbb0a0"))
	# cost tooltip on hover
	if hovered and phase != Phase.GAMEOVER:
		var maxed := lvl >= def.max_level
		var label := "MAX" if maxed else "%d or" % building_cost(id)
		var affordable := (not maxed) and gold >= building_cost(id)
		var col := Color("3fae54") if affordable else Color("b06a6a")
		if maxed:
			col = Color("d9b477")
		draw_rect(Rect2(pos + Vector2(-70, 40), Vector2(140, 40)), Color("120d14"), true)
		draw_rect(Rect2(pos + Vector2(-70, 40), Vector2(140, 40)), Color(def.color), false, 1.5)
		_ui_text(pos + Vector2(-62, 56), def.desc.substr(0, 22), 9, Color("9a8690"))
		_ui_text(pos + Vector2(-62, 74), label, 12, col)

func _draw_enemy(e: Enemy) -> void:
	var def: Dictionary = GameData.ENEMIES[e.type]
	var bob := sin(e.bob * 8.0) * 2.0
	var draw_pos := e.pos + Vector2(0, bob)
	# shadow
	draw_circle(e.pos + Vector2(0, 6), def.draw_w * 0.24, Color(0,0,0,0.35))
	var scale_w: float = def.draw_w * (1.35 if e.boss else 1.0)
	# flip toward facing
	var flip := -1.0 if e.facing.x < 0 else 1.0
	var t: Texture2D = tex.get(e.type)
	if t:
		var s := scale_w / float(t.get_width())
		var sz := Vector2(t.get_width(), t.get_height()) * s
		draw_set_transform(draw_pos, 0.0, Vector2(flip, 1.0))
		var origin := Vector2(-sz.x * 0.5, -sz.y * 0.82)
		# hit flash: draw white-ish overlay by modulate
		var mod := Color(1,1,1,1)
		if e.hit_flash > 0.0:
			mod = Color(1, 0.6, 0.6, 1).lerp(Color(1,1,1,1), 1.0 - e.hit_flash)
		draw_texture_rect(t, Rect2(origin, sz), false, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if e.slow_timer > 0.0:
		draw_circle(e.pos, def.draw_w * 0.4, Color(0.5, 0.9, 0.3, 0.12))
	# hp bar
	var bw: float = def.draw_w * 0.8
	var bp := e.pos + Vector2(-bw*0.5, -def.draw_w * (0.95 if e.boss else 0.75))
	draw_rect(Rect2(bp, Vector2(bw, 5)), Color("140d10"), true)
	var r: float = clamp(e.hp / e.hp_max, 0.0, 1.0)
	var col := Color("d43a3a") if not e.boss else Color("ff8a2a")
	draw_rect(Rect2(bp, Vector2(bw * r, 5)), col, true)

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _draw_hud() -> void:
	# Top bar
	draw_rect(Rect2(0, 0, SCREEN.x, TOP_BAR), Color("0b0910"), true)
	draw_line(Vector2(0, TOP_BAR), Vector2(SCREEN.x, TOP_BAR), Color("71343e"), 2.0)
	_ui_text(Vector2(24, 30), "GLOOM BASTION", 22, Color("dfb6a1"))
	_ui_text(Vector2(24, 50), "LA NUIT SE SOUVIENT", 11, Color("80636c"))
	_ui_text(Vector2(430, 40), "OR  %d" % gold, 22, Color("d9b477"))
	_ui_text(Vector2(600, 40), "VAGUE  %d" % wave, 22, Color("c87879"))
	_ui_text(Vector2(770, 40), "ÉCLATS  %d" % Save.shards, 18, Color("b57bd6"))
	# phase indicator + wave button
	if phase == Phase.BUILD:
		_ui_text(Vector2(960, 26), "PHASE DE CONSTRUCTION", 13, Color("9ad1a0"))
		_button(Rect2(960, 34, 240, 24), "▶  INVOQUER LA VAGUE  (Espace)", "begin_wave", null, true, Color("3fae54"))
	else:
		var remaining := (total_this_wave - spawned_this_wave) + enemies.size()
		_ui_text(Vector2(960, 40), "COMBAT — restants: %d" % remaining, 15, Color("d47a7a"))

	# Bottom build bar
	var by := SCREEN.y - BOTTOM_BAR
	draw_rect(Rect2(0, by, SCREEN.x, BOTTOM_BAR), Color("0b0910"), true)
	draw_line(Vector2(0, by), Vector2(SCREEN.x, by), Color("71343e"), 2.0)
	_ui_text(Vector2(24, by + 24), "TOURS  (1-3 ou clic)", 13, Color("9a8690"))
	var x := 24.0
	for id in GameData.TOWER_ORDER:
		_draw_tower_card(Rect2(x, by + 34, 220, 84), id)
		x += 232
	# building hint
	_ui_text(Vector2(x + 8, by + 40), "VILLE →", 14, Color("9a8690"))
	_ui_text(Vector2(x + 8, by + 62), "Clique les socles près", 11, Color("7a6670"))
	_ui_text(Vector2(x + 8, by + 78), "du donjon pour bâtir /", 11, Color("7a6670"))
	_ui_text(Vector2(x + 8, by + 94), "améliorer ta ville.", 11, Color("7a6670"))

func _draw_tower_card(rect: Rect2, id: String) -> void:
	var def: Dictionary = GameData.TOWERS[id]
	var selected := selected_tower_type == id
	var affordable := gold >= def.cost
	var bg := Color("1a151f")
	if selected:
		bg = Color("2c2030")
	elif rect.has_point(mouse_pos):
		bg = Color("241c28")
	draw_rect(rect, bg, true)
	draw_rect(rect, Color(def.color) if selected else Color("4a3038"), false, 2.0 if selected else 1.5)
	# icon
	_draw_sprite(id, rect.position + Vector2(34, 58), 52.0)
	_ui_text(rect.position + Vector2(64, 20), def.name, 14, Color("e7d5c6"))
	var costcol := Color("d9b477") if affordable else Color("a05a5a")
	_ui_text(rect.position + Vector2(64, 40), "%d or" % def.cost, 13, costcol)
	_ui_text(rect.position + Vector2(64, 58), "DMG %d · PORT %d" % [int(def.damage), int(def.range)], 10, Color("8a7680"))
	_ui_text(rect.position + Vector2(64, 74), def.desc.substr(0, 24), 9, Color("7a6670"))
	buttons.append({"rect": rect, "action": "select_tower", "arg": id})

# ---------------------------------------------------------------------------
# Menu (with meta-progression shop)
# ---------------------------------------------------------------------------
func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, SCREEN.x, SCREEN.y), Color("0a0810"), true)
	# atmospheric keep on the right
	_draw_sprite("keep", Vector2(1000, 380), 460.0)
	draw_rect(Rect2(0, 0, SCREEN.x, SCREEN.y), Color(0.05, 0.02, 0.04, 0.35), true)

	_ui_text(Vector2(90, 130), "GLOOM BASTION", 60, Color("d9453f"))
	_ui_text(Vector2(94, 168), "LA NUIT SE SOUVIENT", 18, Color("80636c"))
	_ui_text(Vector2(94, 205), "Tower defense roguelite — défends le donjon, bâtis ta cité maudite.", 15, Color("9a8690"))

	_button(Rect2(94, 240, 260, 54), "⚔   COMMENCER LA DESCENTE", "start_run", null, true, Color("b83240"))

	_ui_text(Vector2(94, 330), "SANCTUAIRE DU SANG — améliorations permanentes", 15, Color("b57bd6"))
	_ui_text(Vector2(94, 352), "Éclats de Sang : %d   ·   Meilleure vague : %d   ·   Descentes : %d" % [Save.shards, Save.best_wave, Save.runs], 12, Color("8a7680"))

	var y := 380.0
	for id in GameData.META_ORDER:
		_draw_meta_card(Rect2(94, y, 560, 56), id)
		y += 64

	_ui_text(Vector2(94, 690), "Astuce : gagne des Éclats de Sang à chaque descente, même en mourant.", 12, Color("6a5660"))

func _draw_meta_card(rect: Rect2, id: String) -> void:
	var def: Dictionary = GameData.META[id]
	var lvl := Save.meta_level(id)
	var maxed := lvl >= def.max_level
	draw_rect(rect, Color("15111b"), true)
	draw_rect(rect, Color("3a2b40"), false, 1.5)
	_ui_text(rect.position + Vector2(14, 22), def.name, 15, Color("e7d5c6"))
	_ui_text(rect.position + Vector2(14, 42), def.desc, 11, Color("8a7680"))
	# level pips
	for i in def.max_level:
		var col := Color("b57bd6") if i < lvl else Color("2e2436")
		draw_rect(Rect2(rect.position + Vector2(360 + i*14, 14), Vector2(10, 10)), col, true)
	# buy button
	var btn := Rect2(rect.position + Vector2(rect.size.x - 118, 12), Vector2(104, 32))
	if maxed:
		draw_rect(btn, Color("15121a"), true)
		draw_rect(btn, Color("3a2b40"), false, 1.5)
		_ui_text(btn.position + Vector2(38, 21), "MAX", 14, Color("d9b477"))
	else:
		var cost := Save.meta_cost(id)
		var ok := Save.shards >= cost
		_button(btn, "%d ◈" % cost, "buy_meta", id, ok, Color("7a4a99"))

# ---------------------------------------------------------------------------
# Game over
# ---------------------------------------------------------------------------
func _draw_gameover() -> void:
	draw_rect(Rect2(0, 0, SCREEN.x, SCREEN.y), Color(0.03, 0.0, 0.02, 0.78), true)
	_ui_text(Vector2(SCREEN.x*0.5 - 220, 260), "LE DONJON EST TOMBÉ", 46, Color("d9453f"))
	_ui_text(Vector2(SCREEN.x*0.5 - 140, 310), "Vague atteinte : %d" % wave, 22, Color("cbb0a0"))
	_ui_text(Vector2(SCREEN.x*0.5 - 140, 345), "Éclats de Sang gagnés : %d ◈" % shards_this_run, 20, Color("b57bd6"))
	_button(Rect2(SCREEN.x*0.5 - 240, 400, 220, 52), "⟲  NOUVELLE DESCENTE", "restart", null, true, Color("b83240"))
	_button(Rect2(SCREEN.x*0.5 + 20, 400, 220, 52), "☗  SANCTUAIRE", "to_menu", null, true, Color("7a4a99"))

