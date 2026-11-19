class_name TowerRenderer
extends Node2D
const VC := preload("res://scripts/view/view_consts.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const Palette := preload("res://scripts/view/palette.gd")
const PixelLayer := preload("res://scripts/view/pixel_layer.gd")
## Draws the tower on a low-resolution canvas (10.2). World space is native pixels (8 px per column,
## 24 px per floor, see view_consts.gd). The rooms, links, floors and shafts go into one SubViewport
## that is redrawn only when the floors or rooms change or every STATIC_REFRESH_TICKS ticks (the in-use
## look follows people); the elevator cars, queues and people go into a second one redrawn each sim
## tick and while cars slide. Each is shown as a nearest-filtered sprite, and the camera zooms by whole
## numbers, so a native pixel is always a whole number of screen pixels. Sky and ground are flat
## rectangles drawn directly. Reads the Tower read-only; never mutates sim state.

const MARGIN: int = 4000  ## Sky and ground extend this far past the tower, in pixels.
const IN_USE_CHECK_TICKS: int = 6  ## How often the set of rooms in use is compared; a change redraws the static layer.
const STATIC_REFRESH_TICKS: int = 60  ## Redraw even when nothing moved, so sim state (dirty, vacant) shows within this.
const FIGURE_W: int = VC.FIGURE_W
const FIGURE_H: int = VC.FIGURE_H
const GLIDE_MAX_COLUMNS := 12.0  ## A move longer than this between two ticks is a new trip, not a glide.

## Back to front; every name is a method taking the canvas item to paint on. Links (stairs,
## escalators) and shafts sit in front of the rooms behind them (#126); the floor slabs come after
## rooms because a room fills its whole row and would hide its own slab.
const STATIC_LAYERS: Array[String] = ["_draw_backdrop", "_draw_lobby", "_draw_rooms", "_draw_links", "_draw_floors", "_draw_shafts"]
const DYNAMIC_LAYERS: Array[String] = ["_draw_queues", "_draw_cars", "_draw_people"]
const DRAW_ORDER: Array[String] = ["_draw_backdrop", "_draw_lobby", "_draw_rooms", "_draw_links", "_draw_floors", "_draw_shafts", "_draw_queues", "_draw_cars", "_draw_people"]

var tower: Tower = null
var _people_view := PeopleView.new()
var _elevators := ElevatorView.new()
var _seen_tick: int = -1
var _static_tick: int = -1000000
var _since_tick: float = 0.0  ## Seconds since the sim last ticked.
var _tick_len: float = 1.0 / 30.0  ## Seconds the last tick took; cars slide over this long.
var _seen_revision: int = -1
var _seen_occupants: int = -1
var _figures: Array[Dictionary] = []
var _from: Dictionary = {}  ## Person id -> Vector2(column, row) at the previous tick, to glide from.
var _has_moving: bool = false
var _in_use: Dictionary = {}  ## Room id -> true for rooms with someone resting in them.
var _checked_tick: int = -1000000
var _floor_rects: Array[Rect2i] = []  ## Runs of built floor units, one row tall; rebuilt when the layout changes.
var _room_runs: Array[Array] = []  ## [id, owning room id, rect] per placed room run.
var _link_runs: Array[Array] = []  ## [kind, two-floor rect] per stairs or escalator.
var _static_view: SubViewport = null
var _static_layer: Node2D = null
var _dynamic_view: SubViewport = null
var _dynamic_layer: Node2D = null


func _ready() -> void:
	var size := Vector2i(VC.world_rect().size)
	_static_layer = _make_layer(size, _paint_static)
	_static_view = _static_layer.get_parent()
	_dynamic_layer = _make_layer(size, _paint_dynamic)
	_dynamic_view = _dynamic_layer.get_parent()
	queue_redraw()


## A SubViewport at native size with a layer in it, shown by a nearest-filtered sprite at the origin.
func _make_layer(size: Vector2i, painter: Callable) -> Node2D:
	var view := SubViewport.new()
	view.size = size
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var layer: Node2D = PixelLayer.new()
	layer.set("painter", painter)
	view.add_child(layer)
	var sprite := Sprite2D.new()
	sprite.texture = view.get_texture()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return layer


## Redraws what changed; the view never polls the whole tower.
func _process(delta: float) -> void:
	if tower == null or _static_layer == null:
		return
	_since_tick += delta
	var new_tick := tower.tick != _seen_tick
	if _elevators.observe(tower):
		_tick_len = maxf(_since_tick, 0.001)
		_since_tick = 0.0
	var occupants := tower.grid.occupant_count() + tower.rooms.links.occupant_count() + tower.rooms.links_over.occupant_count()
	var layout_changed := tower.floors.revision != _seen_revision or occupants != _seen_occupants
	if layout_changed:
		_seen_revision = tower.floors.revision
		_seen_occupants = occupants
		_people_view.route_cache.clear()
		_rebuild_runs()
	if new_tick or layout_changed:
		_remember_positions()
		_figures = _people_view.figures(tower)
		_has_moving = false
		for figure: Dictionary in _figures:
			if figure["moving"]:
				_has_moving = true
				break
	var dirty := layout_changed or tower.tick - _static_tick >= STATIC_REFRESH_TICKS or tower.tick < _static_tick
	if not dirty and (tower.tick - _checked_tick >= IN_USE_CHECK_TICKS or tower.tick < _checked_tick):
		_checked_tick = tower.tick
		var before := _in_use
		_in_use = _rooms_in_use()
		dirty = _in_use != before
	elif dirty:
		_checked_tick = tower.tick
		_in_use = _rooms_in_use()
	if dirty:
		_static_tick = tower.tick
		_static_layer.queue_redraw()
		_static_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var sliding := (tower.rooms.total_cars() > 0 and _since_tick <= _tick_len * 2.0) or (_has_moving and _since_tick <= _tick_len)
	if new_tick or layout_changed or sliding:
		_dynamic_layer.queue_redraw()
		_dynamic_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_seen_tick = tower.tick


func set_tower(value: Tower) -> void:
	tower = value
	_static_tick = -1000000
	_seen_revision = -1
	_seen_tick = -1
	queue_redraw()


## Redraws everything after the palette in use changed.
func refresh_palette() -> void:
	_static_tick = -1000000
	_seen_revision = -1
	_seen_tick = -1
	queue_redraw()


## Rooms with someone resting in them, from the figures drawn this tick.
func _rooms_in_use() -> Dictionary:
	var used: Dictionary = {}
	for figure: Dictionary in _figures:
		if figure["moving"]:
			continue
		var id: int = tower.grid.cell_at(figure["floor"], figure["x"])
		if id != Tower.Grid.EMPTY:
			used[tower.rooms.room_of(id)] = true
	return used


## The floor, room and link runs as rects, found once per layout change and reused by every redraw.
func _rebuild_runs() -> void:
	_floor_rects.clear()
	_room_runs.clear()
	_link_runs.clear()
	var seen: Dictionary = {}
	var links_seen: Dictionary = {}
	for index: int in Tower.Grid.FLOOR_COUNT:
		var floor_number := Tower.Grid.index_to_floor(index)
		var row_y := VC.floor_to_row(floor_number) * VC.CELL_H
		var column := 0
		var floor_start := -1
		while column <= Tower.Grid.WIDTH_UNITS:
			var built := column < Tower.Grid.WIDTH_UNITS and tower.floors.has_floor(floor_number, column)
			if built and floor_start < 0:
				floor_start = column
			elif not built and floor_start >= 0:
				_floor_rects.append(Rect2i(floor_start * VC.CELL_W, row_y, (column - floor_start) * VC.CELL_W, VC.CELL_H))
				floor_start = -1
			column += 1
		column = 0
		while column < Tower.Grid.WIDTH_UNITS:
			var id := tower.grid.cell_at(floor_number, column)
			if id == Tower.Grid.EMPTY or seen.has(id):
				column += 1
				continue
			seen[id] = true
			var run := tower.grid.run_of(id)
			var owner_room: int = tower.rooms.room_of(id)
			if owner_room != 0:
				_room_runs.append([id, owner_room, Rect2i(run[1] * VC.CELL_W, row_y, run[2] * VC.CELL_W, VC.CELL_H)])
			column += maxi(run[2], 1)
		for layer: Tower.Grid in [tower.rooms.links, tower.rooms.links_over]:  # a stacked flight's lower half sits in the second layer (#259)
			column = 0
			while column < Tower.Grid.WIDTH_UNITS:
				var link := layer.cell_at(floor_number, column)
				if link == Tower.Grid.EMPTY or links_seen.has(link) or not Tower.RoomsScript.is_stair_kind(tower.rooms.kind_of(link)):
					column += 1
					continue
				links_seen[link] = true
				var link_run := layer.run_of(link)
				var top := VC.floor_to_row(Tower.RoomsScript.floor_above(floor_number)) * VC.CELL_H
				_link_runs.append([tower.rooms.kind_of(link), Rect2i(link_run[1] * VC.CELL_W, top, link_run[2] * VC.CELL_W, 2 * VC.CELL_H)])
				column += maxi(link_run[2], 1)


func _paint_static(canvas: CanvasItem) -> void:
	if tower == null:
		return
	for layer: String in STATIC_LAYERS:
		call(layer, canvas)


func _paint_dynamic(canvas: CanvasItem) -> void:
	if tower == null:
		return
	for layer: String in DYNAMIC_LAYERS:
		call(layer, canvas)


## Sky above the ground line and earth below, in the palette in use. Flat colour, so no low-res
## canvas is needed; the tower's own sprites sit in front.
func _draw() -> void:
	var p := Palette.get_palette()
	var world := Rect2i(VC.world_rect())
	var ground_y := Tower.Grid.FLOOR_MAX * VC.CELL_H  # bottom of floor 1, top of B1
	var left := -MARGIN
	var width := world.size.x + 2 * MARGIN
	draw_rect(Rect2i(left, world.position.y - MARGIN, width, ground_y + MARGIN), p["sky_day"])
	var horizon: Color = p["sky_horizon"]
	for band in 4:  # a lighter haze toward the horizon, in whole-pixel bands
		draw_rect(Rect2i(left, ground_y - (band + 1) * VC.CELL_H, width, VC.CELL_H), (p["sky_day"] as Color).lerp(horizon, 0.25 * (4 - band) / 4.0))
	draw_rect(Rect2i(left, ground_y, width, world.size.y - ground_y + MARGIN), p["earth"])
	draw_rect(Rect2i(left, ground_y, width, 3), p["ground"])


## A dim wall behind every built floor unit, so an empty floor reads as an empty box in the cutaway.
func _draw_backdrop(canvas: CanvasItem) -> void:
	var wall: Color = (Palette.get_palette()["wall"] as Color).lightened(0.12)
	for rect: Rect2i in _floor_rects:
		canvas.draw_rect(rect, wall)


## Built floor units: a thin slab along the bottom of each floor's row.
func _draw_floors(canvas: CanvasItem) -> void:
	var slab: Color = Palette.get_palette()["slab"]
	var highlight: Color = Palette.get_palette()["slab_hi"]
	for rect: Rect2i in _floor_rects:
		canvas.draw_rect(Rect2i(rect.position.x, rect.end.y - VC.SLAB_H, rect.size.x, VC.SLAB_H), slab)
		canvas.draw_rect(Rect2i(rect.position.x, rect.end.y - VC.SLAB_H, rect.size.x, 1), highlight)  # 1 px lit edge


## The ground lobby over floors 1 to its height, with the lobby recipe on its bottom floor.
func _draw_lobby(canvas: CanvasItem) -> void:
	var span := tower.floors.lobby_span()
	if span.is_empty():
		return
	var rect := Rect2i(span[0] * VC.CELL_W, VC.floor_to_row(span[2]) * VC.CELL_H, (span[1] - span[0] + 1) * VC.CELL_W, span[2] * VC.CELL_H)
	RoomLook.draw_recipe(canvas, "lobby", rect, Palette.hue("lobby"), true)


func _draw_rooms(canvas: CanvasItem) -> void:
	var broken: Array[int] = Parking.broken_ids(tower.rooms, tower.grid)  # cut-off parking is crossed out
	for run: Array in _room_runs:
		RoomLook.draw(canvas, tower, run[0], run[2], broken, _in_use.has(run[1]))


## Stairs and escalators (the link layer) in front of the rooms: each spans its own floor and the one
## above, climbing to the right across its width.
func _draw_links(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	for run: Array in _link_runs:
		_draw_link(canvas, p, run[0], run[1])


## One link in its two-floor rect. The tread climbs one floor over the width: filled steps for
## stairs, a slanted belt with handrail and slats for an escalator.
func _draw_link(canvas: CanvasItem, p: Dictionary, kind: String, span: Rect2i) -> void:
	var hue := Palette.hue(kind)
	var base_y := span.end.y - VC.SLAB_H  # the lower floor's surface
	var rise := VC.CELL_H
	canvas.draw_rect(Rect2i(span.position.x, span.position.y, span.size.x, span.size.y - VC.SLAB_H), (p["wall"] as Color).lightened(0.05))
	var outline: Color = p["outline"]
	if kind == "stairs":
		var steps := maxi(span.size.x / 4, 1)
		for i in steps:
			var top := base_y - (i + 1) * rise / steps
			var x := span.position.x + i * span.size.x / steps
			var w := span.position.x + (i + 1) * span.size.x / steps - x
			canvas.draw_rect(Rect2i(x, top, w, base_y - top), hue)
			canvas.draw_rect(Rect2i(x, top, w, 1), hue.lightened(0.35))
			canvas.draw_rect(Rect2i(x, top - 7, 1, 1), outline)  # rail posts
	else:
		for x in range(0, span.size.x, 2):
			var y := base_y - (x + 1) * rise / span.size.x
			canvas.draw_rect(Rect2i(span.position.x + x, y - 3, 2, 4), hue if (x / 2) % 2 == 0 else hue.darkened(0.25))
			canvas.draw_rect(Rect2i(span.position.x + x, y - 9, 2, 1), outline)
	canvas.draw_rect(Rect2i(span.position.x, span.position.y, 1, span.size.y - VC.SLAB_H), p["wall"])


## Remembers where the moving figures were, so the next tick's positions can be glided to.
func _remember_positions() -> void:
	_from.clear()
	for figure: Dictionary in _figures:
		if figure["moving"]:
			_from[figure["id"]] = Vector2(figure["fx"], figure["frow"])


## Where a figure is drawn now, as a fractional column and row: a moving one glides from its last
## tick's spot, but a jump of more than a few columns or a floor (a new trip) snaps instead.
func _shown_at(figure: Dictionary) -> Vector2:
	var now := Vector2(figure["fx"], figure["frow"])
	if not figure["moving"] or not _from.has(figure["id"]):
		return now
	var before: Vector2 = _from[figure["id"]]
	if absf(now.x - before.x) > GLIDE_MAX_COLUMNS or absf(now.y - before.y) > 1.5:
		return now
	return before.lerp(now, clampf(_since_tick / _tick_len, 0.0, 1.0))


## One figure, FIGURE_W x FIGURE_H, feet at `feet`: head, body, legs, then the stress marks above.
## Everything is sized from the figure constants so a bigger figure needs no change here. pose and
## phase choose the frame: walking alternates legs apart and together every half column, stairs
## lift one leg and bob, an escalator rider stands with legs together.
func _draw_figure(canvas: CanvasItem, x: int, feet: int, shirt: Color, band: int, skin: Color, pose: int = 0, phase: int = 0) -> void:
	var head_h := maxi(FIGURE_H / 3, 2)
	var leg_h := maxi(FIGURE_H / 4, 1)
	var bob := 1 if pose == PeopleView.POSE_STAIRS and phase % 2 == 1 else 0
	var top := feet - FIGURE_H - bob
	var legs := shirt.darkened(0.4)
	canvas.draw_rect(Rect2i(x, top, FIGURE_W, head_h), skin)  # head
	canvas.draw_rect(Rect2i(x, top + head_h, FIGURE_W, FIGURE_H - head_h - leg_h), shirt)  # body
	var leg_y := feet - leg_h - bob
	var apart := (pose == PeopleView.POSE_WALK and phase % 2 == 0) or pose == PeopleView.POSE_STAIRS
	var raised_left := pose == PeopleView.POSE_STAIRS and phase < 2
	var raised_right := pose == PeopleView.POSE_STAIRS and phase >= 2
	if apart:
		canvas.draw_rect(Rect2i(x, leg_y - (1 if raised_left else 0), 1, leg_h), legs)
		canvas.draw_rect(Rect2i(x + FIGURE_W - 1, leg_y - (1 if raised_right else 0), 1, leg_h), legs)
	else:  # together, under the middle
		canvas.draw_rect(Rect2i(x + FIGURE_W / 2, leg_y, 1, leg_h), legs)
		canvas.draw_rect(Rect2i(x + (FIGURE_W - 1) / 2, leg_y, 1, leg_h), legs)
	for mark in PeopleView.marks_of(band):  # shape cue: one dot uneasy, two angry
		canvas.draw_rect(Rect2i(x + mark * 2 - 2, top - 2, 1, 1), shirt)


func _draw_people(canvas: CanvasItem) -> void:
	var skin: Color = Palette.get_palette()["skin"]
	var types: Array = Palette.get_palette()["people"]
	for figure: Dictionary in _figures:
		var band: int = figure["band"]
		var at := _shown_at(figure)
		var x := roundi(at.x * VC.CELL_W) + (VC.CELL_W - FIGURE_W) / 2
		var feet := roundi((at.y + 1.0) * VC.CELL_H) - 3
		var pose: int = figure["pose"]
		var phase := int(at.x * 2.0) & 1
		if pose == PeopleView.POSE_STAIRS:
			phase = int(at.x * 4.0) & 3
		# A colour per type (a stand-in until the sim has types: the person's id); a stressed
		# person wears the band colour instead, so the mood still reads at a glance.
		var shirt: Color = types[(figure["id"] as int) % types.size()] if band == 0 else PeopleView.color_of(band)
		_draw_figure(canvas, x, feet, shirt, band, skin, pose, phase)


## Each shaft across its span; a floor it stops at has door slits, a disabled one a red cross.
func _draw_shafts(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var shaft_color := Palette.hue("shaft")
	var edge: Color = shaft_color.lightened(0.4)
	var door: Color = shaft_color.lightened(0.5)
	for shaft: Dictionary in ElevatorView.shafts(tower):
		var top_row := VC.floor_to_row(shaft["top"])
		var bottom_row := VC.floor_to_row(shaft["bottom"])
		var rect := Rect2i((shaft["x"] as int) * VC.CELL_W, top_row * VC.CELL_H, (shaft["width"] as int) * VC.CELL_W, (bottom_row - top_row + 1) * VC.CELL_H)
		canvas.draw_rect(rect, shaft_color)
		canvas.draw_rect(Rect2i(rect.position.x + rect.size.x / 2, rect.position.y, 1, rect.size.y), edge.darkened(0.3))
		canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, 1, rect.size.y), edge)
		canvas.draw_rect(Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y), edge)
		for machine: int in Tower.RoomsScript.machine_floors(shaft["bottom"], shaft["top"]):  # the machine-room caps (#228)
			canvas.draw_rect(Rect2i(rect.position.x, VC.floor_to_row(machine) * VC.CELL_H, rect.size.x, VC.CELL_H - VC.SLAB_H), shaft_color.lightened(0.15))
		for floor_number: int in shaft["stops"]:
			var yb := (VC.floor_to_row(floor_number) + 1) * VC.CELL_H - VC.SLAB_H
			canvas.draw_rect(Rect2i(rect.position.x + 2, yb - 16, 1, 16), door)
			canvas.draw_rect(Rect2i(rect.end.x - 3, yb - 16, 1, 16), door)
		for floor_number: int in shaft["disabled"]:
			var top := VC.floor_to_row(floor_number) * VC.CELL_H
			var red: Color = p["red"]
			for n in 8:  # a pixel-stepped cross
				canvas.draw_rect(Rect2i(rect.position.x + 6 + n, top + 6 + n, 1, 1), red)
				canvas.draw_rect(Rect2i(rect.position.x + 13 - n, top + 6 + n, 1, 1), red)


