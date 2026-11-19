extends RefCounted
## Room recipes (10.2): for every catalogue kind, a hue, furniture shapes, and the spots where
## people can stand (used by 10.6). Pure data plus a resolver; reads nothing from the sim.
##
## Coordinates are native pixels inside one floor of the room: x from the room's left edge, y from
## its top, over WIDTH x INTERIOR_H (the bottom SLAB_H rows belong to the floor slab).
## A shape is [x, y, w, h, role] with an optional sixth item, the anchor: "l" (default) measures x
## from the left edge, "r" from the right edge (x is usually negative), "c" from the centre.
## w == 0 stretches the shape to span the room, leaving x pixels on each side.
## Roles name palette colours (see RoomDraw.role_color): furn, accent, lamp, window, ink, white,
## red, gold, green, wood, car.
## "repeats" tile shapes along the room: origin = pad + n * every while the tile (from origin + lo to
## origin + hi) fits, at most "max" tiles (0 = no limit); every is always above 0, so the loop ends.
## Spots are [x, feet_y] and the optional anchor; a figure stands feet_y rows down with its 3x7 body above.
## "upper" replaces the layout of the upper half of a tall room that is drawn in halves (recycling).
## Kinds with "drawn_by" are drawn by another layer (slab, links, shafts, cars); their recipe is
## only the hue. Placeholders for most kinds: 10.3 and 10.4 refine them.

const VC := preload("res://scripts/view/view_consts.gd")

const INTERIOR_H: int = VC.CELL_H - VC.SLAB_H  ## Usable rows above the floor slab.
const DESIGN_H: int = 22  ## The interior height the recipes were drawn for; they stand on the floor, so they shift down by the extra.
const FLOOR_DY: int = INTERIOR_H - DESIGN_H
const FIGURE_W: int = VC.FIGURE_W  ## A standing figure's size, used to keep spots inside the room.
const FIGURE_H: int = VC.FIGURE_H

