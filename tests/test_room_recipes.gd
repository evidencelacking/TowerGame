extends RefCounted
## Room recipes and the palette table (10.2): every catalogue kind has a recipe, its spots and
## shapes lie inside the room, all three palettes carry the same colour keys, and the renderer's
## pixel space matches the grid.

const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")


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
	check.call(Palette.DEFAULT_INDEX == 0, "palette: A is the default")
	# Native pixel space: 8 px per column, 24 px per floor, whole numbers.
	check.call(VC.CELL_W == 8 and VC.CELL_H == 24, "renderer: native space is 8 px per column and 24 px per floor")
