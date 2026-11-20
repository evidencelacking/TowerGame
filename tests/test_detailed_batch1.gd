extends RefCounted
## Detailed graphics batch 1 (#302): the lobby, every office variant and suite, condos, hotel rooms and
## housekeeping draw in the Detailed look without error, stay inside their room, report spots at double
## density that land inside the room and on furniture, and leave Classic alone.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const DetailLight := preload("res://scripts/view/detail_light.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestPests := preload("res://tests/test_pests.gd")

const REACH := 8  ## Pixels beside a furniture shape that still count as being at it.
const IDS_TRIED := 64  ## Room ids tried to meet every variant of a kind.


## Records draw_rect calls.
class Recorder:
	extends RefCounted
	var rects: Array[Rect2] = []

	func draw_rect(r: Variant, _c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		rects.append(Rect2(r))

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		pass


static func _width_px(kind: String) -> int:
	if kind == "lobby":
		return 64 * VC.CELL_W
	return int(CatalogueScript.field(kind, "width")) * VC.CELL_W


static func _inside(rects: Array[Rect2], bounds: Rect2) -> bool:
	for r: Rect2 in rects:
		if not bounds.encloses(r):
			return false
	return true


static func run(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var classic := GraphicsStyle.for_detailed(false)
	check.call(detailed.density() == 2 and classic.density() == 1, "detailed: Detailed is double density, Classic is not")
	_draws(check)
	_suites(check)
	_placed(check, classic, detailed)
	_spots(check)
	_lighting(check)


## Every kind, every variant, in use and empty, at the kind's width and wider: draws and stays in its rect.
static func _draws(check: Callable) -> void:
	var drawn := true
	var inside := true
	var all_variants := true
	var kinds := 0
	for kind: String in DetailRooms.KINDS:
		kinds += 1
		var seen: Dictionary = {}
		for id: int in IDS_TRIED:
			seen[RoomRecipes.variant_for(kind, id)] = true
		all_variants = all_variants and seen.size() == RoomRecipes.variant_count(kind)
		for width: int in [_width_px(kind), _width_px(kind) + 3 * VC.CELL_W]:
			var rect := Rect2i(40, 96, width, VC.CELL_H * (2 if kind == "lobby" else 1))
			var bounds := Rect2(rect)
			for id: int in IDS_TRIED:
				for lit: bool in [false, true]:
					var rec := Recorder.new()
					DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), lit, false, id)
					drawn = drawn and not rec.rects.is_empty()
					inside = inside and _inside(rec.rects, bounds)
	check.call(kinds == 7, "detailed: batch 1 has seven kinds (lobby, office, condo, three hotel rooms, housekeeping)")
	check.call(all_variants, "detailed: the room ids tried reach every variant of every batch 1 kind")
	check.call(drawn, "detailed: every batch 1 kind and variant draws, in use and empty")
	check.call(inside, "detailed: a batch 1 room paints only inside its own rect")


static func _suites(check: Callable) -> void:
	var count := 0
	var drawn := true
	for kind: String in DetailRooms.KINDS:
		if not RoomRecipes.has_suite(kind):
			continue
		count += 1
		var rect := Rect2i(0, 64, 16 * VC.CELL_W, VC.CELL_H)
		var rec := Recorder.new()
		GraphicsStyle.for_detailed(true).suite(rec, kind, rect, 3)
		drawn = drawn and not rec.rects.is_empty() and _inside(rec.rects, Rect2(rect))
	check.call(count >= 1, "detailed: a batch 1 kind has a joined suite recipe (%d)" % count)
	check.call(drawn, "detailed: joined suites draw inside their union rect")


## Placed rooms through the full room path: Detailed differs from Classic for batch 1 and equals it for the rest.
static func _placed(check: Callable, classic: GraphicsStyle, detailed: GraphicsStyle) -> void:
	var t := TestPests._tower()
	var ids: Dictionary = {}
	var floor_number := 3
	for kind: String in ["office", "condo", "hotel_single", "hotel_twin", "hotel_suite", "housekeeping"]:
		t.floors.fill_span(floor_number, 100, 131)
		ids[kind] = TestPests._room(t, kind, floor_number, 100)
		floor_number += 1
	var differs := true
	var rect := Rect2i(0, 0, 8 * 8, VC.CELL_H)
	for kind: String in ids:
		var id: int = ids[kind]
		if id < 0:
			differs = false
			continue
		var by_classic := Recorder.new()
		classic.room(by_classic, t, id, rect, null, true, false)
		var by_detailed := Recorder.new()
		detailed.room(by_detailed, t, id, rect, null, true, false)
		differs = differs and not by_detailed.rects.is_empty() and by_detailed.rects != by_classic.rects
	check.call(differs, "detailed: placed batch 1 rooms draw in the Detailed look")
	# A dirty hotel room looks different from a clean one (the state tint and marks carry over).
	var hotel: int = ids["hotel_single"]
	TestPests._dirty(t, hotel, 0)
	var dirty := Recorder.new()
	detailed.room(dirty, t, hotel, rect, null, false, false)
	TestPests._clean(t, hotel)
	var clean := Recorder.new()
	detailed.room(clean, t, hotel, rect, null, false, false)
	check.call(dirty.rects != clean.rects, "detailed: a dirty hotel room looks different from a clean one")


