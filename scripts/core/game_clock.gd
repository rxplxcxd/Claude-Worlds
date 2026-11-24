extends Node
## Game time model (Phase 1: local, single player).
##
## Real time  -> advances game time at `minutes_per_second * speed`.
## Game time  -> stored as total elapsed game minutes since world start
##               (float, deterministic, easy to persist and to replace later by
##               a server-authoritative clock).
## See docs/ARCHITECTURE.md, section "Zeitmodell".

signal minute_changed(total_minutes: int)
signal hour_changed(day: int, hour: int)

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
const DAYS_PER_YEAR := 120 # Planned calendar, see WORLD_DESIGN.md (open question).
const START_MINUTES := 8 * MINUTES_PER_HOUR # Day 1, 08:00

## Game minutes per real second at speed 1.
@export var minutes_per_second: float = 1.0
## 0 = paused, 1 = normal, higher = fast forward.
var speed: float = 1.0

var _total_minutes: float = START_MINUTES
var _last_minute: int = -1
var _last_hour: int = -1


func _process(delta: float) -> void:
	if speed <= 0.0:
		return
	advance(delta * minutes_per_second * speed)


## Advances the clock by game minutes and emits change signals.
func advance(game_minutes: float) -> void:
	_total_minutes += maxf(game_minutes, 0.0)
	var minute := int(_total_minutes)
	if minute != _last_minute:
		_last_minute = minute
		minute_changed.emit(minute)
		var hour_index := minute / MINUTES_PER_HOUR
		if hour_index != _last_hour:
			_last_hour = hour_index
			hour_changed.emit(get_day(), get_hour())


## Jumps forward to the next occurrence of `hour:00`.
func skip_to_hour(hour: int) -> void:
	var minute_of_day := fmod(_total_minutes, MINUTES_PER_DAY)
	var target := float(hour * MINUTES_PER_HOUR)
	var delta := target - minute_of_day
	if delta <= 0.0:
		delta += MINUTES_PER_DAY
	advance(delta)


func set_total_minutes(value: float) -> void:
	_total_minutes = maxf(value, 0.0)
	_last_minute = -1
	_last_hour = -1
	advance(0.0)


func get_total_minutes() -> float:
	return _total_minutes


## 1-based day counter since world start.
func get_day() -> int:
	return int(_total_minutes / MINUTES_PER_DAY) + 1


func get_year() -> int:
	return (get_day() - 1) / DAYS_PER_YEAR + 1


func get_hour() -> int:
	return int(fmod(_total_minutes, MINUTES_PER_DAY) / MINUTES_PER_HOUR)


func get_minute() -> int:
	return int(fmod(_total_minutes, MINUTES_PER_HOUR))


## 0.0 .. 1.0 position inside the current day.
func get_day_fraction() -> float:
	return fmod(_total_minutes, MINUTES_PER_DAY) / MINUTES_PER_DAY


## 0.0 (full day) .. 1.0 (deep night). Smooth dawn/dusk transitions.
func get_night_factor() -> float:
	var h := get_day_fraction() * HOURS_PER_DAY
	if h >= 7.0 and h <= 19.0:
		return 0.0
	if h > 19.0 and h < 21.5:
		return smoothstep(19.0, 21.5, h)
	if h > 4.5 and h < 7.0:
		return 1.0 - smoothstep(4.5, 7.0, h)
	return 1.0


func format_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]
