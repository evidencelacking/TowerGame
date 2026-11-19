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
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const RAIL_H: int = 9  ## Handrail height above a tread.
const DOOR_H: int = 18
const PIPS: int = 4  ## Lamps in a door's indicator.
const ARRIVED_SLACK: float = 0.15  ## A car this close to a floor level counts as there.
const RIDERS_SHOWN: int = 5


## Whether the flight in a span climbs to the left (odd floor rows) instead of to the right.
static func flips(span: Rect2i) -> bool:
	return (span.end.y / VC.CELL_H) % 2 == 1


## One stairs or escalator in its two-floor rect; only the lower floor is drawn on. An escalator's moving
## parts (step edges, handrail dashes) are draw_belt, redrawn each tick; this is its fixed frame.
static func draw_link(canvas: Object, kind: String, span: Rect2i) -> void:
	var p := Palette.get_palette()
	var hue := Palette.hue(kind)
	var base_y := span.end.y - VC.SLAB_H  # the lower floor's surface
	if kind == "stairs":
		_draw_stairs(canvas, p, hue, span, base_y)
	else:
		_draw_escalator(canvas, p, hue, span, base_y)


## Row of the tread top `i` columns into the climb (0 at the lower floor, w - 1 at the upper one), so every
## flight starts and ends at a floor's walking height and stacked flights meet there (#259).
static func surface_y(base_y: int, w: int, i: int) -> int:
	return base_y - 1 - i * VC.CELL_H / maxi(w - 1, 1)


## Pixel column of the `i`th column of the climb.
static func column_x(span: Rect2i, i: int) -> int:
	return span.end.x - 1 - i if flips(span) else span.position.x + i


## A rect clipped to the link's cells, so nothing drawn can spill out of them.
static func _fill(canvas: Object, span: Rect2i, rect: Rect2i, color: Color) -> void:
	var r := span.intersection(rect)
	if r.size.x > 0 and r.size.y > 0:
		canvas.draw_rect(r, color)


## A diagonal band following the climb, `dy` rows from the tread line: one column at a time. With `join`
## each column also spans the rise to the next, so a steep band has no gaps.
static func _diag(canvas: Object, span: Rect2i, base_y: int, dy: int, thick: int, color: Color, join: bool = true) -> void:
	var w := span.size.x
	for i in w:
		var y := surface_y(base_y, w, i) + dy
		var top := y
		if join and i < w - 1:
			top = surface_y(base_y, w, i + 1) + dy
		_fill(canvas, span, Rect2i(column_x(span, i), top, 1, y - top + thick), color)


## A landing plate: the floor's walking surface, `n` columns from column `i`, a lit line over a dark one.
static func _plate(canvas: Object, p: Dictionary, span: Rect2i, i: int, n: int, y: int, color: Color) -> void:
	for k in n:
		var x := column_x(span, i + k)
		_fill(canvas, span, Rect2i(x, y, 1, 1), color)
		_fill(canvas, span, Rect2i(x, y + 1, 1, 1), p["outline"])


static func _draw_stairs(canvas: Object, p: Dictionary, hue: Color, span: Rect2i, base_y: int) -> void:
	var w := span.size.x
	var steps := maxi(w / 4, 2)
	var light := hue.lightened(0.4)
	var riser_color := hue.darkened(0.5)
	var rail := (p["wall"] as Color).lightened(0.55)
	var outline: Color = p["outline"]
	_diag(canvas, span, base_y, 4, 1, outline)  # the stringer under the treads
	var prev_y := base_y - 1
	for n in steps:
		var i0 := n * w / steps
		var i1 := (n + 1) * w / steps
		var y := surface_y(base_y, w, i0)
		var x0 := column_x(span, i1 - 1)
		var x1 := column_x(span, i0)
		var left := mini(x0, x1)
		_fill(canvas, span, Rect2i(left, y, i1 - i0, 1), light)  # lit tread edge
		_fill(canvas, span, Rect2i(left, y + 1, i1 - i0, 1), hue.darkened(0.15))  # tread underside
		if prev_y > y:  # the riser up to this tread, on its leading side
			_fill(canvas, span, Rect2i(x1, y + 1, 1, prev_y - y), riser_color)
		prev_y = y
		if n % 2 == 0:  # posts down from the rail to the tread
			var pi := (i0 + i1) / 2
			_fill(canvas, span, Rect2i(column_x(span, pi), surface_y(base_y, w, pi) - RAIL_H + 2, 1, RAIL_H - 2), outline)
	_diag(canvas, span, base_y, -RAIL_H, 1, rail)  # handrail
	_diag(canvas, span, base_y, -RAIL_H + 1, 1, outline)
	_plate(canvas, p, span, 0, 3, base_y - 1, light)  # landing at each floor
	_plate(canvas, p, span, w - 3, 3, base_y - 1 - VC.CELL_H, light)