const RECIPES: Dictionary = {
	"lobby": {
		"hue": "lobby",
		"fixed": [
			[-16, 15, 32, 7, "furn", "c"], [-16, 13, 32, 2, "accent", "c"],
			[10, 18, 5, 4, "furn"], [8, 11, 9, 7, "green"],
			[40, 8, 8, 12, "window"], [-60, 8, 8, 12, "window", "r"],
			[-4, 2, 8, 1, "lamp", "c"],
		],
		"repeats": [{"pad": 40, "every": 48, "lo": 0, "hi": 16, "shapes": [[0, 18, 16, 3, "furn"]], "spots": [[6, 18]]}],
		"spots": [[24, 21], [-30, 21, "r"], [-4, 21, "c"]],
	},
	"floor": {"hue": "floor", "drawn_by": "slab"},
	"stairs": {"hue": "stairs", "drawn_by": "link"},
	"escalator": {"hue": "escalator", "drawn_by": "link"},
	"local_shaft": {"hue": "shaft", "drawn_by": "shaft"},
	"service_shaft": {"hue": "shaft", "drawn_by": "shaft"},
	"express_shaft": {"hue": "shaft", "drawn_by": "shaft"},
	"local_car": {"hue": "car", "drawn_by": "car"},
	"service_car": {"hue": "car", "drawn_by": "car"},
	"express_car": {"hue": "car", "drawn_by": "car"},
	"office": {
		"hue": "office",
		"fixed": [[-5, 3, 10, 1, "lamp", "c"]],
		"repeats": [{"pad": 6, "every": 20, "lo": 0, "hi": 14, "shapes": [
			[0, 14, 10, 2, "furn"], [1, 16, 1, 4, "furn"], [8, 16, 1, 4, "furn"],
			[3, 10, 4, 3, "lamp"], [11, 18, 3, 4, "furn"]], "spots": [[4, 21]]}],
	},
	"condo": {
		"hue": "condo",
		"fixed": [[-5, 3, 10, 1, "lamp", "c"]],
		"repeats": [{"pad": 4, "every": 36, "lo": 0, "hi": 30, "shapes": [
			[0, 16, 14, 4, "furn"], [0, 11, 3, 9, "furn"], [20, 12, 8, 6, "ink"], [21, 13, 6, 4, "lamp"],
			[18, 19, 10, 2, "wood"]], "spots": [[6, 21]]}],
	},
	"fast_food": {
		"hue": "food",
		"fixed": [[2, 15, 0, 5, "wood"], [2, 13, 0, 2, "accent"]],
		"repeats": [
			{"pad": 0, "every": 8, "lo": 0, "hi": 8, "shapes": [[0, 2, 4, 5, "red"], [4, 2, 4, 5, "gold"]]},
			{"pad": 10, "every": 24, "lo": -4, "hi": 6, "shapes": [[0, 11, 4, 2, "gold"]], "spots": [[-4, 21]]},
		],
	},
	"hotel_single": {
		"hue": "hotel",
		"fixed": [[-9, 3, 7, 6, "window", "r"], [-4, 3, 8, 1, "lamp", "c"]],
		"repeats": [{"pad": 3, "every": 32, "lo": 0, "hi": 22, "shapes": [
			[0, 17, 20, 4, "furn"], [0, 11, 2, 10, "furn"], [3, 15, 5, 2, "white"]], "spots": [[10, 18]]}],
	},
	"hotel_twin": {
		"hue": "hotel",
		"fixed": [[-4, 3, 8, 1, "lamp", "c"]],
		"repeats": [{"pad": 2, "every": 24, "lo": 0, "hi": 20, "shapes": [
			[0, 17, 18, 4, "furn"], [0, 11, 2, 10, "furn"], [3, 15, 5, 2, "white"]], "spots": [[9, 18]]}],
	},
	"hotel_suite": {
		"hue": "hotel",
		"fixed": [[-16, 3, 9, 8, "window", "r"], [-4, 3, 8, 1, "lamp", "c"], [-3, 14, 6, 6, "gold", "c"]],
		"repeats": [{"pad": 4, "every": 32, "lo": 0, "hi": 24, "shapes": [
			[0, 17, 22, 4, "furn"], [0, 11, 2, 10, "furn"], [3, 15, 5, 2, "white"]], "spots": [[10, 18]]}],
	},
	"housekeeping": {
		"hue": "service",
		"repeats": [{"pad": 4, "every": 24, "lo": 0, "hi": 20, "shapes": [
			[0, 13, 10, 6, "white"], [4, 14, 2, 4, "red"], [3, 15, 4, 2, "red"], [1, 19, 2, 2, "ink"],
			[7, 19, 2, 2, "ink"], [12, 6, 1, 14, "wood"], [10, 18, 5, 2, "gold"]], "spots": [[16, 21]]}],
	},
	"security": {
		"hue": "service",
		"fixed": [[2, 15, 0, 3, "wood"], [-14, 4, 10, 8, "gold", "r"]],
		"repeats": [{"pad": 4, "every": 11, "lo": 0, "hi": 9, "max": 3, "shapes": [[0, 3, 9, 6, "ink"], [1, 4, 7, 4, "green"]]}],
		"spots": [[30, 21], [-40, 21, "r"]],
	},
	"restaurant": {
		"hue": "food",
		"fixed": [[1, 3, 0, 1, "gold"]],
		"repeats": [{"pad": 12, "every": 28, "lo": -3, "hi": 13, "shapes": [
			[0, 14, 8, 1, "furn"], [3, 15, 2, 6, "furn"], [-3, 17, 2, 4, "furn"], [9, 17, 2, 4, "furn"],
			[1, 8, 5, 2, "lamp"], [3, 4, 1, 4, "ink"]], "spots": [[-3, 21], [9, 21]]}],
	},
	"retail": {
		"hue": "shop",
		"fixed": [[0, 1, 0, 2, "green"]],
		"repeats": [{"pad": 2, "every": 12, "lo": 0, "hi": 9, "shapes": [
			[0, 4, 9, 10, "window"], [2, 10, 5, 4, "accent"], [3, 8, 3, 2, "red"]], "spots": [[3, 21]]}],
	},
	"movie_theatre": {
		"hue": "civic",
		"fixed": [[16, 4, 0, 10, "white"]],
		"repeats": [{"pad": 16, "every": 12, "lo": 0, "hi": 8, "shapes": [[0, 16, 8, 5, "furn"]], "spots": [[2, 19]]}],
	},
	"party_hall": {
		"hue": "civic",
		"fixed": [[8, 3, 0, 2, "accent"], [-2, 5, 4, 4, "gold", "c"]],
		"repeats": [{"pad": 12, "every": 24, "lo": 0, "hi": 13, "shapes": [
			[0, 16, 12, 2, "furn"], [5, 18, 2, 3, "furn"]], "spots": [[0, 21], [9, 21]]}],
	},
	"medical": {
		"hue": "medical",
		"fixed": [[6, 5, 4, 12, "red"], [2, 9, 12, 4, "red"]],
		"repeats": [{"pad": 22, "every": 40, "lo": 0, "hi": 24, "shapes": [
			[0, 15, 18, 4, "accent"], [0, 13, 4, 2, "white"], [21, 5, 1, 14, "ink"], [19, 5, 4, 5, "window"],
			[0, 19, 2, 2, "ink"], [16, 19, 2, 2, "ink"]], "spots": [[8, 19]]}],
	},
	"recycling": {
		"hue": "recycling",
		"repeats": [{"pad": 4, "every": 16, "lo": -1, "hi": 15, "shapes": [
			[0, 13, 10, 8, "green"], [-1, 12, 12, 2, "ink"], [4, 15, 2, 4, "white"]], "spots": [[12, 21]]}],
		"upper": {
			"fixed": [[2, 4, 0, 2, "green"]],
			"repeats": [{"pad": 10, "every": 24, "lo": 0, "hi": 2, "shapes": [[0, 4, 2, 18, "green"]]}],
		},
	},
	"parking_ramp": {
		"hue": "parking",
		"fixed": [
			[3, 18, 3, 2, "ink"], [6, 16, 3, 4, "ink"], [9, 14, 3, 6, "ink"], [12, 12, 3, 8, "ink"],
			[15, 10, 3, 10, "ink"], [18, 8, 3, 12, "ink"], [21, 6, 3, 14, "ink"], [24, 4, 3, 16, "ink"],
			[1, 4, 4, 2, "gold"],
		],
	},
	"parking_space": {
		"hue": "parking",
		"fixed": [
			[0, 4, 1, 18, "white"], [-1, 4, 1, 18, "white", "r"],
			[4, 14, 22, 5, "car"], [9, 11, 10, 3, "window"], [6, 18, 4, 3, "ink"], [19, 18, 4, 3, "ink"],
		],
	},
	"metro": {
		"hue": "civic",
		"fixed": [[0, 18, 0, 4, "furn"], [0, 17, 0, 1, "gold"]],
		"repeats": [{"pad": 24, "every": 48, "lo": 0, "hi": 12, "shapes": [[0, 4, 12, 5, "ink"], [1, 5, 10, 3, "lamp"]], "spots": [[4, 17]]}],
	},
	"cathedral": {
		"hue": "civic",
		"fixed": [[-8, 16, 16, 6, "furn", "c"], [-1, 6, 2, 10, "gold", "c"]],
		"repeats": [{"pad": 12, "every": 24, "lo": 0, "hi": 10, "shapes": [[0, 6, 10, 16, "window"], [2, 3, 6, 3, "window"]]}],
		"spots": [[20, 21], [-30, 21, "r"]],
	},
}

