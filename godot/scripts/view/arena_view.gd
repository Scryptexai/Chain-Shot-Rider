extends Node3D
## Draws the simulation and owns the look of the arena. Owns no rules.
##
## Arah visual: NEON, dari key art di docs/17-keyart-neon-analysis.md.
## Rencana rombakannya di docs/18-neon-rebuild-roadmap.md. Satu hal yang
## TIDAK berubah di sana: berkas ini tidak memiliki satu pun aturan main.
##
## Enemies are drawn with MultiMesh rather than one node each. At 200 enemies
## a node per unit means hundreds of transform updates and draw calls per
## frame on a Snapdragon 660, which is the whole frame budget spent on
## bookkeeping. One MultiMesh per unit type is a single draw call regardless
## of count. Hujan tracer dan kerumunan jauh memakai jalur yang sama persis,
## dan karena itulah keduanya mampu ada sama sekali.
##
## Simulation space is (x, z) with z running away from the player. World space
## maps that to (x, y, -z) so the camera can sit at +Z looking down the lane.
##
## The palette comes from the active variant, not from constants here, so the
## arena, the crowd and the HUD always agree on what colour the world is.

## Panjang tambahan lantai di depan garis bertahan (lihat APRON di render3d.js).
const APRON := 34.0

## Lantai juga diteruskan melewati gerbang spawn supaya ujungnya larut dalam
## kabut, bukan berhenti sebagai garis lurus di sepertiga atas layar.
const APRON_FAR := 120.0

## Impact shells kept alive at once, and how long one lasts. Both are budget
## decisions: docs 08 caps active particles at 200, and these are the most
## frequent effect in the game.
const IMPACT_POOL := 48
const IMPACT_SECONDS := 0.35

## Kerumunan hiasan di balik gerbang spawn. Key art memperlihatkan musuh
## sampai ke garis kabut; arena hanya sepanjang 40 unit, jadi sisanya diisi
## siluet yang tidak pernah masuk simulasi dan tidak pernah bisa ditembak.
const FAR_CROWD := 220
const FAR_CROWD_FROM := 44.0
const FAR_CROWD_TO := 96.0

const FLOOR_SHADER := "res://shaders/floor_grid.gdshader"
const WALL_SHADER := "res://shaders/bumper_wall.gdshader"
const BACKDROP_SHADER := "res://shaders/backdrop.gdshader"

## Nama unit ber-tulang dalam urutan enemyTypes config, plus pemain dan bos.
## Urutannya mengikat indeks tipe simulasi ke sebuah berkas GLB; kalau config
## menambah jenis musuh, daftar ini ikut bertambah atau unit itu jatuh ke
## jalur MultiMesh dengan sendirinya.
const ENEMY_UNITS := ["grunt", "runner", "brute", "shielder", "splitter", "bomber"]
const PLAYER_UNIT := "trooper"
const BOSS_UNIT := "boss"

## Pemain digambar lebih besar daripada siapa pun di arena. Itu bukan selera:
## key art menempatkan satu prajurit setinggi 19% layar sebagai jangkar
## komposisi, dan satu unit seukuran musuh tidak akan pernah memegang peran
## itu (docs/17 §17.2).
const PLAYER_SCALE := 1.35

var _sim: SimWorld
var _pal: Dictionary = {}
## Warna per tipe musuh, dibaca dari config.enemyTypes[].color. Dulu daftar
## konstanta di berkas ini, yang berarti palet hidup di dua tempat dan
## pelan-pelan menjadi dua palet berbeda.
var _enemy_colors: PackedColorArray = PackedColorArray()
var _enemy_mm: MultiMeshInstance3D
var _auto_mm: MultiMeshInstance3D
var _far_crowd_mm: MultiMeshInstance3D
var _chain: MeshInstance3D
var _chain_trail: MeshInstance3D
var _chain_trail_mesh: ImmediateMesh
## Jejak peluru chain dalam ruang dunia, titik terbaru di depan.
var _chain_points: Array[Vector3] = []
var _backdrop: MeshInstance3D
var _wall_mats: Array[ShaderMaterial] = []
## Empat benturan dinding terakhir: x = lane z, y = sisa umur.
var _wall_hits := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _wall_hit_next := 0
var _fx: ArenaFx
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
var _alpha: float = 1.0
var _squad_firing := 0.0
## Tingkat "panas" combo 0..1, dikirim ke lantai supaya kisinya ikut menyala.
var _combo_heat := 0.0
## Posisi squad frame lalu: dari sini datang jawaban "sedang jalan atau diam",
## yang menentukan klip lari atau siaga. Simulasi tidak menyimpan kecepatan
## squad, dan menanyakannya ke input akan salah saat squad masih meluncur.
var _squad_x_prev := 0.0
var _squad_moving := false


