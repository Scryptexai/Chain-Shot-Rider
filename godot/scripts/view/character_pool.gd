class_name CharacterPool
extends Node3D
## Kolam karakter ber-tulang, dipinjam per frame.
##
## Satu-satunya tempat di proyek Godot yang tahu cara memasang GLB ber-rig,
## memutar klipnya, dan mendaur ulang nodenya. ArenaView hanya meminta "beri
## aku seorang grunt di sini, sedang berlari" dan tidak perlu tahu apa pun
## tentang Skeleton3D, AnimationPlayer, atau BoneAttachment3D.
##
## Kenapa kolam, bukan instantiate per musuh: satu GLB ber-skin berarti satu
## Skeleton3D, satu AnimationPlayer, dan pose yang dihitung ulang tiap frame.
## Pada gelombang 200 musuh itu ratusan skeleton — anggaran frame ponsel habis
## hanya untuk tulang yang lebarnya dua piksel di layar. Jadi hanya sejumlah
## kecil unit TERDEKAT yang mendapat tubuh ber-tulang; sisanya tetap digambar
## ArenaView lewat MultiMesh seperti sebelumnya. Batasnya sama persis dengan
## versi web (js/render3d.js), supaya kedua target terlihat sama.
##
## Pemakaian per frame:
##     pool.begin()
##     var actor := pool.take("grunt")
##     actor.place(x, z, facing)   ; actor.play("run")
##     pool.end(delta)

## Anggaran LOD — kembar dari SKIN di js/render3d.js.
const BUDGET := {"troops": 10, "enemies": 16, "corpses": 8}

## Tinggi manusia 0,96 unit di lorong selebar 20 unit itu benar secara skala,
## tapi di layar ponsel jadi dua puluhan piksel. Semua unit dibesarkan dengan
## faktor yang sama — termasuk MultiMesh di ArenaView — supaya tidak ada
## lompatan ukuran saat unit berpindah antara jalur ber-tulang dan jalur
## statis. Simulasi tidak ikut diubah: radius tabrakan tetap apa adanya.
const CHAR_SCALE := 2.0

## Berapa lama mayat tergeletak sebelum memudar, dan lama memudarnya.
const CORPSE_SECONDS := 1.5
const CORPSE_FADE := 0.5

const MODEL_DIR := "res://assets/models/rigged/%s.glb"

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
	var mesh: MeshInstance3D
	var current := ""
	## Sisa detik sebelum klip sesaat boleh diganti klip lain.
	var lock := 0.0
	## Fase dan kecepatan sendiri-sendiri. Tanpa ini tiga puluh musuh
	## melangkah seperti satu tubuh dan pasukan terlihat baris-berbaris.
	var phase := 0.0
	var rate := 1.0

	func _init(
		unit: String,
		node: Node3D,
		player: AnimationPlayer,
		socket: Node3D,
		skin: MeshInstance3D
	) -> void:
		kind = unit
		root = node
		anim = player
		muzzle = socket
		mesh = skin
		phase = randf()
		rate = 0.92 + randf() * 0.16

	## Menaruh aktor di koordinat simulasi (x, z). Dunia memetakan z ke -z.
	func place(x: float, z: float, facing: float) -> void:
		root.position = Vector3(x, 0.0, -z)
		root.rotation.y = facing

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


var _scenes: Dictionary = {}
var _pools: Dictionary = {}
var _used: Dictionary = {}
var _corpses: Array = []
var _corpse_life := PackedFloat32Array()
var _loaded := 0


## Memuat GLB yang disebut namanya. Dipanggil sekali sebelum run pertama:
## memuat saat musuh pertama muncul berarti hitch tepat di detik paling ramai.
func warm(kinds: Array) -> int:
	for entry in kinds:
		var kind := String(entry)
		if _scenes.has(kind):
			continue
		var packed := load(MODEL_DIR % kind)
		if packed == null:
			push_warning("CharacterPool: model %s tidak ada, memakai MultiMesh" % kind)
			continue
		_scenes[kind] = packed
		_loaded += 1
	return _loaded


func loaded_count() -> int:
	return _loaded


func has_kind(kind: String) -> bool:
	return _scenes.has(kind)


## Menandai awal frame: semua aktor dianggap bebas sampai ada yang meminjam.
func begin() -> void:
	for kind in _used:
		_used[kind] = 0


## Meminjam satu aktor. null berarti model tidak ada — pemanggil harus punya
## jalur cadangan (MultiMesh), karena karakter hilang lebih buruk daripada
## karakter sederhana.
func take(kind: String) -> Actor:
	if not _scenes.has(kind):
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
func drop_corpse(kind: String, x: float, z: float) -> void:
	if not _scenes.has(kind):
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
	_corpse_life[slot] = CORPSE_SECONDS


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
	var packed: PackedScene = _scenes.get(kind)
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	root.scale = Vector3.ONE * CHAR_SCALE
	var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if player == null:
		root.queue_free()
		return null
	_prepare_clips(player)
	var socket := _attach_muzzle(root)
	add_child(root)
	return Actor.new(kind, root, player, socket, _find_mesh(root))


## glTF tidak menyimpan "klip ini berulang", jadi importer Godot menandai
## semuanya sekali-jalan. Tanpa perbaikan ini musuh melangkah satu langkah
## lalu membeku di udara.
func _prepare_clips(player: AnimationPlayer) -> void:
	for name in player.get_animation_list():
		var clip := player.get_animation(name)
		if clip == null:
			continue
		if name in ONCE_CLIPS:
			clip.loop_mode = Animation.LOOP_NONE
		else:
			clip.loop_mode = Animation.LOOP_LINEAR


## Soket moncong diekspor sebagai tulang bernama "muzzle", jadi di Godot ia
## diambil lewat BoneAttachment3D, bukan dicari sebagai node biasa.
func _attach_muzzle(root: Node3D) -> Node3D:
	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		return null
	var bone := skeleton.find_bone("muzzle")
	if bone < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "MuzzleSocket"
	attachment.bone_name = "muzzle"
	attachment.bone_idx = bone
	skeleton.add_child(attachment)
	return attachment


## Mesh ber-skin dicari sekali saat tubuh dibuat, bukan tiap frame: pencarian
## node dengan pola sama mahalnya dengan menggambar unitnya.
func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _age_corpses(delta: float) -> void:
	for i in range(_corpses.size()):
		if _corpse_life[i] <= 0.0:
			continue
		_corpse_life[i] = maxf(_corpse_life[i] - delta, 0.0)
		var corpse: Actor = _corpses[i]
		if _corpse_life[i] <= 0.0:
			corpse.root.visible = false
			continue
		# Memudar di setengah detik terakhir, bukan hilang mendadak.
		var alpha := minf(_corpse_life[i] / CORPSE_FADE, 1.0)
		if corpse.mesh != null:
			corpse.mesh.transparency = 1.0 - alpha
