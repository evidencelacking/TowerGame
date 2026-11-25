extends RefCounted
## Overview map (#489): each filter's cell colour is the main view's colour for the same room, a click maps to the right
## floor and column and moves the camera, alert pins appear for the active alerts, and a quiet frame redraws nothing.

const Map := preload("res://scripts/view/overview_map.gd")
const HeatLook := preload("res://scripts/view/heat_look.gd")
const DisruptionLook := preload("res://scripts/view/disruption_look.gd")
const AlertsScript := preload("res://scripts/sim/alerts.gd")
const AlertMarkers := preload("res://scripts/view/alert_markers.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")
const TestPests := preload("res://tests/test_pests.gd")
const TestFire := preload("res://tests/test_fire.gd")


static func run(check: Callable) -> void:
	_colours(check)
	_clicks(check)
	_pins(check)
	_quiet(check)


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and absf(a.a - b.a) < 0.01


## Paints the map for `which` and compares the pixel at each painted cell to the colour the main view uses.
static func _matching(check: Callable, t: Object, which: int) -> void:
	var image := Image.create(Map.COLS, Map.ROWS, false, Image.FORMAT_RGBA8)
	Map.paint(image, t, which)
	var cells: Array[Dictionary] = []
	if which == Map.PROBLEMS:
		for room: Dictionary in DisruptionLook.suffering_rooms(t):
			cells.append({"rect": room["rect"], "colour": DisruptionLook.tint(room["points"])})
	else:
		for room: Dictionary in HeatLook.painted_rooms(t, which):
			cells.append({"rect": room["rect"], "colour": room["colour"]})
	var same := 0
	for cell: Dictionary in cells:
		var rect: Rect2i = cell["rect"]
		if _close(image.get_pixel(rect.position.x / VC.CELL_W, rect.position.y / VC.CELL_H), cell["colour"]):
			same += 1
	check.call(not cells.is_empty() and same == cells.size(), "overview map: every %s cell is the main view's colour (%d of %d)" % [Map.FILTER_NAMES[which], same, cells.size()])


static func _colours(check: Callable) -> void:
	var office := TestEvaluation._pair("office")
	for which: int in [HeatLook.INCOME, HeatLook.RENT, HeatLook.GRADE]:
		_matching(check, office, which)
	var hotel := TestPests._tower()
	TestPests._room(hotel, "hotel_single", 3, 100)
	TestPests._room(hotel, "hotel_single", 3, 104)
	_matching(check, hotel, HeatLook.HOTEL)
	var condo := TestEvaluation._pair("condo")
	condo.floors.fill_span(4, 100, 200)
	condo.rooms.place_room(condo.grid, condo.floors, condo.ledger, 0, Catalogue.IDS.find("nightclub"), 4, 108)
	_matching(check, condo, Map.PROBLEMS)
	var off := Image.create(Map.COLS, Map.ROWS, false, Image.FORMAT_RGBA8)
	Map.paint(off, office, HeatLook.OFF)
	var id := -1
	for r: int in office.rooms.room_ids():
		if office.rooms.kind_of(r) == "office":
			id = r
			break
	var run: Array[int] = office.grid.run_of(id)
	check.call(id > 0 and _close(off.get_pixel(run[1], VC.floor_to_row(run[0])), Map.kind_colour("office")), "overview map: the Off filter paints the room's kind colour")
	# Following the main view.
	var map := Map.new()
	var cam := TowerCamera.new()
	map.bind(office, cam)
	HeatLook.mode = HeatLook.RENT
	map.refresh()
	check.call(map.filter == HeatLook.RENT, "overview map: the filter follows the main heat mode")
	HeatLook.mode = HeatLook.OFF
	map.refresh()
	check.call(map.filter == HeatLook.RENT, "overview map: switching the heat mode off leaves the filter alone")
	(map.panel.find_child("Grade", true, false) as Button).pressed.emit()
	check.call(map.filter == HeatLook.GRADE, "overview map: a filter button sets the filter")
	map.free()
	cam.free()


