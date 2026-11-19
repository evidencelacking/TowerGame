extends RefCounted
## Native-shape looks for the M6 room kinds (#155): hotel single/twin/suite (clean, dirty,
## occupied, infested), housekeeping station, fast food, restaurant and retail (leased, vacant).
## M7 adds (#174) security office, medical centre, recycling centre (two floors; a rubbish level
## that rises, idle when full), parking ramp and parking space (broken when cut off from the ramp).
## describe() reads sim state only; draw() paints into a canvas item with drawn shapes, no images.
## Each kind has its own base colour and its own glyph, so kinds stay apart at any zoom: the colour
## carries it when far out, the glyph when close.

const HotelScript := preload("res://scripts/sim/hotel.gd")
const RecyclingScript := preload("res://scripts/sim/recycling.gd")

## States, as names so tests and the info text can read them.
const CLEAN := "clean"
const DIRTY := "dirty"
const OCCUPIED := "occupied"
const INFESTED := "infested"
const LEASED := "leased"
const VACANT := "vacant"
const OPEN := "open"
const IDLE := "idle"  ## A full recycling centre: it takes nothing until the truck comes.
const BROKEN := "broken"  ## Parking cut off from its ramp.

const SINGLE_COLOR := Color(0.93, 0.80, 0.55)
const TWIN_COLOR := Color(0.95, 0.68, 0.30)
const SUITE_COLOR := Color(0.75, 0.55, 0.85)
const HOUSEKEEPING_COLOR := Color(0.45, 0.82, 0.80)
const FAST_FOOD_COLOR := Color(0.95, 0.45, 0.20)
const RESTAURANT_COLOR := Color(0.62, 0.20, 0.28)
const RETAIL_COLOR := Color(0.60, 0.85, 0.55)
const SECURITY_COLOR := Color(0.30, 0.42, 0.68)
const MEDICAL_COLOR := Color(0.93, 0.96, 0.96)
const RECYCLING_COLOR := Color(0.45, 0.65, 0.40)
const IDLE_TINT := Color(0.52, 0.55, 0.50)
const RUBBISH_COLOR := Color(0.45, 0.33, 0.20, 0.85)
const RAMP_COLOR := Color(0.50, 0.50, 0.55)
const SPACE_COLOR := Color(0.62, 0.62, 0.68)
const BROKEN_COLOR := Color(0.85, 0.15, 0.15)
const VACANT_COLOR := Color(0.62, 0.66, 0.60)
const DIRTY_TINT := Color(0.42, 0.34, 0.26)
const INFESTED_TINT := Color(0.32, 0.38, 0.22)
const GLOW_COLOR := Color(1.0, 0.93, 0.50)
const PEST_COLOR := Color(0.85, 0.10, 0.10)
const SHADE := Color(0, 0, 0, 0.45)
const INK := Color(0.10, 0.08, 0.08)

const KINDS: Array[String] = ["hotel_single", "hotel_twin", "hotel_suite", "housekeeping", "fast_food", "restaurant", "retail", "security", "medical", "recycling", "parking_ramp", "parking_space"]


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
		"security": return SECURITY_COLOR
		"medical": return MEDICAL_COLOR
		"recycling": return RECYCLING_COLOR
		"parking_ramp": return RAMP_COLOR
		"parking_space": return SPACE_COLOR
	return Color(0.85, 0.2, 0.85)


## {"kind", "state", "color", "fill"} for a placed room (room_id may be the upper half of a tall
## one). fill is the recycling centre's rubbish in thousandths of capacity, else 0. Pure read of the
## tower. broken lists the cut-off parking ids when the caller already has them (one search per
## frame, not per room); null finds them here.
static func describe(tower: Tower, room_id: int, broken: Variant = null) -> Dictionary:
	var id := tower.rooms.room_of(room_id)
	var kind := tower.rooms.kind_of(id)
	var fill := 0
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
	elif kind == "recycling":
		fill = tower.recycling.fill_of(id) * 1000 / RecyclingScript.CAPACITY
		if tower.recycling.is_idle(id):
			state = IDLE
			color = IDLE_TINT
	elif Parking.is_parking(kind):
		var cut_off: Array[int] = broken if broken != null else Parking.broken_ids(tower.rooms, tower.grid)
		if cut_off.has(id):
			state = BROKEN
			color = color.darkened(0.35)
	return {"kind": kind, "state": state, "color": color, "fill": fill}


