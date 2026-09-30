extends Node3D
## Draws the simulation. Owns no rules.
##
## Enemies and troops are drawn with MultiMesh rather than one node each. At
## 200 enemies plus a squad of 60, a node per unit means hundreds of transform
## updates and draw calls per frame on a Snapdragon 660, which is the whole
## frame budget spent on bookkeeping. One MultiMesh per unit type is a single
## draw call regardless of count.
##
## Simulation space is (x, z) with z running away from the player. World space
## maps that to (x, y, -z) so the camera can sit at +Z looking down the lane.

const MAX_TROOPS_DRAWN := 128

## Enemy palette, in the order of config enemyTypes. Values are lifted
## verbatim from docs/02-visual-style-guide.md so that art, prototype and
## build cannot drift into three different reds.
const ENEMY_COLORS := [
	Color("#FF4D3D"),  # grunt    — Enemy Red
	Color("#FF8A2B"),  # runner   — Enemy Orange
	Color("#B14DFF"),  # brute    — Bumper Magenta, reads as heavy
	Color("#FFC93C"),  # shielder — Enemy Yellow
	Color("#FF3DBE"),  # splitter — Magenta Hot
	Color("#FF6A1F"),  # bomber   — hot orange
]

const PLAYER_CYAN := Color("#00E5FF")
const DEFENSE_LINE_Z_THICKNESS := 0.12

var _sim: SimWorld
var _enemy_mm: MultiMeshInstance3D
var _troop_mm: MultiMeshInstance3D
var _auto_mm: MultiMeshInstance3D
var _chain: MeshInstance3D
var _gate_pool: Array[MeshInstance3D] = []
var _ground: MeshInstance3D


func _ready() -> void:
	_build_ground()
	_enemy_mm = _make_multimesh(_capsule(0.35, 1.0), Color(0.85, 0.30, 0.32), SimWorld.MAX_ENEMIES)
	_troop_mm = _make_multimesh(_capsule(0.22, 0.8), PLAYER_CYAN, MAX_TROOPS_DRAWN)
	_auto_mm = _make_multimesh(_sphere(0.12), Color("#FFF1D0"), SimWorld.MAX_AUTO_BULLETS)
	_chain = MeshInstance3D.new()
	_chain.mesh = _sphere(0.26)
	_chain.material_override = _emissive(PLAYER_CYAN)
	add_child(_chain)
	_build_defense_line()


## Called by Game once a run starts.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim


## Pushes one frame of simulation state into the scene.
func render_frame() -> void:
	if _sim == null:
		return
	_render_enemies()
	_render_troops()
	_render_auto()
	_render_chain()
	_render_gates()


func _render_enemies() -> void:
	var mm := _enemy_mm.multimesh
	mm.visible_instance_count = _sim.enemy_count
	for i in range(_sim.enemy_count):
		var pos := Vector3(_sim.enemy_x[i], 0.5, -_sim.enemy_z[i])
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		var type_index: int = _sim.enemy_type[i] % ENEMY_COLORS.size()
		mm.set_instance_color(i, ENEMY_COLORS[type_index])


func _render_troops() -> void:
	var mm := _troop_mm.multimesh
	var shown: int = mini(_sim.troops, MAX_TROOPS_DRAWN)
	mm.visible_instance_count = shown
	var columns := 5
	var spacing := 0.42
	for i in range(shown):
		var row := i / columns
		var col := i % columns
		var offset_x := (float(col) - float(columns - 1) * 0.5) * spacing
		var offset_z := float(row) * spacing
		var pos := Vector3(_sim.squad_x + offset_x, 0.4, -(SimWorld.SQUAD_Z - offset_z))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))


func _render_auto() -> void:
	var mm := _auto_mm.multimesh
	mm.visible_instance_count = _sim.auto_count
	for i in range(_sim.auto_count):
		var pos := Vector3(_sim.auto_x[i], 0.5, -_sim.auto_z[i])
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))


func _render_chain() -> void:
	_chain.visible = _sim.chain_active
	if _sim.chain_active:
		_chain.position = Vector3(_sim.chain_pos.x, 0.6, -_sim.chain_pos.y)


func _render_gates() -> void:
	var needed: int = _sim.gates.size() * 2
	while _gate_pool.size() < needed:
		var panel := MeshInstance3D.new()
		panel.mesh = BoxMesh.new()
		add_child(panel)
		_gate_pool.append(panel)
	for i in range(_gate_pool.size()):
		_gate_pool[i].visible = i < needed
	for g in range(_sim.gates.size()):
		var gate: Dictionary = _sim.gates[g]
		_apply_gate_panel(_gate_pool[g * 2], gate["left"], -5.3, float(gate["z"]))
		_apply_gate_panel(_gate_pool[g * 2 + 1], gate["right"], 5.3, float(gate["z"]))


func _apply_gate_panel(panel: MeshInstance3D, side: Dictionary, x: float, z: float) -> void:
	var box := panel.mesh as BoxMesh
	box.size = Vector3(9.4, 2.4, 0.3)
	panel.position = Vector3(x, 1.2, -z)
	var positive := bool(side.get("positive", true))
	var tint := Color(0.25, 0.75, 0.95, 0.55) if positive else Color(0.95, 0.30, 0.35, 0.55)
	panel.material_override = _transparent(tint)


func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GameConfig.num("arena.width"), GameConfig.num("arena.height"))
	_ground.mesh = plane
	_ground.position = Vector3(0.0, 0.0, -GameConfig.num("arena.height") * 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = GameConfig.color("variants.0.theme.bgBottom")
	material.roughness = 0.95
	_ground.material_override = material
	add_child(_ground)


## The defense line must always be visible: it is the only thing telling the
## player what losing looks like. Drawn as geometry rather than a HUD overlay
## so it sits in the world and respects perspective.
func _build_defense_line() -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GameConfig.num("arena.width"), 0.06, DEFENSE_LINE_Z_THICKNESS)
	line.mesh = box
	line.position = Vector3(0.0, 0.03, -GameConfig.num("arena.defenseLineZ"))
	line.material_override = _emissive(PLAYER_CYAN)
	add_child(line)


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
	material.roughness = 0.8
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


func _emissive(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.0
	return material


func _transparent(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.8
	return material
