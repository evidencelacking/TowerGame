extends RefCounted
## Detailed graphics for the venue kinds (#352): each draws in the Detailed look, in use and empty, stays
## inside its room, and has furniture at every spot people stand at.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const DetailVenues := preload("res://scripts/view/detail_venues.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const Batch1 := preload("res://tests/test_detailed_batch1.gd")


static func run(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var handled := true
	var drawn := true
	var inside := true
	var at_furniture := true
	var failures: Array[String] = []
	for kind: String in DetailVenues.KINDS:
		handled = handled and DetailRooms.handles(kind)
		var width := Batch1._width_px(kind)
		for w: int in [width, width + 3 * VC.CELL_W]:
			var rect := Rect2i(40, 96, w, VC.CELL_H)
			for id: int in [0, 1, 5]:
				for lit: bool in [false, true]:
					var rec := Batch1.Recorder.new()
					DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit, false, id)
					drawn = drawn and not rec.rects.is_empty()
					inside = inside and Batch1._inside(rec.rects, Rect2(rect))
		var rect0 := Rect2i(0, 0, width, VC.CELL_H)
		var rec0 := Batch1.Recorder.new()
		DetailRooms.draw(rec0, kind, rect0, Palette.hue(RoomRecipes.hue_key(kind)), true, false, 0)
		var spots := RoomRecipes.layout(kind, width, false, 0)["spots"] as Array
		for spot: Vector2i in spots:
			if not Batch1._at_furniture(rec0.rects, spot):
				at_furniture = false
				failures.append("%s spot %s" % [kind, str(spot)])
		var wide := detailed.spots(kind, width, 0)
		inside = inside and wide.size() == spots.size()
	check.call(handled, "detailed: the venue kinds are routed to a Detailed draw")
	check.call(drawn, "detailed: every venue kind draws, in use and empty")
	check.call(inside, "detailed: a venue room paints only inside its own rect")
	check.call(at_furniture, "detailed: people at venue spots are at furniture %s" % str(failures))
