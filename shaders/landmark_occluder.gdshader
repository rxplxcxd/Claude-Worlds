shader_type canvas_item;
// Overlay copy of a landmark tile: keeps only the pixels that lie IN FRONT
// of the figure (per-pixel footprint depth x + y from the depth texture,
// docs/WORLD_COUNCIL_ART_DIRECTION.md §6). Ground-level pixels never cover.
// Ghosting: inside the ghost ellipses (around the figure, around a door the
// figure is at) these front parts are drawn only faintly, so the figure,
// the entrance and the floor it stands on stay readable.
uniform sampler2D depth_tex : filter_nearest;
uniform float figure_key = 0.0;   // (x + y + 200) * 100 of the figure's feet
uniform float tolerance = 40.0;   // 0.4 m: figures may stand close to walls
uniform bool occluder_mode = true; // false: a plain (door patch) layer, ghosted only
uniform vec2 ghost_a_center = vec2(0.0);
uniform vec2 ghost_a_radius = vec2(0.0);
uniform vec2 ghost_b_center = vec2(0.0);
uniform vec2 ghost_b_radius = vec2(0.0);
uniform float ghost_alpha = 0.14;
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float ghost(vec2 c, vec2 r) {
	if (r.x <= 0.0) {
		return 1.0;
	}
	float d = length((world - c) / r);
	return mix(ghost_alpha, 1.0, smoothstep(0.72, 1.0, d));
}

void fragment() {
	if (occluder_mode) {
		vec4 d = texture(depth_tex, UV);
		float key = floor(d.r * 255.0 + 0.5) * 256.0 + floor(d.g * 255.0 + 0.5);
		bool ground = floor(d.b * 255.0 + 0.5) >= 127.5;   // B: 128 = ground, + water code
		if (d.a < 0.5 || ground || key <= figure_key + tolerance) {
			discard;
		}
	}
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= min(ghost(ghost_a_center, ghost_a_radius), ghost(ghost_b_center, ghost_b_radius));
}
