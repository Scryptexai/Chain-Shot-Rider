extends Node3D
## Draws the simulation and owns the look of the arena. Owns no rules.
##
## Enemies and troops are drawn with MultiMesh rather than one node each. At
## 200 enemies plus a squad of 100, a node per unit means hundreds of transform
## updates and draw calls per frame on a Snapdragon 660, which is the whole
## frame budget spent on bookkeeping. One MultiMesh per unit type is a single
## draw call regardless of count.
##
## Simulation space is (x, z) with z running away from the player. World space
## maps that to (x, y, -z) so the camera can sit at +Z looking down the lane.
##
## The palette comes from the active variant, not from constants here, so the
## arena, the crowd and the HUD always agree on what colour the world is.

const MAX_TROOPS_DRAWN := 128
## Impact shells kept alive at once, and how long one lasts. Both are budget
## decisions: docs 08 caps active particles at 200, and these are the most
## frequent effect in the game.
const IMPACT_POOL := 48
const IMPACT_SECONDS := 0.35

## Enemy palette in config enemyTypes order, lifted verbatim from
## docs/02-visual-style-guide.md so art, prototype and build cannot drift
## into three different reds.
const ENEMY_COLORS := [
	Color("#FF4D3D"),  # grunt    — Enemy Red
	Color("#FF8A2B"),  # runner   — Enemy Orange
	Color("#B14DFF"),  # brute    — Bumper Magenta, reads as heavy
	Color("#FFC93C"),  # shielder — Enemy Yellow
	Color("#FF3DBE"),  # splitter — Magenta Hot
	Color("#FF6A1F"),  # bomber   — hot orange
]

const FLOOR_SHADER := "res://shaders/floor_grid.gdshader"

## Nama unit ber-tulang dalam urutan enemyTypes config, plus prajurit dan bos.
## Urutannya mengikat indeks tipe simulasi ke sebuah berkas GLB; kalau config
## menambah jenis musuh, daftar ini ikut bertambah atau unit itu jatuh ke
## jalur MultiMesh dengan sendirinya.
const ENEMY_UNITS := ["grunt", "runner", "brute", "shielder", "splitter", "bomber"]
const SQUAD_UNIT := "trooper"
const BOSS_UNIT := "boss"

var _sim: SimWorld
var _pal: Dictionary = {}
var _enemy_mm: MultiMeshInstance3D
var _troop_mm: MultiMeshInstance3D
var _auto_mm: MultiMeshInstance3D
var _chain: MeshInstance3D
var _gate_pool: Array[MeshInstance3D] = []
var _gate_labels: Array[Label3D] = []
var _floor: MeshInstance3D
var _environment: WorldEnvironment
var _obstacle_nodes: Array[Node3D] = []
var _boss: Node3D
var _impacts: Array[MeshInstance3D] = []
var _impact_life := PackedFloat32Array()
var _impact_scale := PackedFloat32Array()
var _impact_next := 0
var _chars: CharacterPool
## Darah terakhir tiap musuh, dibaca per indeks. Simulasi tidak mengirim event
## "kena pukul", tapi HP yang turun adalah sinyal yang sama persis dan tidak
## menambah kopling ke aturan main.
var _enemy_hp_seen := PackedFloat32Array()
var _squad_firing := 0.0
## Posisi squad frame lalu: dari sini datang jawaban "sedang jalan atau diam",
## yang menentukan klip lari atau siaga. Simulasi tidak menyimpan kecepatan
## squad, dan menanyakannya ke input akan salah saat squad masih meluncur.
var _squad_x_prev := 0.0
var _squad_moving := false


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_build_environment()
	_build_floor()
	_build_actors()
	_build_impacts()


## Called by Game once a run starts. The furniture can only be built now:
## which obstacles exist is a property of the run, not of the scene.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim
	_build_obstacles()


## Pushes one frame of simulation state into the scene.
func render_frame() -> void:
	if _sim == null:
		return
	var delta := get_process_delta_time()
	_squad_firing = maxf(_squad_firing - delta, 0.0)
	for entry in _sim.events:
		if String((entry as Dictionary).get("type", "")) == "auto_fired":
			_squad_firing = 0.12
	_squad_moving = absf(_sim.squad_x - _squad_x_prev) > 0.004
	_squad_x_prev = _sim.squad_x
	if _chars != null:
		_chars.begin()
	_render_enemies()
	_render_troops()
	_render_auto()
	_render_chain()
	_render_gates()
	_render_obstacles()
	_render_boss()
	_spawn_impacts()
	_age_impacts()
	if _chars != null:
		_chars.end(delta)


