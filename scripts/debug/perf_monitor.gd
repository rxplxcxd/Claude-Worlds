extends Node
## Autoload "PerfMonitor": diagnostic performance overlay (Paket 2.1).
##
## Purely diagnostic – changes nothing about rendering. Shows live values and
## can run a timed measurement whose summary can be photographed on the
## iPhone (docs/PERFORMANCE.md §7). Open with F3, via the menu
## ("Leistungsanzeige") or with "?perf=1" in the URL; "?perf=1&perfauto=8"
## starts a measurement automatically after 8 s (used by tools/perf_measure.js).
##
## Values (all from the engine, nothing estimated):
##   FPS, frame time (avg / p95 / max), CPU time of the main loop (process +
##   physics), draw calls, primitives, objects drawn (3D) and visible world
##   objects (counted by the active view), node count, video/texture memory,
##   static memory, GPU/CPU render time where the platform supports timer
##   queries (WebGL usually not → "n/v"), render resolution and pixel ratio.

const MEASURE_SECONDS := 20.0

var overlay_visible := false
var measuring := false
var last_report: Dictionary = {}

var _layer: CanvasLayer
var _panel: PanelContainer
var _label: Label
var _button: Button
var _frames: PackedFloat32Array = PackedFloat32Array()
var _samples: Array = []
var _measure_left := 0.0
var _update_t := 0.0
var _auto_after := -1.0
var _measure_gpu := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(8, 8)
	_layer.add_child(_panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_label)
	_button = Button.new()
	_button.text = "Messung starten (%d s)" % int(MEASURE_SECONDS)
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(0, 40)
	_button.pressed.connect(start_measurement)
	v.add_child(_button)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_measure_gpu = true
	overlay_visible = bool(LocalProfile.get_setting("show_debug", false))
	_read_url()
	_apply_visible()


func _read_url() -> void:
	if not OS.has_feature("web"):
		return
	var q := str(JavaScriptBridge.eval("location.search", true))
	if q.contains("perf=1"):
		overlay_visible = true
	var m := q.find("perfauto=")
	if m >= 0:
		_auto_after = float(q.substr(m + 9).split("&")[0])


func set_overlay_visible(on: bool) -> void:
	overlay_visible = on
	_apply_visible()


func toggle() -> void:
	set_overlay_visible(not overlay_visible)


func _apply_visible() -> void:
	if _panel:
		_panel.visible = overlay_visible


func start_measurement() -> void:
	measuring = true
	_measure_left = MEASURE_SECONDS
	_samples.clear()
	_button.disabled = true


func _process(delta: float) -> void:
	_frames.append(delta)
	if _frames.size() > 120:
		_frames = _frames.slice(_frames.size() - 120)
	if _auto_after > 0.0:
		_auto_after -= delta
		if _auto_after <= 0.0:
			_auto_after = -1.0
			start_measurement()
	if measuring:
		_samples.append(_sample(delta))
		_measure_left -= delta
		if _measure_left <= 0.0:
			_finish_measurement()
	if not overlay_visible:
		return
	_update_t -= delta
	if _update_t > 0.0:
		return
	_update_t = 0.25
	_label.text = _live_text()
	_button.text = ("Messung läuft … %d s" % int(ceil(_measure_left))) if measuring else "Messung starten (%d s)" % int(MEASURE_SECONDS)


## One sample of all raw values for the current frame.
func _sample(delta: float) -> Dictionary:
	var view := _view_stats()
	return {
		"dt": delta,
		"cpu_process": Performance.get_monitor(Performance.TIME_PROCESS),
		"cpu_physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_3d": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"visible_objects": view.get("visible_objects", -1),
		"gpu_ms": _gpu_ms(),
		"render_cpu_ms": _render_cpu_ms(),
	}


func _gpu_ms() -> float:
	if not _measure_gpu:
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func _render_cpu_ms() -> float:
	if not _measure_gpu:
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())


## Stats from the active view (SettlementScene / GlobeScreen) via group.
func _view_stats() -> Dictionary:
	var nodes := get_tree().get_nodes_in_group("perf_view")
	for n in nodes:
		if n.is_inside_tree() and n.has_method("perf_stats") and (n as Node).can_process():
			return n.perf_stats()
	return {"view": "–"}


