shader_type spatial;
// Glow around the globe (slightly larger sphere, additive).
render_mode unshaded, blend_add, cull_front, depth_draw_never;

uniform vec3 glow_color : source_color = vec3(0.45, 0.7, 1.0);

void fragment() {
	// cull_front: we see the inside of the shell; the rim is where the
	// shell's normal is perpendicular to the view direction.
	float d = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.5) * smoothstep(0.0, 0.35, d);
	ALBEDO = glow_color * a * 0.9;
}