func _build_environment() -> void:
	# Glow is what sells neon. Without it the emissive materials are merely
	# bright flat colours; with it they bleed and read as light sources.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _pal["bg_bottom"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _pal["bg_top"]
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.85
	# Fog hides the spawn gate's hard edge and gives the long lane real depth
	# for free, which a portrait screen badly needs.
	env.fog_enabled = true
	env.fog_light_color = _pal["bg_top"]
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0

	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)


func _build_floor() -> void:
	var width := GameConfig.num("arena.width")
	var length := GameConfig.num("arena.height")
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	# Subdivision keeps the shader's derivative-based anti-aliasing stable
	# across the length of the lane.
	plane.subdivide_depth = 8

	var shader: Shader = load(FLOOR_SHADER)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("bg_top", _pal["bg_top"])
	material.set_shader_parameter("bg_bottom", _pal["bg_bottom"])
	material.set_shader_parameter("grid_color", _pal["grid"])
	material.set_shader_parameter("arena_length", length)
	material.set_shader_parameter("defense_line_z", GameConfig.num("arena.defenseLineZ"))
	material.set_shader_parameter("defense_color", _pal["primary"])

	_floor = MeshInstance3D.new()
	_floor.mesh = plane
	_floor.material_override = material
	_floor.position = Vector3(0.0, 0.0, -length * 0.5)
	add_child(_floor)

	_build_side_walls(width, length)


func _build_side_walls(width: float, length: float) -> void:
	# Thin emissive strips, not solid walls: the player has to read where the
	# bounce surface is without the geometry eating the playfield.
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.5, length)
		strip.mesh = box
		strip.position = Vector3(side * width * 0.5, 0.25, -length * 0.5)
		strip.material_override = _emissive(_pal["bumper"], 1.4)
		add_child(strip)


func _build_actors() -> void:
	# Karakter ber-tulang untuk unit terdekat, MultiMesh untuk sisanya. Dua
	# jalur, satu ukuran: kapsul ikut dibesarkan CHAR_SCALE supaya barisan
	# belakang tidak menciut saat sebuah unit berpindah jalur.
	_chars = CharacterPool.new()
	_chars.name = "Characters"
	add_child(_chars)
	var roster: Array = ENEMY_UNITS.duplicate()
	roster.append(SQUAD_UNIT)
	roster.append(BOSS_UNIT)
	_chars.warm(roster)

	var scale: float = CharacterPool.CHAR_SCALE
	_enemy_mm = _make_multimesh(_capsule(0.35 * scale, 1.0 * scale), Color.WHITE, SimWorld.MAX_ENEMIES)
	_troop_mm = _make_multimesh(_capsule(0.22 * scale, 0.8 * scale), _pal["primary"], MAX_TROOPS_DRAWN)
	_auto_mm = _make_multimesh(_sphere(0.12), Color("#FFF1D0"), SimWorld.MAX_AUTO_BULLETS)
	_chain = MeshInstance3D.new()
	_chain.mesh = _sphere(0.26)
	_chain.material_override = _emissive(_pal["primary"], 3.0)
	add_child(_chain)


## Builds one node per obstacle, once. They are few and long-lived, so a
## MultiMesh would cost more in bookkeeping than it saves in draw calls.
func _build_obstacles() -> void:
	for node in _obstacle_nodes:
		node.queue_free()
	_obstacle_nodes.clear()
	if _sim == null or _sim.field == null:
		return
	for entry in _sim.field.obstacles:
		var obstacle: Dictionary = entry
		var node := _make_obstacle(obstacle)
		add_child(node)
		_obstacle_nodes.append(node)

	if _boss != null:
		_boss.queue_free()
	_boss = MeshInstance3D.new()
	var boss_mesh := SphereMesh.new()
	boss_mesh.radius = 1.8
	boss_mesh.height = 3.6
	(_boss as MeshInstance3D).mesh = boss_mesh
	(_boss as MeshInstance3D).material_override = _emissive(_pal["enemy"], 2.2)
	_boss.visible = false
	add_child(_boss)