## The escalator's fixed frame: a truss under the belt, a see-through balustrade panel, a handrail band,
## a rounded newel at each end and a lit footplate at the top and bottom.
static func _draw_escalator(canvas: Object, p: Dictionary, hue: Color, span: Rect2i, base_y: int) -> void:
	var w := span.size.x
	var rail := (p["wall"] as Color).lightened(0.3)
	var outline: Color = p["outline"]
	var truss := hue.darkened(0.6)
	_diag(canvas, span, base_y, 1, 3, truss)  # truss under the belt
	_diag(canvas, span, base_y, 4, 1, outline)
	_diag(canvas, span, base_y, 0, 1, hue.darkened(0.3))  # the belt bed
	_diag(canvas, span, base_y, -RAIL_H + 2, RAIL_H - 3, Color(truss.r, truss.g, truss.b, 0.35), false)  # balustrade panel
	_diag(canvas, span, base_y, -RAIL_H, 2, rail)  # handrail band
	_diag(canvas, span, base_y, -RAIL_H + 2, 1, outline)
	for end: int in 2:  # a rounded newel where the rail meets each floor
		var lift := VC.CELL_H if end == 1 else 0
		for k in 3:
			var i := (w - 1 - k) if end == 1 else k
			var height := RAIL_H - (2 - k)
			_fill(canvas, span, Rect2i(column_x(span, i), base_y - 1 - lift - height, 1, height), truss)
		_plate(canvas, p, span, (w - 4) if end == 1 else 0, 4, base_y - 1 - lift, hue.lightened(0.5))  # footplate
		_fill(canvas, span, Rect2i(column_x(span, (w - 2) if end == 1 else 1), base_y - 2 - lift, 1, 1), p["gold"])  # its lamp


const BELT_PERIOD: int = 4  ## Columns between step edges on an escalator.
const RAIL_PERIOD: int = 6  ## Columns between dashes on its moving handrail.


## How far the steps have moved along the climb at a sim tick: one column a tick, so it repeats every
## BELT_PERIOD ticks and depends only on the tick.
static func belt_phase(tick: int) -> int:
	return posmod(tick, BELT_PERIOD)


## An escalator's moving parts at a sim tick: step edges running up the incline, and light dashes on the
## handrail. Deterministic in the tick; draws nothing but inside the link's cells.
static func draw_belt(canvas: Object, span: Rect2i, tick: int, hue: Color) -> void:
	var p := Palette.get_palette()
	var base_y := span.end.y - VC.SLAB_H
	var w := span.size.x
	var phase := belt_phase(tick)
	var rail_phase := posmod(tick, RAIL_PERIOD)
	var edge := hue.lightened(0.45)
	var gap := hue.darkened(0.45)
	var dash := (p["wall"] as Color).lightened(0.8)
	for i in range(4, w - 4):  # between the footplates
		var y := surface_y(base_y, w, i)
		var x := column_x(span, i)
		var q := posmod(i - phase, BELT_PERIOD)
		if q < 2:
			_fill(canvas, span, Rect2i(x, y, 1, 1), edge)  # a step's lit edge
		elif q == 2:
			_fill(canvas, span, Rect2i(x, y + 1, 1, 1), gap)  # the riser's shadow
		if posmod(i - rail_phase, RAIL_PERIOD) < 2:
			_fill(canvas, span, Rect2i(x, y - RAIL_H, 1, 1), dash)


## The shaft's back wall: centre seam and side edges over rect, as the shaft hue.
static func draw_shaft_body(canvas: Object, rect: Rect2i, shaft_color: Color) -> void:
	var edge := shaft_color.lightened(0.4)
	canvas.draw_rect(rect, shaft_color)
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, rect.position.y, 1, rect.size.y), edge.darkened(0.3))
	canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, 1, rect.size.y), edge)
	canvas.draw_rect(Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y), edge)


