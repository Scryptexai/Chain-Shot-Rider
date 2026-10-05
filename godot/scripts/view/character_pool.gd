class_name CharacterPool
extends Node3D
## Kolam karakter KayKit, dipinjam per frame.
##
## Satu-satunya tempat di proyek Godot yang tahu cara merakit karakter dari
## berkas pack, memutar klipnya, dan mendaur ulang nodenya. ArenaView hanya
## meminta "beri aku seorang grunt di sini, sedang berlari".
##
## Yang dimuat adalah berkas KayKit APA ADANYA — tidak ada GLB turunan, tidak
## ada mesh yang digabung, tidak ada tekstur yang dipanggang ulang:
##
##     Characters/gltf/Knight.glb        tubuh (9 mesh, 23 tulang)
##     Animations/gltf/Rig_Medium/*.glb  klip, dipakai bersama seluruh cast
##     Assets/gltf/sword_1handed.gltf    senjata, digantung di tulang handslot
##
## Tiga berkas itu baru bertemu di sini, di runtime.
##
## Satu-satunya perlakuan terhadap geometrinya adalah penyatuan di memori:
## kesembilan potongan tubuh dipakai memakai skin dan material yang sama, jadi
## atributnya disambung berturut-turut menjadi satu ArrayMesh (lihat
## _merge_body). Hasilnya identik verteks-per-verteks — UV, normal, bobot
## tulang, dan tekstur dibawa apa adanya — tapi GPU dipanggil sekali per aktor,
## bukan sembilan kali. Berkas pack-nya sendiri tidak pernah ditulis ulang.
##
## Kenapa kolam, bukan instantiate per musuh: satu karakter berarti satu
## Skeleton3D dan satu AnimationPlayer yang dihitung ulang tiap frame. Pada
## gelombang 200 musuh itu ratusan skeleton. Jadi hanya unit TERDEKAT yang
## mendapat tubuh sungguhan; sisanya tetap MultiMesh di ArenaView. Batasnya
## kembar dengan versi web (js/render3d.js).
##
## Pemakaian per frame:
##     pool.begin()
##     var actor := pool.take("grunt")
##     actor.place(x, z, facing)   ; actor.play("run")
##     pool.end(delta)

## Anggaran LOD — kembar dari SKIN di js/render3d.js.
const BUDGET := {"troops": 10, "enemies": 24, "corpses": 8}

## Tinggi semua karakter di dunia game, dalam unit arena. Karakter KayKit
## lahir setinggi 2,17–2,66 unit dan tingginya berbeda-beda; satu-satunya
## penyesuaian yang dilakukan di sini adalah skala node supaya semuanya
## sepakat di angka ini. Nilainya sama dengan versi lama (0,96 x 2,0), jadi
## kamera, formasi, dan kotak tabrakan tidak perlu disetel ulang.
const CHAR_HEIGHT := 1.92

## Skala untuk jalur MultiMesh (kapsul musuh jauh) yang bukan karakter.
## Dipisah dari skala karakter karena kapsulnya memang bukan model KayKit.
const CHAR_SCALE := 2.0

## Berapa lama mayat tergeletak sebelum memudar, dan lama memudarnya.
const CORPSE_SECONDS := 1.5
const CORPSE_FADE := 0.5

const KIT := "res://assets/models/kaykit/"
const ANIM_FILES := [
	"Animations/gltf/Rig_Medium/Rig_Medium_General.glb",
	"Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb",
]

## Peran -> karakter, senjata, klip tembak, ukuran. Hanya PEMILIHAN; tidak ada
## satu pun angka di sini yang mengubah isi berkasnya. Kembar dari CAST di
## js/render3d.js — kalau yang satu berubah, yang lain harus ikut.
const CAST := {
	# Pemain tidak memakai satu pun aset senjata pack: pedang dan perisai
	# fantasi dibuang, zirahnya dicat ulang oleh ARMOR_SHADER, dan senjata
	# api dibangun prosedural di _make_rifle(). Lihat docs/00-art-bible.md §3.
	"trooper": {"model": "Knight", "skin": "armor"},
	"grunt": {"model": "Rogue", "right": "dagger"},
	"runner": {"model": "Ranger", "right": "bow_withString"},
	"brute": {"model": "Barbarian", "right": "axe_2handed"},
	"splitter":
	{"model": "Mage", "right": "staff", "left": "spellbook_closed", "shoot": "Use_Item"},
	"bomber": {"model": "Rogue_Hooded", "right": "smokebomb"},
	"shielder": {"model": "Knight", "right": "sword_1handed", "left": "shield_square_color"},
	"boss": {"model": "Knight", "right": "sword_2handed_color", "size": 2.0},
}

