shader_type canvas_item;
// Living water on the baked landmark tiles (docs/WORLD_COUNCIL_ART_DIRECTION.md §6):
// the depth tile's blue channel marks water pixels (code 1 = surface, 2 = falling).
// Surfaces get drifting ripple highlights and a slow shimmer, falling water gets
// streaks running down. Everything else is drawn unchanged.
uniform sampler2D depth_tex : filter_nearest;
uniform vec2 tile_origin = vec2(0.0);   // world px of the tile's top-left corner
uniform vec2 tile_size = vec2(512.0);   // world px covered by the tile
uniform float speed = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float flags = floor(texture(depth_tex, UV).b * 255.0 + 0.5);
	float code = mod(flags, 128.0);
	if (code > 0.5 && c.a > 0.5) {
		vec2 w = tile_origin + UV * tile_size;
		float t = TIME * speed;
		if (code < 1.5) {
			// ground-plane coordinates of the isometric view (metres-ish)
			vec2 g = vec2(w.x / 53.0 + w.y / 30.2, w.y / 30.2 - w.x / 53.0);
			float r = sin(g.x * 2.7 + t * 1.3) * sin(g.y * 2.1 - t * 0.9) + 0.55 * sin((g.x - g.y) * 4.3 + t * 2.1);
			float hl = smoothstep(1.05, 1.32, r);
			c.rgb = mix(c.rgb, vec3(0.80, 0.94, 0.98), hl * 0.75);
			float shimmer = 0.5 + 0.5 * sin(g.x * 0.9 - g.y * 0.7 + t * 0.7);
			c.rgb *= 0.95 + 0.07 * shimmer;
		} else {
			float s = fract(w.y / 11.0 - t * 1.9 + sin(w.x * 0.31) * 0.35);
			c.rgb = mix(c.rgb, vec3(0.88, 0.97, 1.0), smoothstep(0.62, 0.92, s) * 0.8);
		}
	}
	COLOR = c;
}
