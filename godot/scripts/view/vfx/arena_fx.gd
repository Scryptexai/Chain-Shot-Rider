class_name ArenaFx
extends Node3D
## Efek serangan arena: hujan tracer, busur petir, dan cincin kejut.
##
## Dipisahkan dari ArenaView bukan karena rapi, tapi karena ketiganya adalah
## satu kategori keputusan: efek murni tampilan yang TIDAK pernah menyentuh
## aturan main, punya kolam tetap, dan boleh dibuang seluruhnya pada perangkat
## kelas bawah tanpa mengubah satu pun hasil pertandingan. Spesifikasinya ada
## di docs/17 §17.5 (E2, E3, E4, E5).
##
## Semua efek di sini memakai kolam berukuran tetap dan indeks melingkar: slot
## tertua kalah saat kolam penuh. Efek yang hilang jauh lebih murah daripada
## satu frame yang dipakai menumbuhkan kolam, dan pada combo tinggi mata tidak
## pernah menghitung busur keberapa yang tidak digambar.

## Peluru tracer musuh yang hidup bersamaan. Ini efek paling padat di layar
## dan sekaligus yang paling mudah membanjiri frame, jadi jumlahnya dipatok,
## bukan diturunkan dari jumlah musuh.
const TRACER_POOL := 160
const TRACER_SECONDS := 0.55

## Busur petir antara titik pantul dan korbannya.
const ARC_POOL := 6
const ARC_SECONDS := 0.2
const ARC_SEGMENTS := 7

## Cincin kejut di lantai saat sesuatu meledak.
## Kulit benturan: satu bola aditif yang mengembang lalu padam. Dipakai oleh
## SEMUA peristiwa (kill, ledakan, pantulan, kilatan moncong) dengan warna
## dan radius berbeda — satu kolam, empat arti, dibedakan hanya oleh warna.
const IMPACT_POOL := 48
const IMPACT_SECONDS := 0.35

const RING_POOL := 8
const RING_SECONDS := 0.45

var _pal: Dictionary = {}
var _sim: SimWorld
var _fx_rng := RandomNumberGenerator.new()

var _tracer_mm: MultiMeshInstance3D
var _tracer_life := PackedFloat32Array()
var _tracer_from := PackedVector3Array()
var _tracer_to := PackedVector3Array()
var _tracer_next := 0
var _tracer_clock := 0.0

var _arcs: Array[MeshInstance3D] = []
var _arc_mesh: Array[ImmediateMesh] = []
var _arc_life := PackedFloat32Array()
var _arc_next := 0

var _rings: Array[MeshInstance3D] = []
var _ring_life := PackedFloat32Array()
var _ring_scale := PackedFloat32Array()
var _ring_next := 0

var _impacts: Array[MeshInstance3D] = []
var _impact_life := PackedFloat32Array()
var _impact_scale := PackedFloat32Array()
var _impact_next := 0


## Dipanggil sekali oleh ArenaView, dengan palet varian yang sedang berjalan.
func build(pal: Dictionary, seed_value: int) -> void:
	_pal = pal
	_fx_rng.seed = seed_value
	_build_tracers()
	_build_arcs()
	_build_rings()
	_build_impacts()


func bind_sim(sim: SimWorld) -> void:
	_sim = sim


## Satu panggilan per frame dari ArenaView, setelah peristiwa dibaca.
func tick(delta: float) -> void:
	_tick_tracers(delta)
	_age_arcs(delta)
	_age_rings(delta)
	_age_impacts()


