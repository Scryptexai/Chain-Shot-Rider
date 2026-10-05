shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Zirah sci-fi pemain, dicat di atas rig apa pun.
//
// Masalah yang diselesaikan: key art memperlihatkan satu prajurit
// hard-surface biru-putih sebagai jangkar komposisi, sementara rig yang
// tersedia adalah ksatria fantasi bertekstur emas-cokelat. Mengganti modelnya
// butuh aset yang belum ada; mengganti CARA ia dicat tidak.
//
// Tiga keputusan, semuanya diturunkan dari gambar:
//
// 1. Nilai warna dibagi oleh arah normal, bukan oleh tekstur. Permukaan yang
//    menghadap ke atas menangkap cahaya ruangan dan menjadi steel terang;
//    permukaan yang menghadap ke bawah dan ke samping jatuh ke biru tua. Itu
//    menghasilkan pembacaan "pelat" tanpa satu pun peta tekstur, dan ia bekerja
//    pada mesh mana pun karena hanya membaca normal.
//
// 2. Rim fresnel cyan. Di gambar, siluet pemain dipisahkan dari lantai gelap
//    sepenuhnya oleh garis cahaya tepi — bukan oleh kontras albedo. Emissive
//    memastikan garis itu bertahan sekalipun pemain berdiri di bayangan.
//
// 3. Tekstur asli dibuang total, tidak dibaurkan. Emas KayKit yang tersisa
//    10% pun langsung terbaca sebagai fantasi dan merusak seluruh adegan.

uniform vec3 steel_color : source_color = vec3(0.86, 0.90, 0.95);
uniform vec3 deep_color : source_color = vec3(0.18, 0.36, 0.85);
uniform vec3 rim_color : source_color = vec3(0.17, 0.91, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 3.2;
uniform float rim_strength : hint_range(0.0, 6.0) = 2.4;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.34;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 0 di permukaan yang menghadap ke bawah, 1 di yang menghadap ke atas.
	float up = world_normal.y * 0.5 + 0.5;
	// Dua langkah, bukan gradien mulus: pelat harus punya tepi.
	float plate = smoothstep(0.42, 0.62, up);
	vec3 albedo = mix(deep_color, steel_color, plate);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);

	ALBEDO = albedo;
	METALLIC = metallic_amount;
	ROUGHNESS = mix(roughness_amount, roughness_amount * 0.4, plate);
	EMISSION = rim_color * fresnel * rim_strength;
}