## Called by Game before the first frame, with the variant for this stage.
func build(variant_index: int) -> void:
	_pal = UiTheme.palette(GameConfig.dict("variants.%d.theme" % variant_index))
	_load_enemy_colors()
	_build_environment()
	_build_backdrop()
	_build_floor()
	_build_actors()
	_build_far_crowd()
	_build_impacts()
	_fx = ArenaFx.new()
	_fx.name = "ArenaFx"
	add_child(_fx)
	_fx.build(_pal, 0x4E454F4E + variant_index)


## Palet musuh datang dari config, dalam urutan enemyTypes.
func _load_enemy_colors() -> void:
	_enemy_colors = PackedColorArray()
	for entry in GameConfig.list("enemyTypes"):
		var type_entry: Dictionary = entry
		_enemy_colors.append(
			Color.from_string(String(type_entry.get("color", "#E03A2F")), _pal["enemy"])
		)
	if _enemy_colors.is_empty():
		_enemy_colors.append(_pal["enemy"])


## Called by Game once a run starts. The furniture can only be built now:
## which obstacles exist is a property of the run, not of the scene.
func bind_sim(sim: SimWorld) -> void:
	_sim = sim
	if _fx != null:
		_fx.bind_sim(sim)
	_build_obstacles()


## Pushes one frame of simulation state into the scene.
func render_frame() -> void:
	if _sim == null:
		return
	var delta := get_process_delta_time()
	# Satu alpha untuk seluruh frame: semua entitas harus diinterpolasi pada
	# titik waktu yang sama, kalau tidak peluru dan musuh yang bertabrakan di
	# simulasi akan terlihat meleset di layar.
	_alpha = Engine.get_physics_interpolation_fraction()
	_squad_firing = maxf(_squad_firing - delta, 0.0)
	for entry in _sim.events:
		if String((entry as Dictionary).get("type", "")) == "auto_fired":
			_squad_firing = 0.12
	_squad_moving = absf(_sim.squad_x - _squad_x_prev) > 0.004
	_squad_x_prev = _sim.squad_x
	if _chars != null:
		_chars.begin()
	_render_enemies()
	_render_player()
	_render_auto()
	_render_chain()
	_render_gates()
	_render_obstacles()
	_render_boss()
	_spawn_impacts()
	_age_impacts()
	_age_wall_hits(delta)
	if _fx != null:
		_fx.tick(delta)
	_update_heat(delta)
	if _chars != null:
		_chars.end(delta)


## Posisi render: di antara pose tick sebelumnya dan pose tick sekarang.
##
## Simulasi melangkah 60 Hz, layar menggambar 90 atau 120 Hz. Tanpa ini setiap
## entitas melompat satu tick sekaligus lalu diam — getaran halus yang paling
## terasa justru pada musuh dekat, yang pikselnya paling besar.
func _ip(prev: float, now: float) -> float:
	return prev + (now - prev) * _alpha


