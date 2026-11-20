extends Node2D
## Drawing primitives for the "Detailed" art mock-ups (E Illustrated, F Rich pixel, G Lit).
## One layout is drawn three ways: each primitive picks smooth shapes (E) or crisp pixels (F, G).
## Mock-up only: not part of the game, and it reads nothing from the simulation.

enum Style { ILLUSTRATED, PIXEL, LIT }
## Which canvas a draw call belongs to when lighting splits the picture in three (G only):
## BG is the sky behind the tower, WORLD is lit, EMIT sits on top and is never darkened.
enum Layer { WORLD, EMIT, BG }

const BAYER: Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const NIGHT_BLUE: Color = Color("1a2048")

var style: int = Style.ILLUSTRATED
var night: bool = false
## Which canvas this node paints when lighting is on (see Layer). Unlit styles use WORLD only.
var pass_layer: int = Layer.WORLD
var _layer: int = Layer.WORLD
## 0 to 1: how far the current room is pushed toward night colours (E and F; G uses real light).
var _dark: float = 0.0
var _tex_cache: Array[ImageTexture] = []


func _smooth() -> bool:
	return style == Style.ILLUSTRATED


func _lighting() -> bool:
	return style == Style.LIT


## True when the call being made belongs on this node.
func _active() -> bool:
	if not _lighting():
		return true
	return pass_layer == _layer


## Palette shift for a room that is dark at night. Alpha is kept.
func _c(c: Color) -> Color:
	if _dark <= 0.0:
		return c
	var d: Color = c.lerp(NIGHT_BLUE, 0.5 * _dark)
	var k: float = 1.0 - 0.5 * _dark
	return Color(d.r * k, d.g * k, d.b * k, c.a)


func _in_layer(layer: int) -> int:
	var prev: int = _layer
	_layer = layer
	return prev