## Nama klip di pack -> nama yang dipakai state machine game. Klip tidak
## di-rename di dalam berkas; pemetaan hidup di sini saja.
const CLIP_SOURCE := {
	"idle": "Idle_A",
	"run": "Running_A",
	"shoot": "Throw",
	"hit": "Hit_A",
	"die": "Death_A",
}

## Tulang tempat senjata digantung, disediakan rig KayKit khusus untuk ini.
const SOCKET := {"right": "handslot.r", "left": "handslot.l"}

## Cat zirah sci-fi pemain. Lihat berkasnya untuk alasan tiap keputusannya.
const ARMOR_SHADER := "res://shaders/player_armor.gdshader"

## Klip yang tidak boleh berulang: aksi sesaat yang harus berhenti di frame
## terakhirnya (roboh harus tetap roboh).
const ONCE_CLIPS := ["shoot", "hit", "die"]


## Satu tubuh ber-tulang yang bisa dipinjam. Bukan Node: hanya pembungkus
## tipis supaya pemanggil tidak perlu mengurus skeleton dan mixer sendiri.
class Actor:
	extends RefCounted

	var kind: String
	var root: Node3D
	var anim: AnimationPlayer
	var muzzle: Node3D
	## Semua mesh milik satu karakter. KayKit memecah tubuh jadi sembilan
	## bagian, jadi efek yang menyentuh "model"-nya (memudar saat jadi mayat)
	## harus menyentuh kesembilannya.
	var meshes: Array
	var current := ""
	## Skala rig apa adanya, sebelum pemain membesarkannya.
	var base_scale := 1.0
	## Sisa detik sebelum klip sesaat boleh diganti klip lain.
	var lock := 0.0
	## Fase dan kecepatan sendiri-sendiri. Tanpa ini tiga puluh musuh
	## melangkah seperti satu tubuh dan pasukan terlihat baris-berbaris.
	var phase := 0.0
	var rate := 1.0

	func _init(
		unit: String, node: Node3D, player: AnimationPlayer, socket: Node3D, skins: Array
	) -> void:
		kind = unit
		root = node
		base_scale = node.scale.x
		anim = player
		muzzle = socket
		meshes = skins
		phase = randf()
		rate = 0.92 + randf() * 0.16

	## Menaruh aktor di koordinat simulasi (x, z). Dunia memetakan z ke -z.
	func place(x: float, z: float, facing: float) -> void:
		root.position = Vector3(x, 0.0, -z)
		root.rotation.y = facing

	## Pembesar ukuran, dipakai hanya oleh pemain.
	##
	## Aktor dipinjam dari kolam bersama, jadi skala harus disetel ulang tiap
	## frame: badan yang kemarin jadi pemain bisa jadi musuh hari ini, dan
	## seorang grunt sebesar 1,35x akan terbaca sebagai elite yang tidak ada.
	## Karena itu pengalinya selalu dihitung dari base_scale rig, bukan
	## ditumpuk di atas skala frame sebelumnya.
	func set_scale_multiplier(factor: float) -> void:
		root.scale = Vector3.ONE * base_scale * factor

	func play(name: String, blend := 0.12) -> void:
		if current == name or not anim.has_animation(name):
			return
		anim.play(name, blend)
		if name in CharacterPool.ONCE_CLIPS:
			anim.speed_scale = 1.0
		else:
			# Klip berulang masuk di titik acak lintasannya.
			anim.speed_scale = rate
			anim.seek(phase * anim.get_animation(name).length, true)
		current = name

	## Klip sesaat yang tidak boleh dipotong klip lain selama `seconds`.
	func one_shot(name: String, seconds: float) -> void:
		if lock > 0.0:
			return
		play(name, 0.05)
		lock = seconds

	## Posisi dunia moncong senjata, mengikuti ayunan lengan. Dipakai untuk
	## menempelkan kilatan tembakan di ujung laras, bukan di tengah dada.
	func muzzle_point() -> Vector3:
		if muzzle == null:
			return root.global_position + Vector3(0.0, 0.9, -0.6)
		return muzzle.global_position

	func tick(delta: float) -> void:
		lock = maxf(lock - delta, 0.0)


