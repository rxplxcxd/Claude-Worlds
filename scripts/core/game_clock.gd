extends Node
## Real-time clock (autoload "GameClock").
##
## WORLDS runs on real time. Four clearly separated notions (see
## docs/ARCHITECTURE.md §4 "Zeitmodell"):
##   1. UTC           – the ONLY shared time base. Shared events, contracts and
##                      server state are stored and compared in UTC.
##   2. Local offset  – the player's current UTC offset incl. daylight saving,
##                      detected from the browser/OS (IANA name, e.g.
##                      "Europe/Berlin"); re-checked every minute, so DST
##                      switches apply automatically.
##   3. Local time    – UTC + local offset; shown in the HUD and used for the
##                      sky (sun position) the player sees.
##   4. Settlement time zone – stored on each settlement at founding; rules
##                      that must be identical for everyone in that settlement
##                      (e.g. opening hours, later NPC schedules) use it.
## Server time: `server_offset_seconds` will be set from the authoritative
## server once multiplayer exists; the client clock is never trusted for
## shared state.

signal minute_changed(total_minutes: int)
signal hour_changed(day: int, hour: int)

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
## Latitude used for sunrise/sunset until settlements have real coordinates
## on the planet (Phase 2). 51° N = central Germany.
const DEFAULT_LATITUDE := 51.0
const WEEKDAYS := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
const MONTHS := ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

## Correction to the device clock (later: from the server).
var server_offset_seconds: float = 0.0
## Detected time zone.
var timezone_name := ""
var timezone_abbr := ""
var utc_offset_minutes := 0
var is_dst := false
var latitude := DEFAULT_LATITUDE
## Time-of-day preview for testing the lighting (menu). -1 = real time.
## Only affects visuals, never stored or shared.
var preview_minute_of_day := -1.0
## Test hook: fixed UTC unix time (-1 = use the real clock).
var fixed_utc_unix := -1.0

var _last_minute := -1
var _last_hour := -1
var _tz_check := 0.0


func _ready() -> void:
	detect_timezone()
	_read_url_preview()
	_tick()


## QA helper: "?preview=23:30" in the page URL sets the time-of-day preview
## (visuals only, same as the menu slider).
func _read_url_preview() -> void:
	if not OS.has_feature("web"):
		return
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('preview')||''", true)
	var parts := str(v).split(":")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		preview_minute_of_day = clampf(int(parts[0]) * 60.0 + int(parts[1]), 0.0, 1439.0)


func _process(delta: float) -> void:
	_tz_check += delta
	if _tz_check >= 1.0:
		_tz_check = 0.0
		_tick()


func _tick() -> void:
	var m := int(get_local_unix() / 60.0)
	if m != _last_minute:
		_last_minute = m
		if m % 15 == 0:
			detect_timezone() # catches daylight-saving switches
		minute_changed.emit(m)
		var hour_index := m / MINUTES_PER_HOUR
		if hour_index != _last_hour:
			_last_hour = hour_index
			hour_changed.emit(get_day(), get_hour())


## Reads time zone and current offset from the browser (or the OS).
func detect_timezone() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js := "(function(){var d=new Date(),y=d.getFullYear();var p=new Intl.DateTimeFormat('de-DE',{timeZoneName:'short'}).formatToParts(d).find(function(x){return x.type==='timeZoneName'});return JSON.stringify({tz:Intl.DateTimeFormat().resolvedOptions().timeZone||'',off:-d.getTimezoneOffset(),jan:-new Date(y,0,1).getTimezoneOffset(),jul:-new Date(y,6,1).getTimezoneOffset(),abbr:p?p.value:''});})()"
		var raw: Variant = JavaScriptBridge.eval(js, true)
		var info: Variant = JSON.parse_string(str(raw)) if raw != null else null
		if typeof(info) == TYPE_DICTIONARY:
			timezone_name = str(info.get("tz", ""))
			timezone_abbr = str(info.get("abbr", ""))
			utc_offset_minutes = int(info.get("off", 0))
			var standard := mini(int(info.get("jan", 0)), int(info.get("jul", 0)))
			is_dst = utc_offset_minutes > standard
			return
	# Desktop/headless: difference between local and UTC wall clock.
	var local := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false))
	var utc := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(true))
	utc_offset_minutes = int(round((local - utc) / 60.0))
	var tz := Time.get_time_zone_from_system()
	timezone_name = str(tz.get("name", ""))
	timezone_abbr = timezone_name
	is_dst = false


# --- time bases -------------------------------------------------------------

