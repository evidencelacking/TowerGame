extends RefCounted
## Sky and light (10.8): daylight is smooth across a whole day and deterministic, the sky colours run
## from the palette's night to its day, windows and empty rooms follow, and rain is a flag that changes the look.

const Clock := preload("res://scripts/sim/clock.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const Palette := preload("res://scripts/view/palette.gd")

const MAX_CHANNEL_STEP := 0.02  ## The most a sky colour channel may change between adjacent ticks.


## Records draw_rect calls.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Rect2i, c: Color) -> void:
		calls.append([r, c])


static func _day_ticks() -> int:
	var total := 0
	for index in Clock.PERIODS:
		total += Clock.period_ticks(index)
	return total


static func _step(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


static func run(check: Callable) -> void:
	var clock := Clock.new()
	var p := Palette.get_palette()
	var worst := 0.0
	var worst_window := 0.0
	var seen_dark := false
	var seen_light := false
	var rain_worst := 0.0
	var previous: Dictionary = {}
	var previous_window := Color()
	var previous_rain: Dictionary = {}
	var deterministic := true
	# Two days of ticks, so the wrap past midnight is covered too.
	for tick in 2 * _day_ticks():
		clock.set_to_tick(tick)
		var dl := SkyLook.daylight_at(clock.minute_of_day())
		deterministic = deterministic and dl == SkyLook.daylight_at(clock.minute_of_day())
		seen_dark = seen_dark or dl == 0
		seen_light = seen_light or dl == SkyLook.FULL
		var now := SkyLook.colors(p, dl, false)
		var window := SkyLook.window_color(p, true, dl, false)
		var wet := SkyLook.colors(p, dl, true)
		if not previous.is_empty():
			worst = maxf(worst, maxf(_step(previous["top"], now["top"]), _step(previous["horizon"], now["horizon"])))
			worst_window = maxf(worst_window, _step(previous_window, window))
			rain_worst = maxf(rain_worst, maxf(_step(previous_rain["top"], wet["top"]), _step(previous_rain["horizon"], wet["horizon"])))
		previous = now
		previous_window = window
		previous_rain = wet
	check.call(seen_dark and seen_light, "sky: a day reaches full night and full day")
	check.call(deterministic, "sky: daylight is a pure function of the minute")
	check.call(worst < MAX_CHANNEL_STEP, "sky: colour is continuous between adjacent ticks (worst step %.4f)" % worst)
	check.call(worst_window < MAX_CHANNEL_STEP and rain_worst < MAX_CHANNEL_STEP, "sky: windows and rainy sky are continuous too (%.4f, %.4f)" % [worst_window, rain_worst])

	check.call((SkyLook.colors(p, SkyLook.FULL, false)["top"] as Color).is_equal_approx(p["sky_day"]), "sky: noon is the palette's day sky")
	check.call((SkyLook.colors(p, 0, false)["top"] as Color).is_equal_approx(p["sky_night"]) and (SkyLook.colors(p, 0, false)["horizon"] as Color).is_equal_approx(p["sky_night_horizon"]), "sky: midnight is the palette's night sky")
	check.call(SkyLook.daylight_at(12 * 60) == SkyLook.FULL and SkyLook.daylight_at(0) == 0 and SkyLook.daylight_at(1440 + 12 * 60) == SkyLook.FULL, "sky: noon is day, midnight is night, minutes wrap")
	var dawn := SkyLook.daylight_at((SkyLook.DAWN_FROM + SkyLook.DAWN_TO) / 2)
	check.call(dawn > 300 and dawn < 700, "sky: dawn is halfway lit at its middle (%d)" % dawn)

	# Windows show the sky, and by night a room in use shines.
	var night_window := SkyLook.window_color(p, true, 0, false)
	check.call(SkyLook.window_color(p, false, 0, false) == SkyLook.colors(p, 0, false)["horizon"], "sky: an empty room's window shows the night sky")
	check.call(night_window.get_luminance() > SkyLook.window_color(p, false, 0, false).get_luminance(), "sky: a room in use is lit at night")
	check.call(SkyLook.window_color(p, true, SkyLook.FULL, false) == SkyLook.window_color(p, false, SkyLook.FULL, false), "sky: by day use does not change the window")
	check.call(SkyLook.dim_at(0.45, SkyLook.FULL) == 0.45 and absf(SkyLook.dim_at(0.45, 0) - SkyLook.NIGHT_DIM) < 0.001, "sky: empty rooms dim to the art standard's 45% by day and 80% by night")

	# Rain: a flag, off by default, that changes the look and draws streaks.
	check.call(not SkyLook.rain, "sky: it is not raining by default")
	check.call(SkyLook.colors(p, SkyLook.FULL, true)["top"] != SkyLook.colors(p, SkyLook.FULL, false)["top"], "sky: rain changes the sky colour")
	var dry := Recorder.new()
	var wet_rec := Recorder.new()
	SkyLook.draw(dry, p, 12 * 60, SkyLook.FULL, false, 0, 0, 800, 800, 400, 32)
	SkyLook.draw(wet_rec, p, 12 * 60, SkyLook.FULL, true, 0, 0, 800, 800, 400, 32)
	check.call(not dry.calls.is_empty() and wet_rec.calls.size() > dry.calls.size(), "sky: rain draws streaks over the sky")
	var again := Recorder.new()
	SkyLook.draw(again, p, 12 * 60, SkyLook.FULL, false, 0, 0, 800, 800, 400, 32)
	check.call(again.calls == dry.calls, "sky: the same moment draws the same")
	SkyLook.set_rain(true)
	var flagged := SkyLook.rain
	SkyLook.set_rain(false)
	check.call(flagged and not SkyLook.rain, "sky: set_rain turns the look on and off")