var _scenes: Dictionary = {}  ## nama karakter -> PackedScene pack
var _items: Dictionary = {}  ## nama senjata -> PackedScene pack
var _clips: Dictionary = {}  ## nama klip KayKit -> Animation
var _heights: Dictionary = {}  ## nama karakter -> tinggi aslinya
var _merged: Dictionary = {}  ## nama karakter -> ArrayMesh gabungan (satu draw call)
var _rigs: Dictionary = {}  ## peran -> resep siap pakai
var _pools: Dictionary = {}
var _used: Dictionary = {}
var _corpses: Array = []
var _corpse_life := PackedFloat32Array()
## Lemparan mayat: kecepatan sisa dan laju jungkir, sejajar dengan _corpses.
var _corpse_vel: Array[Vector3] = []
var _corpse_spin: PackedFloat32Array = PackedFloat32Array()
var _loaded := 0
var _armor: ShaderMaterial = null
var _armor_steel := Color("#DCE6F2")
var _armor_deep := Color("#2E5BD8")
var _armor_rim := Color("#2BE8FF")


## Memuat berkas pack untuk peran yang disebut. Dipanggil sekali sebelum run
## pertama: memuat saat musuh pertama muncul berarti hitch tepat di detik
## paling ramai.
##
## Tiga jenis berkas dimuat di sini dan masing-masing sekali saja. Knight
## dipakai tiga peran; memuatnya per peran berarti membaca berkas yang sama
## tiga kali dan menyimpan tiga salinan di memori.
func warm(kinds: Array) -> int:
	_load_clips()
	for entry in kinds:
		var kind := String(entry)
		if _rigs.has(kind):
			continue
		var recipe: Dictionary = CAST.get(kind, {})
		if recipe.is_empty():
			push_warning("CharacterPool: peran %s tidak ada di CAST" % kind)
			continue
		var model := String(recipe["model"])
		if not _scenes.has(model):
			var packed := load(KIT + "Characters/gltf/%s.glb" % model)
			if packed == null:
				push_warning("CharacterPool: karakter %s tidak ada" % model)
				continue
			_scenes[model] = packed
			_heights[model] = _measure_height(packed)
		for hand in ["right", "left"]:
			if not recipe.has(hand):
				continue
			var item := String(recipe[hand])
			if not _items.has(item):
				var weapon := load(KIT + "Assets/gltf/%s.gltf" % item)
				if weapon != null:
					_items[item] = weapon
		var height: float = _heights.get(model, CHAR_HEIGHT)
		_rigs[kind] = {
			"model": model,
			"scale": (CHAR_HEIGHT / maxf(height, 0.001)) * float(recipe.get("size", 1.0)),
			"shoot": String(recipe.get("shoot", CLIP_SOURCE["shoot"])),
			"right": recipe.get("right", ""),
			"left": recipe.get("left", ""),
			"skin": String(recipe.get("skin", "")),
		}
		_loaded += 1
	return _loaded


## Mengumpulkan klip dari dua berkas animasi pack.
##
## Berkas animasi KayKit adalah scene terpisah berisi manekin + AnimationPlayer.
## Yang diambil hanya Animation-nya; manekinnya langsung dibuang. Karena jalur
## track-nya (`Rig_Medium/Skeleton3D:hips`) sama persis dengan struktur node di
## berkas karakter, klip itu langsung cocok tanpa retarget apa pun.
func _load_clips() -> void:
	if not _clips.is_empty():
		return
	for rel in ANIM_FILES:
		var packed := load(KIT + rel)
		if packed == null:
			push_warning("CharacterPool: berkas animasi %s tidak ada" % rel)
			continue
		var scene: Node = packed.instantiate()
		var player: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		if player != null:
			for name in player.get_animation_list():
				var clip := player.get_animation(name)
				if clip != null:
					_clips[name] = clip.duplicate()
		scene.free()


## Tinggi karakter dalam berkasnya sendiri, dipakai untuk menghitung skala.
func _measure_height(packed: PackedScene) -> float:
	var scene: Node = packed.instantiate()
	var box := AABB()
	var first := true
	for mesh in _all_meshes(scene):
		var mesh_box: AABB = mesh.get_aabb()
		if first:
			box = mesh_box
			first = false
		else:
			box = box.merge(mesh_box)
	scene.free()
	return box.size.y


