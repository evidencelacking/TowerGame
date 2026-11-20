extends RefCounted
## Drawing primitives for Detailed graphics (#302), ported from the G Lit mock-up (mockups/detail_prims.gd,
## its crisp-pixel path). Every coordinate is in mock-up pixels: half a world pixel, so 16 per column and 64
## per floor, counted from `origin` (world pixels). Everything is drawn with draw_rect on any canvas item,
## so the same world rects serve Classic and Detailed; the renderer shows Detailed on a 2x canvas.
## `dark` (0 to 1) pushes tinted colours toward night blue; GR (a light-emitting rectangle) and GW are never
## tinted. Night itself is lighting (#305): the renderer darkens the whole canvas, and `glow` records the
## soft lights a lit room adds (lamp pools, window glow, screen glow) in DetailLight for an additive layer.
## `night` turns glows on. Nothing here reads the simulation.
## `flip` mirrors what is drawn around a vertical axis, so a desk can face either way.

const BAYER: Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const NIGHT_BLUE: Color = Color("1a2048")
const HALF: float = 0.5  ## World pixels per mock-up pixel.
const Light := preload("res://scripts/view/detail_light.gd")

var canvas: Object = null
var origin: Vector2 = Vector2.ZERO
var dark: float = 0.0
var night: bool = false
var sleeping: bool = false  ## Someone sleeps here: the bedside lamp is the one light.
var lit: bool = false  ## The room's main lights are on (windows glow only then).
var limit: Rect2i = Rect2i()  ## Mock-up pixels: nothing paints outside it. An empty rect clips nothing.
var flip_on: bool = false
var flip_axis: float = 0.0


func _init(target: Object, at: Vector2, darkness: float = 0.0, is_night: bool = false) -> void:
	canvas = target
	origin = at
	dark = darkness
	night = is_night


