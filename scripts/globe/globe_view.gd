class_name GlobeView
extends Node3D
## 3D globe of the planet (docs/GEOGRAPHY_SYSTEM.md §3).
##
## Fixed unit sphere at the origin, orbit camera around it. Only aggregated
## data is shown (terrain texture, region borders, territories, settlement
## markers) – never settlement scenes, buildings or NPC nodes.
## Zoom levels follow the camera altitude: planetar → kontinental → regional;
## "lokal" is the settlement scene itself (entered from the UI).

signal zoom_level_changed(level: String)

const LEVELS := ["planetar", "kontinental", "regional"]
const MIN_DIST := 1.18
const MAX_DIST := 4.2
const LEVEL_LIMITS := [2.35, 1.6] # altitude thresholds (distance) planetar/kontinental
const FOV := 38.0

var planet: PlanetData
var camera: Camera3D
var distance := 3.2
## Camera position as latitude/longitude (degrees).
var view_lat := 20.0
var view_lon := 0.0
var level := "planetar"
var highlight_region := ""
## Screen-space shift of the globe centre (pixels), so it is centred in the
## area not covered by the info panel.
var screen_shift := Vector2.ZERO

var _material: ShaderMaterial
var _lut_tex: ImageTexture
var _target_dist := 3.2
var _target_lat := 20.0
var _target_lon := 0.0


func setup(p: PlanetData) -> void:
	planet = p
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var globe := MeshInstance3D.new()
	globe.name = "Globe"
	globe.mesh = sphere
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/globe.gdshader")
	_material.set_shader_parameter("color_tex", ImageTexture.create_from_image(PlanetTextures.color_image(p)))
	_material.set_shader_parameter("height_tex", ImageTexture.create_from_image(PlanetTextures.height_image(p)))
	_material.set_shader_parameter("id_tex", ImageTexture.create_from_image(PlanetTextures.id_image(p)))
	_material.set_shader_parameter("tex_size", Vector2(p.width, p.height))
	globe.material_override = _material
	add_child(globe)

	var halo := MeshInstance3D.new()
	halo.name = "Atmosphere"
	var hs := SphereMesh.new()
	hs.radius = 1.07
	hs.height = 2.14
	hs.radial_segments = 64
	hs.rings = 32
	halo.mesh = hs
	var hm := ShaderMaterial.new()
	hm.shader = preload("res://shaders/atmosphere.gdshader")
	halo.material_override = hm
	add_child(halo)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FOV
	camera.near = 0.02
	camera.far = 200.0
	add_child(camera)

	var stars := MeshInstance3D.new()
	stars.name = "Stars"
	var ss := SphereMesh.new()
	ss.radius = 90.0
	ss.height = 180.0
	ss.radial_segments = 32
	ss.rings = 16
	stars.mesh = ss
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/stars.gdshader")
	stars.material_override = sm
	add_child(stars)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.04, 0.09)
	add_child(env)
	update_overlays({}, "")
	_apply_camera()


## Territories / highlight changed → rebuild the per-region lookup row.
func update_overlays(claimed_regions: Dictionary, highlight: String) -> void:
	highlight_region = highlight
	var img := PlanetTextures.region_lut(planet, claimed_regions, highlight)
	if _lut_tex == null:
		_lut_tex = ImageTexture.create_from_image(img)
	else:
		_lut_tex.update(img)
	_material.set_shader_parameter("lut_tex", _lut_tex)
	_material.set_shader_parameter("lut_width", float(img.get_width()))


func make_current() -> void:
	camera.make_current()


## Smoothly turns the globe so (lat, lon) faces the camera.
func focus(lat: float, lon: float, dist: float = -1.0, instant: bool = false) -> void:
	_target_lat = clampf(lat, -80.0, 80.0)
	_target_lon = lon
	if dist > 0.0:
		_target_dist = clampf(dist, MIN_DIST, MAX_DIST)
	if instant:
		view_lat = _target_lat
		view_lon = _target_lon
		distance = _target_dist
		_apply_camera()


## Drag in screen pixels → rotate (slower when close to the surface).
func rotate_by_screen(delta: Vector2) -> void:
	var h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var k := (distance - 1.0) * 95.0 / h
	_target_lon = _target_lon - delta.x * k
	_target_lat = clampf(_target_lat + delta.y * k, -80.0, 80.0)
	view_lon = _target_lon
	view_lat = _target_lat
	_apply_camera()


