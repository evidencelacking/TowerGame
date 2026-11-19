extends RefCounted
## How the transport kinds look (10.4): stairs and escalators, elevator shafts with doors and indicators,
## and cars with their riders. Pure drawing at native resolution; reads only what it is given.
##
## A stair or escalator is drawn with no background, only treads, slope and handrail, so the room behind
## shows through. It climbs one floor over its width, from the lower floor's surface to the upper floor's,
## and the direction alternates with the floor row (up to the right on even rows, up to the left on odd),
## so flights stacked in the same columns turn back on each other: one flight ends where the next begins,
## at the same height with its rail at the same height, so treads, slope and handrail meet there (#259).

const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const RAIL_H: int = 9  ## Handrail height above a tread.
const DOOR_H: int = 18
const PIPS: int = 4  ## Lamps in a door's indicator.
const ARRIVED_SLACK: float = 0.15  ## A car this close to a floor level counts as there.
const RIDERS_SHOWN: int = 5


## Whether the flight in a span climbs to the left (odd floor rows) instead of to the right.
static func flips(span: Rect2i) -> bool:
	return (span.end.y / VC.CELL_H) % 2 == 1


## One stairs or escalator in its two-floor rect; only the lower floor is drawn on.
static func draw_link(canvas: CanvasItem, kind: String, span: Rect2i) -> void:
	var p := Palette.get_palette()
	var hue := Palette.hue(kind)
	var base_y := span.end.y - VC.SLAB_H  # the lower floor's surface
	if kind == "stairs":
		_draw_stairs(canvas, p, hue, span, base_y)
	else:
		_draw_escalator(canvas, p, hue, span, base_y)


## A tread or rail segment: the colour on top over a dark line.
static func _lit_line(canvas: CanvasItem, p: Dictionary, x: int, y: int, w: int, color: Color) -> void:
	canvas.draw_rect(Rect2i(x, y, w, 1), color)
	canvas.draw_rect(Rect2i(x, y + 1, w, 1), p["outline"])


static func _draw_stairs(canvas: CanvasItem, p: Dictionary, hue: Color, span: Rect2i, base_y: int) -> void:
	var w := span.size.x
	var flip := flips(span)
	var steps := maxi(w / 4, 2)
	var light := hue.lightened(0.25)
	var rail := (p["wall"] as Color).lightened(0.55)
	var outline: Color = p["outline"]
	var prev_y := base_y
	for i in steps:
		var y := base_y - (i + 1) * VC.CELL_H / (steps + 1)  # the top step stops one riser short of the upper floor
		var x0 := i * w / steps
		var x1 := (i + 1) * w / steps
		var x := span.position.x + (w - x1 if flip else x0)
		var sw := x1 - x0
		_lit_line(canvas, p, x, y, sw, light)
		canvas.draw_rect(Rect2i(x + sw - 1 if flip else x, y, 1, prev_y - y), outline)  # riser
		var ry := y - RAIL_H
		_lit_line(canvas, p, x, ry, sw, rail)
		if i > 0:  # join the rail to the previous run's height
			canvas.draw_rect(Rect2i(x + sw - 1 if flip else x, ry, 1, prev_y - y + 1), rail)
		if i % 3 == 0:  # posts
			canvas.draw_rect(Rect2i(x + sw / 2, ry + 1, 1, RAIL_H - 1), outline)
		prev_y = y


static func _draw_escalator(canvas: CanvasItem, p: Dictionary, hue: Color, span: Rect2i, base_y: int) -> void:
	var w := span.size.x
	var flip := flips(span)
	var rail := (p["wall"] as Color).lightened(0.55)
	var outline: Color = p["outline"]
	for x in range(0, w, 2):
		var y := base_y - (x + 2) * VC.CELL_H / w  # from the lower surface to exactly the upper one
		var sx := span.position.x + (w - 2 - x if flip else x)
		var slat := hue if (x / 4) % 2 == 0 else hue.darkened(0.3)
		canvas.draw_rect(Rect2i(sx, y, 2, 2), slat)
		canvas.draw_rect(Rect2i(sx, y + 2, 2, 1), outline)  # truss under the belt
		var ry := y - RAIL_H
		_lit_line(canvas, p, sx, ry, 2, rail)
		if x % 8 == 0:
			canvas.draw_rect(Rect2i(sx, ry + 2, 1, RAIL_H - 2), outline)  # balusters


