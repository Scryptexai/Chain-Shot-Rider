shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Latar: kota cyberpunk, kabut, dan vortex.
//
// Di key art, sepertiga atas layar bukan langit kosong — ada siluet menara,
// kabut ungu tebal, dan sebuah vortex di kanan atas. Tanpa itu lorong
// berakhir sebagai pita hitam dan seluruh komposisi kehilangan kedalaman.
//
// Digambar prosedural pada satu quad besar di belakang arena, bukan sebagai
// skybox cubemap: nol berkas tekstur, warnanya ikut palet varian, dan satu
// quad adalah satu draw call yang tidak pernah di-overdraw karena ia menolak
// menulis depth dan digambar paling awal.
//
// VORTEX ADALAH DEKORASI. Ia tidak menarik peluru dan tidak ada di simulasi
// (docs/17 §17.8). Gravity well yang sesungguhnya adalah rintangan kecil di
// lantai, dan memberi dua benda arti gameplay yang sama hanya membingungkan.

uniform vec3 fog_color : source_color = vec3(0.165, 0.075, 0.25);
uniform vec3 night_color : source_color = vec3(0.027, 0.039, 0.078);
uniform vec3 city_glow : source_color = vec3(0.17, 0.91, 1.0);
uniform vec3 vortex_color : source_color = vec3(0.42, 0.18, 0.66);
uniform vec2 vortex_center = vec2(0.72, 0.17);
uniform float vortex_radius = 0.13;
uniform float time_scale = 0.08;

varying vec2 uv;

void vertex() {
	uv = UV;
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

void fragment() {
	// Langit: kabut di bawah (tempat lorong larut) menuju malam di atas.
	float sky = smoothstep(0.0, 0.75, uv.y);
	vec3 color = mix(night_color, fog_color, sky);

	// Siluet kota. Menara dengan lebar acak berbenih tetap; yang penting
	// hanya garis atapnya, karena di key art badannya memang nyaris hitam.
	float column = floor(uv.x * 46.0);
	float tower_h = 0.10 + hash11(column) * 0.26;
	float horizon = 0.78;
	float is_tower = step(uv.y, horizon) * step(horizon - tower_h, uv.y);
	vec3 tower_body = night_color * 0.55;
	color = mix(color, tower_body, is_tower);

	// Jendela: titik kecil yang menyala di badan menara.
	float win_x = fract(uv.x * 46.0);
	float win_y = fract(uv.y * 150.0);
	float lit = step(0.55, hash11(column * 3.7 + floor(uv.y * 150.0)));
	float window = is_tower
		* step(0.25, win_x) * step(win_x, 0.75)
		* step(0.3, win_y) * step(win_y, 0.7) * lit;
	color += city_glow * window * 0.32;

	// Vortex: cincin berpilin. Dua lengan spiral yang berputar lambat.
	vec2 d = uv - vortex_center;
	d.x *= 0.62;  // quad jauh lebih tinggi daripada lebar dalam ruang UV
	float r = length(d);
	float a = atan(d.y, d.x);
	float spiral = sin(a * 2.0 + r * 48.0 - TIME * time_scale * 12.0) * 0.5 + 0.5;
	float disc = smoothstep(vortex_radius, vortex_radius * 0.25, r);
	float ring = smoothstep(vortex_radius * 1.15, vortex_radius * 0.92, r)
		* smoothstep(vortex_radius * 0.55, vortex_radius * 0.8, r);
	color = mix(color, night_color * 0.2, disc);
	color += vortex_color * (ring * (0.45 + spiral * 0.85) + disc * 0.15);

	// Kabut tebal di dasar langit: di sinilah ujung lantai harus menghilang,
	// jadi warnanya identik dengan horizon_fade di floor_grid.
	color = mix(color, fog_color, smoothstep(0.42, 0.0, uv.y));

	ALBEDO = color;
}