func loaded_count() -> int:
	return _loaded


func has_kind(kind: String) -> bool:
	return _rigs.has(kind)


## Menandai awal frame: semua aktor dianggap bebas sampai ada yang meminjam.
func begin() -> void:
	for kind in _used:
		_used[kind] = 0


## Meminjam satu aktor. null berarti model tidak ada — pemanggil harus punya
## jalur cadangan (MultiMesh), karena karakter hilang lebih buruk daripada
## karakter sederhana.
func take(kind: String) -> Actor:
	if not _rigs.has(kind):
		return null
	if not _pools.has(kind):
		_pools[kind] = []
		_used[kind] = 0
	var pool: Array = _pools[kind]
	var index: int = _used[kind]
	if index >= pool.size():
		var actor := _spawn(kind)
		if actor == null:
			return null
		pool.append(actor)
	_used[kind] = index + 1
	var taken: Actor = pool[index]
	taken.root.visible = true
	# Skala dikembalikan ke ukuran rig setiap kali aktor dipinjam. Pemain
	# membesarkan badannya sendiri setelah ini; tanpa reset, badan bekas
	# pemain akan muncul kembali sebagai musuh raksasa di frame berikutnya.
	taken.root.scale = Vector3.ONE * taken.base_scale
	return taken


## Menutup frame: aktor yang tidak dipinjam disembunyikan DAN animasinya
## dihentikan, supaya skeleton yang tak terlihat tidak ikut dibayar.
func end(delta: float) -> void:
	for kind in _pools:
		var pool: Array = _pools[kind]
		var used: int = _used.get(kind, 0)
		for i in range(pool.size()):
			var actor: Actor = pool[i]
			if i < used:
				actor.tick(delta)
			elif actor.root.visible:
				actor.root.visible = false
				actor.anim.stop()
				actor.current = ""
	_age_corpses(delta)


## Merobohkan satu tubuh di tempat musuh mati. Mayat bukan aktor pinjaman:
## ia harus tetap ada setelah musuhnya hilang dari simulasi.
## `impulse` adalah lemparan ledakan: murni tampilan, sama sekali tidak
## kembali ke simulasi. Musuhnya sudah mati pada tick yang sama baik ia
## terbang maupun tidak — yang ditambahkan hanyalah bukti bahwa ledakan itu
## punya tenaga. Tanpa ini, satu drum yang meledak di tengah kerumunan
## terbaca sebagai dua puluh unit yang sekadar menghilang.
func drop_corpse(kind: String, x: float, z: float, impulse := Vector3.ZERO) -> void:
	if not _rigs.has(kind):
		return
	var slot := -1
	for i in range(_corpses.size()):
		if _corpse_life[i] <= 0.0:
			slot = i
			break
	if slot < 0:
		if _corpses.size() >= BUDGET["corpses"]:
			return
		var actor := _spawn(kind)
		if actor == null:
			return
		_corpses.append(actor)
		_corpse_life.append(0.0)
		_corpse_vel.append(Vector3.ZERO)
		_corpse_spin.append(0.0)
		slot = _corpses.size() - 1
	elif _corpses[slot].kind != kind:
		# Slot bebas tapi jenisnya salah: tubuh lama dibuang, diganti yang
		# benar. Grunt yang roboh tidak boleh berubah jadi brute.
		_corpses[slot].root.queue_free()
		var replacement := _spawn(kind)
		if replacement == null:
			return
		_corpses[slot] = replacement
	var corpse: Actor = _corpses[slot]
	corpse.root.visible = true
	corpse.place(x, z, PI)
	corpse.current = ""
	corpse.anim.speed_scale = 1.0
	corpse.play("die", 0.0)
	corpse.root.rotation.x = 0.0
	corpse.root.rotation.z = 0.0
	_corpse_life[slot] = CORPSE_SECONDS
	_corpse_vel[slot] = impulse
	# Jungkirnya diturunkan dari lemparannya sendiri: makin keras terlempar,
	# makin cepat berputar. Arahnya ikut tanda x supaya dua mayat di sisi
	# berlawanan dari ledakan tidak berputar ke arah yang sama.
	_corpse_spin[slot] = signf(impulse.x) * impulse.length() * 0.9