## The shaft's back wall: centre seam and side edges over rect, as the shaft hue.
static func draw_shaft_body(canvas: CanvasItem, rect: Rect2i, shaft_color: Color) -> void:
	var edge := shaft_color.lightened(0.4)
	canvas.draw_rect(rect, shaft_color)
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, rect.position.y, 1, rect.size.y), edge.darkened(0.3))
	canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, 1, rect.size.y), edge)
	canvas.draw_rect(Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y), edge)


## Closed doors on a floor the shaft stops at (floor_bottom is the pixel row of its floor surface): a frame,
## a centre seam, door panels, and an indicator of lamps above (dark; draw_arrival lights it).
static func draw_doors(canvas: CanvasItem, rect: Rect2i, floor_bottom: int, shaft_color: Color) -> void:
	var door := shaft_color.lightened(0.55)
	var x := rect.position.x + 3
	var w := rect.size.x - 6
	canvas.draw_rect(Rect2i(x, floor_bottom - DOOR_H, w, DOOR_H), door, false, 1.0)
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, floor_bottom - DOOR_H, 1, DOOR_H), door)
	canvas.draw_rect(Rect2i(x + 2, floor_bottom - DOOR_H + 2, 1, DOOR_H - 3), door.darkened(0.35))
	canvas.draw_rect(Rect2i(x + w - 3, floor_bottom - DOOR_H + 2, 1, DOOR_H - 3), door.darkened(0.35))
	_indicator(canvas, rect, floor_bottom, door)


static func _indicator(canvas: CanvasItem, rect: Rect2i, floor_bottom: int, color: Color) -> void:
	var left := rect.position.x + rect.size.x / 2 - (PIPS * 4 - 2) / 2
	for n in PIPS:
		canvas.draw_rect(Rect2i(left + n * 4, floor_bottom - DOOR_H - 4, 2, 2), color)


## Lights the indicator over the doors of the floor a car stands at (nothing while it is between floors).
## level is the car's floor level; floor_bottom_of maps a whole floor level to its surface row.
static func draw_arrival(canvas: CanvasItem, rect: Rect2i, level: float, floor_bottom_of: Callable) -> void:
	var nearest := roundi(level)
	if absf(level - nearest) > ARRIVED_SLACK:
		return
	_indicator(canvas, rect, floor_bottom_of.call(nearest) as int, Color("ff5030"))


## A car: dark frame, body, ceiling lamp, centre doors, a rail, and up to five riders as small figures.
static func draw_car(canvas: CanvasItem, rect: Rect2i, car_color: Color, load: int, people: Array) -> void:
	var p := Palette.get_palette()
	canvas.draw_rect(rect.grow(1), p["outline"])
	canvas.draw_rect(rect, car_color)
	canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, 1), car_color.lightened(0.3))
	canvas.draw_rect(Rect2i(rect.position.x + 2, rect.position.y + 1, rect.size.x - 4, 1), p["lamp"])
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, rect.position.y + 2, 1, rect.size.y - 2), car_color.darkened(0.35))
	canvas.draw_rect(Rect2i(rect.position.x + 1, rect.position.y + 12, rect.size.x - 2, 1), car_color.darkened(0.25))
	var spread := (rect.size.x - 4) / RIDERS_SHOWN
	var feet := rect.end.y - 1
	for n in mini(load, RIDERS_SHOWN):
		var shirt: Color = people[n % people.size()]
		var fx := rect.position.x + 2 + n * spread + (spread - VC.FIGURE_W) / 2
		canvas.draw_rect(Rect2i(fx, feet - 9, VC.FIGURE_W, 3), p["skin"])
		canvas.draw_rect(Rect2i(fx, feet - 6, VC.FIGURE_W, 5), shirt)
		canvas.draw_rect(Rect2i(fx, feet - 1, VC.FIGURE_W, 1), shirt.darkened(0.4))
