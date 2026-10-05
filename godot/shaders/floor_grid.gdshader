shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

// Lantai NEON: pelat logam basah dengan kisi cahaya.
//
// Basis: key art "Neon Bullet-Hell Combo Assault" (docs/17 §17.4 E). Yang
// harus terbaca dari gambar itu ada empat hal, dan semuanya ada di sini:
//
//   1. pelat besar, bukan kisi seragam — lantai punya skala
//   2. garis kisi cyan yang MENEBAL di dekat pemain dan meredup ke horizon
//   3. permukaan basah: pantulan pita neon dinding merembes ke lantai
//   4. ujung lorong larut ke kabut, tidak berhenti sebagai garis potong
//
// Tetap shader prosedural, bukan tekstur. Alasannya tidak berubah sejak versi
// batu: nol VRAM, tetap tajam di ujung lorong alih-alih jadi bubur, dan
// warnanya datang dari palet varian saat runtime sehingga satu material
// melayani kelima arena.
//
// Unshaded on purpose. The floor is a backdrop; letting the directional light
// touch it flattens the contrast the neon elements rely on.
//
// Kabut engine dimatikan khusus untuk lantai. Kabut MENERANGKAN apa pun yang
// jauh, jadi ujung lantai justru menjadi pita terang yang berhenti mendadak
// di depan langit gelap — persis garis potong yang ingin disembunyikan.
// Lantai memudar lewat horizon_fade ke warna kabut; kabut engine tetap hidup
// untuk musuh dan rintangan, di mana efeknya memang membantu membaca jarak.

uniform vec3 bg_top : source_color = vec3(0.07, 0.10, 0.22);
uniform vec3 bg_bottom : source_color = vec3(0.027, 0.039, 0.078);
// Warna kisi. Ini warna "milik pemain" di key art, jadi satu-satunya cyan
// besar di layar. Dipakai hemat: lihat grid_alpha.
uniform vec3 grid_color : source_color = vec3(0.17, 0.91, 1.0);
// Dua warna pelat: dekat pemain sedikit lebih terang, ujung jauh tenggelam.
uniform vec3 ground_near : source_color = vec3(0.055, 0.075, 0.125);
uniform vec3 ground_far : source_color = vec3(0.024, 0.031, 0.055);
// Pantulan dinding bumper yang merembes ke lantai basah.
uniform vec3 wall_glow : source_color = vec3(1.0, 0.17, 0.84);
uniform vec3 fog_color : source_color = vec3(0.165, 0.075, 0.25);
uniform float grid_spacing = 2.0;
uniform float line_width = 0.035;
uniform float grid_alpha = 0.85;
// Pelat besar: sambungan setiap plate_size unit, jauh lebih redup daripada
// kisi. Inilah yang memberi lantai skala — tanpa ini kisi 2 unit terbaca
// sebagai kertas milimeter.
uniform float plate_size = 8.0;
uniform float plate_alpha = 0.35;
// Basah: kekuatan pantulan dinding dan goresan vertikal di permukaan.
uniform float wetness = 0.55;
uniform float arena_half_width = 6.0;
uniform float patch_scale = 0.6;
uniform float patch_strength = 0.22;
uniform float arena_length = 40.0;
uniform float defense_line_z = 5.0;
uniform vec3 defense_color : source_color = vec3(1.0, 0.16, 0.16);
// Dinaikkan HUD saat combo tinggi: lantai ikut memanas. 0 = diam.
uniform float combo_heat = 0.0;
uniform float horizon_fade = 90.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Acak berbenih tetap per sel: bentuknya tidak pernah berubah antar frame
// maupun antar build, jadi lantainya tidak berkedip saat kamera bergerak.
float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Distance to the nearest grid line, in world units, anti-aliased by the
// screen-space derivative so distant lines fade instead of aliasing.
float grid_line(float coord, float spacing, float width) {
	float cell = abs(fract(coord / spacing - 0.5) - 0.5) * spacing;
	float aa = fwidth(coord) * 0.75 + 0.0001;
	return 1.0 - smoothstep(width, width + aa, cell);
}

void fragment() {
	// Simulation z runs away from the player; world z is negative there.
	float lane_z = -world_pos.z;
	float depth = clamp(lane_z / arena_length, 0.0, 1.0);
	vec3 base = mix(ground_near, ground_far, depth);

	// Kotoran pelat: dua oktaf, yang kedua separuh skala supaya tepinya tidak
	// terlalu rapi. Dipusatkan di nol agar sebagian menggelapkan dan sebagian
	// menerangkan.
	float blotch = value_noise(world_pos.xz * patch_scale) * 0.65
		+ value_noise(world_pos.xz * patch_scale * 2.7) * 0.35;
	base += (blotch - 0.5) * 2.0 * patch_strength * base;

	// Sambungan pelat besar: gelap, bukan menyala. Ia bagian dari logam.
	float plates = max(
		grid_line(world_pos.x, plate_size, 0.07),
		grid_line(world_pos.z, plate_size, 0.07)
	);
	base *= 1.0 - plates * plate_alpha;

	// Kisi cahaya. Dua hal terjadi bersamaan dan keduanya disengaja: garis
	// MENEBAL di dekat pemain (near_boost) dan MEREDUP ke kejauhan (falloff).
	// Itu yang membuat zona pemain terbaca sebagai lantai dan zona spawn
	// terbaca sebagai kedalaman, bukan sebagai dinding garis yang berebut
	// perhatian dengan kerumunan.
	float near_boost = mix(1.9, 1.0, clamp(lane_z / 14.0, 0.0, 1.0));
	float lines = max(
		grid_line(world_pos.x, grid_spacing, line_width * near_boost),
		grid_line(world_pos.z, grid_spacing, line_width * near_boost)
	);
	float falloff = pow(1.0 - depth, 1.6);
	float heat = 1.0 + combo_heat * 0.8;
	vec3 color = base + grid_color * lines * grid_alpha * falloff * heat;

	// Permukaan basah. Pantulan dinding bumper dimodelkan sebagai dua pita
	// yang menguat ke arah tepi lorong — bukan SSR, karena target terendah
	// proyek ini adalah ponsel kelas Snapdragon 660 dan pantulan sungguhan
	// berharga lebih mahal daripada seluruh sisa frame ini.
	float edge = clamp((abs(world_pos.x) - arena_half_width * 0.45)
		/ max(arena_half_width * 0.55, 0.001), 0.0, 1.0);
	// Goresan memanjang: pantulan di lantai basah selalu tertarik searah
	// pandangan, tidak pernah berbentuk cakram.
	float streak = value_noise(vec2(world_pos.x * 3.0, world_pos.z * 0.12));
	float reflection = edge * edge * wetness * (0.55 + streak * 0.75) * (1.0 - depth * 0.6);
	color += wall_glow * reflection;

	// Garis pertahanan adalah satu-satunya potongan lantai yang tidak boleh
	// hilang dari perhatian pemain, jadi ia digambar lebih terang daripada
	// garis kisi mana pun dan tidak pernah memudar.
	float defense = grid_line(world_pos.z + defense_line_z, 1000.0, 0.08);
	color = mix(color, defense_color, defense * 0.9);

	float beyond = clamp((lane_z - arena_length) / max(horizon_fade, 0.001), 0.0, 1.0);
	color = mix(color, fog_color, smoothstep(0.0, 1.0, beyond));

	ALBEDO = color;
}