## Each kind reads as itself at a glance: bumpers glow, pillars are dead
## weight, wells are translucent volumes, barrels are small and hot.
func _make_obstacle(obstacle: Dictionary) -> Node3D:
	var node := MeshInstance3D.new()
	var kind := String(obstacle["kind"])
	var radius := float(obstacle["radius"])
	match kind:
		"gravityWell":
			var well := SphereMesh.new()
			well.radius = radius
			well.height = radius * 2.0
			node.mesh = well
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = Color(_pal["bumper"], 0.16)
			glass.emission_enabled = true
			glass.emission = _pal["bumper"]
			glass.emission_energy_multiplier = 0.5
			node.material_override = glass
		"barrel":
			node.mesh = _cylinder(0.6, 1.2)
			node.material_override = _emissive(Color("#FF8A2B"), 1.8)
		"shieldWall", "movingPlatform":
			var slab := BoxMesh.new()
			slab.size = Vector3(float(obstacle["width"]), 0.9, 0.5)
			node.mesh = slab
			node.material_override = _emissive(_pal["bumper"], 0.9)
		"pillar":
			node.mesh = _cylinder(radius, 3.0)
			var stone := StandardMaterial3D.new()
			stone.albedo_color = _pal["grid"].darkened(0.4)
			stone.roughness = 0.9
			node.material_override = stone
		_:
			var ball := SphereMesh.new()
			ball.radius = radius
			ball.height = radius * 2.0
			node.mesh = ball
			node.material_override = _emissive(_pal["bumper"], 2.0)
	return node


## Only position and visibility change per frame; meshes never rebuild.
func _render_obstacles() -> void:
	if _sim == null or _sim.field == null:
		return
	var list: Array = _sim.field.obstacles
	for i in range(mini(list.size(), _obstacle_nodes.size())):
		var obstacle: Dictionary = list[i]
		var node := _obstacle_nodes[i]
		node.visible = bool(obstacle["alive"])
		if node.visible:
			node.position = Vector3(float(obstacle["x"]), 0.5, -float(obstacle["z"]))


func _render_boss() -> void:
	if _boss == null:
		return
	# Bos selalu ber-tulang: cuma ada satu, dan ia satu-satunya hal di layar
	# yang ditatap pemain lama-lama.
	var actor: CharacterPool.Actor = null
	if _sim.boss_active and _chars != null:
		actor = _chars.take(BOSS_UNIT)
	if actor != null:
		_boss.visible = false
		actor.place(_sim.boss_pos.x, _sim.boss_pos.y, PI)
		if actor.lock <= 0.0:
			actor.play("idle")
		return
	_boss.visible = _sim.boss_active
	if _boss.visible:
		_boss.position = Vector3(_sim.boss_pos.x, 1.4, -_sim.boss_pos.y)


func _cylinder(radius: float, height: float) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


## A fixed ring of impact shells, reused forever. Pooled rather than spawned
## because a busy frame can produce dozens of kills, and allocating a node
## per kill is exactly the per-frame garbage the budget forbids.
func _build_impacts() -> void:
	for i in range(IMPACT_POOL):
		var shell := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		shell.mesh = mesh
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_color = _pal["primary"]
		shell.material_override = material
		shell.visible = false
		add_child(shell)
		_impacts.append(shell)
		_impact_life.append(0.0)
		_impact_scale.append(1.0)


## Reads this tick's events and lights a shell for each one worth seeing.
func _spawn_impacts() -> void:
	for entry in _sim.events:
		var event: Dictionary = entry
		var kind := String(event.get("type", ""))
		var radius := 0.0
		var tint: Color = _pal["primary"]
		match kind:
			"kill":
				radius = 0.9
				tint = _pal["enemy"]
				if _chars != null:
					var fallen := _unit_name(int(event.get("enemy", 0)) % ENEMY_UNITS.size())
					_chars.drop_corpse(
						fallen, float(event.get("x", 0.0)), float(event.get("z", 0.0))
					)
			"explosion":
				radius = float(event.get("radius", 3.0))
				tint = Color("#FF8A2B")
			"bounce":
				radius = 0.6
				tint = _pal["bumper"]
			_:
				continue
		_light_impact(
			Vector3(float(event.get("x", 0.0)), 0.6, -float(event.get("z", 0.0))), radius, tint
		)


