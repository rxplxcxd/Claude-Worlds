shader_type spatial;
// Planet surface. Displays the baked planet (scripts/geography/planet_textures.gd);
// it does NOT classify terrain itself (single source of truth = PlanetData).
// Coordinates: unit sphere, y = north (see scripts/geography/geo.gd).
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D color_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_enable;
uniform sampler2D id_tex : filter_nearest, repeat_enable;
uniform sampler2D lut_tex : filter_nearest;
uniform vec2 tex_size = vec2(512.0, 256.0);
uniform float lut_width = 160.0;
uniform float border_strength : hint_range(0.0, 1.0) = 0.0;
uniform float territory_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 territory_color : source_color = vec3(1.0, 0.72, 0.2);
uniform vec3 highlight_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 light_dir_view = vec3(-0.45, 0.55, 0.7);
// Paket 2.1: territories are 1 × 1 km squares (not regions). Up to 32 nearest
// are passed per frame: centre (unit vector) and east axis + half size (km).
uniform int terr_count = 0;
uniform vec4 terr_c[32];
uniform vec4 terr_e[32];
uniform float radius_km = 4000.0;
uniform float zone_km = 20.5; // founding gap + half the new start square
uniform float zone_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 zone_color : source_color = vec3(0.9, 0.22, 0.2);

varying vec3 obj_pos;

const float SEA = 0.5019608; // 128/255

void vertex() {
	obj_pos = VERTEX;
}

vec2 uv_of(vec3 n) {
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(-n.z, n.x);
	return vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
}

float region_at(vec2 uv) {
	vec4 id = texture(id_tex, uv);
	return floor(id.r * 255.0 + 0.5) + floor(id.g * 255.0 + 0.5) * 256.0;
}

// Cheap 3D value noise: breaks up the 50-km cell grid of the colour texture.
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 lut(float region) {
	return texture(lut_tex, vec2((region + 0.5) / lut_width, 0.5)).rgb;
}

void fragment() {
	vec3 n = normalize(obj_pos);
	vec2 uv = uv_of(n);
	float e = texture(height_tex, uv).r;
	float aa = max(fwidth(e) * 1.3, 0.002);
	float land = smoothstep(SEA - aa, SEA + aa, e);

	// Water: shallow near the coast, deep further out.
	float depth = clamp((SEA - e) / SEA, 0.0, 1.0);
	vec3 water = mix(vec3(0.27, 0.56, 0.76), vec3(0.11, 0.28, 0.47), smoothstep(0.0, 0.55, depth));
	// Colour lookup slightly warped by noise (display only; coastline,
	// borders and picking use the exact data).
	vec2 warp = (vec2(vnoise(n * 160.0), vnoise(n * 160.0 + 17.3)) - 0.5) * (1.6 / tex_size);
	vec3 land_col = texture(color_tex, uv + warp).rgb;
	land_col *= 0.94 + 0.12 * vnoise(n * 900.0);
	vec3 col = mix(water, land_col, land);

	// Coastline outline (dark, like the Penzilla sprites' outlines).
	float coast = 1.0 - smoothstep(0.0, aa * 1.6, abs(e - SEA));
	col = mix(col, vec3(0.12, 0.16, 0.2), coast * 0.55);

	// Regions: borders + territories + highlight (only on land). Borders are
	// thin lines (constant screen width) along the cell edges, not whole cells.
	float r = region_at(uv);
	if (r > 0.5 && land > 0.5) {
		vec2 px = 1.0 / tex_size;
		vec2 tc = uv * tex_size;
		vec2 f = fract(tc);
		vec2 lw = clamp(fwidth(tc) * 1.6, vec2(0.02), vec2(0.45)); // line width in texels
		float rr = region_at(uv + vec2(px.x, 0.0));
		float rl = region_at(uv - vec2(px.x, 0.0));
		float rd = region_at(uv + vec2(0.0, px.y));
		float ru = region_at(uv - vec2(0.0, px.y));
		// 1 where this pixel lies within the line width of a differing side.
		float e_r = (rr != r && rr > 0.5) ? 1.0 - smoothstep(lw.x * 0.5, lw.x, 1.0 - f.x) : 0.0;
		float e_l = (rl != r && rl > 0.5) ? 1.0 - smoothstep(lw.x * 0.5, lw.x, f.x) : 0.0;
		float e_d = (rd != r && rd > 0.5) ? 1.0 - smoothstep(lw.y * 0.5, lw.y, 1.0 - f.y) : 0.0;
		float e_u = (ru != r && ru > 0.5) ? 1.0 - smoothstep(lw.y * 0.5, lw.y, f.y) : 0.0;
		float edge = max(max(e_r, e_l), max(e_d, e_u));
		vec3 info = lut(r);
		if (info.g > 0.5) {
			col = mix(col, highlight_color, 0.18);
			col = mix(col, highlight_color, edge);
		} else {
			col = mix(col, vec3(0.15, 0.13, 0.1), edge * 0.5 * border_strength);
		}
	}

	// Territories (gold square) and founding exclusion zones (red, 20 km
	// around every territory border). Exact local distance to each square:
	// azimuthal frame at the territory centre; atan(|c×n|, c·n) keeps the
	// angle precise in single precision (acos would not).
	if (terr_count > 0) {
		float min_d = 5000.0; // km; "far away" (finite, so derivatives stay sane)
		for (int i = 0; i < 32; i++) {
			if (i >= terr_count) {
				break;
			}
			vec3 c = terr_c[i].xyz;
			float cd = dot(n, c);
			if (cd < 0.98) {
				continue;
			}
			vec3 e = terr_e[i].xyz;
			vec3 no = cross(c, e);
			vec3 cr = cross(c, n);
			float ang = atan(length(cr), cd);
			vec3 proj = n - c * cd;
			float pl = length(proj);
			vec2 xy = pl > 1e-9 ? vec2(dot(proj, e), dot(proj, no)) / pl * ang * radius_km : vec2(0.0);
			vec2 q = abs(xy) - vec2(terr_e[i].w);
			float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
			min_d = min(min_d, d);
		}
		// Line/edge width = about one pixel in km; clamped so the jump at the
		// distance cut-off (cd < 0.98) never produces a visible ring.
		float w = clamp(fwidth(min_d), 0.001, 25.0);
		if (zone_strength > 0.0 && min_d < zone_km + w) {
			float inside = 1.0 - smoothstep(zone_km - w, zone_km + w, min_d);
			col = mix(col, zone_color, 0.28 * inside * zone_strength);
			float line = 1.0 - smoothstep(0.0, w * 1.5, abs(min_d - zone_km));
			col = mix(col, zone_color * 0.8, line * 0.9 * zone_strength);
		}
		if (territory_strength > 0.0) {
			float fill = 1.0 - smoothstep(-w, w, min_d);
			col = mix(col, territory_color, 0.6 * fill * territory_strength);
			float edge = 1.0 - smoothstep(0.0, w * 1.5, abs(min_d));
			col = mix(col, territory_color * 0.7, edge * territory_strength);
		}
	}

	// Soft light from the upper left, never fully dark (map readability).
	float lambert = max(dot(normalize(NORMAL), normalize(light_dir_view)), 0.0);
	col *= 0.62 + 0.48 * lambert;
	// Atmospheric rim.
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	col = mix(col, vec3(0.55, 0.78, 1.0), rim * 0.55);
	ALBEDO = col;
}
