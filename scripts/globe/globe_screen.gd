class_name GlobeScreen
extends Node
## World map: the 3D globe plus its UI (docs/GEOGRAPHY_SYSTEM.md §3, §5).
##
## Modes:
##   "found"  – the player has no settlement yet (first launch). Choose a site,
##              see its rating, name the settlement, found it. No way back to
##              a settlement because none exists (empty planet rule).
##   "browse" – opened from the settlement (HUD "Karte"): explore the planet,
##              regions, territories; "Siedlung betreten" returns (zoom level
##              "lokal").
## The settlement scene is paused and hidden while the map is open; the map
## itself only holds aggregated data.

signal closed
signal found_requested(site: Dictionary, settlement_name: String)
## "Ansehen" on a world landmark (World Council development preview).
signal landmark_view_requested(landmark_id: String)

var mode := "browse"
var view: GlobeView
var labels: GlobeLabels
var selected_region := ""
var candidate: Dictionary = {} # rated site in found mode
var show_territories := true

var _layer: CanvasLayer
var _root: Control
var _title: Label
var _subtitle: Label
var _panel: PanelContainer
var _info: RichTextLabel
var _rating_box: VBoxContainer
var _name_edit: LineEdit
var _found_button: Button
var _enter_button: Button
var _visit_button: Button
var _selected_landmark := ""
var _suggest_button: Button
var _back_button: Button
var _loading: Label
var _territory_button: Button
## Founding on an "extreme" site needs an explicit confirmation.
var _extreme_ok: CheckBox


## Diagnostics for PerfMonitor.
func perf_stats() -> Dictionary:
	if view == null:
		return {"view": "Globus (lädt)"}
	var vis := 0
	for r in view.planet.regions:
		var c: Vector2 = r["center"]
		if view.project(c.x, c.y)["visible"]:
			vis += 1
	return {"view": "Globus · " + view.level, "visible_objects": vis, "total_objects": view.planet.regions.size(),
		"territories": WorldState.get_territories().size()}


func open(p_mode: String) -> void:
	mode = p_mode


