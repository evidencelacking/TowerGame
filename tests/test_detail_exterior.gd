extends RefCounted
## The Detailed exterior (#306): facade edges and roofs on the built floor runs, the street at the ground and
## the city skyline. Checks that Classic draws none of it, that roofs sit only where nothing is above, that
## everything stays near its floor run, that the street leaves built stretches clear, that the skyline grows
## with the star rating, that night lights windows by day not, and that drawing is repeatable.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailExterior := preload("res://scripts/view/detail_exterior.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const Renderer := preload("res://scripts/view/tower_renderer.gd")

const GROUND := 3200
const WORLD_W := 3200
const LIT := Color("ffd27a")


## Records draw_rect calls with their colours.
class Recorder:
	extends RefCounted
	var rects: Array[Rect2] = []
	var colors: Array[Color] = []

	func draw_rect(r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		rects.append(Rect2(r))
		colors.append(c)

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		pass

	func top() -> float:  ## The highest edge drawn, as a y (smaller is higher).
		var best := 1.0e9
		for r: Rect2 in rects:
			best = minf(best, r.position.y)
		return best

	func count_of(c: Color) -> int:
		var n := 0
		for k: Color in colors:
			if k.is_equal_approx(c):
				n += 1
		return n


## A stack three floors tall at the left and a lower wing beside it.
static func _runs() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	rects.append(Rect2i(800, 96, 160, 32))
	rects.append(Rect2i(800, 128, 160, 32))
	rects.append(Rect2i(800, 160, 160, 32))
	rects.append(Rect2i(960, 160, 96, 32))
	return rects


static func run(check: Callable) -> void:
	var classic := GraphicsStyle.for_detailed(false)
	var detailed := GraphicsStyle.for_detailed(true)
	var p := Palette.get_palette()
	var rects := _runs()

	var quiet := Recorder.new()
	classic.exterior(quiet, rects, SkyLook.FULL)
	classic.street(quiet, SkyLook.FULL, WORLD_W, GROUND, {})
	classic.skyline(quiet, p, SkyLook.FULL, false, 3, 1, WORLD_W, GROUND)
	check.call(quiet.rects.is_empty(), "exterior: Classic draws no facade, roof, street or skyline")

	# Roofs sit only where nothing is above.
	var runs := DetailExterior.roof_runs(rects)
	var spans: Array[Vector2i] = []
	var rank_ok := true
	for roof: Array in runs:
		spans.append(Vector2i(int(roof[0]), int(roof[1])))
		rank_ok = rank_ok and (int(roof[3]) == 0) == (int(roof[1]) == 96)
	check.call(runs.size() == 2 and spans.has(Vector2i(800, 96)) and spans.has(Vector2i(960, 160)), "exterior: only the top of a stack and the open wing get a roof")
	check.call(rank_ok, "exterior: the highest stretch is rank 0, the lower wing is not")

	# Everything stays close to its floor runs: edges inside the run, roofs a little above it.
	for dl: int in [SkyLook.FULL, 0]:
		var rec := Recorder.new()
		detailed.exterior(rec, rects, dl)
		var bounds := Rect2(790, 50, 276, 150)
		var inside := true
		for r: Rect2 in rec.rects:
			inside = inside and bounds.encloses(r)
		check.call(rec.rects.size() > 100 and inside, "exterior: the facade and roof draw and stay near their floor runs (daylight %d)" % dl)
	var first := Recorder.new()
	var again := Recorder.new()
	detailed.exterior(first, rects, SkyLook.FULL)
	detailed.exterior(again, rects, SkyLook.FULL)
	check.call(first.rects == again.rects, "exterior: drawing twice gives the same picture")
	var edges := Recorder.new()
	detailed.exterior(edges, [Rect2i(800, 96, 160, 32)] as Array[Rect2i], SkyLook.FULL)
	var has_left := false
	var has_right := false
	for r: Rect2 in edges.rects:
		has_left = has_left or (r.position.x <= 800.5 and r.position.y >= 96.0 and r.size.y >= 8.0)
		has_right = has_right or (r.end.x >= 959.5 and r.position.y >= 96.0 and r.size.y >= 8.0)
	check.call(has_left and has_right, "exterior: both ends of a run get a brick edge")
	var day_roof := Recorder.new()
	var night_roof := Recorder.new()
	detailed.exterior(day_roof, rects, SkyLook.FULL)
	detailed.exterior(night_roof, rects, 0)
	check.call(night_roof.rects.size() > day_roof.rects.size(), "exterior: rooftop lights and beacons add light at night")

	# The street leaves built stretches of floor 1 clear.
	var wall: Dictionary = {}
	for column: int in WORLD_W / VC.CELL_W:
		wall[column] = true
	var closed := Recorder.new()
	detailed.street(closed, SkyLook.FULL, WORLD_W, GROUND, wall)
	var open := Recorder.new()
	detailed.street(open, SkyLook.FULL, WORLD_W, GROUND, {})
	var above_closed := 0
	var above_open := 0
	for r: Rect2 in closed.rects:
		if r.position.y < GROUND - 1.0:
			above_closed += 1
	for r: Rect2 in open.rects:
		if r.position.y < GROUND - 1.0:
			above_open += 1
	check.call(above_open > 50 and above_closed < above_open, "street: trees, lamps and walkers stand where floor 1 is unbuilt, not over the tower")
	check.call(closed.rects.size() > 100, "street: the sidewalk and road draw under a built floor 1")

	# The skyline grows with the star rating.
	var low := Recorder.new()
	var high := Recorder.new()
	detailed.skyline(low, p, SkyLook.FULL, false, 1, 0, WORLD_W, GROUND)
	detailed.skyline(high, p, SkyLook.FULL, false, 5, 0, WORLD_W, GROUND)
	check.call(high.top() < low.top() - 20.0, "skyline: five stars reach higher than one star")
	check.call(high.rects.size() > low.rects.size(), "skyline: five stars fill more of the city than one star")
	var mid_a := Recorder.new()
	var mid_b := Recorder.new()
	detailed.skyline(mid_a, p, SkyLook.FULL, false, 3, 1, WORLD_W, GROUND)
	detailed.skyline(mid_b, p, SkyLook.FULL, false, 3, 1, WORLD_W, GROUND)
	check.call(mid_a.rects == mid_b.rects and mid_a.rects.size() > 100, "skyline: repeatable, no shimmer")
	var day := Recorder.new()
	var night := Recorder.new()
	detailed.skyline(day, p, SkyLook.FULL, false, 4, 1, WORLD_W, GROUND)
	detailed.skyline(night, p, 0, false, 4, 1, WORLD_W, GROUND)
	check.call(night.count_of(LIT) > 20 and day.count_of(LIT) == 0, "skyline: windows light up at night and not by day")
	var all_above := true
	for r: Rect2 in night.rects:
		all_above = all_above and r.end.y <= GROUND + 0.5
	check.call(all_above, "skyline: buildings stand on the ground line, none below it")

	# The renderer paints the exterior in front of the shafts and behind the moving layers.
	var order: Array[String] = Renderer.DRAW_ORDER
	check.call(order.has("_draw_exterior") and order.find("_draw_shafts") < order.find("_draw_exterior") and order.find("_draw_exterior") < order.find("_draw_belts"), "exterior: drawn after the shafts, before the moving layers")
