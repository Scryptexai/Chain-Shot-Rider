class_name RenderPose
extends RefCounted

## Pose tick sebelumnya — milik renderer, bukan milik aturan main.
##
## Simulasi melangkah tepat 60 kali per detik; layar ponsel menggambar 90 atau
## 120 kali. Tanpa pose sebelumnya renderer hanya bisa memaku tiap entitas ke
## posisi tick terakhir, dan gerakan yang mulus di simulasi muncul di layar
## sebagai getaran — paling terasa pada musuh dekat, yang pikselnya paling
## besar.
##
## Disimpan di kelas terpisah supaya satu hal tetap jelas: tidak ada satu pun
## angka di sini yang boleh dibaca oleh aturan main. SimWorld hanya menulis ke
## sini; yang membaca cuma ArenaView. Karena itu nilai-nilai ini tidak masuk
## hash determinisme dan tidak mungkin mengubah hasil sebuah run.

var squad_x: float = 0.0
var boss_pos: Vector2 = Vector2.ZERO
var enemy_x := PackedFloat32Array()
var enemy_z := PackedFloat32Array()
var auto_x := PackedFloat32Array()
var auto_z := PackedFloat32Array()


func allocate(max_enemies: int, max_auto: int) -> void:
	enemy_x.resize(max_enemies)
	enemy_z.resize(max_enemies)
	auto_x.resize(max_auto)
	auto_z.resize(max_auto)


## Dipanggil di awal tick, sebelum satu pun entitas bergerak.
func capture(sim: Object) -> void:
	squad_x = sim.squad_x
	boss_pos = sim.boss_pos
	for i in range(sim.enemy_count):
		enemy_x[i] = sim.enemy_x[i]
		enemy_z[i] = sim.enemy_z[i]
	for i in range(sim.auto_count):
		auto_x[i] = sim.auto_x[i]
		auto_z[i] = sim.auto_z[i]


## Entitas baru tidak punya masa lalu: titik awalnya adalah dirinya sendiri.
## Tanpa ini ia meluncur masuk dari slot milik entitas yang mati sebelumnya.
func born_enemy(index: int, x: float, z: float) -> void:
	enemy_x[index] = x
	enemy_z[index] = z


func born_auto(index: int, x: float, z: float) -> void:
	auto_x[index] = x
	auto_z[index] = z


## Kembaran dari swap-remove di SimWorld. Kalau slotnya tidak ikut dipindahkan,
## entitas terakhir mewarisi titik awal milik yang baru saja mati dan renderer
## menariknya melintasi arena dalam satu frame.
func swap_enemy(index: int, last: int) -> void:
	enemy_x[index] = enemy_x[last]
	enemy_z[index] = enemy_z[last]


func swap_auto(index: int, last: int) -> void:
	auto_x[index] = auto_x[last]
	auto_z[index] = auto_z[last]