func _ready() -> void:
	add_to_group("perf_view")
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_root = Control.new()
	_root.theme = UiTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	_loading = Label.new()
	_loading.text = "Karte von Aurel wird geladen …"
	_loading.add_theme_font_size_override("font_size", 22)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_root.add_child(_loading)
	# Let the loading text appear before the (blocking) planet load.
	await get_tree().process_frame
	await get_tree().process_frame
	var planet := Geography.planet()
	if planet == null:
		_loading.text = "Planetendaten fehlen."
		return
	view = GlobeView.new()
	view.name = "GlobeView"
	add_child(view)
	view.setup(planet)
	view.make_current()
	view.zoom_level_changed.connect(func(_l: String) -> void: _refresh_header())
	_loading.queue_free()
	_build_ui()
	_refresh_overlays()
	var own := WorldState.get_settlement_of(LocalProfile.player_id)
	if mode == "browse" and own.has("position"):
		view.focus(own["position"]["lat"], own["position"]["lon"], 1.9, true)
		select_point(own["position"]["lat"], own["position"]["lon"])
	else:
		view.focus(25.0, -20.0, 3.6, true)
	_refresh_header()
	_refresh_panel()
	get_viewport().size_changed.connect(_layout)
	_layout()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var gestures := GestureSurface.new()
	gestures.name = "GestureSurface"
	_root.add_child(gestures)
	gestures.tapped.connect(_on_tap)
	gestures.panned.connect(func(d: Vector2) -> void: view.rotate_by_screen(d))
	gestures.pinched.connect(func(f: float, _c: Vector2) -> void: view.zoom_by(f))

	labels = GlobeLabels.new()
	labels.view = view
	_root.add_child(labels)

	var head := PanelContainer.new()
	head.name = "Header"
	head.add_theme_stylebox_override("panel", UiTheme.panel_style())
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(head)
	head.position = Vector2(14, 14)
	var hb := VBoxContainer.new()
	head.add_child(hb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	hb.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(300, 0)
	hb.add_child(_subtitle)

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 8)
	_root.add_child(buttons)
	_back_button = _button("Zurück", "Zurück zur Siedlung", "ui.icon.close")
	_back_button.pressed.connect(func() -> void: closed.emit())
	_back_button.visible = mode == "browse"
	buttons.add_child(_back_button)
	var zin := _button("+", "Hineinzoomen")
	zin.pressed.connect(func() -> void: view.zoom_by(1.35))
	buttons.add_child(zin)
	var zout := _button("–", "Herauszoomen")
	zout.pressed.connect(func() -> void: view.zoom_by(1.0 / 1.35))
	buttons.add_child(zout)
	_territory_button = _button("Gebiete", "Territorien ein-/ausblenden")
	_territory_button.toggle_mode = true
	_territory_button.button_pressed = true
	_territory_button.toggled.connect(func(on: bool) -> void:
		show_territories = on
		_refresh_overlays())
	buttons.add_child(_territory_button)

	_panel = PanelContainer.new()
	_panel.name = "InfoPanel"
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG_SOLID))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_size_override("normal_font_size", 15)
	_info.add_theme_font_size_override("bold_font_size", 18)
	box.add_child(_info)
	_rating_box = VBoxContainer.new()
	_rating_box.add_theme_constant_override("separation", 4)
	box.add_child(_rating_box)
	# Actions stay visible at the bottom of the panel (never scrolled away).
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	outer.add_child(actions)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name der Siedlung (z. B. Lichtfeld)"
	_name_edit.max_length = 32
	_name_edit.custom_minimum_size = Vector2(0, 44)
	actions.add_child(_name_edit)
	_extreme_ok = CheckBox.new()
	_extreme_ok.text = "Ich will diesen extremen Standort trotzdem gründen."
	_extreme_ok.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extreme_ok.visible = false
	_extreme_ok.toggled.connect(func(_on: bool) -> void: _found_button.disabled = not candidate.get("valid", false) or not _extreme_ok.button_pressed)
	actions.add_child(_extreme_ok)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	actions.add_child(row)
	_suggest_button = _button("Vorschlag", "Zeigt nacheinander gut bewertete, verschiedene freie Orte")
	_suggest_button.pressed.connect(suggest_site)
	row.add_child(_suggest_button)
	_found_button = _button("Hier gründen", "Siedlung an diesem Ort gründen")
	_found_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_found_button.add_theme_stylebox_override("normal", UiTheme.accent_style(false))
	_found_button.add_theme_stylebox_override("hover", UiTheme.accent_style(false))
	_found_button.add_theme_stylebox_override("pressed", UiTheme.accent_style(true))
	_found_button.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	_found_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_DARK)
	_found_button.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.3))
	_found_button.pressed.connect(_on_found_pressed)
	row.add_child(_found_button)
	_enter_button = _button("Siedlung betreten", "Zur lokalen Ansicht deiner Siedlung")
	_enter_button.pressed.connect(func() -> void: closed.emit())
	actions.add_child(_enter_button)
	_visit_button = _button("Ansehen (Vorschau)", "Den Weltratssitz in der Entwicklungsvorschau besuchen")
	_visit_button.pressed.connect(func() -> void: landmark_view_requested.emit(_selected_landmark))
	_visit_button.visible = false
	actions.add_child(_visit_button)


func _button(text: String, tip: String, icon_key: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 48)
	b.add_theme_font_size_override("font_size", 22 if text.length() <= 2 else 16)
	var icon := AssetRegistry.get_texture(icon_key) if icon_key != "" else null
	if icon:
		b.icon = icon
		b.text = ""
		b.custom_minimum_size = Vector2(52, 52)
	return b


func _layout() -> void:
	if _panel == null:
		return
	var vp := _root.get_viewport_rect().size
	var landscape := vp.x > vp.y
	var buttons := _root.get_node("Buttons") as Control
	buttons.reset_size()
	if landscape:
		var w := minf(340.0, vp.x * 0.38)
		_panel.position = Vector2(vp.x - w - 12, 12)
		_panel.size = Vector2(w, vp.y - 24)
		buttons.position = Vector2(vp.x - w - 24 - buttons.size.x, 12)
		view.screen_shift = Vector2(-(w + 12.0) * 0.5, 0.0)
	else:
		var h := vp.y * 0.42
		_panel.position = Vector2(10, vp.y - h - 10)
		_panel.size = Vector2(vp.x - 20, h)
		buttons.position = Vector2(vp.x - buttons.size.x - 12, 120)
		view.screen_shift = Vector2(0.0, -(h + 10.0) * 0.5 + 50.0)
	view._apply_camera()
	_subtitle.custom_minimum_size.x = minf(320.0, vp.x - 40.0) if not landscape else 300.0