func _build_environment() -> void:
	# Glow is what sells neon. Without it the emissive materials are merely
	# bright flat colours; with it they bleed and read as light sources. Nilai
	# ambang/intensitas datang dari config.artDirection.postfx supaya arah
	# visual bisa disetel tanpa menyentuh kode.
	var fx := GameConfig.dict("artDirection.postfx")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _pal["bg_bottom"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _pal["bg_top"]
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = Cfg.num(fx, "glowIntensity", 1.15)
	env.glow_bloom = Cfg.num(fx, "glowBloom", 0.28)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = Cfg.num(fx, "glowThreshold", 0.6)
	# ACES: inti ledakan di key art hampir putih tanpa pernah terlihat
	# "terbakar" jadi bidang rata. Tonemap linear tidak bisa melakukan itu.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = Cfg.num(fx, "exposure", 1.1)
	env.tonemap_white = Cfg.num(fx, "tonemapWhite", 6.0)
	# Fog hides the spawn gate's hard edge and gives the long lane real depth
	# for free, which a portrait screen badly needs.
	env.fog_enabled = true
	env.fog_light_color = _pal["fog"]
	env.fog_density = Cfg.num(fx, "fogDensity", 0.022)
	env.fog_sky_affect = 0.0
	# Vignette ungu + butir halus: keduanya menyatukan partikel dan bloom,
	# dan memusatkan mata ke lorong. Adjustments murah, tidak seperti SSAO.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05

	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)


## Langit, kota, dan vortex dalam satu quad di belakang segalanya.
func _build_backdrop() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = load(BACKDROP_SHADER)
	material.set_shader_parameter("fog_color", _pal["fog"])
	material.set_shader_parameter("night_color", _pal["bg_bottom"])
	material.set_shader_parameter("city_glow", _pal["primary"])
	material.set_shader_parameter("vortex_color", _pal["vortex"])
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = quad
	_backdrop.material_override = material
	# Digambar paling awal dan tidak pernah di-cull: vertex shader-nya
	# memaksa posisi layar penuh, jadi AABB-nya berbohong.
	_backdrop.extra_cull_margin = 16384.0
	_backdrop.sorting_offset = -1000.0
	add_child(_backdrop)


func _build_floor() -> void:
	var width := GameConfig.num("arena.width")
	var length := GameConfig.num("arena.height")
	# Apron: lantai dipanjangkan ke arah kamera, sama seperti APRON di
	# js/render3d.js. Tanpa itu, layar jangkung memperlihatkan tepi lantai
	# dekat pemain sebagai garis hitam — arena jadi terlihat seperti meja
	# melayang, bukan lorong.
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length + APRON + APRON_FAR)
	# Subdivision keeps the shader's derivative-based anti-aliasing stable
	# across the length of the lane.
	plane.subdivide_depth = 8

	var shader: Shader = load(FLOOR_SHADER)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("bg_top", _pal["bg_top"])
	material.set_shader_parameter("bg_bottom", _pal["bg_bottom"])
	material.set_shader_parameter("grid_color", _pal["primary"])
	material.set_shader_parameter("wall_glow", _pal["bumper"])
	material.set_shader_parameter("fog_color", _pal["fog"])
	# Logam gelap, bukan warna palet yang diredupkan: lantai di key art
	# nyaris netral, dan seluruh warnanya datang dari pantulan.
	material.set_shader_parameter("ground_near", _pal["bg_top"].darkened(0.55))
	material.set_shader_parameter("ground_far", _pal["bg_bottom"].lightened(0.06))
	material.set_shader_parameter("arena_half_width", width * 0.5)
	material.set_shader_parameter("arena_length", length)
	material.set_shader_parameter("defense_line_z", GameConfig.num("arena.defenseLineZ"))
	material.set_shader_parameter("defense_color", UiTheme.DANGER)
	material.set_shader_parameter("horizon_fade", APRON_FAR * 0.75)

	_floor = MeshInstance3D.new()
	_floor.mesh = plane
	_floor.material_override = material
	_floor.position = Vector3(0.0, 0.0, -length * 0.5 + (APRON - APRON_FAR) * 0.5)
	add_child(_floor)

	_build_side_walls(width, length)