func corpse_count() -> int:
	var n := 0
	for i in range(_corpse_life.size()):
		if _corpse_life[i] > 0.0:
			n += 1
	return n


## Jumlah aktor ber-tulang yang dipakai frame ini. Dipakai tes asap untuk
## membuktikan anggaran LOD benar-benar dihormati.
func active_count() -> int:
	var n := 0
	for kind in _used:
		n += int(_used[kind])
	return n


func _spawn(kind: String) -> Actor:
	var rig: Dictionary = _rigs.get(kind, {})
	if rig.is_empty():
		return null
	var packed: PackedScene = _scenes.get(rig["model"])
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	root.scale = Vector3.ONE * float(rig["scale"])
	_merge_body(root, String(rig["model"]))

	var player := _build_player(rig)
	root.add_child(player)

	var socket := _attach_items(root, rig)
	if String(rig.get("skin", "")) == "armor":
		_wear_armor(root, socket)
	add_child(root)
	return Actor.new(kind, root, player, socket, _all_meshes(root))


## Warna zirah pemain, diambil dari palet ruangan yang sedang aktif.
##
## Dipanggil sebelum warm(): materialnya dibangun sekali saat aktor pertama
## lahir, jadi perubahan setelah itu tidak akan terbaca.
func set_player_skin(steel: Color, deep: Color, rim: Color) -> void:
	_armor_steel = steel
	_armor_deep = deep
	_armor_rim = rim
	if _armor != null:
		_paint(_armor)


func _paint(material: ShaderMaterial) -> void:
	material.set_shader_parameter("steel_color", _armor_steel)
	material.set_shader_parameter("deep_color", _armor_deep)
	material.set_shader_parameter("rim_color", _armor_rim)


## Satu material dipakai bersama semua mesh pemain: ia tidak pernah berbeda
## per bagian tubuh, dan berbagi material berarti berbagi state GPU.
func _armor_material() -> ShaderMaterial:
	if _armor != null:
		return _armor
	var shader: Shader = load(ARMOR_SHADER)
	if shader == null:
		return null
	_armor = ShaderMaterial.new()
	_armor.shader = shader
	_paint(_armor)
	return _armor


## Mengecat seluruh tubuh dan menggantungkan senjata prosedural.
func _wear_armor(root: Node3D, socket: Node3D) -> void:
	var material := _armor_material()
	if material == null:
		return
	for mesh in _all_meshes(root):
		(mesh as MeshInstance3D).material_override = material
	if socket != null:
		socket.add_child(_make_rifle(material))


