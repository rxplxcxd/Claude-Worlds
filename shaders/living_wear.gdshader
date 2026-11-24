shader_type canvas_item;
// Living Assets – tier 1: wear without extra per-asset textures.
// Grows flat, hard-edged dirt patches (Penzilla cel look) from ONE shared,
// tileable field texture (assets/vfx/grime_field.png) by thresholding;
// more dirt near the base of the sprite. Outlines are never dirtied.
// docs/living_assets/TECHNICAL_INTEGRATION.md
//
// One material per quantised wear level is shared by all sprites at that
// level, so sprites keep batching (no per-instance uniforms needed).

uniform sampler2D grime_tex : filter_linear, repeat_enable;
uniform float dirt : hint_range(0.0, 1.0) = 0.0;      // 0 clean … 1 very dirty
uniform float fade : hint_range(0.0, 1.0) = 0.0;      // colour loss (sun, age)
uniform float darken : hint_range(0.0, 0.5) = 0.0;
uniform float grime_px = 180.0;                         // field period in texture pixels
uniform vec3 grime_color : source_color = vec3(0.30, 0.23, 0.17);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 p = UV * tex_size / grime_px;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float is_line = step(l, 0.17);
	float field = texture(grime_tex, p).r * 0.75 + UV.y * 0.45;
	float thr = 1.08 - dirt * 0.62;
	float w = fwidth(field) * 0.75;
	float patch = smoothstep(thr - w, thr + w, field) * (1.0 - is_line) * step(0.001, dirt);
	// darker rim at the patch edge (cel-shaded stain border)
	float rim = smoothstep(thr - w, thr, field) - smoothstep(thr + 0.012, thr + 0.012 + w, field);
	vec3 dirty = c.rgb * 0.70 + grime_color * 0.30;
	vec3 col = mix(c.rgb, dirty, patch);
	col = mix(col, dirty * 0.9, clamp(rim, 0.0, 1.0) * patch);
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), fade * (1.0 - is_line));
	col *= 1.0 - darken * (1.0 - is_line);
	COLOR = vec4(col, c.a) * COLOR;
}
