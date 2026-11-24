class_name PlanetTextures
extends RefCounted
## Builds the globe textures from PlanetData (single source of truth: the
## shader only displays, it does not classify terrain).
##   color  – RGB8: biome colours with hill shading and rivers
##   height – L8: elevation, sea level at 128 (smooth coastlines in the shader)
##   ids    – RGB8, nearest filtered: region index (R low byte, G high byte),
##            B = 255 for river cells
## Colours follow the flat, saturated Penzilla look of the settlement view.

const COLORS := {
	PlanetData.Biome.OCEAN: Color("2f6f9e"),
	PlanetData.Biome.LAKE: Color("4f9fcf"),
	PlanetData.Biome.ICE: Color("e9f2f5"),
	PlanetData.Biome.TUNDRA: Color("a7b28f"),
	PlanetData.Biome.MOUNTAIN: Color("8d8070"),
	PlanetData.Biome.HILLS: Color("93a85a"),
	PlanetData.Biome.DESERT: Color("e2c37c"),
	PlanetData.Biome.FOREST: Color("4a8a3e"),
	PlanetData.Biome.PLAIN: Color("a9c454"),
}
const DEEP_SEA := Color("1f4f7a")
const RIVER := Color("4f9fcf")
const SNOW := Color("f4f6f7")


static func color_image(p: PlanetData) -> Image:
	var img := Image.create(p.width, p.height, false, Image.FORMAT_RGB8)
	for y in p.height:
		for x in p.width:
			var i := y * p.width + x
			var b := p.biome[i]
			var c: Color = COLORS[b]
			var e := p.elevation_m[i]
			if b == PlanetData.Biome.OCEAN:
				c = c.lerp(DEEP_SEA, clampf(-e / 4000.0, 0.0, 1.0))
			elif b != PlanetData.Biome.LAKE:
				if e > 3300.0:
					c = c.lerp(SNOW, clampf((e - 3300.0) / 700.0, 0.0, 0.9))
				if p.river[i] == 1:
					c = RIVER
				else:
					# Hill shading, light from the north-west.
					var nw := p.elevation_m[p.index(x - 1, maxi(y - 1, 0))]
					var se := p.elevation_m[p.index(x + 1, mini(y + 1, p.height - 1))]
					var shade := clampf((maxf(nw, 0.0) - maxf(se, 0.0)) / 1400.0, -0.25, 0.25)
					c = c.lightened(shade) if shade > 0.0 else c.darkened(-shade)
			img.set_pixel(x, y, c)
	return img


static func height_image(p: PlanetData) -> Image:
	var img := Image.create(p.width, p.height, false, Image.FORMAT_L8)
	for i in p.elevation_m.size():
		var e := p.elevation_m[i]
		var v := 128.0 + (e / 4800.0 * 127.0 if e >= 0.0 else e / 5200.0 * 128.0)
		# Lakes sit below "sea level" so the shader draws their shores.
		if p.biome[i] == PlanetData.Biome.LAKE:
			v = minf(v, 120.0)
		elif p.biome[i] != PlanetData.Biome.OCEAN:
			v = maxf(v, 131.0)
		img.set_pixel(i % p.width, i / p.width, Color(v / 255.0, 0, 0))
	return img


static func id_image(p: PlanetData) -> Image:
	var img := Image.create(p.width, p.height, false, Image.FORMAT_RGB8)
	for i in p.region_of.size():
		var r := p.region_of[i]
		img.set_pixel(i % p.width, i / p.width, Color8(r & 255, r >> 8, 255 if p.river[i] == 1 else 0))
	return img


## Per-region lookup row: R = territory (1 = claimed), G = highlight,
## B = development (0 wild … 1 urban). Updated when territories change.
static func region_lut(p: PlanetData, claimed: Dictionary, highlight: String) -> Image:
	var img := Image.create(maxi(p.regions.size() + 1, 1), 1, false, Image.FORMAT_RGB8)
	for k in p.regions.size():
		var rid: String = p.regions[k]["region_id"]
		var dev := 0.0
		match p.regions[k].get("development", "wild"):
			"sparse": dev = 0.33
			"settled": dev = 0.66
			"urban": dev = 1.0
		img.set_pixel(k + 1, 0, Color(1.0 if claimed.has(rid) else 0.0, 1.0 if rid == highlight else 0.0, dev))
	return img