func _live_text() -> String:
	var avg := 0.0
	var worst := 0.0
	for f in _frames:
		avg += f
		worst = maxf(worst, f)
	avg /= maxf(_frames.size(), 1)
	var view := _view_stats()
	var gpu := _gpu_ms()
	var lines := PackedStringArray()
	lines.append("%s · FPS %d · Frame %.1f ms (max %.1f)" % [view.get("view", "–"), Engine.get_frames_per_second(), avg * 1000.0, worst * 1000.0])
	lines.append("CPU: Prozess %.1f ms · Physik %.1f ms · Rendern %s" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		("%.1f ms" % _render_cpu_ms()) if _render_cpu_ms() > 0.0 else "n/v"])
	lines.append("GPU: %s" % (("%.1f ms" % gpu) if gpu > 0.0 else "n/v (Plattform liefert keine GPU-Zeit)"))
	lines.append("Draw Calls %d · Primitive %d · Objekte sichtbar %s / gesamt %s · Knoten %d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		str(view.get("visible_objects", "–")), str(view.get("total_objects", "–")),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	lines.append("Speicher: Video %s · Texturen %s · statisch %s" % [
		_mb(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		_mb(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		_mb(Performance.get_monitor(Performance.MEMORY_STATIC))])
	lines.append("Auflösung %s · Pixeldichte %s" % [str(get_window().size), _dpr()])
	if not last_report.is_empty():
		lines.append("— Letzte Messung (%s, %d s): Ø %.1f FPS · 1%%-Tief %.1f · Ø %.1f ms · p95 %.1f ms · Draw Calls Ø %d" % [
			last_report["view"], int(last_report["seconds"]), last_report["fps_avg"], last_report["fps_1pct_low"],
			last_report["frame_ms_avg"], last_report["frame_ms_p95"], int(last_report["draw_calls_avg"])])
	return "\n".join(lines)


func _finish_measurement() -> void:
	measuring = false
	_button.disabled = false
	last_report = summarize(_samples)
	last_report["view"] = _view_stats().get("view", "–")
	last_report["resolution"] = str(get_window().size)
	last_report["pixel_ratio"] = _dpr()
	last_report["video_mem_mb"] = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)
	last_report["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	print("PERF_REPORT " + JSON.stringify(last_report))


## Aggregates raw samples (pure function, unit-tested).
static func summarize(samples: Array) -> Dictionary:
	var n := samples.size()
	if n == 0:
		return {"samples": 0}
	var dts: Array = samples.map(func(s): return float(s["dt"]))
	var total := 0.0
	for d in dts:
		total += d
	var sorted := dts.duplicate()
	sorted.sort()
	var p95: float = sorted[mini(n - 1, int(n * 0.95))]
	# 1 % low FPS = average FPS of the slowest 1 % of frames.
	var worst: Array = sorted.slice(maxi(0, n - maxi(1, n / 100)))
	var worst_avg := 0.0
	for d in worst:
		worst_avg += d
	worst_avg /= worst.size()
	var avg_of := func(key: String) -> float:
		var t := 0.0
		for s in samples:
			t += float(s[key])
		return t / n
	var max_of := func(key: String) -> float:
		var m := 0.0
		for s in samples:
			m = maxf(m, float(s[key]))
		return m
	return {
		"samples": n,
		"seconds": snappedf(total, 0.1),
		"fps_avg": snappedf(n / maxf(total, 0.0001), 0.1),
		"fps_1pct_low": snappedf(1.0 / maxf(worst_avg, 0.0001), 0.1),
		"frame_ms_avg": snappedf(total / n * 1000.0, 0.01),
		"frame_ms_p95": snappedf(p95 * 1000.0, 0.01),
		"frame_ms_max": snappedf(float(sorted[n - 1]) * 1000.0, 0.01),
		"cpu_process_ms_avg": snappedf(avg_of.call("cpu_process") * 1000.0, 0.01),
		"cpu_physics_ms_avg": snappedf(avg_of.call("cpu_physics") * 1000.0, 0.01),
		"render_cpu_ms_avg": snappedf(avg_of.call("render_cpu_ms"), 0.01),
		"gpu_ms_avg": snappedf(avg_of.call("gpu_ms"), 0.01),
		"draw_calls_avg": snappedf(avg_of.call("draw_calls"), 0.1),
		"draw_calls_max": max_of.call("draw_calls"),
		"primitives_avg": snappedf(avg_of.call("primitives"), 1.0),
		"visible_objects_avg": snappedf(avg_of.call("visible_objects"), 0.1),
	}


static func _mb(bytes: float) -> String:
	return ("%.1f MB" % (bytes / 1048576.0)).replace(".", ",")


func _dpr() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.devicePixelRatio", true))
	return str(DisplayServer.screen_get_scale())
