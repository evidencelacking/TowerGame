extends RefCounted
## Room recipes (10.2, 10.3, 10.4): for every catalogue kind, a hue, furniture shapes, and the spots
## where people can stand or sit (used by 10.6). Pure data plus a resolver; reads nothing from the sim.
## Real recipes are drawn for the full floor in the approved 32 px look (mockups/art_d32.tscn); the
## kinds still in PLACEHOLDERS (none now) were drawn for a 22 px interior and shift down.
##
## Coordinates are native pixels inside one floor of the room: x from the room's left edge, y from
## its top, over WIDTH x INTERIOR_H (the bottom SLAB_H rows belong to the floor slab); y = INTERIOR_H is the floor.
## A shape is [x, y, w, h, role] with optional sixth and seventh items: the anchor, "l" (default) measures
## x from the left edge, "r" from the right edge (x is usually negative), "c" from the centre; and a gate,
## "use" (drawn only while the room is in use) or "idle" (only while empty). w == 0 stretches the shape to
## span the room, leaving x pixels on each side.
## Roles name palette colours (see RoomLook._role_colors): furn (drawn as a hollow frame when larger than
## 2 px), accent, lamp (lit in use, dark when empty), window, ink, white, red, gold, green, wood, car.
## "repeats" tile shapes along the room: origin = pad + n * every while the tile (from origin + lo to
## origin + hi) fits, at most "max" tiles (0 = no limit); every is always above 0, so the loop ends.
## A repeat may set "reserve" (px kept free at the right edge) and "avoid" (half-width of a zone around the
## centre that no tile may touch). Shapes that would fall outside a narrow room are dropped.
## Spots are [x, feet_y] and the optional anchor; a figure stands feet_y rows down with its 4x9 body above.
## "upper" replaces the layout of the upper half of a tall room that is drawn in halves.
## Kinds with "drawn_by" are drawn by another layer (slab, links, shafts, cars); their recipe is
## only the hue.

const VC := preload("res://scripts/view/view_consts.gd")
const Batch2 := preload("res://scripts/view/recipes_batch_2.gd")

const INTERIOR_H: int = VC.CELL_H - VC.SLAB_H  ## Usable rows above the floor slab.
const DESIGN_H: int = 22  ## The interior height the placeholder recipes were drawn for; they shift down by the extra.
const FLOOR_DY: int = INTERIOR_H - DESIGN_H
const FIGURE_W: int = VC.FIGURE_W  ## A standing figure's size, used to keep spots inside the room.
const FIGURE_H: int = VC.FIGURE_H

const PLACEHOLDERS: Dictionary = {}  ## Every kind has a real recipe now; the table stays for kinds added before their art.

## Real recipes with no spot: nobody stands in them (cars, ramps and the like).
const RECIPES_WITHOUT_SPOTS: Array[String] = ["parking_ramp", "parking_space"]

static var _real: Dictionary = {}
static var _cache: Dictionary = {}


## Whether a kind has a recipe.
static func has(kind: String) -> bool:
	return _table().has(kind) or PLACEHOLDERS.has(kind)


## Whether a kind still has only its placeholder recipe.
static func is_placeholder(kind: String) -> bool:
	return PLACEHOLDERS.has(kind) and not _table().has(kind)


## The hue key of a kind ("office", ...), "" if it has no recipe.
static func hue_key(kind: String) -> String:
	var recipe: Dictionary = _recipe(kind)
	return recipe.get("hue", "")


static func _recipe(kind: String) -> Dictionary:
	var real: Dictionary = _table()
	if real.has(kind):
		return real[kind]
	return PLACEHOLDERS.get(kind, {})


