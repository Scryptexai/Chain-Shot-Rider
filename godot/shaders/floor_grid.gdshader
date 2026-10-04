shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

// Tanah arena: lempeng batu berlumut, bukan kisi neon.
//
// Sejak arah visual bergeser ke fantasi, lantai neon adalah satu-satunya
// permukaan terbesar di layar yang masih berteriak "sci-fi". Versi web
// menggambar lempeng batu berlumut ke sebuah canvas 256² (`makeGridTexture`
// di js/render3d.js); shader ini meniru gambar yang sama secara prosedural
// supaya kedua target terlihat sama tanpa satu pun berkas tekstur ikut build.
//
// Tetap shader, bukan tekstur, karena tiga alasan yang berarti di Snapdragon
// 660: tidak makan VRAM, tetap tajam di ujung jauh lorong alih-alih jadi
// bubur, dan warnanya diambil dari palet varian saat runtime sehingga satu
// material melayani kelima arena.
//
// Unshaded on purpose. The floor is a backdrop; letting the directional light
// touch it flattens the contrast the neon elements rely on.
//
// Kabut engine juga dimatikan khusus untuk lantai. Kabut MENERANGKAN apa pun
// yang jauh, jadi ujung lantai justru menjadi pita terang yang berhenti
// mendadak di depan langit gelap — persis garis potong yang ingin
// disembunyikan. Lantai memudar lewat horizon_fade di bawah, ke warna latar
// yang sama persis; kabut tetap hidup untuk musuh dan rintangan, di mana
// efeknya memang membantu membaca jarak.

uniform vec3 bg_top : source_color = vec3(0.04, 0.06, 0.19);
uniform vec3 bg_bottom : source_color = vec3(0.01, 0.02, 0.06);
uniform vec3 grid_color : source_color = vec3(0.43, 0.48, 0.37);
// Dua warna tanah: dekat pemain lebih hangat dan terang, ujung jauh meredup
// ke lumut gelap. Sama persis dengan PAL.floor / PAL.floorFar di web.
uniform vec3 ground_near : source_color = vec3(0.17, 0.20, 0.14);
uniform vec3 ground_far : source_color = vec3(0.086, 0.106, 0.075);
uniform float grid_spacing = 2.0;
// Nat antar lempeng: lebih tebal dan jauh lebih redup daripada garis neon
// lama. Ia hanya perlu memberi tahu mata bahwa tanah ini berpetak.
uniform float line_width = 0.05;
uniform float grid_alpha = 0.22;
// Bercak lumut/tanah. Di web ini 90 elips acak berbenih tetap; di sini ia
// noise nilai dua oktaf, yang memberi kesan sama dengan biaya tetap.
uniform float patch_scale = 1.15;
uniform float patch_strength = 0.17;
uniform float arena_length = 40.0;
uniform float defense_line_z = 5.0;
uniform vec3 defense_color : source_color = vec3(0.0, 0.9, 1.0);
// Panjang lebur di balik gerbang spawn. Lantai diteruskan jauh melewati arena
// supaya ujungnya tidak terbaca sebagai garis potong di sepertiga atas layar;
// bagian itu harus luruh ke warna latar, bukan berhenti mendadak.
uniform float horizon_fade = 90.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Acak berbenih tetap per sel, padanan rnd() di makeGridTexture: bentuknya
// tidak pernah berubah antar frame maupun antar build, jadi tanahnya tidak
// berkedip saat kamera bergerak.
float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Noise nilai dengan interpolasi halus — bercak lumut, bukan kotak-kotak.
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
	float depth = clamp(-world_pos.z / arena_length, 0.0, 1.0);
	vec3 base = mix(ground_near, ground_far, depth);

	// Bercak: dua oktaf, yang kedua separuh skala supaya tepinya tidak terlalu
	// rapi. Dipusatkan di nol agar sebagian bercak menggelapkan dan sebagian
	// menerangkan, seperti elips terang/gelap di versi canvas.
	float blotch = value_noise(world_pos.xz * patch_scale) * 0.65
		+ value_noise(world_pos.xz * patch_scale * 2.7) * 0.35;
	base += (blotch - 0.5) * 2.0 * patch_strength * base;

	float lines = max(
		grid_line(world_pos.x, grid_spacing, line_width),
		grid_line(world_pos.z, grid_spacing, line_width)
	);

	// Nat memudar dengan jarak supaya zona spawn terbaca sebagai kedalaman,
	// bukan sebagai dinding garis yang berebut perhatian dengan kerumunan.
	float falloff = 1.0 - depth * 0.55;
	vec3 color = mix(base, grid_color, lines * grid_alpha * falloff);

	// The defense line is the one piece of floor the player must never lose
	// track of, so it is drawn brighter than any grid line and never fades.
	float defense = grid_line(world_pos.z + defense_line_z, 1000.0, 0.06);
	color = mix(color, defense_color, defense * 0.85);

	float beyond = clamp((-world_pos.z - arena_length) / max(horizon_fade, 0.001), 0.0, 1.0);
	color = mix(color, bg_bottom, smoothstep(0.0, 1.0, beyond));

	ALBEDO = color;
}