func _light_impact(where: Vector3, radius: float, tint: Color) -> void:
	if _impacts.is_empty():
		return
	# Oldest slot wins when the pool is exhausted: a dropped effect is far
	# cheaper than a frame spent growing the pool.
	var index := _impact_next % _impacts.size()
	_impact_next += 1
	var shell := _impacts[index]
	shell.position = where
	shell.visible = true
	_impact_life[index] = 1.0
	_impact_scale[index] = radius
	var material := shell.material_override as StandardMaterial3D
	material.albedo_color = tint


## Shells expand and fade on a square curve, which reads as a pop rather than
## a balloon. Uses unscaled ticks so slow motion stretches them with the world.
func _age_impacts() -> void:
	var delta := float(Engine.get_frames_per_second())
	var step := 1.0 / maxf(delta, 20.0) / IMPACT_SECONDS
	for i in range(_impacts.size()):
		if _impact_life[i] <= 0.0:
			continue
		_impact_life[i] = maxf(_impact_life[i] - step, 0.0)
		var shell := _impacts[i]
		if _impact_life[i] <= 0.0:
			shell.visible = false
			continue
		var grow := 1.0 - _impact_life[i]
		shell.scale = Vector3.ONE * _impact_scale[i] * (0.25 + grow * 0.9)
		var material := shell.material_override as StandardMaterial3D
		material.albedo_color.a = _impact_life[i] * _impact_life[i]