## Senjata api sederhana: popor, badan, laras, inti menyala.
##
## Prosedural dan bukan model, karena satu-satunya hal yang harus benar pada
## ukuran di layar ini adalah SILUET-nya — balok panjang horizontal dengan
## satu titik panas cyan di ujungnya. Begitu ada model sci-fi CC0 yang
## sungguhan, fungsi ini diganti satu baris load().
func _make_rifle(material: ShaderMaterial) -> Node3D:
	var gun := Node3D.new()
	gun.name = "Rifle"
	var parts := [
		# [ukuran, posisi di sumbu senjata]
		[Vector3(0.09, 0.22, 0.12), 0.02],
		[Vector3(0.11, 0.34, 0.16), 0.30],
	]
	for part in parts:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		box.mesh = mesh
		box.position = Vector3(0.0, part[1], 0.0)
		box.material_override = material
		gun.add_child(box)
	var barrel := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.035
	tube.bottom_radius = 0.045
	tube.height = 0.42
	tube.radial_segments = 8
	barrel.mesh = tube
	barrel.position = Vector3(0.0, 0.66, 0.0)
	barrel.material_override = material
	gun.add_child(barrel)
	# Inti cyan di ujung laras: titik yang sama tempat kilatan tembakan lahir,
	# jadi senjata tetap terbaca sebagai milik pemain bahkan saat diam.
	var core := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.055
	bulb.height = 0.11
	bulb.radial_segments = 8
	bulb.rings = 4
	core.mesh = bulb
	core.position = Vector3(0.0, 0.88, 0.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = _armor_rim
	glow.emission_enabled = true
	glow.emission = _armor_rim
	glow.emission_energy_multiplier = 3.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = glow
	gun.add_child(core)
	return gun


## Merakit AnimationPlayer berisi lima klip yang dipakai game.
##
## Berkas karakter KayKit tidak membawa animasi sama sekali — ia hanya tubuh
## dan rig. Jadi playernya dibuat di sini, diisi salinan klip dari berkas
## animasi, lalu dinamai ulang ke nama peran (`idle`, `run`, ...). Yang
## di-rename adalah salinan di memori; berkas pack tidak disentuh.
##
## `root_node` dibiarkan pada default (induk player, yaitu akar karakter),
## karena jalur track di berkas animasi memang relatif terhadap titik itu:
## `Rig_Medium/Skeleton3D:hips`.
func _build_player(rig: Dictionary) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for role in CLIP_SOURCE:
		var source: String = rig["shoot"] if role == "shoot" else String(CLIP_SOURCE[role])
		var clip: Animation = _clips.get(source)
		if clip == null:
			continue
		var copy: Animation = clip.duplicate()
		# glTF tidak menyimpan "klip ini berulang", jadi importer menandai
		# semuanya sekali-jalan. Tanpa perbaikan ini musuh melangkah satu
		# langkah lalu membeku di udara.
		copy.loop_mode = Animation.LOOP_NONE if role in ONCE_CLIPS else Animation.LOOP_LINEAR
		library.add_animation(role, copy)
	player.add_animation_library("", library)
	return player


## Menggantung senjata di tulang tangan dan mengembalikan soket tangan kanan
## (dipakai sebagai titik lahir peluru dan kilatan tembakan).
##
## BoneAttachment3D adalah cara Godot mengikuti satu tulang; senjata KayKit
## diekspor pada titik asal supaya cukup di-parent ke situ tanpa offset.
func _attach_items(root: Node3D, rig: Dictionary) -> Node3D:
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		return null
	var right_socket: Node3D = null
	for hand in ["right", "left"]:
		var bone_name: String = SOCKET[hand]
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Socket_" + hand
		attachment.bone_name = bone_name
		attachment.bone_idx = bone
		skeleton.add_child(attachment)
		if hand == "right":
			right_socket = attachment
		var item_name := String(rig.get(hand, ""))
		if item_name == "":
			continue
		var item: PackedScene = _items.get(item_name)
		if item != null:
			attachment.add_child(item.instantiate())
	return right_socket


## Menyatukan potongan tubuh menjadi satu MeshInstance3D — di memori, sekali
## per karakter, hasilnya dipakai semua aktor peran itu.
##
## KayKit mengirim tubuh sebagai 7-9 mesh terpisah (lengan, kepala, helm,
## jubah, ...). Kesembilannya memakai skin yang sama dan material yang sama,
## jadi menyambung array permukaannya menghasilkan mesh yang identik
## verteks-per-verteks dengan aslinya. Yang hilang hanya delapan draw call.
##
## Kalau syaratnya tidak terpenuhi (material berbeda, skin berbeda, format
## verteks berbeda), fungsi ini tidak melakukan apa-apa dan karakter digambar
## sebagai sembilan mesh seperti di berkasnya.
func _merge_body(root: Node3D, model: String) -> void:
	var parts: Array = _body_parts(root)
	if parts.size() < 2 or not _parts_uniform(parts):
		return

	var first: MeshInstance3D = parts[0]
	var parent := first.get_parent()
	var merged: ArrayMesh = _merged.get(model)
	if merged == null:
		merged = _join_surfaces(
			parts, first.mesh.surface_get_format(0), first.mesh.surface_get_material(0)
		)
		if merged == null:
			return
		_merged[model] = merged

	var body := MeshInstance3D.new()
	body.name = model + "_merged"
	body.mesh = merged
	body.skin = first.skin
	body.skeleton = first.skeleton
	body.transform = first.transform
	for part in parts:
		var mi: MeshInstance3D = part
		parent.remove_child(mi)
		mi.queue_free()
	parent.add_child(body)


## Potongan tubuh: mesh ber-skin dengan satu permukaan. Senjata (tanpa skin)
## dan node lain tidak ikut.
func _body_parts(root: Node3D) -> Array:
	var parts: Array = []
	for mesh in _all_meshes(root):
		var mi := mesh as MeshInstance3D
		if mi.skin != null and mi.mesh != null and mi.mesh.get_surface_count() == 1:
			parts.append(mi)
	return parts


## Syarat penyatuan: satu induk, satu transform, satu format verteks, satu
## material, satu skin. Kalau salah satu meleset, menyambungnya akan mengubah
## tampilan karakter — dan itu justru yang harus dihindari.
func _parts_uniform(parts: Array) -> bool:
	var first: MeshInstance3D = parts[0]
	var parent := first.get_parent()
	var fmt: int = first.mesh.surface_get_format(0)
	var material: Material = first.mesh.surface_get_material(0)
	var ok := true
	for part in parts:
		var mi: MeshInstance3D = part
		if (
			mi.get_parent() != parent
			or not mi.transform.is_equal_approx(first.transform)
			or mi.mesh.surface_get_format(0) != fmt
			or mi.mesh.surface_get_material(0) != material
			or not _same_skin(mi.skin, first.skin)
		):
			ok = false
			break
	return ok


## Dua skin dianggap sama kalau jumlah, nama, dan bind pose tulangnya sama.
## Kalau tidak, indeks tulang di ARRAY_BONES menunjuk tulang yang berbeda dan
## karakternya akan terpelintir — lebih baik batal menyatukan.
func _same_skin(a: Skin, b: Skin) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	var ok := a.get_bind_count() == b.get_bind_count()
	var i := 0
	while ok and i < a.get_bind_count():
		if (
			a.get_bind_name(i) != b.get_bind_name(i)
			or a.get_bind_bone(i) != b.get_bind_bone(i)
			or not a.get_bind_pose(i).is_equal_approx(b.get_bind_pose(i))
		):
			ok = false
		i += 1
	return ok


## Menyambung array permukaan beberapa mesh menjadi satu ArrayMesh.
func _join_surfaces(parts: Array, fmt: int, material: Material) -> ArrayMesh:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	var offset := 0
	for part in parts:
		var mi: MeshInstance3D = part
		var src: Array = mi.mesh.surface_get_arrays(0)
		var count: int = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for slot in range(Mesh.ARRAY_MAX):
			if src[slot] == null:
				continue
			if slot == Mesh.ARRAY_INDEX:
				var shifted := PackedInt32Array()
				for index in src[slot] as PackedInt32Array:
					shifted.append(index + offset)
				if out[slot] == null:
					out[slot] = shifted
				else:
					out[slot] = (out[slot] as PackedInt32Array) + shifted
			elif out[slot] == null:
				out[slot] = src[slot]
			else:
				out[slot] = out[slot] + src[slot]
		offset += count
	if out[Mesh.ARRAY_VERTEX] == null or out[Mesh.ARRAY_INDEX] == null:
		return null

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, fmt)
	mesh.surface_set_material(0, material)
	return mesh


