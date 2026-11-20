extends RefCounted
## Detailed graphics batch 2 (#303): food, shops, services and parking draw in the Detailed look without
## error, stay inside their room, report spots at double density that land inside the room and on furniture,
## and leave Classic alone. Reuses the batch 1 helpers.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const DetailShops := preload("res://scripts/view/detail_shops.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const Batch1 := preload("res://tests/test_detailed_batch1.gd")
const TestPests := preload("res://tests/test_pests.gd")

const IDS_TRIED := 64  ## Room ids tried to meet every variant of a kind.
const STILL_CLASSIC: Array[String] = ["party_hall", "movie_theatre", "cathedral", "metro"]


static func run(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var classic := GraphicsStyle.for_detailed(false)
	_draws(check)
	_placed(check, classic, detailed)
	_spots(check, detailed)
	_untouched(check, classic, detailed)


static func _id_for(kind: String, variant: int) -> int:
	for candidate: int in IDS_TRIED:
		if RoomRecipes.variant_for(kind, candidate) == variant:
			return candidate
	return 0


## Every kind, variant and floor of a tall room, in use and empty, at its width and wider: draws, stays inside.
static func _draws(check: Callable) -> void:
	var drawn := true
	var inside := true
	var all_variants := true
	for kind: String in DetailShops.KINDS:
		var seen: Dictionary = {}
		for id: int in IDS_TRIED:
			seen[RoomRecipes.variant_for(kind, id)] = true
		all_variants = all_variants and seen.size() == RoomRecipes.variant_count(kind)
		for width: int in [Batch1._width_px(kind), Batch1._width_px(kind) + 3 * VC.CELL_W]:
			var rect := Rect2i(40, 96, width, VC.CELL_H)
			for id: int in IDS_TRIED:
				for lit: bool in [false, true]:
					for upper: bool in [false, true]:
						var rec := Batch1.Recorder.new()
						DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit, upper, id)
						drawn = drawn and not rec.rects.is_empty()
						inside = inside and Batch1._inside(rec.rects, Rect2(rect))
	check.call(DetailShops.KINDS.size() == 8, "detailed: batch 2 has eight food, shop, service and parking kinds")
	check.call(all_variants, "detailed: the room ids tried reach every variant of every batch 2 kind")
	check.call(drawn, "detailed: every batch 2 kind and variant draws, in use and empty, on every floor")
	check.call(inside, "detailed: a batch 2 room paints only inside its own rect")
	var suites := true
	for kind: String in DetailShops.KINDS:
		if not RoomRecipes.has_suite(kind):
			continue
		var rect := Rect2i(0, 64, 16 * VC.CELL_W, VC.CELL_H)
		var rec := Batch1.Recorder.new()
		GraphicsStyle.for_detailed(true).suite(rec, kind, rect, 3)
		suites = suites and not rec.rects.is_empty() and Batch1._inside(rec.rects, Rect2(rect))
	check.call(suites, "detailed: batch 2 joined suites draw inside their union rect")


## Placed rooms through the full room path differ from Classic.
static func _placed(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var t := TestPests._tower()
	var rect := Rect2i(0, 0, 8 * 8, VC.CELL_H)
	var differs := true
	var floor_number := 3
	for kind: String in ["fast_food", "restaurant", "retail", "security", "medical"]:
		t.floors.fill_span(floor_number, 100, 131)
		var id := TestPests._room(t, kind, floor_number, 100)
		floor_number += 1
		if id < 0:
			differs = false
			continue
		var by_classic := Batch1.Recorder.new()
		classic.room(by_classic, t, id, rect, null, true, false)
		var by_detailed := Batch1.Recorder.new()
		detailed.room(by_detailed, t, id, rect, null, true, false)
		differs = differs and not by_detailed.rects.is_empty() and by_detailed.rects != by_classic.rects
	check.call(differs, "detailed: placed batch 2 rooms draw in the Detailed look")


## Spots at density 2 are the shared ones doubled, inside the room, and the furniture stands where they are.
static func _spots(check: Callable, detailed: GraphicsStyle) -> void:
	var doubled := true
	var inside := true
	var at_furniture := true
	var failures: Array[String] = []
	for kind: String in DetailShops.KINDS:
		var width := Batch1._width_px(kind)
		for variant: int in RoomRecipes.variant_count(kind):
			for upper: bool in [false, true]:
				var base := RoomRecipes.layout(kind, width, upper, variant)["spots"] as Array
				var wide := detailed.spots(kind, width, variant)
				var rect := Rect2i(0, 0, width, VC.CELL_H)
				var rec := Batch1.Recorder.new()
				DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true, upper, _id_for(kind, variant))
				for i: int in base.size():
					var spot: Vector2i = base[i]
					if not upper:
						doubled = doubled and wide[i] == spot * 2
						inside = inside and wide[i].x >= 0 and wide[i].x + 2 * VC.FIGURE_W <= width * 2 and wide[i].y - 2 * VC.FIGURE_H >= 0 and wide[i].y <= (VC.CELL_H - VC.SLAB_H) * 2
					if not Batch1._at_furniture(rec.rects, spot):
						at_furniture = false
						failures.append("%s v%d%s spot %s" % [kind, variant, " up" if upper else "", str(spot)])
	check.call(doubled, "detailed: every batch 2 spot is the shared spot at twice the pixels")
	check.call(inside, "detailed: every batch 2 spot, doubled, holds a doubled figure inside the room")
	check.call(at_furniture, "detailed: people at batch 2 spots are at furniture %s" % str(failures))


## Kinds still to come draw Classic under Detailed.
static func _untouched(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var same := true
	for kind: String in STILL_CLASSIC:
		var rect := Rect2i(0, 0, Batch1._width_px(kind), VC.CELL_H)
		var a := Batch1.Recorder.new()
		classic.recipe(a, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true)
		var b := Batch1.Recorder.new()
		detailed.recipe(b, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true)
		same = same and a.rects == b.rects
	check.call(same, "detailed: kinds not yet in the Detailed look draw Classic under Detailed")
