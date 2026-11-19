extends RefCounted
## Room variants (#275): offices, food rooms and shops have several looks. Every variant keeps its shapes and
## spots inside the room at every width, people placed on its spots stay inside, the same room id always
## gets the same look, and neighbouring rooms often differ.

const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const KINDS: Array[String] = ["office", "restaurant", "fast_food", "retail"]
const WIDTHS: Array[int] = [40, 72, 96, 128, 192, 400, 3200]


static func run(check: Callable) -> void:
	var counts_ok := true
	var shapes_bad: Array[String] = []
	var spots_bad: Array[String] = []
	var no_spots: Array[String] = []
	var thin: Array[String] = []
	var poses_bad: Array[String] = []
	for kind: String in KINDS:
		var count := RoomRecipes.variant_count(kind)
		counts_ok = counts_ok and count >= 3 and count <= 5
		var catalogue_w: int = int(CatalogueScript.field(kind, "width")) * VC.CELL_W
		var seen: Dictionary = {}
		for variant: int in count:
			var widths: Array[int] = WIDTHS.duplicate()
			widths.append(catalogue_w)
			for width_px: int in widths:
				var room := Rect2i(0, 0, width_px, RoomRecipes.INTERIOR_H)
				var parts := RoomRecipes.layout(kind, width_px, false, variant)
				for shape: Array in parts["shapes"]:
					if not room.encloses(Rect2i(shape[0], shape[1], shape[2], shape[3])) or (shape[2] as int) <= 0 or (shape[3] as int) <= 0:
						shapes_bad.append("%s v%d w%d %s" % [kind, variant, width_px, str(shape)])
				for spot: Vector2i in parts["spots"]:
					if not RoomRecipes.spot_inside(spot, width_px):
						spots_bad.append("%s v%d w%d %s" % [kind, variant, width_px, str(spot)])
				for act: int in ActivityLook.COUNT:
					if act == ActivityLook.SLEEPING:
						continue
					for turn in 4:
						var at := ActivityLook.place(act, ActivityLook.spot_for(kind, width_px, turn * 5, turn, act, variant), width_px)
						if not room.encloses(ActivityLook.body_rect(act, at.x, at.y)):
							poses_bad.append("%s v%d w%d %s" % [kind, variant, width_px, ActivityLook.NAMES[act]])
			var here := RoomRecipes.layout(kind, catalogue_w, false, variant)
			if (here["spots"] as Array).is_empty():
				no_spots.append("%s v%d" % [kind, variant])
			var has_lamp := false
			for shape: Array in here["shapes"]:
				has_lamp = has_lamp or shape[4] == "lamp"
			if (here["shapes"] as Array).size() < 8 or not has_lamp:
				thin.append("%s v%d" % [kind, variant])
			seen[str(here["shapes"])] = true
		check.call(seen.size() == count, "variants: every %s variant draws differently (%d of %d)" % [kind, seen.size(), count])
	check.call(counts_ok, "variants: offices, restaurants, food and shops each have 3 to 5 looks")
	check.call(shapes_bad.is_empty(), "variants: shapes lie inside the room at every width (%s)" % str(shapes_bad.slice(0, 3)))
	check.call(spots_bad.is_empty(), "variants: spots lie inside the room at every width (%s)" % str(spots_bad.slice(0, 3)))
	check.call(poses_bad.is_empty(), "variants: figures on a variant's spots stay inside the room (%s)" % str(poses_bad.slice(0, 3)))
	check.call(no_spots.is_empty(), "variants: each has spots at its catalogue width (%s)" % str(no_spots))
	check.call(thin.is_empty(), "variants: each is detailed and has a lamp for the in-use look (%s)" % str(thin))
	# Same id, same look; neighbours differ often; every look gets used.
	var stable := true
	var differ := 0
	var pairs := 0
	for kind: String in KINDS:
		var used: Dictionary = {}
		var count := RoomRecipes.variant_count(kind)
		for id in 200:
			var v := RoomRecipes.variant_for(kind, id)
			stable = stable and v == RoomRecipes.variant_for(kind, id) and v >= 0 and v < count
			used[v] = true
			pairs += 1
			if v != RoomRecipes.variant_for(kind, id + 1):
				differ += 1
		check.call(used.size() == count, "variants: every %s look is used across room ids" % kind)
	check.call(stable, "variants: a room id always gets the same look, in range")
	check.call(differ * 100 >= pairs * 60, "variants: neighbouring rooms differ often (%d of %d)" % [differ, pairs])
	check.call(RoomRecipes.variant_for("lobby", 5) == 0 and RoomRecipes.variant_count("lobby") == 1, "variants: kinds without extra looks stay at variant 0")