## Hash noise in 0..1 so textures are the same on every draw.
static func hn(a: int, b: int = 0) -> float:
	var h: int = (a * 374761393 + b * 668265263 + 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


# ---------------------------------------------------------------- shapes

func R(x: float, y: float, w: float, h: float, c: Color) -> void:
	if _active() and w > 0.0 and h > 0.0:
		draw_rect(Rect2(x, y, w, h), _c(c))


## A light-emitting rectangle (bulb, screen, sky in a window): never darkened by the room.
## Unlit styles draw it opaque. Lit style draws a near-black base in the world and the colour
## on the additive emissive canvas above, so it adds to the base instead of covering it.
func GR(x: float, y: float, w: float, h: float, c: Color) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	if not _lighting():
		draw_rect(Rect2(x, y, w, h), c)
	elif pass_layer == Layer.WORLD:
		draw_rect(Rect2(x, y, w, h), Color(0.05, 0.05, 0.07))
	elif pass_layer == Layer.EMIT:
		draw_rect(Rect2(x, y, w, h), c)


## A glow wash on top of the picture (additive in the lit style, a faint alpha elsewhere).
func GW(x: float, y: float, w: float, h: float, c: Color) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	if not _lighting():
		draw_rect(Rect2(x, y, w, h), Color(c.r, c.g, c.b, 0.18))
	elif pass_layer == Layer.EMIT:
		draw_rect(Rect2(x, y, w, h), c)


## A pool of lamp light on a surface. Only unlit styles paint it: the lit style has real lights.
func pool(cx: float, cy: float, rx: float, ry: float, c: Color, strength: float) -> void:
	if not _lighting():
		soft_ell(cx, cy, rx, ry, c, strength, true)


func _arc_pts(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5)
	var corners: Array = [
		[x + w - r, y + r, -90.0], [x + w - r, y + h - r, 0.0],
		[x + r, y + h - r, 90.0], [x + r, y + r, 180.0]]
	for cn: Array in corners:
		for i: int in 6:
			var a: float = deg_to_rad(float(cn[2]) + 90.0 * float(i) / 5.0)
			pts.append(Vector2(float(cn[0]) + cos(a) * r, float(cn[1]) + sin(a) * r))
	return pts


func poly(pts: PackedVector2Array, c: Color) -> void:
	if _active() and pts.size() >= 3:
		draw_colored_polygon(pts, _c(c))


## Filled ellipse. Pixel styles scan it row by row so the edge is crisp.
func ell(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	if not _active():
		return
	if _smooth():
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 32:
			var a: float = TAU * float(i) / 32.0
			pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
		draw_colored_polygon(pts, _c(c))
		return
	var iy: int = int(ceil(ry))
	for dy: int in range(-iy, iy):
		var t: float = (float(dy) + 0.5) / ry
		if absf(t) >= 1.0:
			continue
		var hw: float = rx * sqrt(1.0 - t * t)
		var x0: float = roundf(cx - hw)
		var x1: float = roundf(cx + hw)
		if x1 > x0:
			draw_rect(Rect2(x0, floorf(cy) + float(dy), x1 - x0, 1.0), _c(c))


## Outline of a circle of radius r and the given thickness.
func ring(cx: float, cy: float, r: float, c: Color, width: float = 1.0) -> void:
	if not _active():
		return
	if _smooth():
		draw_arc(Vector2(cx, cy), r, 0.0, TAU, 32, _c(c), width * 0.8, true)
		return
	var ir: float = r - width
	var iy: int = int(ceil(r))
	for dy: int in range(-iy, iy):
		var t: float = (float(dy) + 0.5) / r
		if absf(t) >= 1.0:
			continue
		var ho: float = r * sqrt(1.0 - t * t)
		var hi: float = 0.0
		if absf(float(dy) + 0.5) < ir:
			hi = sqrt(ir * ir - (float(dy) + 0.5) * (float(dy) + 0.5))
		var yy: float = floorf(cy) + float(dy)
		if hi <= 0.0:
			draw_rect(Rect2(roundf(cx - ho), yy, roundf(ho) * 2.0, 1.0), _c(c))
		else:
			draw_rect(Rect2(roundf(cx - ho), yy, roundf(ho - hi), 1.0), _c(c))
			draw_rect(Rect2(roundf(cx + hi), yy, roundf(ho - hi), 1.0), _c(c))


## Vertical gradient. E blends smoothly, F and G dither between steps with an ordered pattern.
func gradv(x: float, y: float, w: float, h: float, c1: Color, c2: Color, raw: bool = false) -> void:
	if not _active() or w <= 0.0 or h <= 0.0:
		return
	var a: Color = c1 if raw else _c(c1)
	var b: Color = c2 if raw else _c(c2)
	if _smooth():
		draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]),
			PackedColorArray([a, a, b, b]))
		return
	var iw: int = int(w)
	var ih: int = int(h)
	var img: Image = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	var steps: int = 4
	for py: int in ih:
		var t: float = (float(py) + 0.5) / float(ih) * float(steps)
		var lo: int = int(floor(t))
		var f: float = t - float(lo)
		var ca: Color = a.lerp(b, float(lo) / float(steps))
		var cb: Color = a.lerp(b, float(mini(lo + 1, steps)) / float(steps))
		for px: int in iw:
			var th: float = (float(BAYER[((py + int(y)) & 3) * 4 + ((px + int(x)) & 3)]) + 0.5) / 16.0
			img.set_pixel(px, py, cb if f > th else ca)
	_blit(img, x, y)


func _blit(img: Image, x: float, y: float) -> void:
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_tex_cache.append(tex)
	draw_texture(tex, Vector2(x, y))


## A translucent wash of colour: smooth alpha (E) or an ordered dither at the same density (F, G).
func wash(x: float, y: float, w: float, h: float, c: Color, density: float, raw: bool = false) -> void:
	if not _active() or w <= 0.0 or h <= 0.0 or density <= 0.0:
		return
	var cc: Color = c if raw else _c(c)
	if _smooth():
		draw_rect(Rect2(x, y, w, h), Color(cc.r, cc.g, cc.b, cc.a * density))
		return
	var iw: int = int(w)
	var ih: int = int(h)
	var img: Image = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	for py: int in ih:
		for px: int in iw:
			if (float(BAYER[((py + int(y)) & 3) * 4 + ((px + int(x)) & 3)]) + 0.5) / 16.0 < density:
				img.set_pixel(px, py, cc)
	_blit(img, x, y)