## Shared world time: seconds since 1970-01-01 UTC.
func get_utc_unix() -> float:
	if fixed_utc_unix >= 0.0:
		return fixed_utc_unix
	return Time.get_unix_time_from_system() + server_offset_seconds


## Player-local time as a unix-style timestamp (UTC + offset).
func get_local_unix() -> float:
	return get_utc_unix() + utc_offset_minutes * 60.0


## Kept for persistence/compatibility: minutes of shared world time.
func get_total_minutes() -> float:
	return get_utc_unix() / 60.0


## Real time cannot be set; kept so old saves load without errors.
func set_total_minutes(_value: float) -> void:
	pass


func local_datetime() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(get_local_unix()))


## Minute of the (local) day, honouring the preview override.
func get_minute_of_day() -> float:
	if preview_minute_of_day >= 0.0:
		return preview_minute_of_day
	return fmod(get_local_unix() / 60.0, MINUTES_PER_DAY)


func get_hour() -> int:
	return int(get_minute_of_day() / MINUTES_PER_HOUR)


func get_minute() -> int:
	return int(fmod(get_minute_of_day(), MINUTES_PER_HOUR))


## Days since the unix epoch in local time (only used for display/ordering).
func get_day() -> int:
	return int(get_local_unix() / 86400.0)


func get_day_fraction() -> float:
	return get_minute_of_day() / MINUTES_PER_DAY


func format_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func format_date() -> String:
	var d := local_datetime()
	return "%s %d. %s" % [WEEKDAYS[int(d.get("weekday", 0))], int(d.get("day", 1)), MONTHS[int(d.get("month", 1)) - 1]]


# --- sun & light ------------------------------------------------------------

## Sun altitude in degrees for the local date/time (simple solar model:
## declination by day of year, solar noon ~12:20 standard time, +1 h in DST).
func get_sun_altitude() -> float:
	var d := local_datetime()
	var doy := _day_of_year(int(d.get("year", 2026)), int(d.get("month", 1)), int(d.get("day", 1)))
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var solar_noon := 12.0 + (1.0 if is_dst else 0.0) + 0.33
	var hour := get_minute_of_day() / 60.0
	var h_angle := deg_to_rad(15.0 * (hour - solar_noon))
	var lat := deg_to_rad(latitude)
	var s := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(h_angle)
	return rad_to_deg(asin(clampf(s, -1.0, 1.0)))


## Sunrise and sunset (local hours) for today, or [-1, -1] in polar day/night.
func get_sun_times() -> Vector2:
	var d := local_datetime()
	var doy := _day_of_year(int(d.get("year", 2026)), int(d.get("month", 1)), int(d.get("day", 1)))
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var lat := deg_to_rad(latitude)
	var c := (sin(deg_to_rad(-0.83)) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
	if absf(c) > 1.0:
		return Vector2(-1, -1)
	var half := rad_to_deg(acos(c)) / 15.0
	var noon := 12.0 + (1.0 if is_dst else 0.0) + 0.33
	return Vector2(noon - half, noon + half)


## "" normally, "polar_day" (sun never sets) or "polar_night" (never rises)
## for the current date and latitude – the whole planet is settleable, so
## polar settlements get real polar days and nights.
func polar_state() -> String:
	var d := local_datetime()
	var doy := _day_of_year(int(d.get("year", 2026)), int(d.get("month", 1)), int(d.get("day", 1)))
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + doy) / 365.0)
	var lat := deg_to_rad(clampf(latitude, -89.99, 89.99))
	var c := (sin(deg_to_rad(-0.83)) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
	if c > 1.0:
		return "polar_night"
	if c < -1.0:
		return "polar_day"
	return ""


## 0 = full daylight, 1 = deep night (smooth over civil twilight).
func get_night_factor() -> float:
	return 1.0 - smoothstep(-8.0, 4.0, get_sun_altitude())


## Colour the world is tinted with (CanvasModulate), from the sun altitude.
func get_ambient_color() -> Color:
	var alt := get_sun_altitude()
	var night := Color(0.34, 0.40, 0.66)
	var twilight := Color(0.93, 0.66, 0.62)
	var golden := Color(1.0, 0.9, 0.78)
	var day := Color(1, 1, 1)
	if alt <= -8.0:
		return night
	if alt <= -2.0:
		return night.lerp(twilight, smoothstep(-8.0, -2.0, alt))
	if alt <= 6.0:
		return twilight.lerp(golden, smoothstep(-2.0, 6.0, alt))
	return golden.lerp(day, smoothstep(6.0, 18.0, alt))


static func _day_of_year(y: int, m: int, d: int) -> int:
	var days := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	return days[m - 1] + d + (1 if leap and m > 2 else 0)
