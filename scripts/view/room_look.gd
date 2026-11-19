extends RefCounted
## Native-shape looks for the M6 room kinds (#155): hotel single/twin/suite (clean, dirty,
## occupied, infested), housekeeping station, fast food, restaurant and retail (leased, vacant).
## describe() reads sim state only; draw() paints into a canvas item with drawn shapes, no images.
## Each kind has its own base colour and its own glyph, so kinds stay apart at any zoom: the colour
## carries it when far out, the glyph when close.

const HotelScript := preload("res://scripts/sim/hotel.gd")

## States, as names so tests and the info text can read them.
const CLEAN := "clean"
const DIRTY := "dirty"
const OCCUPIED := "occupied"
const INFESTED := "infested"
const LEASED := "leased"
const VACANT := "vacant"
const OPEN := "open"

const SINGLE_COLOR := Color(0.93, 0.80, 0.55)
const TWIN_COLOR := Color(0.95, 0.68, 0.30)
const SUITE_COLOR := Color(0.75, 0.55, 0.85)
const HOUSEKEEPING_COLOR := Color(0.45, 0.82, 0.80)
const FAST_FOOD_COLOR := Color(0.95, 0.45, 0.20)
const RESTAURANT_COLOR := Color(0.62, 0.20, 0.28)
const RETAIL_COLOR := Color(0.60, 0.85, 0.55)
const VACANT_COLOR := Color(0.62, 0.66, 0.60)
const DIRTY_TINT := Color(0.42, 0.34, 0.26)
const INFESTED_TINT := Color(0.32, 0.38, 0.22)
const GLOW_COLOR := Color(1.0, 0.93, 0.50)
const PEST_COLOR := Color(0.85, 0.10, 0.10)
const SHADE := Color(0, 0, 0, 0.45)
const INK := Color(0.10, 0.08, 0.08)

const KINDS: Array[String] = ["hotel_single", "hotel_twin", "hotel_suite", "housekeeping", "fast_food", "restaurant", "retail"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


static func base_color(kind: String) -> Color:
	match kind:
		"hotel_single": return SINGLE_COLOR
		"hotel_twin": return TWIN_COLOR
		"hotel_suite": return SUITE_COLOR
		"housekeeping": return HOUSEKEEPING_COLOR
		"fast_food": return FAST_FOOD_COLOR
		"restaurant": return RESTAURANT_COLOR
		"retail": return RETAIL_COLOR
	return Color(0.85, 0.2, 0.85)


## {"kind", "state", "color"} for a placed room. Pure read of the tower.
static func describe(tower: Tower, id: int) -> Dictionary:
	var kind := tower.rooms.kind_of(id)
	var state := OPEN
	var color := base_color(kind)
	if tower.hotel.is_hotel(id):
		if tower.hotel.is_infested(id):
			state = INFESTED
			color = INFESTED_TINT
		elif tower.hotel.is_dirty(id):
			state = DIRTY
			color = DIRTY_TINT
		elif tower.hotel.state_of(id) == HotelScript.STAYING:
			state = OCCUPIED
			color = color.lerp(GLOW_COLOR, 0.55)
		else:
			state = CLEAN
	elif kind == "retail":
		if tower.commerce.is_vacant(id):
			state = VACANT
			color = VACANT_COLOR
		else:
			state = LEASED
	return {"kind": kind, "state": state, "color": color}


## Paints one room's run into rect (already in the canvas item's pixels).
static func draw(canvas: CanvasItem, tower: Tower, id: int, rect: Rect2i) -> void:
	var look := describe(tower, id)
	var color: Color = look["color"]
	var kind: String = look["kind"]
	var state: String = look["state"]
	canvas.draw_rect(rect, color)
	match kind:
		"hotel_single": _hotel(canvas, rect, 1, false, state)
		"hotel_twin": _hotel(canvas, rect, 2, false, state)
		"hotel_suite": _hotel(canvas, rect, 2, true, state)
		"housekeeping": _housekeeping(canvas, rect)
		"fast_food": _fast_food(canvas, rect)
		"restaurant": _restaurant(canvas, rect)
		"retail": _retail(canvas, rect, state)
	var edge := color.darkened(0.5)
	if state == VACANT:
		_dashed_border(canvas, rect, edge)
	else:
		canvas.draw_rect(rect, edge, false, 1.0)
	if state == INFESTED:
		canvas.draw_rect(rect.grow(-1), PEST_COLOR, false, 2.0)
		_bug(canvas, Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2))


