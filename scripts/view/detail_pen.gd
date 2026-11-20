extends RefCounted
## A pen for Detailed graphics (#302), the "G Lit" look: crisp 2x pixel art on a sub-pixel grid. Every
## coordinate it takes is in sub-pixels, half a native pixel (so 16 per column and 64 per floor), counted
## from an origin in world pixels. It paints to any canvas item that has draw_rect, so the same canvas
## (and the same world rects) serve Classic and Detailed; the renderer shows Detailed on a 2x canvas, which
## is what makes each sub-pixel a whole screen pixel at zoom 1.
## `dark` (0 to 1) pushes tinted colours toward night blue, for an empty room. `E` (emit) is never tinted:
## lit screens, bulbs and the sky in a window. Nothing here reads the simulation.

const NIGHT_BLUE := Color("1a2048")
const INK := Color("2a1f2b")
const HALF := 0.5  ## World pixels per sub-pixel.

var canvas: Object = null
var origin: Vector2 = Vector2.ZERO
var dark: float = 0.0
var limit: Rect2i = Rect2i()  ## Sub-pixel clip: nothing paints outside it. An empty rect clips nothing.


func _init(target: Object, at: Vector2, darkness: float = 0.0) -> void:
	canvas = target
	origin = at
	dark = darkness


## A colour as this room shows it: shifted toward night blue and dimmed when the room is dark.
func tone(c: Color) -> Color:
	if dark <= 0.0:
		return c
	var d: Color = c.lerp(NIGHT_BLUE, 0.5 * dark)
	var k := 1.0 - 0.5 * dark
	return Color(d.r * k, d.g * k, d.b * k, c.a)


## A tinted rectangle in sub-pixels.
func R(x: int, y: int, w: int, h: int, c: Color) -> void:
	_rect(Rect2i(x, y, w, h), tone(c))


## A light-emitting rectangle: never darkened by the room.
func E(x: int, y: int, w: int, h: int, c: Color) -> void:
	_rect(Rect2i(x, y, w, h), c)


func _rect(r: Rect2i, c: Color) -> void:
	if limit.has_area():
		r = r.intersection(limit)
	if r.has_area():
		canvas.draw_rect(Rect2(origin.x + r.position.x * HALF, origin.y + r.position.y * HALF, r.size.x * HALF, r.size.y * HALF), c)


## A solid object in the house style: a hard selective outline, a light top edge, a dark bottom edge and a
## shaded right side, so it reads in three tones.
func item(x: int, y: int, w: int, h: int, c: Color, outline: bool = true) -> void:
	if w <= 0 or h <= 0:
		return
	if outline:
		var edge := c.darkened(0.55)
		R(x, y - 1, w, h + 2, edge)
		R(x - 1, y, w + 2, h, edge)
	R(x, y, w, h, c)
	if h >= 3 and w >= 3:
		R(x + 1, y, w - 2, 1, c.lightened(0.3))
		R(x, y + h - 1, w, 1, c.darkened(0.28))
		if w >= 6:
			R(x + w - 1, y + 1, 1, h - 2, c.darkened(0.14))
	if h >= 5 and w >= 4:
		R(x, y + 1, 1, h - 2, c.lightened(0.12))


## A hollow frame of thickness t (sub-pixels) in colour c.
func frame(x: int, y: int, w: int, h: int, c: Color, t: int = 2) -> void:
	R(x, y, w, t, c)
	R(x, y + h - t, w, t, c)
	R(x, y + t, t, h - 2 * t, c)
	R(x + w - t, y + t, t, h - 2 * t, c)


## A two-row ordered dither in colour c over a base already painted: 2-wide cells, the first row on even
## cells and the second on odd ones. A soft step between two tones without a gradient.
func dither_band(x: int, y: int, w: int, c: Color) -> void:
	var at := x
	var cell := 0
	while at < x + w:
		R(at, y + cell % 2, mini(2, x + w - at), 1, c)
		at += 2
		cell += 1