## The shapes ([x, y, w, h, role, gate] in room pixels) and spots (Vector2i: x and feet_y) of a kind drawn
## width_px wide. upper picks the upper-half layout where a recipe has one. Cached: one table per
## kind and width, so drawing a tower of repeated rooms resolves each recipe once.
static func layout(kind: String, width_px: int, upper: bool = false) -> Dictionary:
	var key := "%s:%d:%d" % [kind, width_px, 1 if upper else 0]
	if _cache.has(key):
		var cached: Dictionary = _cache[key]
		return cached
	var recipe: Dictionary = _recipe(kind)
	var dy: int = FLOOR_DY if is_placeholder(kind) else 0
	if upper and recipe.has("upper"):
		recipe = recipe["upper"]
	var shapes: Array = []
	var spots: Array[Vector2i] = []
	for shape: Array in recipe.get("fixed", []):
		_add_shape(shapes, _place(shape, width_px, 0, dy), width_px)
	for spot: Array in recipe.get("spots", []):
		_add_spot(spots, _spot(spot, 0, width_px, dy), width_px)
	for repeat: Dictionary in recipe.get("repeats", []):
		var origin: int = repeat["pad"]
		var count := 0
		var limit: int = repeat.get("max", 0)
		var every: int = maxi(repeat["every"] as int, 1)
		var lo: int = repeat["lo"]
		var hi: int = repeat["hi"]
		var right_edge: int = width_px - (repeat.get("reserve", 0) as int)
		var avoid: int = repeat.get("avoid", 0)
		while origin + hi <= right_edge and origin + lo >= 0 and (limit == 0 or count < limit):
			var clear := avoid == 0 or origin + hi < width_px / 2 - avoid or origin + lo > width_px / 2 + avoid
			if clear:
				for shape: Array in repeat["shapes"]:
					_add_shape(shapes, _place(shape, width_px, origin, dy), width_px)
				for spot: Array in repeat.get("spots", []):
					_add_spot(spots, _spot(spot, origin, width_px, dy), width_px)
			origin += every
			count += 1
	var out := {"shapes": shapes, "spots": spots}
	_cache[key] = out
	return out


