extends RefCounted
## Room recipes and the palette table (10.2): every catalogue kind has a recipe, its spots and
## shapes lie inside the room, all three palettes carry the same colour keys, and the renderer's
## pixel space matches the grid.

const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")

## Kinds with a real recipe (10.3): not the placeholder, shaped for the full 32 px floor.
const BATCH_1: Array[String] = ["lobby", "office", "condo", "hotel_single", "hotel_twin", "hotel_suite", "housekeeping"]
const BATCH_2: Array[String] = ["fast_food", "restaurant", "retail", "movie_theatre", "party_hall", "medical", "security", "recycling", "parking_ramp", "parking_space", "metro", "cathedral"]


const BATCH_3: Array[String] = ["gym", "daycare", "clinic", "nightclub", "coworking", "observation_deck", "casino", "cafe", "pizza", "sushi", "fine_dining", "bar"]


static func run(check: Callable) -> void:
	var missing: Array[String] = []
	var bad_hue: Array[String] = []
	var outside: Array[String] = []
	var kinds_with_spots := 0
	for kind: String in CatalogueScript.IDS:
		if not RoomRecipes.has(kind):
			missing.append(kind)
			continue
		if not Palette.hue_keys().has(RoomRecipes.hue_key(kind)):
			bad_hue.append(kind)
		var width_px: int = int(CatalogueScript.field(kind, "width")) * VC.CELL_W
		if CatalogueScript.row(kind).get("per_unit", false):  # the lobby and floor are priced per unit; a lobby is at least a few dozen wide
			width_px = 40 * VC.CELL_W
		var room := Rect2i(0, 0, width_px, RoomRecipes.INTERIOR_H)
		for upper: bool in [false, true]:
			var parts := RoomRecipes.layout(kind, width_px, upper)
			for shape: Array in parts["shapes"]:
				var r := Rect2i(shape[0], shape[1], shape[2], shape[3])
				if r.size.x <= 0 or r.size.y <= 0 or not room.encloses(r):
					outside.append("%s shape %s" % [kind, str(shape)])
			for spot: Vector2i in parts["spots"]:
				if not RoomRecipes.spot_inside(spot, width_px):
					outside.append("%s spot %s" % [kind, str(spot)])
		if not RoomRecipes.spots(kind, width_px).is_empty():
			kinds_with_spots += 1
	check.call(missing.is_empty(), "recipes: every catalogue kind has one (missing %s)" % str(missing))
	check.call(bad_hue.is_empty(), "recipes: every hue key exists in the palette (%s)" % str(bad_hue))
	check.call(outside.is_empty(), "recipes: shapes and spots lie inside the room (%s)" % str(outside.slice(0, 4)))
	check.call(kinds_with_spots >= 12, "recipes: the people-holding kinds have spots (%d kinds)" % kinds_with_spots)
	# Spots stay inside other widths too (the lobby runs to the whole tower, shops vary).
	var wide_ok := true
	for kind: String in ["lobby", "office", "restaurant", "retail"]:
		for width_px: int in [40, 96, 400, 3200]:
			for spot: Vector2i in RoomRecipes.spots(kind, width_px):
				wide_ok = wide_ok and RoomRecipes.spot_inside(spot, width_px)
	check.call(wide_ok, "recipes: spots inside at other widths")
	check.call(RoomRecipes.layout("office", 72) == RoomRecipes.layout("office", 72), "recipes: a layout is stable")
	# Palettes: the same keys everywhere, and the default is A.
	var keys_match := true
	var first: Dictionary = Palette.PALETTES[0]
	for palette: Dictionary in Palette.PALETTES:
		keys_match = keys_match and palette.keys() == first.keys() and (palette["hues"] as Dictionary).keys() == (first["hues"] as Dictionary).keys()
	check.call(keys_match and Palette.PALETTES.size() == Palette.NAMES.size(), "palette: A, B and C carry the same keys")
	check.call(Palette.DEFAULT_INDEX == 3, "palette: D (A colours, B lines) is the default")
	# Native pixel space: 8 px per column, 24 px per floor, whole numbers.
	check.call(VC.CELL_W == 8 and VC.CELL_H == 32, "renderer: native space is 8 px per column and 32 px per floor")
	_batch(check, BATCH_1)
	_batch(check, BATCH_2)
	_batch(check, BATCH_3)
	var still_placeholder: Array[String] = []
	for kind: String in CatalogueScript.IDS:
		if RoomRecipes.is_placeholder(kind):
			still_placeholder.append(kind)
	check.call(still_placeholder.is_empty(), "recipes: no catalogue kind is a placeholder (%s)" % str(still_placeholder))


## A batch of real recipes: none is a placeholder, each fills most of the floor height, its in-use and empty
## looks differ, and every spot lies inside the room and fits a 4x9 figure at the catalogue width and at others.
static func _batch(check: Callable, kinds: Array[String]) -> void:
	var placeholders: Array[String] = []
	var short: Array[String] = []
	var same_look: Array[String] = []
	var bad_spots: Array[String] = []
	var no_spots: Array[String] = []
	var p := Palette.get_palette()
	for kind: String in kinds:
		if RoomRecipes.is_placeholder(kind):
			placeholders.append(kind)
			continue
		var width_px: int = int(CatalogueScript.field(kind, "width")) * VC.CELL_W
		if CatalogueScript.row(kind).get("per_unit", false):
			width_px = 40 * VC.CELL_W  # a lobby is at least a few dozen wide
		var layout := RoomRecipes.layout(kind, width_px)
		var top := RoomRecipes.INTERIOR_H
		var shapes: Array = layout["shapes"]
		for shape: Array in shapes:
			top = mini(top, shape[1] as int)
		if shapes.size() < 8 or top > 8:
			short.append(kind)  # a real recipe has detail and reaches near the ceiling
		var hue := Palette.hue(RoomRecipes.hue_key(kind))
		var lit: Dictionary = RoomLook._role_colors(p, hue, true, 0)
		var dim: Dictionary = RoomLook._role_colors(p, hue, false, 0)
		var differs := false
		for role: String in lit:
			if role != "car" and lit[role] != dim[role]:
				differs = true
		var used_lamp := false
		for shape: Array in shapes:
			used_lamp = used_lamp or shape[4] == "lamp" or shape[4] == "white" or shape[5] != ""
		if not differs or not used_lamp:
			same_look.append(kind)
		var spots := RoomRecipes.spots(kind, width_px)
		if spots.is_empty() and not RoomRecipes.RECIPES_WITHOUT_SPOTS.has(kind):
			no_spots.append(kind)
		for w: int in [width_px, width_px * 2, 40]:
			for spot: Vector2i in RoomRecipes.spots(kind, w):
				if not RoomRecipes.spot_inside(spot, w):
					bad_spots.append("%s %s" % [kind, str(spot)])
	check.call(placeholders.is_empty(), "recipes: no placeholder left in the batch (%s)" % str(placeholders))
	check.call(short.is_empty(), "recipes: each real recipe is detailed and uses the full floor height (%s)" % str(short))
	check.call(same_look.is_empty(), "recipes: in-use and empty looks differ (%s)" % str(same_look))
	check.call(bad_spots.is_empty() and no_spots.is_empty(), "recipes: spots lie inside the room and fit a figure (%s %s)" % [str(bad_spots.slice(0, 3)), str(no_spots)])