func _refresh_header() -> void:
	if _title == null:
		return
	var lvl := view.level.capitalize()
	_title.text = "%s · %s" % [view.planet.name, lvl]
	if mode == "found":
		_subtitle.text = "Wähle den Ort deiner Siedlung: Tippe auf das Land. Rote Flächen = Sperrzone (unter 20 km zu einem fremden Gebiet). Ziehen dreht, zwei Finger zoomen."
	else:
		_subtitle.text = {"planetar": "Kontinente und Siedlungen", "kontinental": "Regionen, Gebiete und Siedlungen", "regional": "Regionen im Detail – tippe für Informationen"}.get(view.level, "")


func _refresh_overlays() -> void:
	view.update_overlays(selected_region)
	# Founding mode always shows the exclusion zones (where founding is not
	# allowed); when browsing, "Gebiete" toggles territories and zones.
	view.set_territories(WorldState.get_territories(), show_territories, mode == "found" or show_territories)
	var markers: Array = []
	for s in WorldState.get_settlements():
		if s.has("position"):
			markers.append({"lat": s["position"]["lat"], "lon": s["position"]["lon"], "name": s.get("name", ""), "own": (s.get("resident_player_ids", []) as Array).has(LocalProfile.player_id)})
	labels.settlements = markers
	var lms: Array = []
	for d in Landmarks.all():
		lms.append({"landmark_id": d["landmark_id"], "lat": d["position"]["lat"], "lon": d["position"]["lon"], "name": d["name"], "subtitle": d["subtitle"], "reserve_km": sqrt(Landmarks.property_area_m2(d["landmark_id"]) / PI) / 1000.0})
	labels.landmarks = lms
	labels.candidate = {"lat": candidate["sample"]["lat"], "lon": candidate["sample"]["lon"]} if not candidate.is_empty() else {}
	labels.candidate_valid = candidate.get("valid", true)


# --- interaction -------------------------------------------------------------

func _on_tap(pos: Vector2) -> void:
	var lm_id := labels.landmark_at(pos)
	if lm_id != "":
		select_landmark(lm_id)
		return
	var ll := view.pick(pos)
	if is_nan(ll.x):
		return
	select_point(ll.x, ll.y)


## Selects the region at a point; in found mode the point becomes the
## candidate site and is rated.
func select_point(lat: float, lon: float) -> void:
	var p := view.planet
	var region := p.region_at(lat, lon)
	selected_region = region.get("region_id", "")
	if mode == "found":
		candidate = Geography.rate_site(lat, lon, WorldState.get_settlements(), WorldState.get_territories())
	_refresh_overlays()
	_refresh_panel(lat, lon)


## Shows a world landmark (World Council): its point is selected like any
## other (rating in found mode says "Schutzgebiet"), the panel describes it.
func select_landmark(landmark_id: String) -> void:
	var d := Landmarks.get_def(landmark_id)
	if d.is_empty():
		return
	var ll := Landmarks.position_of(landmark_id)
	select_point(ll.x, ll.y)
	var st := WorldState.landmark_state(landmark_id)
	var stage_label := ""
	for sg in d.get("stages", []):
		if int(sg["stage"]) == int(st.get("stage", 1)):
			stage_label = sg["label"]
	var t := "[b][color=#e0b64a]%s[/color][/b]\n[color=#b9b4a8]%s · Sitz des %ss[/color]\n[i]%s[/i]\n\n" % [d["name"], d["subtitle"], Landmarks.institution_ui_name(), d.get("tagline", {}).get("de", "")]
	t += Landmarks.describe(landmark_id, int(Time.get_unix_time_from_system())).split("\n", false, 1)[1] + "\n"
	t += "Zustand: Stufe %d – %s\n" % [int(st.get("stage", 1)), stage_label]
	t += "Neutrales Gelände: %d × %d m (Grundstücksgrenze) – keine Nation besitzt es, Gewalt ist dort verboten.\n" % [int(sqrt(Landmarks.property_area_m2(landmark_id, st))), int(sqrt(Landmarks.property_area_m2(landmark_id, st)))]
	t += "Position: %s\n" % Geo.format(ll.x, ll.y)
	t += "Klima: warm-gemäßigt, Ø %d °C · Meer ca. %d km im Südwesten\n" % [int(d["site_choice"]["temperature_c"]), int(d["site_choice"]["coast_km"])]
	t += "\n[color=#9a958a]Entwicklungsstand: Reisen dorthin (Phase 8), Restaurierung und Innenräume (Phase 7) und das %s (Phase 10) folgen in späteren Phasen.[/color]" % Landmarks.assembly_official_name()
	if mode == "found":
		_info.text = t + "\n\n" + _info.text
	else:
		_info.text = t
		_selected_landmark = landmark_id
		_visit_button.visible = true