## Paints one room's run into rect (already in the canvas item's pixels).
## id may be either half of a recycling centre; each half is painted in its own rect. broken is as
## for describe().
static func draw(canvas: CanvasItem, tower: Tower, id: int, rect: Rect2i, broken: Variant = null) -> void:
	var look := describe(tower, id, broken)
	var upper := tower.rooms.is_tall_upper(id)
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
		"security": _security(canvas, rect)
		"medical": _medical(canvas, rect)
		"recycling": _recycling(canvas, rect, state, int(look["fill"]), upper)
		"parking_ramp": _ramp(canvas, rect)
		"parking_space": _space(canvas, rect, id)
	var edge := color.darkened(0.5)
	if state == VACANT:
		_dashed_border(canvas, rect, edge)
	else:
		canvas.draw_rect(rect, edge, false, 1.0)
	if state == BROKEN:  # a red cross: this parking does not count
		canvas.draw_line(Vector2(rect.position), Vector2(rect.end), BROKEN_COLOR, 2.0)
		canvas.draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), BROKEN_COLOR, 2.0)
	if state == IDLE:
		canvas.draw_rect(rect.grow(-1), PEST_COLOR, false, 2.0)
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


## A bank of three monitors with green traces over a desk, and a gold shield badge.
static func _security(canvas: CanvasItem, rect: Rect2i) -> void:
	for n in 3:
		var x := rect.position.x + 4 + n * 11
		if x + 9 > rect.end.x - 14:
			break
		canvas.draw_rect(Rect2i(x, rect.position.y + 3, 9, 6), INK)
		canvas.draw_rect(Rect2i(x + 1, rect.position.y + 4, 7, 4), Color(0.20, 0.45, 0.30))
		canvas.draw_line(Vector2(x + 1, rect.position.y + 7), Vector2(x + 4, rect.position.y + 5), Color(0.55, 1.0, 0.6), 1.0)
		canvas.draw_line(Vector2(x + 4, rect.position.y + 5), Vector2(x + 7, rect.position.y + 7), Color(0.55, 1.0, 0.6), 1.0)
	canvas.draw_rect(Rect2i(rect.position.x + 2, rect.end.y - 5, rect.size.x - 4, 3), Color(0.20, 0.14, 0.10))
	var cx := rect.end.x - 8
	var top := rect.position.y + 3
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, top), Vector2(cx + 5, top), Vector2(cx + 5, top + 5), Vector2(cx, top + 10), Vector2(cx - 5, top + 5)]), Color(1.0, 0.85, 0.2))
	canvas.draw_rect(Rect2i(cx - 1, top + 2, 2, 4), SECURITY_COLOR)


## A red cross on the wall and a bed with a drip stand.
static func _medical(canvas: CanvasItem, rect: Rect2i) -> void:
	var cx := rect.position.x + 9
	var cy := rect.position.y + 8
	canvas.draw_rect(Rect2i(cx - 2, cy - 6, 4, 12), BROKEN_COLOR)
	canvas.draw_rect(Rect2i(cx - 6, cy - 2, 12, 4), BROKEN_COLOR)
	for x in range(rect.position.x + 22, rect.end.x - 18, 40):
		canvas.draw_rect(Rect2i(x, rect.end.y - 7, 18, 4), Color(0.55, 0.78, 0.92))
		canvas.draw_rect(Rect2i(x, rect.end.y - 9, 4, 3), Color(0.98, 0.98, 1.0))
		canvas.draw_rect(Rect2i(x, rect.end.y - 3, 2, 3), SHADE)
		canvas.draw_rect(Rect2i(x + 16, rect.end.y - 3, 2, 3), SHADE)
		canvas.draw_line(Vector2(x + 21, rect.end.y - 3), Vector2(x + 21, rect.position.y + 4), Color(0.45, 0.45, 0.50), 1.0)
		canvas.draw_rect(Rect2i(x + 19, rect.position.y + 4, 4, 5), Color(0.75, 0.90, 1.0))