## Cars at their interpolated place, each showing its load as pips (one per person up to ten).
func _draw_cars(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var car_color := Palette.hue("car")
	var t := clampf(_since_tick / _tick_len, 0.0, 1.0)
	for car: Dictionary in _elevators.cars(tower, t):
		var x: int = (car["x"] as int) * VC.CELL_W + 3
		var y := roundi(ElevatorView.level_to_y(car["level"], VC.CELL_H)) + 3
		var w: int = (car["width"] as int) * VC.CELL_W - 6
		var h := VC.CELL_H - VC.SLAB_H - 3
		canvas.draw_rect(Rect2i(x - 1, y - 1, w + 2, h + 2), (p["outline"] as Color))
		canvas.draw_rect(Rect2i(x, y, w, h), car_color)
		canvas.draw_rect(Rect2i(x + w / 2, y, 1, h), car_color.darkened(0.3))
		for n in mini(car["load"] as int, 10):
			canvas.draw_rect(Rect2i(x + 2 + (n % 5) * 4, y + 3 + (n / 5) * 5, 2, 4), p["ink"])


## Hall queues: people going up wait left of the shaft, going down right of it; a long queue shows
## its first figures and a +N count.
func _draw_queues(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var ink: Color = p["ink"]
	var skin: Color = p["skin"]
	for queue: Dictionary in ElevatorView.queues(tower):
		var side: int = queue["side"]
		var feet := (VC.floor_to_row(queue["floor"]) + 1) * VC.CELL_H - 3
		var edge: int = (queue["x"] as int) * VC.CELL_W if side < 0 else ((queue["x"] as int) + (queue["width"] as int)) * VC.CELL_W
		for n: int in queue["shown"]:
			var x := edge - (n + 1) * (FIGURE_W + 2) if side < 0 else edge + 2 + n * (FIGURE_W + 2)
			_draw_figure(canvas, x, feet, ink.lightened(0.35), 0, skin)
		var label: String = queue["label"]
		if label != "":
			var shown_px: int = (queue["shown"] as int) * (FIGURE_W + 2)
			var label_x := edge - shown_px - 16 if side < 0 else edge + shown_px + 4
			canvas.draw_string(ThemeDB.fallback_font, Vector2(label_x, feet), label, HORIZONTAL_ALIGNMENT_LEFT, 16, 8, ink)