## factor > 1 = zoom in.
func zoom_by(factor: float) -> void:
	_target_dist = clampf(1.0 + (_target_dist - 1.0) / factor, MIN_DIST, MAX_DIST)


func _process(delta: float) -> void:
	var t := clampf(delta * 8.0, 0.0, 1.0)
	var moved := absf(distance - _target_dist) > 0.0005 or absf(view_lat - _target_lat) > 0.01 or absf(angle_difference(deg_to_rad(view_lon), deg_to_rad(_target_lon))) > 0.0002
	if moved:
		distance = lerpf(distance, _target_dist, t)
		view_lat = lerpf(view_lat, _target_lat, t)
		view_lon = rad_to_deg(lerp_angle(deg_to_rad(view_lon), deg_to_rad(_target_lon), t))
		_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	camera.position = Geo.to_vec3(view_lat, view_lon) * distance
	camera.look_at(Vector3.ZERO, Vector3.UP)
	# Shift the picture in screen space (frustum offset, no parallax) so the
	# globe centre sits in the area not covered by the info panel.
	# In portrait the field of view is fixed horizontally, so the whole
	# globe fits the narrow screen.
	var vp := get_viewport().get_visible_rect().size
	var portrait := vp.y > vp.x
	var ref := maxf(vp.x if portrait else vp.y, 1.0)
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	camera.size = 2.0 * camera.near * tan(deg_to_rad(camera.fov * 0.5))
	camera.frustum_offset = Vector2(-screen_shift.x, screen_shift.y) * camera.size / ref
	# Region borders fade in when zooming in.
	_material.set_shader_parameter("border_strength", clampf((2.6 - distance) / 0.9, 0.0, 1.0))
	var new_level: String = LEVELS[0]
	if distance < LEVEL_LIMITS[1]:
		new_level = LEVELS[2]
	elif distance < LEVEL_LIMITS[0]:
		new_level = LEVELS[1]
	if new_level != level:
		level = new_level
		zoom_level_changed.emit(level)


## Screen position → Vector2(lat, lon), or Vector2(NAN, NAN) when it misses.
func pick(screen_pos: Vector2) -> Vector2:
	# Ray from the camera's own projection matrix (includes the frustum
	# offset), so picking always matches what is drawn.
	var vp := get_viewport().get_visible_rect().size
	var ndc := Vector2(screen_pos.x / vp.x * 2.0 - 1.0, 1.0 - screen_pos.y / vp.y * 2.0)
	var inv := camera.get_camera_projection().inverse()
	var a := inv * Vector4(ndc.x, ndc.y, -1.0, 1.0)
	var b4 := inv * Vector4(ndc.x, ndc.y, 1.0, 1.0)
	var o := camera.global_transform * (Vector3(a.x, a.y, a.z) / a.w)
	var d := (camera.global_transform * (Vector3(b4.x, b4.y, b4.z) / b4.w) - o).normalized()
	# Ray / unit sphere intersection (nearest hit).
	var b := o.dot(d)
	var c := o.dot(o) - 1.0
	var disc := b * b - c
	if disc < 0.0:
		return Vector2(NAN, NAN)
	var t := -b - sqrt(disc)
	if t < 0.0:
		return Vector2(NAN, NAN)
	return Geo.from_vec3(o + d * t)


## Screen position of a world point via the camera's projection matrix.
func to_screen(p: Vector3) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var v := camera.global_transform.affine_inverse() * p
	var c := camera.get_camera_projection() * Vector4(v.x, v.y, v.z, 1.0)
	if absf(c.w) < 0.00001:
		return Vector2(-9999, -9999)
	return Vector2((c.x / c.w * 0.5 + 0.5) * vp.x, (0.5 - c.y / c.w * 0.5) * vp.y)


## Screen position of a surface point, and whether it faces the camera.
func project(lat: float, lon: float, lift: float = 0.0) -> Dictionary:
	var p := Geo.to_vec3(lat, lon) * (1.0 + lift)
	var to_cam := (camera.global_position - p).normalized()
	var facing := p.normalized().dot(to_cam)
	return {"pos": to_screen(p), "visible": facing > 0.12 and not camera.is_position_behind(p), "facing": facing}


## Approximate screen pixels per km at the screen centre (for label sizes).
func pixels_per_km() -> float:
	var h := get_viewport().get_visible_rect().size.y
	var visible_height := 2.0 * (distance - 1.0) * tan(deg_to_rad(FOV * 0.5))
	return h / maxf(visible_height * planet.radius_km, 1.0)
