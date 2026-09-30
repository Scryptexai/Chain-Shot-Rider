shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Neon floor grid for the arena, per docs/02-visual-style-guide.md.
//
// Drawn in a shader rather than as a texture for three reasons that matter on
// a Snapdragon 660: it costs no VRAM, it stays sharp at any camera distance
// instead of turning to mush in the far half of the arena, and the colour is
// driven by the variant palette at runtime so one material serves all five
// arenas.
//
// Unshaded on purpose. The floor is a backdrop; letting the directional light
// touch it flattens the contrast the neon elements rely on.

uniform vec3 bg_top : source_color = vec3(0.04, 0.06, 0.19);
uniform vec3 bg_bottom : source_color = vec3(0.01, 0.02, 0.06);
uniform vec3 grid_color : source_color = vec3(0.12, 0.83, 0.91);
uniform float grid_spacing = 2.0;
uniform float line_width = 0.035;
uniform float grid_alpha = 0.18;
uniform float arena_length = 40.0;
uniform float defense_line_z = 5.0;
uniform vec3 defense_color : source_color = vec3(0.0, 0.9, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	vec3 base = mix(bg_bottom, bg_top, depth);

	float lines = max(
		grid_line(world_pos.x, grid_spacing, line_width),
		grid_line(world_pos.z, grid_spacing, line_width)
	);

	// Grid fades with distance so the spawn zone reads as depth, not as a
	// wall of lines competing with the crowd for attention.
	float falloff = 1.0 - depth * 0.55;
	vec3 color = mix(base, grid_color, lines * grid_alpha * falloff);

	// The defense line is the one piece of floor the player must never lose
	// track of, so it is drawn brighter than any grid line and never fades.
	float defense = grid_line(world_pos.z + defense_line_z, 1000.0, 0.06);
	color = mix(color, defense_color, defense * 0.85);

	ALBEDO = color;
}