static var _cache: Dictionary = {}


## Whether a kind has a recipe.
static func has(kind: String) -> bool:
	return RECIPES.has(kind)


## The hue key of a kind ("office", ...), "" if it has no recipe.
static func hue_key(kind: String) -> String:
	if not RECIPES.has(kind):
		return ""
	var recipe: Dictionary = RECIPES[kind]
	return recipe["hue"]


## The shapes ([x, y, w, h, role] in room pixels) and spots (Vector2i: x and feet_y) of a kind drawn
## width_px wide. upper picks the upper-half layout where a recipe has one. Cached: one table per
## kind and width, so drawing a tower of repeated rooms resolves each recipe once.
static func layout(kind: String, width_px: int, upper: bool = false) -> Dictionary:
	var key := "%s:%d:%d" % [kind, width_px, 1 if upper else 0]
	if _cache.has(key):
		var cached: Dictionary = _cache[key]
		return cached
	var recipe: Dictionary = RECIPES.get(kind, {})
	if upper and recipe.has("upper"):
		recipe = recipe["upper"]
	var shapes: Array = []
	var spots: Array[Vector2i] = []
	for shape: Array in recipe.get("fixed", []):
		shapes.append(_place(shape, width_px))
	for spot: Array in recipe.get("spots", []):
		spots.append(_spot(spot, 0, width_px))
	for repeat: Dictionary in recipe.get("repeats", []):
		var origin: int = repeat["pad"]
		var count := 0
		var limit: int = repeat.get("max", 0)
		var every: int = maxi(repeat["every"] as int, 1)
		while origin + (repeat["hi"] as int) <= width_px and origin + (repeat["lo"] as int) >= 0 and (limit == 0 or count < limit):
			for shape: Array in repeat["shapes"]:
				shapes.append(_place(shape, width_px, origin))
			for spot: Array in repeat.get("spots", []):
				spots.append(_spot(spot, origin, width_px))
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


## A shape resolved against the room width and a tile origin: [x, y, w, h, role] from the left edge.
static func _place(shape: Array, width_px: int, origin: int = 0) -> Array:
	var anchor: String = shape[5] if shape.size() > 5 else "l"
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
	return [x, (shape[1] as int) + FLOOR_DY, w, shape[3], shape[4]]


static func _spot(spot: Array, origin: int, width_px: int) -> Vector2i:
	var anchor: String = spot[2] if spot.size() > 2 else "l"
	var x: int = spot[0]
	if anchor == "r":
		x += width_px
	elif anchor == "c":
		x += width_px / 2
	else:
		x += origin
	return Vector2i(x, (spot[1] as int) + FLOOR_DY)


## Whether a figure standing at a spot lies inside a room width_px wide (one floor).
static func spot_inside(spot: Vector2i, width_px: int) -> bool:
	return spot.x >= 0 and spot.x + FIGURE_W <= width_px and spot.y - FIGURE_H >= 0 and spot.y <= INTERIOR_H
