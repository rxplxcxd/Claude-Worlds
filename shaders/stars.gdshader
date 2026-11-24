shader_type spatial;
// Star backdrop on a large inverted sphere around the camera.
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 g = d * 420.0;
	vec3 cell = floor(g);
	float h = hash(cell);
	float r = length(fract(g) - 0.5);
	float star = step(0.993, h) * (0.35 + 0.65 * hash(cell + 3.1)) * smoothstep(0.42, 0.05, r);
	vec3 base = mix(vec3(0.02, 0.04, 0.09), vec3(0.05, 0.09, 0.17), d.y * 0.5 + 0.5);
	ALBEDO = base + vec3(star);
}
