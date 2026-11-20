extends RefCounted
## Room looks. describe() reads the sim for the stateful kinds (#155, #174): hotel (clean, dirty,
## occupied, infested), retail (leased, vacant), recycling (fill, idle), parking (broken when cut off
## from its ramp). draw() (10.2) paints any kind from its recipe (room_recipes.gd) in the palette in
## use (palette.gd) at native resolution, in an empty or an in-use look, with the state marks over it.
## No images. The colour constants below are the info-panel and legend colours.

const HotelScript := preload("res://scripts/sim/hotel.gd")
const RecyclingScript := preload("res://scripts/sim/recycling.gd")
const Palette := preload("res://scripts/view/palette.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")

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
const GYM_COLOR := Color(0.28, 0.72, 0.70)
const DAYCARE_COLOR := Color(0.94, 0.44, 0.72)
const CLINIC_COLOR := Color(0.88, 0.94, 0.94)
const NIGHTCLUB_COLOR := Color(0.36, 0.20, 0.52)
const COWORKING_COLOR := Color(0.86, 0.80, 0.62)
const DECK_COLOR := Color(0.40, 0.66, 0.84)
const CASINO_COLOR := Color(0.62, 0.12, 0.20)
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

const KINDS: Array[String] = ["hotel_single", "hotel_twin", "hotel_suite", "housekeeping", "fast_food", "restaurant", "retail", "security", "medical", "recycling", "parking_ramp", "parking_space", "gym", "daycare", "clinic", "nightclub", "coworking", "observation_deck", "casino"]


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
		"gym": return GYM_COLOR
		"daycare": return DAYCARE_COLOR
		"clinic": return CLINIC_COLOR
		"nightclub": return NIGHTCLUB_COLOR
		"coworking": return COWORKING_COLOR
		"observation_deck": return DECK_COLOR
		"casino": return CASINO_COLOR
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


## Paints one room's run into rect (native pixels in the canvas item). id may be either half of a
## recycling centre; each half is painted in its own rect. broken is as for describe(). lit is the
## in-use look: someone is there (the renderer works it out once per refresh); an empty room is dim.
static func draw(canvas: Object, tower: Tower, id: int, rect: Rect2i, broken: Variant = null, lit: bool = false, dark: bool = false) -> void:
	var look := describe(tower, id, broken)
	var kind: String = look["kind"]
	var state: String = look["state"]
	var upper := tower.rooms.is_tall_upper(id)
	var in_use := (lit or state == OCCUPIED or state == LEASED) and not dark  # dark: everyone in it is asleep
	var p := Palette.get_palette()
	var base := Palette.hue(RoomRecipes.hue_key(kind))
	if state == DIRTY or state == INFESTED or state == IDLE or state == VACANT:
		base = look["color"]  # the state tint replaces the hue
	elif state == BROKEN:
		base = base.darkened(0.35)
	draw_recipe(canvas, kind, rect, base, in_use, upper, id)
	var edge: Color = p["outline"]
	var interior := Rect2i(rect.position.x, rect.end.y - VC.CELL_H, rect.size.x, VC.CELL_H - VC.SLAB_H)
	if state == VACANT:
		_dashed_border(canvas, interior, edge)
	if state == BROKEN:  # a red cross: this parking does not count
		canvas.draw_line(Vector2(interior.position), Vector2(interior.end), p["red"], 1.0)
		canvas.draw_line(Vector2(interior.position.x, interior.end.y), Vector2(interior.end.x, interior.position.y), p["red"], 1.0)
	if state == IDLE or state == INFESTED:
		canvas.draw_rect(interior.grow(-1), p["red"], false, 1.0)
	if state == INFESTED:
		_bug(canvas, Vector2i(interior.position.x + interior.size.x / 2, interior.position.y + 11), p)
	if state == DIRTY:
		for n in 3:
			canvas.draw_rect(Rect2i(interior.position.x + 6 + n * maxi((interior.size.x - 12) / 3, 4), interior.position.y + 15 + (n % 2) * 3, 2, 2), p["ink"])
	if kind == "recycling" and int(look["fill"]) > 0:
		_rubbish(canvas, interior, int(look["fill"]), upper)


## A joined suite (#276): one lit space over rect, the union of its rooms, drawn from the kind's suite
## recipe. The rooms lose their shared walls because only the leftmost wall is drawn. id is the first
## room's, for the colours that depend on it.
static func draw_suite(canvas: Object, kind: String, rect: Rect2i, id: int) -> void:
	draw_recipe(canvas, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true, false, id, true)


