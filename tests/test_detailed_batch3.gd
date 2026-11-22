extends RefCounted
## Detailed graphics batch 3 (#303): the movie theatre, party hall, metro station and cathedral draw in the
## Detailed look, stay inside their room, report spots at double density that land inside the room and on
## furniture, and leave Classic alone. Stairs and escalators now have a background panel, and a car draws its
## riders as Detailed figures.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const DetailHall := preload("res://scripts/view/detail_hall.gd")
const DetailTransport := preload("res://scripts/view/detail_transport.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const Glass := preload("res://scripts/view/transport_glass.gd")
const Batch1 := preload("res://tests/test_detailed_batch1.gd")
const Batch2 := preload("res://tests/test_detailed_batch2.gd")


static func run(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var classic := GraphicsStyle.for_detailed(false)
	_draws(check, classic, detailed)
	_spots(check, detailed)
	_backdrops(check, detailed)
	_riders(check)


## Every kind, floor, lit and empty, at its width and wider: draws, stays inside, and differs from Classic.
static func _draws(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var drawn := true
	var inside := true
	var differs := true
	for kind: String in DetailHall.KINDS:
		for width: int in [Batch1._width_px(kind), Batch1._width_px(kind) + 3 * VC.CELL_W]:
			var rect := Rect2i(40, 96, width, VC.CELL_H)
			for id: int in 8:
				for lit: bool in [false, true]:
					for upper: bool in [false, true]:
						var rec := Batch1.Recorder.new()
						DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit, upper, id)
						drawn = drawn and not rec.rects.is_empty()
						inside = inside and Batch1._inside(rec.rects, Rect2(rect))
		var r := Rect2i(0, 0, Batch1._width_px(kind), VC.CELL_H)
		var a := Batch1.Recorder.new()
		classic.recipe(a, kind, r, Palette.hue(RoomRecipes.hue_key(kind)), true)
		var b := Batch1.Recorder.new()
		detailed.recipe(b, kind, r, Palette.hue(RoomRecipes.hue_key(kind)), true)
		differs = differs and not b.rects.is_empty() and a.rects != b.rects
	check.call(DetailHall.KINDS.size() == 4, "detailed: batch 3 has four hall kinds (cinema, party hall, metro, cathedral)")
	check.call(drawn, "detailed: every batch 3 kind draws, in use and empty, on both floors")
	check.call(inside, "detailed: a batch 3 room paints only inside its own rect")
	check.call(differs, "detailed: batch 3 kinds differ from Classic under Detailed")
	check.call(DetailRooms.handles("cathedral") and DetailRooms.handles("metro"), "detailed: DetailRooms handles the hall kinds")


static func _spots(check: Callable, detailed: GraphicsStyle) -> void:
	var doubled := true
	var inside := true
	var at_furniture := true
	var failures: Array[String] = []
	for kind: String in DetailHall.KINDS:
		var width := Batch1._width_px(kind)
		for variant: int in RoomRecipes.variant_count(kind):
			for upper: bool in [false, true]:
				var base := RoomRecipes.layout(kind, width, upper, variant)["spots"] as Array
				var wide := detailed.spots(kind, width, variant)
				var rect := Rect2i(0, 0, width, VC.CELL_H)
				var rec := Batch1.Recorder.new()
				DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true, upper, Batch2._id_for(kind, variant))
				for i: int in base.size():
					var spot: Vector2i = base[i]
					if not upper:
						doubled = doubled and wide[i] == spot * 2
						inside = inside and wide[i].x >= 0 and wide[i].x + 2 * VC.FIGURE_W <= width * 2 and wide[i].y - 2 * VC.FIGURE_H >= 0 and wide[i].y <= (VC.CELL_H - VC.SLAB_H) * 2
					if not Batch1._at_furniture(rec.rects, spot):
						at_furniture = false
						failures.append("%s v%d%s spot %s" % [kind, variant, " up" if upper else "", str(spot)])
	check.call(doubled, "detailed: every batch 3 spot is the shared spot at twice the pixels")
	check.call(inside, "detailed: every batch 3 spot, doubled, holds a doubled figure inside the room")
	check.call(at_furniture, "detailed: people at batch 3 spots are at furniture %s" % str(failures))


## Whether some rect in rects covers the point.
static func _covers(rects: Array[Rect2], at: Vector2) -> bool:
	for r: Rect2 in rects:
		if r.has_point(at):
			return true
	return false


## Stairs and escalators paint a background over their whole span, near every corner of both floors (in the
## opaque look: the see-through one, #367, leaves the rooms behind showing).
static func _backdrops(check: Callable, detailed: GraphicsStyle) -> void:
	var glass_was := Glass.on
	Glass.on = false
	var filled := true
	for kind: String in ["stairs", "escalator"]:
		for row: int in [2, 3]:
			var span := Rect2i(24, (row - 1) * VC.CELL_H, (4 if kind == "stairs" else 8) * VC.CELL_W, VC.CELL_H * 2)
			var rec := Batch1.Recorder.new()
			detailed.link(rec, kind, span)
			for corner: Vector2 in [Vector2(2, 2), Vector2(span.size.x - 3, 2), Vector2(2, VC.CELL_H + 2), Vector2(span.size.x - 3, VC.CELL_H + 2)]:
				filled = filled and _covers(rec.rects, Vector2(span.position) + corner)
	Glass.on = glass_was
	check.call(filled, "detailed: stairs and escalators have a background panel on both floors of their span")


## The riders of a car are Detailed figures: each one adds pieces, they differ from Classic's, and they stay
## inside the car.
static func _riders(check: Callable) -> void:
	var car := Rect2i(19, 3, VC.CELL_W * 2, VC.CELL_H - VC.SLAB_H - 3)
	var shirts: Array = [Color("c8453c"), Color("3f7fb0"), Color("e0a83a")]
	var counts: Array[int] = []
	var inside := true
	for load: int in [0, 1, 3]:
		var rec := Batch1.Recorder.new()
		DetailTransport.riders(rec, car, load, shirts)
		counts.append(rec.rects.size())
		inside = inside and Batch1._inside(rec.rects, Rect2(car))
	check.call(counts[0] == 0 and counts[0] < counts[1] and counts[1] < counts[2], "detailed: each car rider adds a Detailed figure")
	check.call(inside, "detailed: car riders stay inside the car")
	var classic := Batch1.Recorder.new()
	TransportLook.draw_riders(classic, car, 3, shirts)
	var fine := Batch1.Recorder.new()
	DetailTransport.riders(fine, car, 3, shirts)
	check.call(classic.rects != fine.rects and fine.rects.size() > classic.rects.size(), "detailed: car riders have more detail than Classic's")