## The spots of a kind in a room width_px wide (room pixels: x and feet row).
static func spots(kind: String, width_px: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	found.assign(layout(kind, width_px)["spots"])
	return found


## Keeps a placed shape only when it lies inside the room (a narrow room drops what does not fit).
static func _add_shape(shapes: Array, shape: Array, width_px: int) -> void:
	var x: int = shape[0]
	var y: int = shape[1]
	if x >= 0 and x + (shape[2] as int) <= width_px and y >= 0 and y + (shape[3] as int) <= INTERIOR_H:
		shapes.append(shape)


static func _add_spot(found: Array[Vector2i], spot: Vector2i, width_px: int) -> void:
	if spot_inside(spot, width_px):
		found.append(spot)


## A shape resolved against the room width and a tile origin: [x, y, w, h, role, gate] from the left edge.
static func _place(shape: Array, width_px: int, origin: int, dy: int) -> Array:
	var anchor: String = shape[5] if shape.size() > 5 else "l"
	var gate: String = shape[6] if shape.size() > 6 else ""
	var x: int = shape[0]
	var w: int = shape[2]
	if w == 0:
		w = width_px - 2 * x
	if anchor == "r":
		x += width_px
	elif anchor == "c":
		x += width_px / 2
	else:
		x += origin
	return [x, (shape[1] as int) + dy, w, shape[3], shape[4], gate]


static func _spot(spot: Array, origin: int, width_px: int, dy: int) -> Vector2i:
	var anchor: String = spot[2] if spot.size() > 2 else "l"
	var x: int = spot[0]
	if anchor == "r":
		x += width_px
	elif anchor == "c":
		x += width_px / 2
	else:
		x += origin
	return Vector2i(x, (spot[1] as int) + dy)


## Whether a figure standing at a spot lies inside a room width_px wide (one floor).
static func spot_inside(spot: Vector2i, width_px: int) -> bool:
	return spot.x >= 0 and spot.x + FIGURE_W <= width_px and spot.y - FIGURE_H >= 0 and spot.y <= INTERIOR_H


# ---- shape helpers (a recipe is data; these only build shape lists) ----


## A window: sky, frame and cross bars.
static func _win(x: int, y: int, w: int, h: int, a: String = "l") -> Array:
	return [[x, y, w, h, "window", a], [x, y, w, h, "furn", a], [x + w / 2, y, 1, h, "furn", a], [x, y + h / 2, w, 1, "furn", a]]


## A wall clock, 7 px: face, frame and hands.
static func _clock(x: int, y: int, a: String = "l") -> Array:
	return [[x, y, 7, 7, "white", a], [x, y, 7, 7, "furn", a], [x + 3, y + 1, 1, 3, "furn", a], [x + 3, y + 3, 2, 1, "furn", a]]


## A potted plant, 8 px wide, 17 tall, standing on the floor.
static func _plant(x: int, a: String = "l") -> Array:
	return [[x, 24, 8, 6, "furn", a], [x + 3, 17, 1, 7, "green", a], [x + 1, 15, 6, 1, "green", a], [x - 1, 18, 3, 1, "green", a],
		[x + 6, 19, 3, 1, "green", a], [x + 2, 13, 4, 1, "green", a]]


## A bed with headboard, mattress, sheet, pillow and footboard: len px of mattress from x0.
static func _bed(x0: int, len: int) -> Array:
	return [[x0, 15, 2, 15, "furn"], [x0 + 1, 23, len, 4, "furn"], [x0 + 2, 24, len - 2, 2, "white"], [x0 + len - 1, 20, 2, 7, "furn"],
		[x0 + 1, 27, 1, 3, "furn"], [x0 + len, 27, 1, 3, "furn"], [x0 + 3, 20, 7, 3, "furn"], [x0 + 4, 21, 5, 1, "white"]]


## A bedside table with a lamp on it, 6 px wide.
static func _nightstand(x: int) -> Array:
	return [[x, 24, 6, 6, "furn"], [x, 26, 6, 1, "furn"], [x + 2, 19, 1, 5, "furn"], [x + 1, 16, 4, 3, "lamp"], [x + 1, 16, 4, 3, "furn"]]


## A wardrobe, 12 px wide and 23 tall, on the floor.
static func _wardrobe(x: int, a: String = "l") -> Array:
	return [[x, 7, 12, 23, "furn", a], [x + 6, 8, 1, 21, "furn", a], [x + 4, 17, 1, 3, "furn", a], [x + 8, 17, 1, 3, "furn", a]]


static func _table() -> Dictionary:
	if _real.is_empty():
		_real = _build()
	return _real


static func _build() -> Dictionary:
	var out: Dictionary = {}
	out["lobby"] = {
		"hue": "lobby", "look": "full",
		"fixed": [
			[-22, 18, 44, 12, "furn", "c"], [-23, 17, 46, 1, "furn", "c"], [-18, 22, 12, 1, "furn", "c"],  # reception desk and terminal
			[6, 13, 6, 4, "furn", "c"], [7, 14, 4, 2, "lamp", "c"],
			[-36, 5, 72, 8, "furn", "c"], [-35, 6, 70, 6, "accent", "c"],  # sign band
			[-28, 8, 4, 2, "furn", "c"], [-21, 8, 4, 2, "furn", "c"], [-14, 8, 4, 2, "furn", "c"], [-7, 8, 4, 2, "furn", "c"],
			[0, 8, 4, 2, "furn", "c"], [7, 8, 4, 2, "furn", "c"], [14, 8, 4, 2, "furn", "c"], [21, 8, 4, 2, "furn", "c"],
		] + _plant(14) + _plant(-24, "r"),
		"repeats": [
			{"pad": 100, "every": 88, "lo": 0, "hi": 12, "avoid": 44, "shapes": _win(0, 5, 12, 11)},
			{"pad": 40, "every": 150, "lo": 0, "hi": 26, "avoid": 44, "shapes": [
				[0, 24, 26, 6, "furn"], [0, 18, 3, 12, "furn"], [23, 21, 3, 9, "furn"], [3, 20, 20, 1, "furn"]], "spots": [[8, 30]]},
			{"pad": 20, "every": 64, "lo": 0, "hi": 8, "avoid": 44, "shapes": [[0, 2, 8, 1, "lamp"]]},
		],
		"spots": [[-30, 30, "c"], [26, 30, "c"], [-2, 30, "c"]],
	}
	out["office"] = {
		"hue": "office", "look": "full",
		"fixed": _clock(-3, 4, "c") + [[-8, 16, 7, 14, "furn", "r"], [-8, 21, 7, 1, "furn", "r"], [-6, 18, 2, 1, "furn", "r"], [-6, 23, 2, 1, "furn", "r"], [-6, 27, 2, 1, "furn", "r"]],
		"repeats": [
			{"pad": 6, "every": 30, "lo": 0, "hi": 27, "shapes": [
				[0, 20, 20, 1, "furn"], [1, 21, 1, 9, "furn"], [18, 21, 1, 9, "furn"], [2, 22, 9, 1, "furn"],  # desk
				[11, 14, 8, 6, "furn"], [12, 15, 6, 4, "lamp"], [14, 19, 2, 1, "furn"],  # monitor
				[24, 17, 1, 7, "furn"], [22, 24, 4, 1, "furn"], [24, 25, 1, 4, "furn"], [22, 29, 5, 1, "furn"],  # chair
				[4, 2, 12, 1, "lamp"], [10, 1, 1, 1, "furn"]], "spots": [[23, 30]]},
			{"pad": 10, "every": 64, "lo": 0, "hi": 10, "shapes": _win(0, 5, 10, 10)},
		],
		"spots": [[-30, 30, "c"]],
	}
	out["condo"] = {
		"hue": "condo", "look": "full",
		"fixed": [[-20, 6, 16, 24, "furn", "r"], [-20, 14, 16, 1, "furn", "r"], [-20, 22, 16, 1, "furn", "r"],  # bookshelf
			[-18, 9, 2, 5, "red", "r"], [-15, 10, 3, 4, "gold", "r"], [-11, 9, 2, 5, "accent", "r"], [-8, 10, 3, 4, "white", "r"],
			[-18, 17, 3, 5, "accent", "r"], [-14, 18, 2, 4, "gold", "r"], [-10, 17, 3, 5, "red", "r"],
			[-18, 25, 3, 5, "gold", "r"], [-13, 26, 3, 4, "red", "r"], [-8, 25, 2, 5, "accent", "r"]],
		"repeats": [{"pad": 4, "every": 70, "lo": 0, "hi": 62, "shapes": _win(4, 5, 14, 10) + [
			[0, 24, 26, 6, "furn"], [0, 18, 3, 12, "furn"], [23, 21, 3, 9, "furn"], [3, 20, 20, 1, "furn"],  # sofa
			[29, 29, 5, 1, "furn"], [31, 12, 1, 17, "furn"], [29, 8, 5, 4, "lamp"], [29, 8, 5, 4, "furn"],  # floor lamp
			[40, 25, 20, 5, "furn"], [43, 15, 14, 10, "furn"], [44, 16, 12, 8, "lamp"],  # television
			[44, 4, 12, 8, "furn"], [45, 5, 10, 6, "accent"], [10, 2, 10, 1, "lamp"], [44, 2, 10, 1, "lamp"]],
			"spots": [[8, 30], [35, 30], [62, 30]]}],
	}
	out["hotel_single"] = {
		"hue": "hotel", "look": "full",
		"fixed": _bed(1, 17) + _nightstand(22) + [[4, 5, 10, 7, "furn"], [5, 6, 8, 5, "accent"], [8, 2, 8, 1, "lamp"]],
		"spots": [[9, 30], [27, 30]],
	}
	out["hotel_twin"] = {
		"hue": "hotel", "look": "full",
		"fixed": _bed(1, 17) + _nightstand(22) + _win(21, 3, 9, 9) + _wardrobe(-15, "r") + [[4, 5, 10, 7, "furn"], [5, 6, 8, 5, "accent"], [8, 2, 8, 1, "lamp"]],
		"spots": [[9, 30], [30, 30]],
	}
	out["hotel_suite"] = {
		"hue": "hotel", "look": "full",
		"fixed": _bed(4, 25) + _nightstand(33) + _win(43, 5, 10, 11) + _wardrobe(-17, "r") + [
			[10, 5, 11, 8, "furn"], [11, 6, 9, 6, "accent"], [14, 2, 8, 1, "lamp"], [2, 29, 38, 1, "gold"],
			[54, 24, 8, 6, "furn"], [54, 18, 2, 12, "furn"], [-5, 2, 10, 2, "gold", "c"]],
		"spots": [[12, 30], [44, 30], [56, 30]],
	}
	out["housekeeping"] = {
		"hue": "service", "look": "full",
		"fixed": [[-46, 10, 26, 1, "furn", "r"], [-46, 10, 1, 20, "furn", "r"], [-21, 10, 1, 20, "furn", "r"],  # clothes rail
			[-44, 11, 3, 10, "white", "r"], [-40, 11, 3, 12, "gold", "r"], [-36, 11, 3, 9, "red", "r"], [-32, 11, 3, 11, "white", "r"], [-28, 11, 3, 10, "accent", "r"],
			[-18, 14, 14, 16, "furn", "r"], [-15, 18, 8, 8, "furn", "r"], [-14, 19, 6, 6, "accent", "r"], [-17, 15, 3, 1, "lamp", "r"]],  # washing machine
		"repeats": [{"pad": 4, "every": 40, "lo": 0, "hi": 34, "max": 2, "shapes": [
			[0, 17, 14, 9, "furn"], [1, 18, 12, 7, "white"], [2, 26, 1, 4, "furn"], [11, 26, 1, 4, "furn"], [14, 11, 1, 15, "furn"], [14, 11, 4, 1, "furn"],  # linen cart
			[22, 6, 12, 24, "furn"], [22, 14, 12, 1, "furn"], [22, 22, 12, 1, "furn"],  # shelves with towels
			[24, 10, 4, 4, "white"], [29, 9, 4, 5, "gold"], [24, 18, 4, 4, "red"], [29, 17, 4, 5, "white"], [24, 26, 4, 4, "accent"], [29, 25, 4, 5, "white"],
			[4, 2, 14, 1, "lamp"]], "spots": [[18, 30], [36, 30]]}],
	}
	out.merge(Batch2.build())
	return out