## Closed doors on a floor the shaft stops at (floor_bottom is the pixel row of its floor surface): a frame,
## a centre seam, door panels, and an indicator of lamps above (dark; draw_arrival lights it).
static func draw_doors(canvas: Object, rect: Rect2i, floor_bottom: int, shaft_color: Color) -> void:
	var door := shaft_color.lightened(0.55)
	var x := rect.position.x + 3
	var w := rect.size.x - 6
	canvas.draw_rect(Rect2i(x, floor_bottom - DOOR_H, w, DOOR_H), door, false, 1.0)
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, floor_bottom - DOOR_H, 1, DOOR_H), door)
	canvas.draw_rect(Rect2i(x + 2, floor_bottom - DOOR_H + 2, 1, DOOR_H - 3), door.darkened(0.35))
	canvas.draw_rect(Rect2i(x + w - 3, floor_bottom - DOOR_H + 2, 1, DOOR_H - 3), door.darkened(0.35))
	_indicator(canvas, rect, floor_bottom, door)


static func _indicator(canvas: Object, rect: Rect2i, floor_bottom: int, color: Color) -> void:
	var left := rect.position.x + rect.size.x / 2 - (PIPS * 4 - 2) / 2
	for n in PIPS:
		canvas.draw_rect(Rect2i(left + n * 4, floor_bottom - DOOR_H - 4, 2, 2), color)


## Lights the indicator over the doors of the floor a car stands at (nothing while it is between floors).
## level is the car's floor level; floor_bottom_of maps a whole floor level to its surface row.
static func draw_arrival(canvas: Object, rect: Rect2i, level: float, floor_bottom_of: Callable) -> void:
	var nearest := roundi(level)
	if absf(level - nearest) > ARRIVED_SLACK:
		return
	_indicator(canvas, rect, floor_bottom_of.call(nearest) as int, Color("ff5030"))


## How open a car's doors are at a level, 0 (closed) to 1 (open): fully open when the car stands at a floor,
## closing as it leaves (and opening as it arrives) over ARRIVED_SLACK of a level. A car that crosses more
## than a level between two sim ticks is passing through, so its doors stay shut.
static func door_open(level: float, step: float = 0.0) -> float:
	if step > 1.0:
		return 0.0
	return clampf(1.0 - absf(level - roundf(level)) / ARRIVED_SLACK, 0.0, 1.0)


## The gap of open car doors over the doors of the floor whose surface is at floor_bottom: a lit opening in
## the middle that widens with open (0 draws nothing), with the door leaves left on each side.
static func draw_door_gap(canvas: Object, rect: Rect2i, floor_bottom: int, open: float, lit: Color) -> void:
	var full := rect.size.x - 8
	var gap := roundi(open * full)
	if gap <= 0:
		return
	var x := rect.position.x + rect.size.x / 2 - gap / 2
	canvas.draw_rect(Rect2i(x, floor_bottom - DOOR_H + 1, gap, DOOR_H - 1), lit)


## A car: dark frame, body, ceiling lamp, centre doors, a rail, and up to five riders as small figures.
static func draw_car(canvas: Object, rect: Rect2i, car_color: Color, load: int, people: Array) -> void:
	var p := Palette.get_palette()
	canvas.draw_rect(rect.grow(1), p["outline"])
	canvas.draw_rect(rect, car_color)
	canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, 1), car_color.lightened(0.3))
	canvas.draw_rect(Rect2i(rect.position.x + 2, rect.position.y + 1, rect.size.x - 4, 1), p["lamp"])
	canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, rect.position.y + 2, 1, rect.size.y - 2), car_color.darkened(0.35))
	canvas.draw_rect(Rect2i(rect.position.x + 1, rect.position.y + 12, rect.size.x - 2, 1), car_color.darkened(0.25))
	draw_riders(canvas, rect, load, people)


## Up to five riders as figures inside a car rect: three in front, two behind in the gaps, a few pixels higher.
static func draw_riders(canvas: Object, rect: Rect2i, load: int, people: Array) -> void:
	var p := Palette.get_palette()
	var usable := rect.size.x - 4 - VC.FIGURE_W
	var feet := rect.end.y - 1
	var shown := mini(load, RIDERS_SHOWN)
	for back: bool in [true, false]:
		for n in shown:
			if (n % 2 == 1) != back:
				continue
			var shirt: Color = people[n % people.size()]
			var slot := n / 2  # front riders 0, 2, 4 take slots 0..2; back riders 1, 3 take slots 0..1
			var fx := rect.position.x + 2 + (usable * (2 * slot + 1) / 4 if back else usable * slot / 2)
			ActivityLook.draw_person(canvas, fx, feet - (3 if back else 0), shirt, p["skin"])