func _build_side_walls(width: float, length: float) -> void:
	# Slab panel miring yang menyala, bukan palisade batu. Dinding adalah
	# permukaan paling informatif di layar — di sanalah peluru memantul —
	# jadi ia yang paling terang setelah peluru itu sendiri.
	#
	# Tingginya 1.8: cukup untuk terbaca sebagai bidang pantul dari kamera
	# yang rendah, masih cukup pendek untuk tidak menutupi barisan musuh
	# yang berjalan tepat di baliknya.
	_wall_mats.clear()
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 1.8, length + APRON)
		strip.mesh = box
		strip.position = Vector3(side * (width * 0.5 + 0.22), 0.9, -length * 0.5 + APRON * 0.5)
		var material := ShaderMaterial.new()
		material.shader = load(WALL_SHADER)
		material.set_shader_parameter("panel_color", _pal["wall_panel"])
		material.set_shader_parameter("glow_color", _pal["bumper"])
		material.set_shader_parameter("core_color", _pal["bumper_glow"])
		material.set_shader_parameter("fog_color", _pal["fog"])
		material.set_shader_parameter("arena_length", length)
		material.set_shader_parameter("horizon_fade", APRON_FAR * 0.75)
		material.set_shader_parameter("rim_height", 1.8)
		strip.material_override = material
		add_child(strip)
		_wall_mats.append(material)


func _build_actors() -> void:
	# Karakter ber-tulang untuk unit terdekat, MultiMesh untuk sisanya. Dua
	# jalur, satu ukuran: kapsul ikut dibesarkan CHAR_SCALE supaya barisan
	# belakang tidak menciut saat sebuah unit berpindah jalur.
	_chars = CharacterPool.new()
	_chars.name = "Characters"
	add_child(_chars)
	var roster: Array = ENEMY_UNITS.duplicate()
	roster.append(PLAYER_UNIT)
	roster.append(BOSS_UNIT)
	_chars.warm(roster)

	var scale: float = CharacterPool.CHAR_SCALE
	_enemy_mm = _make_multimesh(
		_capsule(0.35 * scale, 1.0 * scale), Color.WHITE, SimWorld.MAX_ENEMIES
	)
	_auto_mm = _make_multimesh(_sphere(0.1), _pal["primary"], SimWorld.MAX_AUTO_BULLETS)

	# Chain shot: selongsong kuningan, bukan bola kecil (docs/17 §17.5 E1).
	# Ini benda yang ditatap pemain selama seluruh pantulan, dan bola 26 cm
	# di ujung lorong tidak terbaca sebagai apa pun.
	_chain = MeshInstance3D.new()
	var shell := CapsuleMesh.new()
	shell.radius = 0.26
	shell.height = 0.92
	shell.radial_segments = 8
	shell.rings = 2
	_chain.mesh = shell
	_chain.material_override = _emissive(_pal["brass"], 2.6)
	add_child(_chain)

	# Jejak api: pita yang menyempit ke belakang, digambar ulang tiap frame.
	# ImmediateMesh dipilih daripada partikel karena bentuknya HARUS persis
	# mengikuti lintasan pantul — partikel akan melengkung di tikungan dan
	# sudut pantul adalah seluruh isi permainan ini.
	_chain_trail_mesh = ImmediateMesh.new()
	_chain_trail = MeshInstance3D.new()
	_chain_trail.mesh = _chain_trail_mesh
	_chain_trail.material_override = _additive(_pal["blast"])
	add_child(_chain_trail)


