shader_type canvas_item;
// Clothing colour from the unified palette (data/character_catalog.json
// palettes.cloth). The Penzilla "Blank" layers are white with purple-grey
// shading and a dark contour. Instead of multiplying (which tinted every
// colour violet and made "black" dark purple) the colour is taken from the
// palette and only the BRIGHTNESS of the blank layer is kept as shading;
// the contour stays Penzilla's.
uniform vec3 target = vec3(1.0);

void fragment() {
	vec4 b = texture(TEXTURE, UV);
	float l = (b.r + b.g + b.b) / 3.0;
	vec3 col;
	if (l < 0.24) {
		col = b.rgb;                                   // contour
	} else {
		float t = clamp((l - 0.24) / 0.76, 0.0, 1.0);  // 0 = deepest fold, 1 = lit
		float shade = mix(0.52, 1.0, t);
		col = target * shade;
		// dark colours: a faint lift in the lit areas keeps folds readable
		float v = max(target.r, max(target.g, target.b));
		col += vec3(0.07) * (1.0 - smoothstep(0.0, 0.35, v)) * smoothstep(0.85, 1.0, t);
	}
	COLOR = vec4(col, b.a) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
