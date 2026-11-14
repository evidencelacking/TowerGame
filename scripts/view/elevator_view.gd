extends RefCounted
## What to draw for elevators (4.9): shafts across their span, cars with their load, and the
## hall queues at each stop. Reads the sim only; never writes to it. Positions are in levels
## (a floor's place on one line: floor 1 is level 1, B1 is level 0), so a car can sit between
## floors. Cars move about 11 floors a tick, so the view keeps the last two sim positions of each
## car and slides between them each frame.

const CarsScript := preload("res://scripts/sim/cars.gd")
const GridScript := preload("res://scripts/sim/grid.gd")

const MAX_QUEUE_FIGURES := 5  ## Queued people drawn per side; the rest are a count label.

## Last two sim levels of each car, keyed by "shaft id:car number in its shaft".
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _seen_tick: int = -1


## A floor's place on one line: there is no floor 0, so basements are 0 and below.
static func level_of(floor_number: int) -> int:
	return floor_number if floor_number > 0 else floor_number + 1


## The car's load as drawn, e.g. "12/17".
static func load_label(load: int, capacity: int) -> String:
	return "%d/%d" % [load, capacity]


## The label for people past the drawn figures, e.g. "+7", or "" when everyone is drawn.
static func overflow_label(count: int, shown: int) -> String:
	return "+%d" % (count - shown) if count > shown else ""


## A level between two sim levels: t 0 is `from`, t 1 is `to` (t is clamped).
static func lerp_level(from: int, to: int, t: float) -> float:
	return from + (to - from) * clampf(t, 0.0, 1.0)


## Pixel row (top edge, world space) of a one-cell-high car at a level.
static func level_to_y(level: float, cell: int) -> float:
	return (GridScript.FLOOR_MAX - level) * cell


## Shafts: [{"id", "x", "width", "bottom", "top", "stops": [floors], "disabled": [floors]}],
## ascending by id. The span is read from the grid cells the shaft occupies.
static func shafts(tower: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in tower.rooms.shaft_ids():
		var x: int = tower.rooms.shaft_x(id)
		var span: Array[int] = []
		for index: int in GridScript.FLOOR_COUNT:
			var floor_number: int = GridScript.index_to_floor(index)
			if tower.rooms._shaft_base(tower.grid.cell_at(floor_number, x)) == id:
				span.append(floor_number)
		if span.is_empty():
			continue
		var width := 1
		while x + width < GridScript.WIDTH_UNITS and tower.rooms._shaft_base(tower.grid.cell_at(span[0], x + width)) == id:
			width += 1
		var stops: Array[int] = tower.rooms.stops_of(id)
		var disabled: Array[int] = []
		for floor_number: int in span:
			if not stops.has(floor_number):
				disabled.append(floor_number)
		out.append({"id": id, "x": x, "width": width, "bottom": span[0], "top": span[span.size() - 1], "stops": stops, "disabled": disabled})
	return out


## Queues at stops: [{"shaft", "x", "width", "floor", "dir", "count", "shown", "side", "label"}].
## People going up queue on the left of the shaft (side -1), people going down on the right (+1).
## Shown is the figures drawn, at most MAX_QUEUE_FIGURES; label is the overflow count.
static func queues(tower: Object) -> Array[Dictionary]:
	var counts: Dictionary = {}  # [shaft id, floor, dir] -> count (reads the sim's queue only)
	for entry: Array in tower.rooms._queue:
		var key := [entry[1], entry[2], CarsScript.dir_to(entry[2], entry[3])]
		counts[key] = int(counts.get(key, 0)) + 1
	var by_id: Dictionary = {}
	for shaft: Dictionary in shafts(tower):
		by_id[shaft["id"]] = shaft
	var out: Array[Dictionary] = []
	for key: Array in counts:
		var shaft: Dictionary = by_id.get(key[0], {})
		if shaft.is_empty():
			continue
		var count: int = counts[key]
		var shown := mini(count, MAX_QUEUE_FIGURES)
		var side := -1 if key[2] == CarsScript.UP else 1
		out.append({"shaft": key[0], "x": shaft["x"], "width": shaft["width"], "floor": key[1], "dir": key[2], "count": count, "shown": shown, "side": side, "label": overflow_label(count, shown)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a["shaft"], a["floor"], a["dir"]] < [b["shaft"], b["floor"], b["dir"]])
	return out


## Notes each car's sim level once per sim tick; call every frame. True when a new tick began.
func observe(tower: Object) -> bool:
	if tower.tick == _seen_tick:
		return false
	_seen_tick = tower.tick
	var number: Dictionary = {}
	var fresh: Dictionary = {}
	for car: Array in tower.rooms._cars:
		var shaft: int = car[CarsScript.SHAFT]
		var key := "%d:%d" % [shaft, int(number.get(shaft, 0))]
		number[shaft] = int(number.get(shaft, 0)) + 1
		fresh[key] = level_of(car[CarsScript.FLOOR])
	_prev.clear()
	for key: String in fresh:
		_prev[key] = _cur.get(key, fresh[key])
	_cur = fresh
	return true


## Cars to draw, t (0 to 1) of the way from the last tick's level to this one's:
## [{"shaft", "x", "width", "level", "load", "label", "moving"}], oldest first.
func cars(tower: Object, t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for shaft: Dictionary in shafts(tower):
		by_id[shaft["id"]] = shaft
	var number: Dictionary = {}
	for car: Array in tower.rooms._cars:
		var id: int = car[CarsScript.SHAFT]
		var key := "%d:%d" % [id, int(number.get(id, 0))]
		number[id] = int(number.get(id, 0)) + 1
		var shaft: Dictionary = by_id.get(id, {})
		if shaft.is_empty():
			continue
		var now: int = _cur.get(key, level_of(car[CarsScript.FLOOR]))
		var before: int = _prev.get(key, now)
		out.append({"shaft": id, "x": shaft["x"], "width": shaft["width"], "level": lerp_level(before, now, t), "load": car[CarsScript.LOAD], "label": load_label(car[CarsScript.LOAD], tower.rooms.car_capacity()), "moving": before != now})
	return out