## The room body and recipe shapes in rect. A rect taller than a floor (the lobby) gets the recipe on its
## bottom floor and plain wall above. base is the room colour; lit picks the in-use or empty look.
static func draw_recipe(canvas: Object, kind: String, rect: Rect2i, base: Color, lit: bool, upper: bool = false, id: int = 0, suite: bool = false) -> void:
	var p := Palette.get_palette()
	var mode: int = p["mode"]
	var body := base if lit else base.darkened(SkyLook.dim_at(p["dim"], SkyLook.daylight))
	var interior_h := VC.CELL_H - VC.SLAB_H
	var body_rect := Rect2i(rect.position.x, rect.position.y, rect.size.x, rect.size.y - VC.SLAB_H)
	canvas.draw_rect(body_rect, body)
	if lit and mode != Palette.MODE_FLAT:
		canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, 3), body.lightened(0.18))
	canvas.draw_rect(Rect2i(rect.position.x, body_rect.end.y - 2, rect.size.x, 2), body.darkened(0.25))
	canvas.draw_rect(Rect2i(rect.position.x, rect.position.y, p["wall_w"], body_rect.size.y), p["wall"])
	if mode == Palette.MODE_LINE:
		canvas.draw_rect(Rect2i(rect.position.x + 1, rect.position.y, rect.size.x - 1, body_rect.size.y), (p["outline"] as Color).darkened(0.3), false, 1.0)
	var colors := _role_colors(p, base, lit, id)
	var top := body_rect.end.y - interior_h
	for shape: Array in RoomRecipes.layout(kind, rect.size.x, upper, RoomRecipes.SUITE if suite else RoomRecipes.variant_for(kind, id))["shapes"]:
		var gate: String = shape[5]
		if gate != "" and (gate == "use") != lit:  # "use" shapes show only while in use, "idle" ones only while empty
			continue
		_box(canvas, Rect2i(rect.position.x + (shape[0] as int), top + (shape[1] as int), shape[2] as int, shape[3] as int), colors[shape[4]], mode, p["outline"], shape[4] == "furn")


## Role -> colour for one room in the palette in use.
static func _role_colors(p: Dictionary, base: Color, lit: bool, id: int) -> Dictionary:
	var mode: int = p["mode"]
	var furn: Color = base.lightened(0.3 if mode == Palette.MODE_FLAT else 0.18)
	if lit:
		furn = base.darkened(0.45 if mode == Palette.MODE_LINE else p["furn"])
	var people: Array = p["people"]
	var white: Color = p["white"]
	return {
		"furn": furn, "accent": base.lightened(0.4), "lamp": p["lamp"] if lit else p["lamp_off"],
		"window": SkyLook.window_color(p, lit, SkyLook.daylight, SkyLook.rain), "ink": p["ink"], "white": white if lit else white.darkened(0.35),
		"red": p["red"], "gold": p["gold"], "green": p["green"], "wood": p["wood"],
		"car": people[id % people.size()],
	}


## A furniture box in the palette's style: outlined (A), edges only for furniture frames (B) or flat (C).
## Only a hollow shape (the "furn" role) is a frame in B; every other role is a solid fill.
static func _box(canvas: Object, r: Rect2i, color: Color, mode: int, outline: Color, hollow: bool = true) -> void:
	if mode == Palette.MODE_OUTLINED:
		canvas.draw_rect(r.grow(1), outline)
		canvas.draw_rect(r, color)
	elif mode == Palette.MODE_LINE and hollow and r.size.x > 2 and r.size.y > 2:
		canvas.draw_rect(r, color, false, 1.0)
	else:
		canvas.draw_rect(r, color)


## Rubbish rising over both halves of a recycling centre (fill is thousandths of capacity); interior is
## the half's floor rows.
static func _rubbish(canvas: Object, interior: Rect2i, fill: int, upper: bool) -> void:
	var level := interior.size.y * 2 * fill / 1000
	var here := clampi(level - (interior.size.y if upper else 0), 0, interior.size.y)
	if here > 0:
		canvas.draw_rect(Rect2i(interior.position.x, interior.end.y - here, interior.size.x, here), RUBBISH_COLOR)


static func _dashed_border(canvas: Object, interior: Rect2i, color: Color) -> void:
	for x in range(interior.position.x, interior.end.x, 4):
		var w := mini(2, interior.end.x - x)
		canvas.draw_rect(Rect2i(x, interior.position.y, w, 1), color)
		canvas.draw_rect(Rect2i(x, interior.end.y - 1, w, 1), color)


## Infested marker: a pest (body and legs) on a white badge, in the middle of the room.
static func _bug(canvas: Object, c: Vector2i, p: Dictionary) -> void:
	canvas.draw_rect(Rect2i(c.x - 4, c.y - 4, 9, 9), p["white"])
	canvas.draw_rect(Rect2i(c.x - 2, c.y - 2, 5, 5), p["ink"])
	for dy in [-2, 0, 2]:
		canvas.draw_rect(Rect2i(c.x - 4, c.y + dy, 2, 1), p["ink"])
		canvas.draw_rect(Rect2i(c.x + 3, c.y + dy, 2, 1), p["ink"])