## Hujan tracer musuh (docs/17 §17.5 E3).
##
## Satu MultiMesh berisi batang tipis. Inilah yang membuat layar terbaca
## sebagai bullet hell tanpa satu pun peluru musuh benar-benar ada di
## simulasi: musuh di game ini melukai pemain dengan MENEROBOS garis
## pertahanan, bukan dengan menembak. Tracer adalah bahasa visual yang
## menjelaskan ancaman itu, dan karena ia tidak pernah menyentuh aturan,
## kepadatannya bebas disetel demi tampilan.
func _build_tracers() -> void:
	var rod := BoxMesh.new()
	rod.size = Vector3(0.06, 0.06, 1.0)
	_tracer_mm = _make_multimesh(rod, _pal["tracer"], TRACER_POOL)
	var material := _tracer_mm.material_override as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_energy_multiplier = 2.4
	_tracer_life.resize(TRACER_POOL)
	_tracer_from.resize(TRACER_POOL)
	_tracer_to.resize(TRACER_POOL)


## Busur petir. Enam slot, masing-masing satu ImmediateMesh zig-zag.
func _build_arcs() -> void:
	for i in range(ARC_POOL):
		var mesh := ImmediateMesh.new()
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _additive(_pal["chain"])
		node.visible = false
		add_child(node)
		_arcs.append(node)
		_arc_mesh.append(mesh)
		_arc_life.append(0.0)


## Cincin kejut di lantai. Torus pipih, bukan partikel: bentuknya harus
## persis lingkaran dengan radius yang sama dengan radius ledakan di
## simulasi, karena pemain memakainya untuk belajar jangkauan barrel.
func _build_rings() -> void:
	for i in range(RING_POOL):
		var torus := TorusMesh.new()
		torus.inner_radius = 0.86
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 6
		var node := MeshInstance3D.new()
		node.mesh = torus
		node.material_override = _additive(_pal["blast_core"])
		node.rotation = Vector3(0.0, 0.0, 0.0)
		node.visible = false
		add_child(node)
		_rings.append(node)
		_ring_life.append(0.0)
		_ring_scale.append(1.0)


## Hujan tracer. Lahir dari posisi musuh yang sesungguhnya ada, menuju titik
## di sekitar pemain, lalu mati. Tidak pernah mengenai apa pun.
func _tick_tracers(delta: float) -> void:
	if _tracer_mm == null:
		return
	var alive := _sim.enemy_count
	if alive > 0:
		# Laju kelahiran naik bersama kerumunan tapi dibatasi: 200 musuh yang
		# masing-masing menembak sungguhan akan menutupi lintasan peluru, dan
		# lintasan peluru tidak boleh tertutup (docs/17 §17.1).
		var rate: float = clampf(float(alive) * 0.9, 4.0, 70.0)
		_tracer_clock += delta * rate
		while _tracer_clock >= 1.0:
			_tracer_clock -= 1.0
			_spawn_tracer()
	var mm := _tracer_mm.multimesh
	var drawn := 0
	for i in range(TRACER_POOL):
		if _tracer_life[i] <= 0.0:
			continue
		_tracer_life[i] = maxf(_tracer_life[i] - delta / TRACER_SECONDS, 0.0)
		if _tracer_life[i] <= 0.0:
			continue
		var travel := 1.0 - _tracer_life[i]
		var from: Vector3 = _tracer_from[i]
		var to: Vector3 = _tracer_to[i]
		var head := from.lerp(to, travel)
		var tail := from.lerp(to, maxf(travel - 0.12, 0.0))
		var middle := (head + tail) * 0.5
		var along := head - tail
		var length := maxf(along.length(), 0.01)
		var basis := Basis.looking_at(along / length, Vector3.UP).scaled(Vector3(1.0, 1.0, length))
		mm.set_instance_transform(drawn, Transform3D(basis, middle))
		var tint: Color = _pal["tracer"]
		tint.a = clampf(_tracer_life[i] * 1.6, 0.0, 1.0)
		mm.set_instance_color(drawn, tint)
		drawn += 1
	mm.visible_instance_count = drawn


