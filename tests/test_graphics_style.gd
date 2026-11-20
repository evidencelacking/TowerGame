extends RefCounted
## Graphics style (#301): Classic and Detailed both draw every room kind, link, shaft, car, person and the
## sky without error; Classic draws exactly what the Look scripts draw directly (the pixel-identical proof);
## Detailed matches it for now; the setting picks the style live; spots map between densities.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestPests := preload("res://tests/test_pests.gd")

const TestDetailedBatch1 := preload("res://tests/test_detailed_batch1.gd")
const BASEMENT: Array[String] = ["recycling", "parking_ramp", "parking_space"]


## Records every draw call, so two draws can be compared.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Variant, c: Color, filled: bool = true, width: float = -1.0) -> void:
		calls.append(["rect", r, c, filled, width])

	func draw_line(a: Vector2, b: Vector2, c: Color, width: float = -1.0) -> void:
		calls.append(["line", a, b, c, width])

	func draw_string(_font: Object, at: Vector2, text: String, _align: int, _w: float, _size: int, c: Color) -> void:
		calls.append(["string", at, text, c])


## A stand-in for a style drawn at double density, to prove spots scale by density.
class Double:
	extends GraphicsStyle

	func density() -> int:
		return 2


static func run(check: Callable) -> void:
	var classic := GraphicsStyle.for_detailed(false)
	var detailed := GraphicsStyle.for_detailed(true)
	check.call(classic != detailed, "graphics: Classic and Detailed are two backends")
	var saved := ViewSettings.detailed_graphics
	ViewSettings.detailed_graphics = false
	check.call(GraphicsStyle.current() == classic, "graphics: the setting off picks Classic")
	ViewSettings.detailed_graphics = true
	check.call(GraphicsStyle.current() == detailed, "graphics: switching the setting picks Detailed at once, no restart")
	ViewSettings.detailed_graphics = saved
	_rooms(check, classic, detailed)
	_every_recipe(check, classic, detailed)
	_the_rest(check, classic, detailed)
	_spots(check, classic, detailed)
	TestDetailedBatch1.run(check)