## Siluet kerumunan di balik gerbang spawn. Satu MultiMesh statis, tidak
## pernah diperbarui setelah dibangun: ia tidak bergerak, tidak bisa kena
## tembak, dan hanya ada supaya ujung lorong tidak kosong.
func _build_far_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x43524F57
	var scale: float = CharacterPool.CHAR_SCALE
	_far_crowd_mm = _make_multimesh(_capsule(0.35 * scale, 1.0 * scale), _pal["enemy"], FAR_CROWD)
	var mm := _far_crowd_mm.multimesh
	var half := GameConfig.num("arena.width") * 0.5
	for i in range(FAR_CROWD):
		var t := float(i) / float(FAR_CROWD)
		var z := lerpf(FAR_CROWD_FROM, FAR_CROWD_TO, t)
		# Melebar ke kejauhan: lorong berakhir di gerbang, tapi pasukan tidak.
		var spread := half * lerpf(1.0, 3.4, t)
		var x := rng.randf_range(-spread, spread)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.5 * scale, -z)))
		# Makin jauh makin larut ke kabut. Alpha tidak dipakai: material
		# kerumunan opaque, jadi yang digelapkan adalah warnanya.
		mm.set_instance_color(i, _pal["enemy"].lerp(_pal["fog"], 0.35 + t * 0.6))
	mm.visible_instance_count = FAR_CROWD


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
			# Drum merah bertanda bahaya di key art: badannya gelap, hanya
			# pita atasnya yang panas. Emissive penuh membuatnya terbaca
			# sebagai lampu dan pemain berhenti takut padanya.
			node.mesh = _cylinder(0.6, 1.2)
			var drum := StandardMaterial3D.new()
			drum.albedo_color = _pal["enemy"].darkened(0.35)
			drum.metallic = 0.6
			drum.roughness = 0.45
			drum.emission_enabled = true
			drum.emission = _pal["blast"]
			drum.emission_energy_multiplier = 0.55
			node.material_override = drum
		"shieldWall", "movingPlatform":
			var slab := BoxMesh.new()
			slab.size = Vector3(float(obstacle["width"]), 0.9, 0.5)
			node.mesh = slab
			node.material_override = _emissive(_pal["bumper"], 0.9)
		"pillar":
			node.mesh = _cylinder(radius, 3.0)
			var column := StandardMaterial3D.new()
			column.albedo_color = _pal["wall_panel"]
			column.metallic = 0.5
			column.roughness = 0.6
			column.emission_enabled = true
			column.emission = _pal["bumper"]
			column.emission_energy_multiplier = 0.22
			node.material_override = column
		_:
			var ball := SphereMesh.new()
			ball.radius = radius
			ball.height = radius * 2.0
			node.mesh = ball
			node.material_override = _emissive(_pal["bumper_glow"], 2.4)
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
		actor.place(
			_ip(_sim.pose.boss_pos.x, _sim.boss_pos.x),
			_ip(_sim.pose.boss_pos.y, _sim.boss_pos.y),
			PI
		)
		if actor.lock <= 0.0:
			actor.play("idle")
		return
	_boss.visible = _sim.boss_active
	if _boss.visible:
		_boss.position = Vector3(
			_ip(_sim.pose.boss_pos.x, _sim.boss_pos.x),
			1.4,
			-_ip(_sim.pose.boss_pos.y, _sim.boss_pos.y)
		)


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
##
## Satu tempat membaca peristiwa, lima efek keluar dari sana. Alternatifnya —
## tiap efek menyapu daftar peristiwa sendiri — berarti lima kali iterasi
## atas daftar yang sama tiap frame, dan lima tempat yang bisa lupa menangani
## jenis peristiwa baru.
func _spawn_impacts() -> void:
	for entry in _sim.events:
		var event: Dictionary = entry
		var kind := String(event.get("type", ""))
		var x := float(event.get("x", 0.0))
		var z := float(event.get("z", 0.0))
		var radius := 0.0
		var tint: Color = _pal["primary"]
		match kind:
			"kill":
				radius = 0.9
				tint = _pal["enemy"]
				if _chars != null:
					var fallen := _unit_name(int(event.get("enemy", 0)) % ENEMY_UNITS.size())
					_chars.drop_corpse(fallen, x, z)
			"explosion":
				radius = float(event.get("radius", 3.0))
				tint = _pal["blast"]
				# Cincin kejut mengambil radius yang SAMA dengan ledakan di
				# simulasi: pemain belajar jangkauan barrel dari cincin ini,
				# jadi cincin yang berbohong lebih buruk daripada tidak ada.
				if _fx != null:
					_fx.explosion_ring(Vector3(x, 0.08, -z), radius)
			"bounce":
				radius = 0.6
				tint = _pal["bumper_glow"]
				_register_wall_hit(x, z)
				if _fx != null:
					_fx.bounce_arc(Vector3(x, 0.7, -z))
			_:
				continue
		_light_impact(Vector3(x, 0.6, -z), radius, tint)