## Hash noise in 0..1 so textures are the same on every draw.
static func hn(a: int, b: int = 0) -> float:
	var h: int = (a * 374761393 + b * 668265263 + 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## Palette shift for a room that is dark at night. Alpha is kept.
func tone(c: Color) -> Color:
	if dark <= 0.0:
		return c
	var d: Color = c.lerp(NIGHT_BLUE, 0.5 * dark)
	var k: float = 1.0 - 0.5 * dark
	return Color(d.r * k, d.g * k, d.b * k, c.a)


## Mirrors what follows around the vertical line x = axis until flip_off.
func flip_around(axis: float) -> void:
	flip_on = true
	flip_axis = axis


func flip_off() -> void:
	flip_on = false


func _emit(x: float, y: float, w: float, h: float, c: Color) -> void:
	if flip_on:
		x = 2.0 * flip_axis - x - w
	var x0: int = roundi(x)
	var y0: int = roundi(y)
	var r := Rect2i(x0, y0, roundi(x + w) - x0, roundi(y + h) - y0)
	if limit.has_area():
		r = r.intersection(limit)
	if r.has_area():
		canvas.draw_rect(Rect2(origin.x + r.position.x * HALF, origin.y + r.position.y * HALF, r.size.x * HALF, r.size.y * HALF), c)


## The x range (mock-up pixels from the room's left wall) this pen paints in: wide open unless limited. Scene
## loops over a wide room start and stop inside it, so painting one slice of a room costs only its share (#346).
func x_from() -> float:
	return float(limit.position.x) if limit.has_area() and not flip_on else -1.0e9


func x_to() -> float:
	return float(limit.end.x) if limit.has_area() and not flip_on else 1.0e9


## The index range [first, last) of repeats `step` apart from x0, `count` of them, `reach` wide each, that can touch the x range.
func repeats(x0: float, step: float, count: int, reach: float) -> Vector2i:
	if not limit.has_area() or flip_on:
		return Vector2i(0, count)
	var first := clampi(int(floorf((x_from() - x0 - reach) / step)), 0, count)
	var last := mini(count, int(ceilf((x_to() - x0) / step)) + 1)
	return Vector2i(first, maxi(first, last))


func R(x: float, y: float, w: float, h: float, c: Color) -> void:
	if not flip_on and limit.has_area() and (x >= limit.end.x or x + w <= limit.position.x):  # cheap reject, so a narrow limit costs little (#346)
		return
	if w > 0.0 and h > 0.0:
		_emit(x, y, w, h, tone(c))


## A light-emitting rectangle (bulb, screen, sky in a window): never darkened by the room.
func GR(x: float, y: float, w: float, h: float, c: Color) -> void:
	if not flip_on and limit.has_area() and (x >= limit.end.x or x + w <= limit.position.x):
		return
	if w > 0.0 and h > 0.0:
		_emit(x, y, w, h, c)


## A faint glow wash on top of the picture.
func GW(x: float, y: float, w: float, h: float, c: Color) -> void:
	if w > 0.0 and h > 0.0:
		_emit(x, y, w, h, Color(c.r, c.g, c.b, 0.18))


## Filled ellipse scanned row by row so the edge is crisp.
func ell(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var iy: int = int(ceil(ry))
	for dy: int in range(-iy, iy):
		var t: float = (float(dy) + 0.5) / ry
		if absf(t) >= 1.0:
			continue
		var hw: float = rx * sqrt(1.0 - t * t)
		var x0: float = roundf(cx - hw)
		var x1: float = roundf(cx + hw)
		if x1 > x0:
			R(x0, floorf(cy) + float(dy), x1 - x0, 1.0, c)


## Vertical gradient in four steps with an ordered dither on the two rows where a step changes.
func gradv(x: float, y: float, w: float, h: float, c1: Color, c2: Color, raw: bool = false) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	var steps: int = 4
	var run := repeats(x, 2.0, int(w) / 2, 2.0)
	var iy: int = int(y)
	var ih: int = int(h)
	for s: int in steps:
		var y0: int = ih * s / steps
		var y1: int = ih * (s + 1) / steps
		var col: Color = c1.lerp(c2, float(s) / float(steps))
		_fill(x, float(iy + y0), w, float(y1 - y0), col, raw)
		if s > 0 and y1 - y0 >= 2:
			var prev: Color = c1.lerp(c2, float(s - 1) / float(steps))
			for dy: int in 2:  # alternate cells of the step above into the first two rows of this one
				for k: int in range(run.x, run.y):
					if (k + dy) % 2 == 0:
						_fill(x + float(k * 2), float(iy + y0 + dy), 2.0, 1.0, prev, raw)


func _fill(x: float, y: float, w: float, h: float, c: Color, raw: bool) -> void:
	if raw:
		GR(x, y, w, h, c)
	else:
		R(x, y, w, h, c)


## A soft elliptical wash (a contact shadow, a lamp pool): two rings of an ordered dither, in cells of
## `cell` pixels so a big pool costs few rects.
func soft_ell(cx: float, cy: float, rx: float, ry: float, c: Color, strength: float, raw: bool = false, cell: int = 1) -> void:
	for ring_i: int in 2:
		var k: float = 1.0 - float(ring_i) * 0.5
		var dens: float = strength * (0.16 if ring_i == 0 else 0.3)
		var iy: int = int(ceil(ry * k))
		for dy: int in range(-iy, iy, cell):
			var t: float = (float(dy) + 0.5 * float(cell)) / (ry * k)
			if absf(t) >= 1.0:
				continue
			var hw: float = rx * k * sqrt(1.0 - t * t)
			var x0: int = int(roundf(cx - hw))
			var x1: int = int(roundf(cx + hw))
			var yy: int = int(floorf(cy)) + dy
			for px: int in range(x0, x1, cell):
				if (float(BAYER[((yy / cell) & 3) * 4 + ((px / cell) & 3)]) + 0.5) / 16.0 < dens:
					_fill(px, yy, cell, cell, c, raw)


## A pool of warm lamp light on a surface, only at night: a soft glow for the additive layer, kept inside
## the room. A flipped drawing mirrors the glow's place too.
func glow(cx: float, cy: float, rx: float, ry: float, c: Color, strength: float) -> void:
	if not night:
		return
	if flip_on:
		cx = 2.0 * flip_axis - cx
	var clip := Rect2(origin + Vector2(limit.position) * HALF, Vector2(limit.size) * HALF) if limit.has_area() else Rect2(origin, Vector2(100000, 100000))
	Light.add(clip, origin + Vector2(cx, cy) * HALF, Vector2(rx, ry) * HALF, c, strength)


## A thin line walked one pixel at a time.
func ln(a: Vector2, b: Vector2, c: Color, width: float = 1.0) -> void:
	var x0: int = int(a.x)
	var y0: int = int(a.y)
	var x1: int = int(b.x)
	var y1: int = int(b.y)
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var wpx: int = maxi(1, int(roundf(width)))
	for _i: int in dx - dy + 2:  # a Bresenham walk takes at most dx + dy + 1 steps
		R(x0, y0, wpx, wpx, c)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## Contact shadow under an object standing on the floor.
func shadow(cx: float, y: float, rx: float, strength: float = 0.5) -> void:
	soft_ell(cx, y, rx, maxf(1.5, rx * 0.16), Color("1a1220"), strength)


## A solid object in the house style: a hard selective outline, a light top edge and a dark bottom edge, so
## it reads in three tones. r above 0 cuts the corners.
func item(x: float, y: float, w: float, h: float, c: Color, r: float = 0.0, outline: bool = true) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	var edge: Color = c.darkened(0.55)
	var cut: int = 1 if r > 0.0 else 0
	if outline:
		R(x - 1 + cut, y - 1, w + 2 - 2 * cut, h + 2, edge)
		R(x - 1, y - 1 + cut, w + 2, h + 2 - 2 * cut, edge)
	R(x, y, w, h, c)
	if h >= 3.0 and w >= 3.0:
		R(x + cut, y, w - 2 * cut, 1, c.lightened(0.3))
		R(x, y + h - 1, w, 1, c.darkened(0.28))
		if w >= 6.0:
			R(x + w - 1, y + 1, 1, h - 2, c.darkened(0.14))
	if h >= 5.0 and w >= 4.0:
		R(x, y + 1, 1, h - 2, c.lightened(0.12))
