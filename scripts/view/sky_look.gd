extends RefCounted
## Sky and light (10.8): how bright the day is at a minute of day, the sky colours from it, and how
## windows and empty rooms follow. All of it is a pure function of the minute of day (and the rain flag),
## so it is smooth across a day and the same moment always gives the same colours. The renderer copies
## the current values into the statics below once per frame; rooms read them when they are drawn.
## Rain is a flag a future event turns on with set_rain(); it greys and darkens the sky and draws streaks.
## Reads nothing from the sim and adds no saved state.

const DAWN_FROM := 300  ## 5:00, the day start: the sky begins to lighten.
const DAWN_TO := 420  ## 7:00: full day.
const DUSK_FROM := 1080  ## 18:00: the sky begins to darken.
const DUSK_TO := 1200  ## 20:00: full night.
const FULL := 1000  ## Daylight is 0 (night) to FULL (day), in thousandths.
const STEP := 20  ## The renderer redraws the sky and windows when daylight moves by this much.
const NIGHT_DIM := 0.8  ## An empty room dims this much at night (the art standard says about 80%).
const RAIN_GREY := 0.55  ## How far rain pulls the sky toward grey.
const RAIN_DARKEN := 0.25
const STARS := 48
const SKY_BANDS := 10  ## Whole-pixel bands of the gradient above the horizon.
const RAIN_SPACING := 40  ## Pixels between rain streaks.

## The values the renderer last set; rooms read them. Daylight starts at full day, no rain.
static var daylight: int = FULL
static var rain: bool = false


static func set_rain(on: bool) -> void:
	rain = on


## Daylight at a minute of day, 0 to FULL: night until DAWN_FROM, a smooth rise to DAWN_TO, day, a smooth
## fall from DUSK_FROM to DUSK_TO, night. Smoothstep, so it has no corners.
static func daylight_at(minute: int) -> int:
	var m := posmod(minute, 1440)
	if m < DAWN_FROM or m >= DUSK_TO:
		return 0
	if m < DAWN_TO:
		return _smooth(m - DAWN_FROM, DAWN_TO - DAWN_FROM)
	if m < DUSK_FROM:
		return FULL
	return FULL - _smooth(m - DUSK_FROM, DUSK_TO - DUSK_FROM)


static func _smooth(at: int, span: int) -> int:
	var t := float(at) / float(span)
	return roundi(t * t * (3.0 - 2.0 * t) * FULL)


## Daylight rounded down to a STEP, which is what the renderer uses so it redraws in a few dozen steps a day.
static func quantized(minute: int) -> int:
	return daylight_at(minute) / STEP * STEP


## The sky colour at the top and at the horizon for a daylight value: day colours by day, night colours
## by night, both lerped in between. Rain greys and darkens them.
static func colors(p: Dictionary, dl: int, raining: bool) -> Dictionary:
	var t := float(dl) / FULL
	var top: Color = (p["sky_night"] as Color).lerp(p["sky_day"], t)
	var horizon: Color = (p["sky_night_horizon"] as Color).lerp(p["sky_horizon"], t)
	if raining:
		top = _wet(top)
		horizon = _wet(horizon)
	return {"top": top, "horizon": horizon}


static func _wet(c: Color) -> Color:
	var grey := Color(c.get_luminance(), c.get_luminance(), c.get_luminance())
	return c.lerp(grey, RAIN_GREY).darkened(RAIN_DARKEN)


## The colour in a window: the sky outside, or by night the lamp light of a room in use.
static func window_color(p: Dictionary, lit: bool, dl: int, raining: bool) -> Color:
	var sky: Color = colors(p, dl, raining)["horizon"]
	if lit and dl < FULL / 2:
		return sky.lerp(p["lamp"], 1.0 - float(dl) / (FULL / 2.0))
	return sky


## An empty room's dimming: the palette's by day, NIGHT_DIM by night (never lighter than the palette's).
static func dim_at(base_dim: float, dl: int) -> float:
	return lerpf(maxf(base_dim, NIGHT_DIM), base_dim, float(dl) / FULL)


## A star's position in a width x height box and its brightness 0 to 1: integer hashing, no randomness.
static func star(index: int, width: int, height: int) -> Vector3:
	var h := (index * 2654435761 + 40503) & 0x7fffffff
	var x := h % maxi(width, 1)
	var y := (h / 7919) % maxi(height, 1)
	return Vector3(x, y, 0.4 + 0.6 * float(h % 5) / 4.0)


## Paints the sky into canvas (anything with draw_rect): the gradient from the top colour down to the
## horizon at ground_y, stars and a moon by night, a sun by day, rain streaks when raining. Native
## pixels, whole-pixel bands. left and width span the sky, top is its upper edge, world_w the tower's width.
static func draw(canvas: Object, p: Dictionary, minute: int, dl: int, raining: bool, left: int, top: int, width: int, ground_y: int, world_w: int, band_h: int) -> void:
	var c := colors(p, dl, raining)
	var top_color: Color = c["top"]
	var horizon: Color = c["horizon"]
	var gradient_top := ground_y - SKY_BANDS * band_h
	canvas.draw_rect(Rect2i(left, top, width, gradient_top - top), top_color)
	for band in SKY_BANDS:
		canvas.draw_rect(Rect2i(left, gradient_top + band * band_h, width, band_h), top_color.lerp(horizon, float(band + 1) / SKY_BANDS))
	var night := FULL - dl
	if night > 0 and not raining:
		for n in STARS:
			var s := star(n, world_w, gradient_top - top)
			canvas.draw_rect(Rect2i(int(s.x), top + int(s.y), 1, 1), Color(1, 1, 1, s.z * float(night) / FULL))
	var m := posmod(minute, 1440)
	if m >= 360 and m <= 1200 and dl > 0 and not raining:  # the sun crosses from 6:00 to 20:00
		var t := float(m - 360) / 840.0
		_disc(canvas, int(world_w * t), ground_y - 30 - int(sin(t * PI) * 700.0), Color(p["gold"], float(dl) / FULL))
	var moon_m := posmod(m - 1200, 1440)  # the moon crosses from 20:00 to 6:00
	if moon_m <= 600 and night > 0 and not raining:
		var mt := float(moon_m) / 600.0
		_disc(canvas, int(world_w * mt), ground_y - 30 - int(sin(mt * PI) * 700.0), Color(p["white"], float(night) / FULL))
	if raining:
		for row in range((ground_y - top) / RAIN_SPACING):
			for column in range(world_w / RAIN_SPACING):
				canvas.draw_rect(Rect2i(column * RAIN_SPACING + (row * 13) % RAIN_SPACING, top + row * RAIN_SPACING, 1, 6), horizon.lightened(0.35))


static func _disc(canvas: Object, x: int, y: int, color: Color) -> void:
	canvas.draw_rect(Rect2i(x - 4, y - 6, 8, 12), color)
	canvas.draw_rect(Rect2i(x - 6, y - 4, 12, 8), color)