## Menyalakan titik benturan di shader dinding, kalau benturannya memang di
## dinding samping dan bukan di bumper tengah lapangan.
func _register_wall_hit(x: float, z: float) -> void:
	var half := GameConfig.num("arena.width") * 0.5
	if absf(absf(x) - half) > 1.2:
		return
	var slot := _wall_hit_next % _wall_hits.size()
	_wall_hit_next += 1
	_wall_hits[slot] = Vector2(z, 1.0)


## Umur benturan dinding turun linear, lalu didorong ke kedua material
## sekaligus. Dikirim per frame dan bukan per benturan: empat uniform vec4
## adalah biaya tetap, sedangkan jumlah benturan tidak terbatas.
func _age_wall_hits(delta: float) -> void:
	if _wall_mats.is_empty():
		return
	var z_values := Vector4.ZERO
	var life_values := Vector4.ZERO
	for i in range(_wall_hits.size()):
		var hit := _wall_hits[i]
		hit.y = maxf(hit.y - delta / 0.3, 0.0)
		_wall_hits[i] = hit
		z_values[i] = hit.x
		life_values[i] = hit.y
	for material in _wall_mats:
		material.set_shader_parameter("hit_z", z_values)
		material.set_shader_parameter("hit_life", life_values)


## Combo memanaskan lantai. Naik cepat, turun lambat: pemain harus melihat
## dunia membalas prestasinya, tapi tidak boleh melihatnya berkedip mati
## setiap kali rantai putus sesaat.
func _update_heat(delta: float) -> void:
	var want: float = clampf(float(_sim.combo) / 40.0, 0.0, 1.0)
	var rate := 6.0 if want > _combo_heat else 1.6
	_combo_heat = move_toward(_combo_heat, want, delta * rate)
	if _floor != null:
		var material := _floor.material_override as ShaderMaterial
		material.set_shader_parameter("combo_heat", _combo_heat)


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
		var type_index: int = _sim.enemy_type[i] % _enemy_colors.size()
		var hurt: bool = _sim.enemy_hp[i] < _enemy_hp_seen[i] - 0.001
		_enemy_hp_seen[i] = _sim.enemy_hp[i]
		var unit := _unit_name(type_index)
		var actor: CharacterPool.Actor = null
		if skinned.has(i) and _chars != null:
			actor = _chars.take(unit)
		var ex := _ip(_sim.pose.enemy_x[i], _sim.enemy_x[i])
		var ez := _ip(_sim.pose.enemy_z[i], _sim.enemy_z[i])
		if actor != null:
			# Menatap pemain: model menghadap -Z, musuh berjalan ke arah +Z.
			actor.place(ex, ez, PI)
			if hurt:
				actor.one_shot("hit", 0.3)
			elif actor.lock <= 0.0:
				actor.play("run")
			continue
		var pos := Vector3(ex, 0.5 * CharacterPool.CHAR_SCALE, -ez)
		mm.set_instance_transform(drawn, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(drawn, _enemy_colors[type_index])
		drawn += 1
	mm.visible_instance_count = drawn


## Indeks tipe simulasi -> nama berkas karakter.
func _unit_name(type_index: int) -> String:
	if type_index < 0 or type_index >= ENEMY_UNITS.size():
		return ENEMY_UNITS[0]
	return String(ENEMY_UNITS[type_index])


## Satu prajurit, bukan peleton (docs/18 Fase 4, keputusan D1).
##
## Simulasi masih menyimpan `troops`, dan aturannya tidak diubah sedikit pun:
## angka itu tetap menaikkan laju tembak dan tetap dipotong saat musuh lolos.
## Yang berubah hanyalah pembacaannya — ia POWER senjata, bukan jumlah badan.
## Itu keputusan yang bisa diambil sepenuhnya di sisi tampilan, jadi replay
## lama tetap cocok bit demi bit.
##
## Konsekuensinya besar untuk komposisi: dengan satu badan di layar, pemain
## boleh digambar 1,35x lebih besar dari siapa pun, diberi rim cyan, dan
## ditempatkan sebagai jangkar di dasar layar persis seperti key art.
func _render_player() -> void:
	var x: float = _ip(_sim.pose.squad_x, _sim.squad_x)
	var z: float = SimWorld.SQUAD_Z
	var actor: CharacterPool.Actor = null
	if _chars != null:
		actor = _chars.take(PLAYER_UNIT)
	if actor == null:
		return
	actor.place(x, z, 0.0)
	if actor.has_method("set_scale_multiplier"):
		actor.call("set_scale_multiplier", PLAYER_SCALE)
	if _squad_firing > 0.0:
		actor.one_shot("shoot", 0.22)
		# Kilatan moncong pemain BIRU, bukan oranye. Di key art itulah satu-
		# satunya cara membedakan tembakan sendiri dari hujan tracer musuh
		# dalam seperlima detik.
		_light_impact(actor.muzzle_point(), 0.34, _pal["primary"])
	elif actor.lock <= 0.0:
		actor.play("run" if _squad_moving else "idle")


func _render_auto() -> void:
	var mm := _auto_mm.multimesh
	mm.visible_instance_count = _sim.auto_count
	for i in range(_sim.auto_count):
		var pos := Vector3(
			_ip(_sim.pose.auto_x[i], _sim.auto_x[i]), 0.5, -_ip(_sim.pose.auto_z[i], _sim.auto_z[i])
		)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, _pal["primary"])