## Placed rooms in every state they are drawn in, through the full room path.
static func _rooms(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var t := TestPests._tower()
	var ids: Dictionary = {}
	var floor_number := 3
	for kind: String in RoomLook.KINDS:
		if BASEMENT.has(kind):
			continue
		t.floors.fill_span(floor_number, 100, 139)
		ids[kind] = TestPests._room(t, kind, floor_number, 100)
		floor_number += 1
	t.floors.fill_span(-1, 90, 131)
	ids["parking_ramp"] = TestPests._room(t, "parking_ramp", -1, 104)
	ids["parking_space"] = TestPests._room(t, "parking_space", -1, 108)
	ids["recycling"] = TestPests._room(t, "recycling", -3, 100)
	var every_kind := true
	var same_as_looks := true
	var detailed_draws := true
	var rect := Rect2i(0, 0, 8 * 8, VC.CELL_H)
	for kind: String in RoomLook.KINDS:
		var id: int = ids[kind]
		if id < 0:
			every_kind = false
			continue
		for lit: bool in [false, true]:
			var direct := Recorder.new()
			RoomLook.draw(direct, t, id, rect, null, lit, false)
			var by_classic := Recorder.new()
			classic.room(by_classic, t, id, rect, null, lit, false)
			var by_detailed := Recorder.new()
			detailed.room(by_detailed, t, id, rect, null, lit, false)
			same_as_looks = same_as_looks and not direct.calls.is_empty() and by_classic.calls == direct.calls
			detailed_draws = detailed_draws and not by_detailed.calls.is_empty()
	check.call(every_kind, "graphics: every room kind was placed for the draw test")
	check.call(same_as_looks, "graphics: Classic draws every placed room kind exactly as RoomLook does")
	check.call(detailed_draws, "graphics: Detailed draws every placed room kind")


## Every catalogue kind that has a recipe, as a recipe and as a suite.
static func _every_recipe(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var drawn := 0
	var same := true
	var detailed_draws := true
	for kind: String in CatalogueScript.IDS:
		if not RoomRecipes.has(kind):
			continue
		drawn += 1
		var rect := Rect2i(0, 0, 8 * 8, VC.CELL_H)
		for lit: bool in [false, true]:
			var direct := Recorder.new()
			RoomLook.draw_recipe(direct, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit)
			var by_classic := Recorder.new()
			classic.recipe(by_classic, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit)
			var by_detailed := Recorder.new()
			detailed.recipe(by_detailed, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit)
			same = same and not direct.calls.is_empty() and by_classic.calls == direct.calls
			detailed_draws = detailed_draws and not by_detailed.calls.is_empty()
		if RoomRecipes.has_suite(kind):
			var suite_direct := Recorder.new()
			RoomLook.draw_suite(suite_direct, kind, Rect2i(0, 0, 16 * 8, VC.CELL_H), 1)
			var suite_classic := Recorder.new()
			classic.suite(suite_classic, kind, Rect2i(0, 0, 16 * 8, VC.CELL_H), 1)
			var suite_detailed := Recorder.new()
			detailed.suite(suite_detailed, kind, Rect2i(0, 0, 16 * 8, VC.CELL_H), 1)
			same = same and not suite_direct.calls.is_empty() and suite_classic.calls == suite_direct.calls
			detailed_draws = detailed_draws and not suite_detailed.calls.is_empty()
	check.call(drawn > 10, "graphics: the catalogue has many kinds with recipes to draw (%d)" % drawn)
	check.call(same, "graphics: Classic draws every recipe and suite exactly as RoomLook does")
	check.call(detailed_draws, "graphics: Detailed draws every recipe and suite")
	var lobby_classic := Recorder.new()
	classic.recipe(lobby_classic, "lobby", Rect2i(0, 0, 64, VC.CELL_H * 2), Palette.hue("lobby"), true)
	var lobby_detailed := Recorder.new()
	detailed.recipe(lobby_detailed, "lobby", Rect2i(0, 0, 64, VC.CELL_H * 2), Palette.hue("lobby"), true)
	check.call(not lobby_classic.calls.is_empty() and not lobby_detailed.calls.is_empty() and lobby_detailed.calls != lobby_classic.calls, "graphics: both styles draw the lobby, Detailed in its own look (#302)")


static func _the_rest(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var p := Palette.get_palette()
	var span := Rect2i(0, 0, 8 * 8, VC.CELL_H * 2)
	var shaft_rect := Rect2i(16, 0, 16, VC.CELL_H * 4)
	var caps: Array[Rect2i] = [Rect2i(16, 0, 16, VC.CELL_H - VC.SLAB_H)]
	var doors: Array[int] = [VC.CELL_H - VC.SLAB_H, VC.CELL_H * 3 - VC.SLAB_H]
	var level_bottom := func(level: int) -> int: return (level + 1) * VC.CELL_H - VC.SLAB_H
	for style: GraphicsStyle in [classic, detailed]:
		var label := "Classic" if style == classic else "Detailed"
		for kind: String in ["stairs", "escalator"]:
			var rec := Recorder.new()
			style.link(rec, kind, span)
			var direct := Recorder.new()
			TransportLook.draw_link(direct, kind, span)
			check.call(not rec.calls.is_empty() and rec.calls == direct.calls, "graphics: %s draws %s" % [label, kind])
		for see_through: bool in [false, true]:
			var rec := Recorder.new()
			style.shaft(rec, shaft_rect, Palette.hue("shaft"), caps, doors, see_through)
			check.call(not rec.calls.is_empty(), "graphics: %s draws a shaft (see-through %s)" % [label, str(see_through)])
		var car_rec := Recorder.new()
		style.car(car_rec, Rect2i(16, 0, 16, VC.CELL_H), Rect2i(19, 3, 10, VC.CELL_H - VC.SLAB_H - 3), 1.0, 0, 3, Palette.hue("car"), p["people"], p["lamp"], level_bottom)
		check.call(not car_rec.calls.is_empty(), "graphics: %s draws a car with riders" % label)
		var walker := Recorder.new()
		style.person(walker, 10, 20, Color.RED, Color.WHITE, true, 0, 1)
		var direct_walker := Recorder.new()
		ActivityLook.draw_person(direct_walker, 10, 20, Color.RED, Color.WHITE, true, 0, 1)
		check.call(not walker.calls.is_empty() and walker.calls == direct_walker.calls, "graphics: %s draws a person" % label)
		var every_activity := true
		for act: int in ActivityLook.NAMES.size():
			var rec := Recorder.new()
			style.activity(rec, 10, 20, act, 0, Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
			every_activity = every_activity and not rec.calls.is_empty()
		check.call(every_activity, "graphics: %s draws every activity" % label)
		var sky := Recorder.new()
		style.sky(sky, p, 12 * 60, 0, 0, 800, 800, 400)
		var direct_sky := Recorder.new()
		SkyLook.draw(direct_sky, p, 12 * 60, SkyLook.daylight, SkyLook.rain, 0, 0, 800, 800, 400, VC.CELL_H)
		check.call(not sky.calls.is_empty() and sky.calls == direct_sky.calls, "graphics: %s draws the sky" % label)


static func _spots(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	check.call(GraphicsStyle.scale_spot(Vector2i(10, 28), 1, 2) == Vector2i(20, 56), "graphics: a spot doubles from density 1 to 2")
	check.call(GraphicsStyle.scale_spot(Vector2i(20, 56), 2, 1) == Vector2i(10, 28), "graphics: a spot halves from density 2 to 1")
	var double := Double.new()
	var round_trip := true
	var shared := true
	var doubled := true
	var count := 0
	for kind: String in CatalogueScript.IDS:
		if not RoomRecipes.has(kind):
			continue
		var base := RoomRecipes.spots(kind, 64)
		count += base.size()
		shared = shared and classic.spots(kind, 64) == base and detailed.spots(kind, 64).size() == base.size()
		var wide := double.spots(kind, 64)
		doubled = doubled and wide.size() == base.size()
		for i in base.size():
			doubled = doubled and wide[i] == base[i] * 2
			round_trip = round_trip and GraphicsStyle.scale_spot(wide[i], 2, 1) == base[i]
	check.call(count > 0, "graphics: the recipes have spots to map")
	check.call(shared, "graphics: Classic reports the recipes' spots as they are, Detailed the same spots (doubled)")
	check.call(doubled, "graphics: a double-density style puts each shared spot at twice the pixels")
	check.call(round_trip, "graphics: every recipe spot survives a trip to density 2 and back")