func _spawn_tracer() -> void:
	if _sim.enemy_count <= 0:
		return
	var source := _fx_rng.randi_range(0, _sim.enemy_count - 1)
	var slot := _tracer_next % TRACER_POOL
	_tracer_next += 1
	var from := Vector3(_sim.enemy_x[source], 1.1, -_sim.enemy_z[source])
	# Menuju sekitar pemain, tidak tepat ke pemain: tembakan yang semuanya
	# bertemu di satu titik terbaca sebagai corong, bukan sebagai hujan.
	var to := Vector3(
		_sim.squad_x + _fx_rng.randf_range(-3.0, 3.0),
		0.1,
		-SimWorld.SQUAD_Z + _fx_rng.randf_range(-2.0, 2.0)
	)
	_tracer_from[slot] = from
	_tracer_to[slot] = to
	_tracer_life[slot] = 1.0


## Busur petir dari titik pantul ke arah lorong, zig-zag acak.
## Dipanggil saat peluru memantul: tenaga berpindah dari dinding ke lorong.
func bounce_arc(where: Vector3) -> void:
	if _arcs.is_empty():
		return
	var index := _arc_next % _arcs.size()
	_arc_next += 1
	var node := _arcs[index]
	var mesh := _arc_mesh[index]
	_arc_life[index] = 1.0
	node.visible = true
	# Busur mengalir menjauh dari dinding, ke tengah lorong: ia menjelaskan
	# "tenaga pindah dari sini ke sana", dan arah itu harus terbaca.
	var toward := Vector3(
		-signf(where.x) * _fx_rng.randf_range(2.0, 4.5), 0.0, _fx_rng.randf_range(-2.0, 2.0)
	)
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(ARC_SEGMENTS):
		var t := float(i) / float(ARC_SEGMENTS - 1)
		var point := where + toward * t
		if i > 0 and i < ARC_SEGMENTS - 1:
			point += Vector3(
				_fx_rng.randf_range(-0.45, 0.45),
				_fx_rng.randf_range(-0.2, 0.5),
				_fx_rng.randf_range(-0.45, 0.45)
			)
		mesh.surface_set_color(_pal["chain"])
		mesh.surface_add_vertex(point)
	mesh.surface_end()


func _age_arcs(delta: float) -> void:
	for i in range(_arcs.size()):
		if _arc_life[i] <= 0.0:
			continue
		_arc_life[i] = maxf(_arc_life[i] - delta / ARC_SECONDS, 0.0)
		var node := _arcs[i]
		if _arc_life[i] <= 0.0:
			node.visible = false
			continue
		# Berkedip, tidak memudar halus: petir yang memudar terbaca sebagai
		# asap. Tiga atau empat frame menyala-padam adalah bahasanya.
		node.visible = fmod(_arc_life[i] * 10.0, 1.0) > 0.35


## Dipanggil saat sesuatu meledak, dengan radius ledakan dari simulasi.
func explosion_ring(where: Vector3, radius: float) -> void:
	if _rings.is_empty():
		return
	var index := _ring_next % _rings.size()
	_ring_next += 1
	var node := _rings[index]
	node.position = where
	node.visible = true
	_ring_life[index] = 1.0
	_ring_scale[index] = radius


func _age_rings(delta: float) -> void:
	for i in range(_rings.size()):
		if _ring_life[i] <= 0.0:
			continue
		_ring_life[i] = maxf(_ring_life[i] - delta / RING_SECONDS, 0.0)
		var node := _rings[i]
		if _ring_life[i] <= 0.0:
			node.visible = false
			continue
		var grow := 1.0 - _ring_life[i]
		var spread: float = _ring_scale[i] * (0.2 + grow * 1.0)
		node.scale = Vector3(spread, spread * 0.12, spread)
		var material := node.material_override as StandardMaterial3D
		material.albedo_color.a = _ring_life[i]


## Material aditif berwarna simpul. Aditif, bukan alpha, karena semua efek di
## berkas ini adalah CAHAYA — alpha blending membuatnya terlihat seperti cat.
func _additive(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material


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


## Menyalakan satu kulit benturan di titik mana pun.
func impact(where: Vector3, radius: float, tint: Color) -> void:
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