## Beds across the room (one each; a suite adds a gold star). Dirty: stains and a grey bed;
## occupied: a sleeper under a blue blanket and a lit window.
static func _hotel(canvas: CanvasItem, rect: Rect2i, beds: int, suite: bool, state: String) -> void:
	var slot := rect.size.x / beds
	var bed_w := mini(slot - 4, 18)
	for n in beds:
		var x := rect.position.x + n * slot + (slot - bed_w) / 2
		var y := rect.end.y - 7
		canvas.draw_rect(Rect2i(x, y, bed_w, 4), Color(0.95, 0.95, 0.98) if state != DIRTY else Color(0.62, 0.55, 0.45))
		canvas.draw_rect(Rect2i(x, y - 2, 3, 3), Color(0.35, 0.25, 0.20))
		canvas.draw_rect(Rect2i(x, y + 4, 2, 2), SHADE)
		canvas.draw_rect(Rect2i(x + bed_w - 2, y + 4, 2, 2), SHADE)
		if state == OCCUPIED:
			canvas.draw_circle(Vector2(x + 5, y - 1), 2.0, Color(0.25, 0.15, 0.10))
			canvas.draw_rect(Rect2i(x + 4, y, bed_w - 5, 3), Color(0.30, 0.45, 0.75))
	if suite:
		var cx := rect.position.x + rect.size.x / 2
		var top := rect.position.y + 2
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx, top), Vector2(cx + 2, top + 3), Vector2(cx + 5, top + 3), Vector2(cx + 3, top + 5), Vector2(cx + 4, top + 8), Vector2(cx, top + 6), Vector2(cx - 4, top + 8), Vector2(cx - 3, top + 5), Vector2(cx - 5, top + 3), Vector2(cx - 2, top + 3)]), Color(1.0, 0.85, 0.2))
	if state == DIRTY:
		for n in 3:
			canvas.draw_circle(Vector2(rect.position.x + 6 + n * (rect.size.x - 8) / 3, rect.position.y + 5 + (n % 2) * 3), 1.5, Color(0.22, 0.16, 0.10))
	if state == OCCUPIED:
		canvas.draw_rect(Rect2i(rect.end.x - 7, rect.position.y + 2, 5, 4), GLOW_COLOR)


## A cleaning trolley: a white bin with a cross on wheels, plus a mop, repeated along the station.
static func _housekeeping(canvas: CanvasItem, rect: Rect2i) -> void:
	var x := rect.position.x + 6
	while x + 16 <= rect.end.x:
		var y := rect.end.y - 4
		canvas.draw_rect(Rect2i(x, y - 7, 10, 6), Color(0.95, 0.95, 0.98))
		canvas.draw_rect(Rect2i(x + 4, y - 6, 2, 4), Color(0.2, 0.45, 0.65))
		canvas.draw_rect(Rect2i(x + 3, y - 5, 4, 2), Color(0.2, 0.45, 0.65))
		canvas.draw_circle(Vector2(x + 2, y), 1.0, Color(0.15, 0.15, 0.2))
		canvas.draw_circle(Vector2(x + 8, y), 1.0, Color(0.15, 0.15, 0.2))
		canvas.draw_line(Vector2(x + 12, y), Vector2(x + 12, rect.position.y + 3), Color(0.45, 0.30, 0.15), 1.0)
		canvas.draw_rect(Rect2i(x + 10, y - 1, 5, 2), Color(0.9, 0.9, 0.6))
		x += 32