func _render_enemies() -> void:
	var mm := _enemy_mm.multimesh
	var count := _sim.enemy_count
	# LOD: yang paling dekat garis pertahanan mendapat tubuh ber-tulang.
	# Mereka yang terbesar di layar dan yang sedang diputuskan nasibnya oleh
	# pemain; musuh di ujung lorong tingginya dua puluh piksel.
	var order: Array = []
	for i in range(count):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _sim.enemy_z[a] < _sim.enemy_z[b])
	var skinned: Dictionary = {}
	var budget: int = mini(int(CharacterPool.BUDGET["enemies"]), order.size())
	for i in range(budget):
		skinned[order[i]] = true

	if _enemy_hp_seen.size() < count:
		_enemy_hp_seen.resize(count)

	var drawn := 0
	for i in range(count):
		var type_index: int = _sim.enemy_type[i] % ENEMY_COLORS.size()
		var hurt: bool = _sim.enemy_hp[i] < _enemy_hp_seen[i] - 0.001
		_enemy_hp_seen[i] = _sim.enemy_hp[i]
		var unit := _unit_name(type_index)
		var actor: CharacterPool.Actor = null
		if skinned.has(i) and _chars != null:
			actor = _chars.take(unit)
		if actor != null:
			# Menatap pemain: model menghadap -Z, musuh berjalan ke arah +Z.
			actor.place(_sim.enemy_x[i], _sim.enemy_z[i], PI)
			if hurt:
				actor.one_shot("hit", 0.3)
			elif actor.lock <= 0.0:
				actor.play("run")
			continue
		var pos := Vector3(_sim.enemy_x[i], 0.5 * CharacterPool.CHAR_SCALE, -_sim.enemy_z[i])
		mm.set_instance_transform(drawn, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(drawn, ENEMY_COLORS[type_index])
		drawn += 1
	mm.visible_instance_count = drawn


## Indeks tipe simulasi -> nama berkas karakter.
func _unit_name(type_index: int) -> String:
	if type_index < 0 or type_index >= ENEMY_UNITS.size():
		return ENEMY_UNITS[0]
	return String(ENEMY_UNITS[type_index])


func _render_troops() -> void:
	var mm := _troop_mm.multimesh
	var shown: int = mini(_sim.troops, MAX_TROOPS_DRAWN)
	var columns := 5
	# Jarak formasi ikut membesar bersama CHAR_SCALE, kalau tidak bahu
	# prajurit saling menembus dan barisan jadi bubur.
	var spacing: float = 0.42 * CharacterPool.CHAR_SCALE
	var drawn := 0
	for i in range(shown):
		@warning_ignore("integer_division")
		var row := i / columns
		var col := i % columns
		var offset_x := (float(col) - float(columns - 1) * 0.5) * spacing
		var offset_z := float(row) * spacing
		var x: float = _sim.squad_x + offset_x
		var z: float = SimWorld.SQUAD_Z - offset_z
		var actor: CharacterPool.Actor = null
		if i < int(CharacterPool.BUDGET["troops"]) and _chars != null:
			actor = _chars.take(SQUAD_UNIT)
		if actor != null:
			actor.place(x, z, 0.0)
			# Tiga terdepan yang mengangkat senjata; kalau sepuluh orang
			# menembak berbarengan recoil-nya berubah jadi gempa.
			if _squad_firing > 0.0 and i < 3:
				actor.one_shot("shoot", 0.22)
				_light_impact(actor.muzzle_point(), 0.28, Color("#FFF3C4"))
			elif actor.lock <= 0.0:
				actor.play("run" if _squad_moving else "idle")
			continue
		var pos := Vector3(x, 0.4 * CharacterPool.CHAR_SCALE, -z)
		mm.set_instance_transform(drawn, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(drawn, _pal["primary"] if i == 0 else Color(1, 1, 1, 0.85))
		drawn += 1
	mm.visible_instance_count = drawn


func _render_auto() -> void:
	var mm := _auto_mm.multimesh
	mm.visible_instance_count = _sim.auto_count
	for i in range(_sim.auto_count):
		var pos := Vector3(_sim.auto_x[i], 0.5, -_sim.auto_z[i])
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, Color("#FFF1D0"))


func _render_chain() -> void:
	_chain.visible = _sim.chain_active
	if _sim.chain_active:
		_chain.position = Vector3(_sim.chain_pos.x, 0.6, -_sim.chain_pos.y)


func _render_gates() -> void:
	var needed: int = _sim.gates.size() * 2
	while _gate_pool.size() < needed:
		_grow_gate_pool()
	for i in range(_gate_pool.size()):
		_gate_pool[i].visible = i < needed
		_gate_labels[i].visible = i < needed
	var half := GameConfig.num("arena.width") * 0.5
	var gap := GameConfig.num("gates.centerGapX") * 0.5
	for g in range(_sim.gates.size()):
		var gate: Dictionary = _sim.gates[g]
		var z := float(gate["z"])
		var dimmed := bool(gate["squad_done"])
		_apply_gate_panel(g * 2, gate["left"], -(half + gap) * 0.5, half - gap, z, dimmed)
		_apply_gate_panel(g * 2 + 1, gate["right"], (half + gap) * 0.5, half - gap, z, dimmed)


func _grow_gate_pool() -> void:
	var panel := MeshInstance3D.new()
	panel.mesh = BoxMesh.new()
	add_child(panel)
	_gate_pool.append(panel)
	# The decision lives in the world, so the number lives in the world too.
	# A gate value read off a HUD corner would arrive too late to act on.
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.outline_size = 24
	label.modulate = UiTheme.INK
	add_child(label)
	_gate_labels.append(label)


func _apply_gate_panel(
	index: int, side: Dictionary, x: float, width: float, z: float, dimmed: bool
) -> void:
	var panel := _gate_pool[index]
	var box := panel.mesh as BoxMesh
	box.size = Vector3(width, 2.4, 0.25)
	panel.position = Vector3(x, 1.2, -z)
	var positive := bool(side.get("positive", true))
	var tint: Color = _pal["primary"] if positive else UiTheme.DANGER
	var alpha := 0.18 if dimmed else 0.42
	panel.material_override = _transparent(tint, alpha)

	var label := _gate_labels[index]
	label.text = "%s%s" % [_op_symbol(String(side.get("op", "add"))), _op_value(side)]
	label.position = Vector3(x, 1.6, -z + 0.2)
	label.modulate = Color(1, 1, 1, 0.45) if dimmed else UiTheme.INK
	label.outline_modulate = Color(0, 0, 0, 0.85)


func _op_symbol(op: String) -> String:
	match op:
		"mul":
			return "x"
		"add":
			return "+"
		"sub":
			return "-"
		"div":
			return "/"
	return "?"


func _op_value(side: Dictionary) -> String:
	return "%d" % int(round(float(side.get("value", 1.0))))


func _make_multimesh(mesh: Mesh, tint: Color, capacity: int) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	instance.multimesh = mm
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.6
	material.roughness = 0.7
	instance.material_override = material
	add_child(instance)
	return instance


func _capsule(radius: float, height: float) -> Mesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 2
	return mesh


func _sphere(radius: float) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


func _emissive(tint: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _transparent(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.2
	return material
