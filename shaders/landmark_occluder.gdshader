shader_type canvas_item;
// Overlay copy of a landmark tile: keeps only the pixels that lie IN FRONT
// of the figure (per-pixel footprint depth x + y from the depth texture,
// docs/WORLD_COUNCIL_ART_DIRECTION.md §6). Ground-level pixels never cover.
uniform sampler2D depth_tex : filter_nearest;
uniform float figure_key = 0.0;   // (x + y + 200) * 100 of the figure's feet
uniform float tolerance = 40.0;   // 0.4 m: figures may stand close to walls

void fragment() {
	vec4 d = texture(depth_tex, UV);
	float key = floor(d.r * 255.0 + 0.5) * 256.0 + floor(d.g * 255.0 + 0.5);
	if (d.a < 0.5 || d.b > 0.5 || key <= figure_key + tolerance) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