## Spots at density 2: the shared recipe spots doubled and inside the room, and the Detailed furniture drawn
## where they are: a piece of furniture (a rect under 40 world px wide, standing on the floor) spans each spot.
static func _spots(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var doubled := true
	var inside := true
	var at_furniture := true
	var failures: Array[String] = []
	for kind: String in DetailRooms.KINDS:
		var width := _width_px(kind)
		for variant: int in RoomRecipes.variant_count(kind):
			var base := RoomRecipes.spots(kind, width, variant)
			var wide := detailed.spots(kind, width, variant)
			doubled = doubled and wide.size() == base.size()
			var rect := Rect2i(0, 0, width, VC.CELL_H)
			var rec := Recorder.new()
			# an id that picks this variant
			var id := 0
			for candidate: int in IDS_TRIED:
				if RoomRecipes.variant_for(kind, candidate) == variant:
					id = candidate
					break
			DetailRooms.draw(rec, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true, false, id)
			for i: int in base.size():
				doubled = doubled and wide[i] == base[i] * 2
				inside = inside and wide[i].x >= 0 and wide[i].x + 2 * VC.FIGURE_W <= width * 2 and wide[i].y - 2 * VC.FIGURE_H >= 0 and wide[i].y <= (VC.CELL_H - VC.SLAB_H) * 2
				if kind != "lobby" and not _at_furniture(rec.rects, base[i]):
					at_furniture = false
					failures.append("%s v%d spot %s" % [kind, variant, str(base[i])])
	check.call(doubled, "detailed: every batch 1 spot is the shared spot at twice the pixels")
	check.call(inside, "detailed: every batch 1 spot, doubled, holds a doubled figure inside the room")
	check.call(at_furniture, "detailed: people at office, condo, hotel and housekeeping spots are at furniture %s" % str(failures))


## Whether a drawn piece of furniture (narrow, resting on the floor) lies under the figure at a spot (world pixels).
static func _at_furniture(rects: Array[Rect2], spot: Vector2i) -> bool:
	var centre := float(spot.x) + VC.FIGURE_W * 0.5
	for r: Rect2 in rects:
		if r.size.x > 40.0 or r.size.y < 2.0 or r.end.y < float(spot.y) - 8.0 or r.end.y > float(VC.CELL_H):
			continue
		if r.position.x - REACH <= centre and r.end.x + REACH >= centre:
			return true
	return false


## Night is lighting (#305): lit rooms record glows inside their own rect only at night, empty ones none
## (a sleeper's bedside lamp aside), and the ambient colour follows the sky.
static func _lighting(check: Callable) -> void:
	var saved := SkyLook.daylight
	var rect := Rect2i(160, 320, 128, 32)
	var hue := Palette.hue("condo")
	SkyLook.daylight = SkyLook.FULL
	DetailLight.clear()
	DetailRooms.draw(Recorder.new(), "condo", rect, hue, true)
	check.call(DetailLight.lights.is_empty(), "detailed: no lights are recorded by day")
	SkyLook.daylight = 0
	DetailLight.clear()
	DetailRooms.draw(Recorder.new(), "condo", rect, hue, false)
	check.call(DetailLight.lights.is_empty(), "detailed: an empty room casts no light at night")
	DetailRooms.draw(Recorder.new(), "hotel_single", Rect2i(160, 320, 32, 32), hue, false, false, 0, false, true)
	check.call(DetailLight.lights.size() == 1, "detailed: a sleeper's room has only its bedside lamp lit")
	DetailLight.clear()
	DetailRooms.draw(Recorder.new(), "condo", rect, hue, true)
	var inside := not DetailLight.lights.is_empty()
	for light: Array in DetailLight.lights:
		inside = inside and Rect2(rect).encloses(light[0])
	check.call(inside, "detailed: a lit room records glows clipped to its own rect")
	check.call(DetailLight.ambient(0).get_luminance() < DetailLight.ambient(SkyLook.FULL).get_luminance() and DetailLight.intensity(SkyLook.FULL) == 0.0 and DetailLight.intensity(0) == 1.0, "detailed: ambient darkens and lights strengthen as the sky goes dark")
	DetailLight.clear()
	SkyLook.daylight = saved
