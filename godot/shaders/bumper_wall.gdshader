shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Dinding pantul NEON.
//
// Di key art, dua slab magenta di kiri dan kanan adalah permukaan paling
// informatif di layar: di sanalah peluru memantul, dan di sanalah pemain
// membaca sudut. Karena itu dinding bukan batu redup lagi melainkan panel
// teknis yang menyala, dengan tiga lapis informasi:
//
//   panel      garis sambungan dan garis data kecil, memberi skala
//   rim        tepi atas menyala penuh — inilah yang terbaca dari kejauhan
//   hit pulse  titik benturan terakhir menyala dan meredup
//
// Hit pulse sengaja hidup di shader, bukan sebagai node efek terpisah.
// Pantulan terjadi hingga belasan kali per detik pada combo tinggi; satu
// node per benturan adalah alokasi per-frame yang dilarang docs/08. Empat
// slot melingkar sudah cukup: benturan kelima dalam 0,25 detik tidak pernah
// terbaca mata.

uniform vec3 panel_color : source_color = vec3(0.165, 0.106, 0.239);
uniform vec3 glow_color : source_color = vec3(1.0, 0.17, 0.84);
uniform vec3 core_color : source_color = vec3(1.0, 0.61, 0.93);
uniform vec3 fog_color : source_color = vec3(0.165, 0.075, 0.25);
uniform float arena_length = 40.0;
uniform float horizon_fade = 90.0;
uniform float rim_height = 1.4;
// Empat benturan terakhir: x = lane z, y = sisa umur 0..1.
uniform vec4 hit_z = vec4(0.0);
uniform vec4 hit_life = vec4(0.0);

varying vec3 world_pos;
varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float stripe(float coord, float spacing, float width) {
	float cell = abs(fract(coord / spacing - 0.5) - 0.5) * spacing;
	float aa = fwidth(coord) * 0.75 + 0.0001;
	return 1.0 - smoothstep(width, width + aa, cell);
}

void fragment() {
	float lane_z = -world_pos.z;
	float height = clamp(world_pos.y / max(rim_height, 0.001), 0.0, 1.0);

	// Panel besar tiap 4 unit, garis data tipis tiap 0,5 unit di bagian bawah.
	float seams = stripe(lane_z, 4.0, 0.05);
	float data = stripe(lane_z, 0.5, 0.012) * (1.0 - height) * 0.6;
	vec3 color = panel_color * (1.0 - seams * 0.5) + glow_color * data * 0.35;

	// Rim: pita menyala di sepertiga atas. Ini garis yang dipakai pemain
	// untuk memperkirakan sudut pantul, jadi ia yang paling terang.
	float rim = smoothstep(0.62, 1.0, height);
	color += glow_color * rim * 1.6;
	// Pendar vertikal lembut di bawah rim, supaya dinding membaca sebagai
	// sumber cahaya dan bukan sebagai stiker.
	color += glow_color * pow(height, 3.0) * 0.45;

	// Hit pulse: empat kernel gaussian sepanjang dinding.
	float pulse = 0.0;
	for (int i = 0; i < 4; i++) {
		float life = hit_life[i];
		if (life <= 0.0) {
			continue;
		}
		float d = abs(lane_z - hit_z[i]);
		// Lebar tumbuh seiring pudarnya umur: benturan menyebar, lalu padam.
		float spread = mix(0.6, 3.2, 1.0 - life);
		pulse += life * life * exp(-(d * d) / (spread * spread));
	}
	color += core_color * clamp(pulse, 0.0, 2.0) * 2.2;

	float beyond = clamp((lane_z - arena_length) / max(horizon_fade, 0.001), 0.0, 1.0);
	color = mix(color, fog_color, smoothstep(0.0, 1.0, beyond) * 0.85);

	ALBEDO = color;
}