static func _clicks(check: Callable) -> void:
	var t := TestEvaluation._pair("office")
	var camera := TowerCamera.new()
	var map := Map.new()
	map.bind(t, camera)
	var p := Map.world_to_map(Vector2(120.5 * VC.CELL_W, AlertMarkers.world_y_of(30)))
	check.call(Map.cell_at(p) == Vector2i(120, 30), "overview map: a point of the map reads as its floor and column")
	check.call(Map.cell_at(Map.world_to_map(Vector2(5.5 * VC.CELL_W, AlertMarkers.world_y_of(-4)))) == Vector2i(5, -4), "overview map: a floor below ground reads right")
	check.call(Map.cell_at(Vector2.ZERO) == Vector2i(0, 100) and Map.cell_at(Map.DISPLAY * 2.0) == Vector2i(Map.COLS - 1, -10), "overview map: the corners are the top and bottom floors")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p
	map._on_gui_input(press)
	check.call(int(camera._focus.x / VC.CELL_W) == 120 and Map.cell_at(Map.world_to_map(camera._focus)).y == 30, "overview map: a click moves the camera to that floor and column")
	var move := InputEventMouseMotion.new()
	move.position = Map.world_to_map(Vector2(40.5 * VC.CELL_W, AlertMarkers.world_y_of(10)))
	map._on_gui_input(move)
	check.call(int(camera._focus.x / VC.CELL_W) == 40 and Map.cell_at(Map.world_to_map(camera._focus)).y == 10, "overview map: dragging scrolls the camera live")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	map._on_gui_input(release)
	move.position = Map.world_to_map(Vector2(80.5 * VC.CELL_W, AlertMarkers.world_y_of(10)))
	map._on_gui_input(move)
	check.call(int(camera._focus.x / VC.CELL_W) == 40, "overview map: after the button is released a move does nothing")
	var rect := Map.view_rect(Vector2(1600.0, 1760.0), 2.0, Vector2(1920.0, 1080.0))
	check.call(is_equal_approx(rect.get_center().x, Map.DISPLAY.x * 0.5) and is_equal_approx(rect.size.x, 960.0 / 3200.0 * Map.DISPLAY.x), "overview map: the camera rectangle is the view over the world, scaled")
	map.free()
	camera.free()


static func _pins(check: Callable) -> void:
	var all: Array = [[AlertsScript.FIRE, 30, 1, 5], [AlertsScript.EVENT, 3, 0, 103], [AlertsScript.THREAT, 0, 1, 0], [AlertsScript.EVENT, -9, 0, 9]]
	var pins := Map.pins_for(all, null)
	check.call(pins.size() == 3 and pins[0]["floor"] == 30 and pins[2]["floor"] == -9, "overview map: a pin per located alert, none for an alert with no floor")
	check.call(Map.cell_at(pins[0]["pos"]).y == 30 and Map.cell_at(pins[2]["pos"]).y == -9, "overview map: each pin sits on its floor")
	var f := TestFire._tower(3)
	TestFire._put(f, "security", 3, 100)
	TestFire._put(f, "office", 30, 100)
	TestFire._force(f)
	check.call(TestFire._until_burning(f), "overview map: a fire breaks out")
	var map := Map.new()
	var cam := TowerCamera.new()
	map.bind(f, cam)
	map.refresh()
	var floor_number: int = f.rooms.floors_of(f.grid, f.fire.burning_rooms()[0])[0]
	var found := false
	for pin: Dictionary in map.pins():
		found = found or (pin["kind"] == AlertsScript.FIRE and pin["floor"] == floor_number and Map.cell_at(pin["pos"]).y == floor_number)
	check.call(found, "overview map: the burning room has a pin on its floor")
	map.free()
	cam.free()


static func _quiet(check: Callable) -> void:
	var t := TestEvaluation._pair("office")
	var map := Map.new()
	var cam := TowerCamera.new()
	map.bind(t, cam)
	map.refresh()
	check.call(map.image_builds == 1 and map.mark_draws == 1, "overview map: the first refresh builds the image and the marks once")
	map.refresh()
	map.refresh()
	check.call(map.image_builds == 1 and map.mark_draws == 1, "overview map: frames with no change redraw nothing")
	for n: int in 20:
		t.step()
		map.refresh()
	check.call(map.image_builds == 1, "overview map: the Off filter does not rebuild with the ticks")
	map.set_filter(HeatLook.INCOME)
	map.refresh()
	check.call(map.image_builds == 2, "overview map: a new filter rebuilds the image")
	for n: int in 10:
		t.step()
		map.refresh()
	check.call(map.image_builds == 2, "overview map: the same filter does not rebuild inside its interval")
	for n: int in HeatOverlay.REFRESH_TICKS:
		t.step()
		map.refresh()
	check.call(map.image_builds == 3, "overview map: it rebuilds once the filter's interval has passed")
	var before := map.image_builds
	t.floors.fill_span(5, 100, 120)
	map.refresh()
	check.call(map.image_builds == before + 1, "overview map: a layout change rebuilds the image")
	check.call(Map.refresh_ticks(HeatLook.TRAFFIC) < Map.refresh_ticks(HeatLook.INCOME) and Map.refresh_ticks(HeatLook.INCOME) < Map.refresh_ticks(HeatLook.RENT), "overview map: each filter keeps the heat overlay's own interval")
	map.free()
	cam.free()
