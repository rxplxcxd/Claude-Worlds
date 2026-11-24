// "X-ray hole" for objects standing in front of the player.
// Only the part of the sprite around the player becomes transparent.
// Per-object strength is passed through the modulate ALPHA:
//   modulate.a = 1.0 -> normal, 0.5 -> full cut-out (smoothly animated).
// One shared material for all occluders keeps draw-call batching intact.
shader_type canvas_item;

uniform vec2 player_pos;          // canvas (world) coordinates
uniform float radius = 40.0;      // world units
uniform float softness = 26.0;
uniform float min_alpha = 0.28;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float strength = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	vec2 d = (world_pos - player_pos) * vec2(1.0, 0.8);
	float hole = mix(min_alpha, 1.0, smoothstep(radius, radius + softness, length(d)));
	COLOR = vec4(tex.rgb * COLOR.rgb, tex.a * mix(1.0, hole, strength));
}