## One half of a recycling centre. Brown rubbish rises from the bottom of the lower half through the
## upper (fill is thousandths of capacity); bins sit on the lower half and pipes on the upper. A full
## centre is idle: grey, with a red frame and a pause mark.
static func _recycling(canvas: CanvasItem, rect: Rect2i, state: String, fill: int, upper: bool) -> void:
	var level := rect.size.y * 2 * fill / 1000  # pixels of rubbish over both halves
	var here := clampi(level - (rect.size.y if upper else 0), 0, rect.size.y)
	if upper:
		canvas.draw_line(Vector2(rect.position.x + 2, rect.position.y + 4), Vector2(rect.end.x - 2, rect.position.y + 4), Color(0.30, 0.45, 0.30), 2.0)
		for x in range(rect.position.x + 10, rect.end.x - 6, 24):
			canvas.draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y), Color(0.30, 0.45, 0.30), 2.0)
	else:
		for x in range(rect.position.x + 4, rect.end.x - 12, 16):
			canvas.draw_rect(Rect2i(x, rect.end.y - 10, 10, 8), Color(0.25, 0.55, 0.30))
			canvas.draw_rect(Rect2i(x - 1, rect.end.y - 11, 12, 2), Color(0.18, 0.40, 0.22))
			canvas.draw_rect(Rect2i(x + 4, rect.end.y - 8, 2, 4), Color(0.9, 1.0, 0.9))
	if here > 0:
		canvas.draw_rect(Rect2i(rect.position.x, rect.end.y - here, rect.size.x, here), RUBBISH_COLOR)
		canvas.draw_line(Vector2(rect.position.x, rect.end.y - here), Vector2(rect.end.x, rect.end.y - here), Color(0.30, 0.20, 0.10), 1.0)
	if state == IDLE and not upper:
		var c := Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y + rect.size.y / 2.0)
		canvas.draw_circle(c, 7.0, Color(1, 1, 1, 0.9))
		canvas.draw_rect(Rect2(c.x - 3, c.y - 4, 2, 8), PEST_COLOR)
		canvas.draw_rect(Rect2(c.x + 1, c.y - 4, 2, 8), PEST_COLOR)


## A ramp: a dark slope wedge with yellow chevrons climbing it.
static func _ramp(canvas: CanvasItem, rect: Rect2i) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(rect.position.x + 1, rect.end.y - 2), Vector2(rect.end.x - 1, rect.end.y - 2), Vector2(rect.end.x - 1, rect.position.y + 3)]), Color(0.28, 0.28, 0.33))
	for x in range(rect.position.x + 8, rect.end.x - 6, 10):
		var y := rect.end.y - 3 - (x - rect.position.x) * (rect.size.y - 6) / maxi(rect.size.x, 1)
		canvas.draw_line(Vector2(x - 2, y), Vector2(x, y - 3), Color(1.0, 0.85, 0.2), 1.0)
		canvas.draw_line(Vector2(x, y - 3), Vector2(x + 2, y), Color(1.0, 0.85, 0.2), 1.0)


## Bays marked in white, a car in every other one (its colour from the room id, so it stays put).
static func _space(canvas: CanvasItem, rect: Rect2i, id: int) -> void:
	var cars: Array[Color] = [Color(0.80, 0.25, 0.25), Color(0.25, 0.45, 0.80), Color(0.90, 0.80, 0.25), Color(0.30, 0.65, 0.40)]
	var n := 0
	for x in range(rect.position.x, rect.end.x - 15, 16):
		canvas.draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y - 2), Color(1, 1, 1, 0.8), 1.0)
		if (n + id) % 2 == 0:
			var car := cars[(n + id) % cars.size()]
			canvas.draw_rect(Rect2i(x + 3, rect.end.y - 9, 11, 5), car)
			canvas.draw_rect(Rect2i(x + 5, rect.end.y - 11, 6, 3), car.lightened(0.4))
			canvas.draw_circle(Vector2(x + 5, rect.end.y - 4), 1.2, INK)
			canvas.draw_circle(Vector2(x + 12, rect.end.y - 4), 1.2, INK)
		n += 1
	canvas.draw_line(Vector2(rect.end.x - 1, rect.position.y + 4), Vector2(rect.end.x - 1, rect.end.y - 2), Color(1, 1, 1, 0.8), 1.0)


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
