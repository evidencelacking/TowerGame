extends RefCounted
## Room looks. describe() reads the sim for the stateful kinds (#155, #174): hotel (clean, dirty,
## occupied, infested), retail (leased, vacant), recycling (fill, idle), parking (broken when cut off
## from its ramp). draw() (10.2) paints any kind from its recipe (room_recipes.gd) in the palette in
## use (palette.gd) at native resolution, in an empty or an in-use look, with the state marks over it.
## No images. The colour constants below are the info-panel and legend colours.

const HotelScript := preload("res://scripts/sim/hotel.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
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
const CHARRED := "charred"  ## Burned out by a fire (#373): blackened, empty, earning nothing until repaired.

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
const PAD_COLOR := Color(0.46, 0.50, 0.56)  ## The helicopter pad (#409).
const BALLROOM_COLOR := Color(0.62, 0.30, 0.46)  ## The ballroom (#359): claret.
const CONFERENCE_COLOR := Color(0.36, 0.50, 0.66)  ## The conference center (#359): slate blue.
const SCHOOL_COLOR := Color(0.78, 0.40, 0.30)  ## The school (#370): brick red.
const GROCERY_COLOR := Color(0.52, 0.72, 0.42)
const DELI_COLOR := Color(0.88, 0.70, 0.40)
const CAFE_COLOR := Color(0.70, 0.52, 0.36)
const PIZZA_COLOR := Color(0.86, 0.42, 0.30)
const SUSHI_COLOR := Color(0.88, 0.52, 0.56)
const FINE_DINING_COLOR := Color(0.50, 0.20, 0.30)
const BAR_COLOR := Color(0.30, 0.34, 0.52)
const CASINO_COLOR := Color(0.62, 0.12, 0.20)
const POOL_COLOR := Color(0.28, 0.66, 0.78)
const RECYCLING_COLOR := Color(0.45, 0.65, 0.40)
const IDLE_TINT := Color(0.52, 0.55, 0.50)
const RUBBISH_COLOR := Color(0.45, 0.33, 0.20, 0.85)
const RAMP_COLOR := Color(0.50, 0.50, 0.55)
const SPACE_COLOR := Color(0.62, 0.62, 0.68)
const BROKEN_COLOR := Color(0.85, 0.15, 0.15)
const VACANT_COLOR := Color(0.62, 0.66, 0.60)
const CHARRED_COLOR := Color(0.13, 0.11, 0.10)
const SOOT := Color(0.04, 0.03, 0.03, 0.78)
const SCORCH := Color(0.02, 0.02, 0.02, 0.9)
const EMBER := Color(0.85, 0.34, 0.10)
const DIRTY_TINT := Color(0.42, 0.34, 0.26)
const INFESTED_TINT := Color(0.32, 0.38, 0.22)
const GLOW_COLOR := Color(1.0, 0.93, 0.50)
const PEST_COLOR := Color(0.85, 0.10, 0.10)
const SHADE := Color(0, 0, 0, 0.45)
const INK := Color(0.10, 0.08, 0.08)

const SPLASH_FRAME_TICKS := 2  ## Sim ticks per frame of the cannonball; PoolLife.SPLASH_TICKS / this frames in all.
const SPLASH_FRAMES := 5
const PoolLifeScript := preload("res://scripts/sim/pool_life.gd")
const KINDS: Array[String] = ["hotel_single", "hotel_twin", "hotel_suite", "housekeeping", "fast_food", "restaurant", "retail", "security", "medical", "recycling", "parking_ramp", "parking_space", "gym", "daycare", "clinic", "nightclub", "coworking", "observation_deck", "casino", "cafe", "pizza", "sushi", "fine_dining", "bar", "grocery", "deli", "helipad", "school", "ballroom", "conference_center", "pool"]


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
		"helipad": return PAD_COLOR
		"school": return SCHOOL_COLOR
		"ballroom": return BALLROOM_COLOR
		"conference_center": return CONFERENCE_COLOR
		"grocery": return GROCERY_COLOR
		"deli": return DELI_COLOR
		"cafe": return CAFE_COLOR
		"pizza": return PIZZA_COLOR
		"sushi": return SUSHI_COLOR
		"fine_dining": return FINE_DINING_COLOR
		"bar": return BAR_COLOR
		"casino": return CASINO_COLOR
		"pool": return POOL_COLOR
		"parking_ramp": return RAMP_COLOR
		"parking_space": return SPACE_COLOR
	return Color(0.85, 0.2, 0.85)


## {"kind", "state", "color", "fill"} for a placed room (room_id may be the upper half of a tall
## one). fill is the recycling centre's rubbish in thousandths of capacity, else 0. Pure read of the
## tower. broken lists the cut-off parking ids when the caller already has them (one search per
## frame, not per room); null finds them here.
static func describe(tower: Tower, room_id: int, broken: Variant = null, workers: Variant = null) -> Dictionary:
	var id := tower.rooms.room_of(room_id)
	var kind := tower.rooms.kind_of(id)
	var facts := state_facts(tower, id, kind, broken, workers)
	var state: String = facts[0]
	var color := base_color(kind)
	match state:
		CHARRED:
			return {"kind": kind, "state": CHARRED, "color": CHARRED_COLOR, "fill": 0, "empty": false}
		INFESTED:
			color = INFESTED_TINT
		DIRTY:
			color = DIRTY_TINT
		OCCUPIED:
			color = color.lerp(GLOW_COLOR, 0.55)
		VACANT:
			color = VACANT_COLOR
		IDLE:
			color = IDLE_TINT
		BROKEN:
			color = color.darkened(0.35)
	var out := {"kind": kind, "state": state, "color": color, "fill": facts[1], "empty": facts[2], "cut_off": facts[3]}
	if kind == PoolLifeScript.KIND:
		out.merge(_pool_life(tower, id))
	return out


## What describe() says of a room without its colours, the part a repaint hangs on: [state, fill, empty,
## cut_off]. id is the owning room and kind its kind. One source of truth for describe and the renderer's
## cheap per-tick signature, which skips building colours and a dictionary per room (#434).
static func state_facts(tower: Tower, id: int, kind: String, broken: Variant = null, workers: Variant = null) -> Array:
	if tower.rooms.is_charred(id):
		return [CHARRED, 0, false, false]
	var fill := 0
	var state := OPEN
	var empty := false  ## Unrented or unoccupied: drawn with the vacant look (#358).
	if HotelScript.is_hotel_kind(kind):
		if tower.hotel.is_infested(id):
			state = INFESTED
		elif tower.hotel.is_dirty(id):
			state = DIRTY
		elif tower.hotel.state_of(id) == HotelScript.STAYING:
			state = OCCUPIED
		else:
			state = CLEAN
			empty = true
	elif kind == "retail":
		if tower.commerce.is_vacant(id):
			state = VACANT
			empty = true
		else:
			state = LEASED
	elif kind == "office":
		var staff: int = int((workers as Dictionary).get(id, 0)) if workers != null else tower.people.workers_in(id)
		empty = staff == 0
	elif CatalogueScript.is_condo(kind):
		empty = not tower.rooms.is_sold(id)
	elif CatalogueScript.is_rental(kind):
		empty = tower.people.homes_in(id) == 0
	elif kind == "recycling":
		fill = tower.recycling.fill_of(id) * 1000 / RecyclingScript.CAPACITY
		if tower.recycling.is_idle(id):
			state = IDLE
	elif Parking.is_parking(kind):
		var cut_off: Array[int] = broken if broken != null else Parking.broken_ids(tower.rooms, tower.grid)
		if cut_off.has(id):
			state = BROKEN
	return [state, fill, empty, tower.rooms.is_cut_off(id)]


## The pool's moving parts for one frame (#328), from the clock and the room id, as the sim (pool_life.gd) has them: the
## swimmers in the water, whether it is shut for cleaning, whether the lifeguard is in her chair and the cannonball, as
## its splash frame (0 to SPLASH_FRAMES - 1, or -1) and the board place it left from. "anim" is all of it in one array,
## which the renderer compares to know when to repaint a pool.
static func _pool_life(tower: Tower, id: int) -> Dictionary:
	var minute: int = tower.clock.minute_of_day()
	var keeps: bool = PoolLifeScript.has_housekeeping(tower.rooms)
	var swimmers := PoolLifeScript.swimmers(tower.commerce.customers_today(id), minute, keeps)
	var cleaning := PoolLifeScript.is_cleaning(minute, keeps)
	var guard := PoolLifeScript.lifeguard_on_duty(minute)
	var age := PoolLifeScript.cannonball_age(id, tower.tick) if PoolLifeScript.is_open(minute, keeps) and swimmers > 0 else -1
	var frame := age / SPLASH_FRAME_TICKS if age >= 0 else -1
	var place := PoolLifeScript.jump_place(id, tower.tick) if age >= 0 else 0
	return {"swimmers": swimmers, "cleaning": cleaning, "guard": guard, "splash": frame, "place": place,
		"anim": [swimmers, cleaning, guard, frame, place]}


## Paints one room's run into rect (native pixels in the canvas item). id may be either half of a
## recycling centre; each half is painted in its own rect. broken is as for describe(). lit is the
## in-use look: someone is there (the renderer works it out once per refresh); an empty room is dim.
static func draw(canvas: Object, tower: Tower, id: int, rect: Rect2i, broken: Variant = null, lit: bool = false, dark: bool = false) -> void:
	var look := describe(tower, id, broken)
	var kind: String = look["kind"]
	var upper := tower.rooms.is_tall_upper(id)
	var shown := appearance(look, lit, dark)  # dark: everyone in it is asleep
	var base: Color = shown[0]
	var in_use: bool = shown[1]
	draw_recipe(canvas, kind, rect, base, in_use, upper, id)
	draw_marks(canvas, look, rect, upper)


## The base colour and in-use look of a placed room, from its describe() result: the state tint replaces
## the hue for dirty, infested, idle and vacant rooms. Returns [colour, in_use]. Shared by both graphics styles.
static func appearance(look: Dictionary, lit: bool, dark: bool) -> Array:
	var state: String = look["state"]
	var base := Palette.hue(RoomRecipes.hue_key(look["kind"]))
	if state == CHARRED:
		return [look["color"], false]
	if state == DIRTY or state == INFESTED or state == IDLE or state == VACANT:
		base = look["color"]
	elif state == BROKEN or bool(look.get("cut_off", false)):  # parking cut off from its ramp, or any room no route reaches (#368)
		base = base.darkened(0.35)
	return [base, (lit or state == OCCUPIED or state == LEASED) and not dark]


## The state marks over a drawn room (vacant border, broken cross, pest, dirt, rubbish), in world pixels.
static func draw_marks(canvas: Object, look: Dictionary, rect: Rect2i, upper: bool, fine: bool = false) -> void:
	var kind: String = look["kind"]
	var state: String = look["state"]
	var p := Palette.get_palette()
	var edge: Color = p["outline"]
	var interior := Rect2i(rect.position.x, rect.end.y - VC.CELL_H, rect.size.x, VC.CELL_H - VC.SLAB_H)
	if state == CHARRED:
		_charred_marks(canvas, interior)
		return
	if bool(look.get("empty", false)) and not upper:  # the vacant look (#358); fine is the Detailed style
		VacantLook.draw(canvas, kind, rect, fine)
	if state == VACANT:
		_dashed_border(canvas, interior, edge)
	if state == BROKEN or bool(look.get("cut_off", false)):  # a red cross: this parking does not count, or no stairs or lift reach this room (#368)
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
	if kind == PoolLifeScript.KIND:
		_pool_marks(canvas, look, interior, upper, p)


## The burned-out look (#373), the same in Classic and Detailed: soot over the whole room, a ragged black scorch
## up from the floor, a few cold embers, and a black cross boarding the room up. Fixed pixels, no randomness.
static func _charred_marks(canvas: Object, interior: Rect2i) -> void:
	canvas.draw_rect(interior, SOOT)
	var step := 6
	var n := 0
	var x := interior.position.x + 2
	while x < interior.end.x - 2:
		var height := 5 + (n * 7 + interior.position.x) % 9  # ragged flame-lick scorch, 5 to 13 px
		canvas.draw_rect(Rect2i(x, interior.end.y - height, mini(step - 1, interior.end.x - 2 - x), height), SCORCH)
		if n % 3 == 1:
			canvas.draw_rect(Rect2i(x + 1, interior.end.y - 2, 2, 1), EMBER)
		x += step
		n += 1
	canvas.draw_line(Vector2(interior.position.x + 1, interior.position.y + 1), Vector2(interior.end.x - 1, interior.end.y - 1), SCORCH, 2.0)
	canvas.draw_line(Vector2(interior.position.x + 1, interior.end.y - 1), Vector2(interior.end.x - 1, interior.position.y + 1), SCORCH, 2.0)


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


## The pool's moving parts over its drawn room (#328), for both looks, in world pixels inside the half's interior. Lower
## half: swimmers' heads in the basin, the lifeguard in her chair, the springboard's jumper and the splash, and a drained
## basin with a sign while it is cleaned. Upper half: spray from a splash, flung up past the floor.
static func _pool_marks(canvas: Object, look: Dictionary, interior: Rect2i, upper: bool, p: Dictionary) -> void:
	var x := interior.position.x
	var y := interior.position.y
	var white: Color = p["white"]
	var skin: Color = p["skin"]
	var frame: int = look["splash"]
	var jump_x := x + 26 + 12 * int(look["place"])
	if upper:
		if frame >= 2:  # droplets thrown up past the slab, over where the jumper went in
			for d in 3:
				canvas.draw_rect(Rect2i(jump_x + 8 + 3 * d - 2 * (frame - 2), y + 26 - 2 * d - (frame - 2), 1, 1), white)
		return
	if look["cleaning"]:  # drained: bare tiles, a yellow "closed" sign and a bucket
		canvas.draw_rect(Rect2i(x + 22, y + 14, 122, 16), Color(0.66, 0.72, 0.74))
		for k in 6:
			canvas.draw_rect(Rect2i(x + 22 + k * 22, y + 14, 1, 16), Color(0.50, 0.57, 0.60))
		canvas.draw_rect(Rect2i(x + 80, y + 6, 14, 8), p["gold"])
		canvas.draw_rect(Rect2i(x + 82, y + 9, 10, 2), p["red"])
		canvas.draw_rect(Rect2i(x + 86, y + 14, 2, 4), p["ink"])
		canvas.draw_rect(Rect2i(x + 112, y + 26, 4, 4), p["gold"])
	else:
		var heads: Array = p["people"]
		for i in int(look["swimmers"]):  # heads in the water: a cap, a face, an arm reaching
			var hx := x + 28 + (i * 17) % 104
			var hy := y + 15 + (i % 3) * 4
			canvas.draw_rect(Rect2i(hx, hy, 3, 1), heads[i % heads.size()])
			canvas.draw_rect(Rect2i(hx, hy + 1, 3, 2), skin)
			canvas.draw_rect(Rect2i(hx + 3, hy + 1, 3, 1), white)
	var seat_x: int = x + interior.size.x - 28
	if look["guard"]:  # the lifeguard in the tall chair, a red top and a whistle's glint
		canvas.draw_rect(Rect2i(seat_x, y + 10, 4, 6), p["red"])
		canvas.draw_rect(Rect2i(seat_x, y + 6, 4, 4), skin)
		canvas.draw_rect(Rect2i(seat_x + 1, y + 11, 1, 1), white)
	if frame < 0:
		return
	match frame:
		0:  # on the end of the board, ready
			canvas.draw_rect(Rect2i(jump_x, y + 5, 4, 8), p["red"])
			canvas.draw_rect(Rect2i(jump_x, y + 2, 4, 3), skin)
		1:  # up and tucking
			canvas.draw_rect(Rect2i(jump_x + 4, y + 1, 5, 5), p["red"])
			canvas.draw_rect(Rect2i(jump_x + 5, y, 3, 2), skin)
		2:  # the cannonball, over the water, coming down
			canvas.draw_rect(Rect2i(jump_x + 9, y + 6, 5, 5), p["red"])
			canvas.draw_rect(Rect2i(jump_x + 10, y + 5, 3, 2), skin)
		3:  # in: a tall white column
			canvas.draw_rect(Rect2i(jump_x + 12, y + 3, 3, 12), white)
			canvas.draw_rect(Rect2i(jump_x + 9, y + 8, 2, 6), white)
			canvas.draw_rect(Rect2i(jump_x + 16, y + 8, 2, 6), white)
			canvas.draw_rect(Rect2i(jump_x + 11, y + 1, 1, 1), white)
			canvas.draw_rect(Rect2i(jump_x + 15, y, 1, 1), white)
		4:  # it falls back and rings outward
			canvas.draw_rect(Rect2i(jump_x + 8, y + 11, 11, 3), white)
			canvas.draw_rect(Rect2i(jump_x + 5, y + 13, 17, 1), white)
			canvas.draw_rect(Rect2i(jump_x + 7, y + 6, 1, 1), white)
			canvas.draw_rect(Rect2i(jump_x + 19, y + 7, 1, 1), white)
			canvas.draw_rect(Rect2i(jump_x + 13, y + 9, 1, 1), white)


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