var _suggestions: Array = []
var _suggest_index := -1


## Each press shows the next good site (different places, best first; after
## the last one it starts again). Any other point can still be tapped.
func suggest_site() -> void:
	if _suggestions.is_empty():
		_suggestions = Geography.good_sites(WorldState.get_settlements(), WorldState.get_territories())
	if _suggestions.is_empty():
		return
	_suggest_index = (_suggest_index + 1) % _suggestions.size()
	var s: Dictionary = _suggestions[_suggest_index]["sample"]
	view.focus(s["lat"], s["lon"], 1.75)
	select_point(s["lat"], s["lon"])
	if _suggest_button:
		_suggest_button.text = "Vorschlag %d/%d" % [_suggest_index + 1, _suggestions.size()]


func _on_found_pressed() -> void:
	if candidate.is_empty() or not candidate.get("valid", false):
		return
	var label := _name_edit.text.strip_edges()
	found_requested.emit(candidate, label)


func _refresh_panel(lat: float = NAN, lon: float = NAN) -> void:
	if _info == null:
		return
	for c in _rating_box.get_children():
		c.queue_free()
	var found := mode == "found"
	_name_edit.visible = found
	_extreme_ok.visible = false
	_found_button.visible = found
	_suggest_button.visible = found
	_enter_button.visible = false
	_visit_button.visible = false
	_selected_landmark = ""
	var p := view.planet
	var region := p.region(selected_region) if selected_region != "" else {}
	var t := ""
	if region.is_empty():
		if is_nan(lat):
			t = "[b]%s[/b]\n%d Kontinente · %d Regionen · Radius %d km\n\n" % [p.name, p.continents.size(), p.regions.size(), int(p.radius_km)]
			t += "Der Planet ist unberührte Natur. Siedlungen entstehen nur, wenn Menschen sie gründen."
			if found:
				t += "\n\n[color=#f2c230]Du bist die erste Person auf %s.[/color] Wähle einen Ort an Land – oder lass dir einen guten Ort vorschlagen." % p.name if WorldState.is_planet_empty() else ""
		else:
			t = "[b]Meer[/b]\n%s\n\nHier kann keine Siedlung entstehen." % Geo.format(lat, lon)
		_info.text = t
		_found_button.disabled = true
		return
	var cont := p.continent(region.get("continent_id", ""))
	var in_region: Array = WorldState.settlements_in_region(selected_region)
	var climate: Dictionary = region["climate"]
	t = "[b]%s[/b]\n" % region["name"]
	t += "[color=#b9b4a8]%s · %s[/color]\n\n" % [cont.get("name", "Insel"), PlanetData.TERRAIN_LABELS.get(region["terrain"], region["terrain"])]
	t += "Fläche: %s km²\n" % _thousands(int(region["area_km2"]))
	t += "Höhe: Ø %d m\n" % int(region["elevation_m"])
	t += "Klima: %s, Ø %.0f °C, %s\n" % [climate["zone"], climate["temperature_c"], _rain_label(climate["rainfall"])]
	t += "Wasser: %s\n" % PlanetData.WATER_LABELS.get(region["water_access"], "–")
	var res: Array = []
	for r in region["resources"]:
		res.append("%s (%s)" % [PlanetData.RESOURCE_LABELS.get(r["type"], r["type"]), _amount(r["abundance"])])
	t += "Rohstoffe: %s\n" % (", ".join(res) if not res.is_empty() else "kaum")
	t += "Erschließung: %s\n" % PlanetData.DEVELOPMENT_LABELS.get(_development(region), "Wildnis")
	var names: Array = in_region.map(func(st): return "[color=#f2c230]%s[/color]" % st.get("name", "?"))
	t += "Siedlungen hier: %s\n" % (", ".join(names) if not names.is_empty() else "noch keine – die Region ist frei besiedelbar")
	if not is_nan(lat):
		t += "Position: %s\n" % Geo.format(lat, lon)
	_info.text = t
	var own := WorldState.get_settlement_of(LocalProfile.player_id)
	_enter_button.visible = mode == "browse" and not own.is_empty() and own.get("region_id", "") == selected_region
	if found:
		_show_rating()