## A soft elliptical wash (shadow, glow). E stacks alpha rings; pixel styles dither two rings.
func soft_ell(cx: float, cy: float, rx: float, ry: float, c: Color, strength: float, raw: bool = false) -> void:
	if not _active():
		return
	var cc: Color = c if raw else _c(c)
	if _smooth():
		for i: int in 9:
			var k: float = 1.0 - float(i) * 0.1
			var pts: PackedVector2Array = PackedVector2Array()
			for j: int in 28:
				var a: float = TAU * float(j) / 28.0
				pts.append(Vector2(cx + cos(a) * rx * k, cy + sin(a) * ry * k))
			draw_colored_polygon(pts, Color(cc.r, cc.g, cc.b, cc.a * strength * 0.12))
		return
	for ring_i: int in 2:
		var k: float = 1.0 - float(ring_i) * 0.5
		var iy: int = int(ceil(ry * k))
		var dens: float = strength * (0.16 if ring_i == 0 else 0.3)
		for dy: int in range(-iy, iy):
			var t: float = (float(dy) + 0.5) / (ry * k)
			if absf(t) >= 1.0:
				continue
			var hw: float = rx * k * sqrt(1.0 - t * t)
			var x0: int = int(roundf(cx - hw))
			var x1: int = int(roundf(cx + hw))
			var yy: int = int(floorf(cy)) + dy
			for px: int in range(x0, x1):
				if (float(BAYER[(yy & 3) * 4 + (px & 3)]) + 0.5) / 16.0 < dens:
					draw_rect(Rect2(px, yy, 1, 1), cc)


## A thin line. E is anti-aliased, pixel styles walk a Bresenham line one pixel at a time.
func ln(a: Vector2, b: Vector2, c: Color, width: float = 1.0) -> void:
	if not _active():
		return
	if _smooth():
		draw_line(a, b, _c(c), width, true)
		return
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
		draw_rect(Rect2(x0, y0, wpx, wpx), _c(c))
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


## A solid object in the house style. E: rounded, gradient, soft highlight. F and G: a hard
## selective outline, a light top edge and a dark bottom edge, so it reads in 3 tones.
func item(x: float, y: float, w: float, h: float, c: Color, r: float = 0.0, outline: bool = true) -> void:
	if not _active() or w <= 0.0 or h <= 0.0:
		return
	if _smooth():
		var pts: PackedVector2Array = _arc_pts(x, y, w, h, maxf(r, 0.8))
		var cols: PackedColorArray = PackedColorArray()
		for p: Vector2 in pts:
			cols.append(_c(c.lightened(0.16).lerp(c.darkened(0.2), clampf((p.y - y) / h, 0.0, 1.0))))
		draw_polygon(pts, cols)
		if outline:
			var edge: PackedVector2Array = pts.duplicate()
			edge.append(pts[0])
			draw_polyline(edge, _c(c.darkened(0.5)), 0.5, true)
		if h > 3.0 and w > 3.0:
			draw_line(Vector2(x + r * 0.6 + 0.5, y + 0.9), Vector2(x + w - r * 0.6 - 0.5, y + 0.9), Color(1, 1, 1, 0.3), 0.6, true)
		return
	var dark: Color = c.darkened(0.55)
	var cut: int = 1 if r > 0.0 else 0
	if outline:
		draw_rect(Rect2(x - 1 + cut, y - 1, w + 2 - 2 * cut, h + 2), _c(dark))
		draw_rect(Rect2(x - 1, y - 1 + cut, w + 2, h + 2 - 2 * cut), _c(dark))
	draw_rect(Rect2(x, y, w, h), _c(c))
	if h >= 3.0 and w >= 3.0:
		draw_rect(Rect2(x + cut, y, w - 2 * cut, 1), _c(c.lightened(0.3)))
		draw_rect(Rect2(x, y + h - 1, w, 1), _c(c.darkened(0.28)))
		if w >= 6.0:
			draw_rect(Rect2(x + w - 1, y + 1, 1, h - 2), _c(c.darkened(0.14)))
	if h >= 5.0 and w >= 4.0:
		draw_rect(Rect2(x, y + 1, 1, h - 2), _c(c.lightened(0.12)))


## A flat panel with no shading (walls, glass backs).
func panel(x: float, y: float, w: float, h: float, c: Color, r: float = 0.0) -> void:
	if not _active():
		return
	if _smooth() and r > 0.0:
		draw_colored_polygon(_arc_pts(x, y, w, h, r), _c(c))
	else:
		draw_rect(Rect2(x, y, w, h), _c(c))