## Chain shot sengaja TIDAK diinterpolasi.
##
## Lintasannya memantul: membaurkan pose sebelum dan sesudah pantulan akan
## memotong sudutnya, dan sudut itulah inti permainannya. Parity dengan
## js/render3d.js, yang mengambil keputusan sama.
func _render_chain() -> void:
	_chain.visible = _sim.chain_active
	if not _sim.chain_active:
		_chain_points.clear()
		_chain_trail_mesh.clear_surfaces()
		return
	var here := Vector3(_sim.chain_pos.x, 0.6, -_sim.chain_pos.y)
	_chain.position = here
	# Selongsong menghadap arah geraknya. Tanpa ini ia berputar acak dan
	# terbaca sebagai pil, bukan peluru.
	var dir := Vector3(_sim.chain_dir.x, 0.0, -_sim.chain_dir.y)
	if dir.length_squared() > 0.0001:
		_chain.look_at(here + dir, Vector3.UP)
		# CapsuleMesh berdiri di sumbu Y; miringkan agar berbaring ke depan.
		_chain.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_chain_points.push_front(here)
	# Panjang jejak 8-10 unit pada kecepatan jelajah; dibatasi jumlah titik
	# supaya biaya menggambarnya tetap konstan berapa pun laju frame.
	while _chain_points.size() > 18:
		_chain_points.pop_back()
	_rebuild_trail()


## Pita api: dua simpul per titik jejak, melebar di kepala dan menyempit di
## ekor. Digambar ulang tiap frame karena jejaknya memang berubah tiap frame;
## tidak ada yang bisa di-cache di sini.
func _rebuild_trail() -> void:
	_chain_trail_mesh.clear_surfaces()
	if _chain_points.size() < 2:
		return
	_chain_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := _chain_points.size()
	for i in range(count):
		var t := float(i) / float(count - 1)
		var point: Vector3 = _chain_points[i]
		var ahead: Vector3 = _chain_points[maxi(i - 1, 0)]
		var along := ahead - point
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		var side := along.normalized().cross(Vector3.UP).normalized() * (0.34 * (1.0 - t))
		# Inti nyaris putih di kepala, oranye di ekor, lalu habis.
		var tint: Color = _pal["blast_core"].lerp(_pal["blast"], t)
		tint.a = (1.0 - t) * (1.0 - t)
		_chain_trail_mesh.surface_set_color(tint)
		_chain_trail_mesh.surface_add_vertex(point - side)
		_chain_trail_mesh.surface_set_color(tint)
		_chain_trail_mesh.surface_add_vertex(point + side)
	_chain_trail_mesh.surface_end()


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


## Material aditif berwarna simpul: dipakai jejak peluru, busur petir, dan
## cincin kejut. Aditif, bukan alpha, karena ketiganya adalah CAHAYA — alpha
## blending membuatnya terlihat seperti cat di atas arena.
func _additive(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.no_depth_test = false
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