## Semua MeshInstance3D di bawah satu node, termasuk senjata.
func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_meshes(child))
	return out


func _age_corpses(delta: float) -> void:
	for i in range(_corpses.size()):
		if _corpse_life[i] <= 0.0:
			continue
		_corpse_life[i] = maxf(_corpse_life[i] - delta, 0.0)
		var corpse: Actor = _corpses[i]
		if _corpse_life[i] <= 0.0:
			corpse.root.visible = false
			continue
		_fly(corpse, i, delta)
		# Memudar di setengah detik terakhir, bukan hilang mendadak.
		var alpha := minf(_corpse_life[i] / CORPSE_FADE, 1.0)
		for mesh in corpse.meshes:
			(mesh as MeshInstance3D).transparency = 1.0 - alpha


## Satu langkah balistik untuk mayat yang sedang terlempar.
##
## Gravitasinya 26 dan bukan 9,8: pada skala karakter 2x dan kamera sependek
## ini, gravitasi sungguhan terbaca seperti rekaman lambat. Yang dicari
## adalah lemparan pendek dan keras yang mendarat dalam setengah detik.
func _fly(corpse: Actor, slot: int, delta: float) -> void:
	var velocity: Vector3 = _corpse_vel[slot]
	if velocity == Vector3.ZERO:
		return
	corpse.root.position += velocity * delta
	corpse.root.rotation.x += _corpse_spin[slot] * delta
	velocity.y -= 26.0 * delta
	if corpse.root.position.y <= 0.0:
		# Mendarat: berhenti total, tidak memantul. Mayat yang memantul
		# terbaca sebagai boneka karet.
		corpse.root.position.y = 0.0
		velocity = Vector3.ZERO
	_corpse_vel[slot] = velocity