## A red and yellow striped awning across the top, a counter with burgers below.
static func _fast_food(canvas: CanvasItem, rect: Rect2i) -> void:
	var x := rect.position.x
	var n := 0
	while x < rect.end.x:
		canvas.draw_rect(Rect2i(x, rect.position.y + 1, mini(4, rect.end.x - x), 5), Color(0.95, 0.20, 0.15) if n % 2 == 0 else Color(1.0, 0.92, 0.35))
		x += 4
		n += 1
	canvas.draw_rect(Rect2i(rect.position.x + 2, rect.end.y - 5, rect.size.x - 4, 3), Color(0.35, 0.20, 0.12))
	for k in range(rect.position.x + 8, rect.end.x - 6, 16):
		canvas.draw_rect(Rect2i(k, rect.end.y - 9, 4, 4), Color(1.0, 0.92, 0.35))
		canvas.draw_rect(Rect2i(k, rect.end.y - 7, 4, 1), Color(0.35, 0.20, 0.12))


## Round tables with white cloths and a candle each, on a deep red room under a gilt rail.
static func _restaurant(canvas: CanvasItem, rect: Rect2i) -> void:
	for x in range(rect.position.x + 6, rect.end.x - 6, 12):
		var cy := rect.end.y - 6
		canvas.draw_rect(Rect2i(x - 1, cy, 2, 4), Color(0.9, 0.9, 0.9))
		canvas.draw_rect(Rect2i(x - 4, cy - 2, 8, 2), Color(0.97, 0.97, 0.97))
		canvas.draw_circle(Vector2(x, cy - 4), 1.5, Color(0.97, 0.85, 0.40))
	canvas.draw_line(Vector2(rect.position.x + 1, rect.position.y + 3), Vector2(rect.end.x - 2, rect.position.y + 3), Color(0.95, 0.80, 0.40), 1.0)


## Leased: shop windows with goods under a green awning edge. Vacant: grey empty panes, a slash,
## and a dashed border.
static func _retail(canvas: CanvasItem, rect: Rect2i, state: String) -> void:
	for x in range(rect.position.x + 2, rect.end.x - 8, 12):
		var pane := Rect2i(x, rect.position.y + 3, 9, 10)
		if state == VACANT:
			canvas.draw_rect(pane, Color(0.78, 0.80, 0.78), false, 1.0)
		else:
			canvas.draw_rect(pane, Color(0.70, 0.88, 0.98))
			canvas.draw_rect(Rect2i(x + 2, pane.end.y - 5, 5, 4), Color(0.95, 0.55, 0.20))
			canvas.draw_rect(Rect2i(x + 3, pane.end.y - 7, 3, 2), Color(0.85, 0.25, 0.30))
	if state == VACANT:
		canvas.draw_line(Vector2(rect.position.x + 2, rect.end.y - 2), Vector2(rect.end.x - 2, rect.position.y + 2), Color(0.45, 0.48, 0.45), 1.0)
	else:
		canvas.draw_rect(Rect2i(rect.position.x, rect.position.y + 1, rect.size.x, 2), Color(0.20, 0.55, 0.30))


static func _dashed_border(canvas: CanvasItem, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.end.x, 4):
		var w := mini(2, rect.end.x - x)
		canvas.draw_rect(Rect2i(x, rect.position.y, w, 1), color)
		canvas.draw_rect(Rect2i(x, rect.end.y - 1, w, 1), color)
	for y in range(rect.position.y, rect.end.y, 4):
		var h := mini(2, rect.end.y - y)
		canvas.draw_rect(Rect2i(rect.position.x, y, 1, h), color)
		canvas.draw_rect(Rect2i(rect.end.x - 1, y, 1, h), color)


## Infested marker: a red-ringed white pest badge (body, legs, antennae) in the middle of the room.
static func _bug(canvas: CanvasItem, c: Vector2i) -> void:
	canvas.draw_circle(Vector2(c), 7.0, Color(1, 1, 1, 0.9))
	canvas.draw_arc(Vector2(c), 7.0, 0.0, TAU, 16, PEST_COLOR, 1.5)
	canvas.draw_circle(Vector2(c), 3.0, INK)
	for s in [-1, 1]:
		for dy in [-2, 0, 2]:
			canvas.draw_line(Vector2(c.x + s * 2, c.y + dy), Vector2(c.x + s * 5, c.y + dy + dy / 2), INK, 1.0)
		canvas.draw_line(Vector2(c.x + s, c.y - 3), Vector2(c.x + s * 3, c.y - 6), INK, 1.0)