func _show_rating() -> void:
	var valid: bool = candidate.get("valid", false)
	var head := Label.new()
	head.text = "Standortbewertung: %d / 100" % int(candidate.get("score", 0)) if valid else "Hier ist keine Gründung möglich"
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", UiTheme.ACCENT if valid else Color("ff8a80"))
	_rating_box.add_child(head)
	var gap: float = candidate.get("nearest_border_km", INF)
	var gap_l := Label.new()
	gap_l.text = "Abstand zur nächsten Gebietsgrenze: %s" % ("keine Siedlung in der Nähe" if gap == INF else "%s km (%s)" % [("%.1f" % gap).replace(".", ","), candidate.get("nearest_name", "")])
	gap_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gap_l.add_theme_font_size_override("font_size", 14)
	_rating_box.add_child(gap_l)
	var diff: Dictionary = candidate.get("difficulty", {})
	if not diff.is_empty():
		var dl := Label.new()
		dl.text = "Schwierigkeit: %s (%s)" % [diff["label"], diff["class"]]
		dl.add_theme_font_size_override("font_size", 16)
		dl.add_theme_color_override("font_color", [Color("9be38a"), Color("f2c230"), Color("ffa25c"), Color("ff6b5e")][int(diff["index"])])
		_rating_box.add_child(dl)
		for req in diff.get("requirements", []):
			var rl := Label.new()
			rl.text = "• " + str(req)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.add_theme_font_size_override("font_size", 13)
			_rating_box.add_child(rl)
		if int(diff["index"]) >= 2:
			var note := Label.new()
			note.text = "Hinweis: Diese Anforderungen werden erst mit Wirtschaft und Technologie (spätere Phasen) spielwirksam. Heute startet jede Siedlung mit dem Grundpaket."
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_font_size_override("font_size", 12)
			note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
			_rating_box.add_child(note)
	for reason in candidate.get("reasons", []):
		var l := Label.new()
		l.text = "• " + str(reason)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 14)
		_rating_box.add_child(l)
	var names := {"water": "Wasser", "climate": "Klima", "soil": "Boden", "resources": "Rohstoffe", "terrain": "Gelände", "neighbours": "Nachbarschaft"}
	var factors: Dictionary = candidate.get("factors", {})
	for k in names.keys():
		if not factors.has(k):
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = names[k]
		l.custom_minimum_size = Vector2(118, 0)
		l.add_theme_font_size_override("font_size", 14)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = float(factors[k]) * 100.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		bg.set_corner_radius_all(7)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.ACCENT.lerp(Color("e5534b"), clampf(1.0 - float(factors[k]) * 1.6, 0.0, 1.0))
		fill.set_corner_radius_all(7)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_rating_box.add_child(row)
	_extreme_ok.visible = valid and int(diff.get("index", 0)) == 3
	if not _extreme_ok.visible:
		_extreme_ok.button_pressed = false
	_found_button.disabled = not valid or (_extreme_ok.visible and not _extreme_ok.button_pressed)


func _development(region: Dictionary) -> String:
	for s in WorldState.get_settlements():
		if s.get("region_id", "") == region["region_id"]:
			return "settled"
	return region.get("development", "wild")


static func _amount(a: float) -> String:
	if a >= 0.75:
		return "sehr viel"
	if a >= 0.5:
		return "viel"
	if a >= 0.3:
		return "mittel"
	return "wenig"


static func _rain_label(r: float) -> String:
	if r < 0.3:
		return "sehr trocken"
	if r < 0.45:
		return "trocken"
	if r < 0.65:
		return "ausgeglichen"
	return "feucht"


static func _thousands(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
