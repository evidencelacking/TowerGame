extends SceneTree
## Automated UI tester (#262). Loads the real main scene in demo mode and plays it the way a
## mouse would: every action is a synthetic InputEvent delivered through Input.parse_input_event at a screen
## position computed from a grid cell through the camera. Nothing here calls the sim or the ghost to
## perform an action; the sim is only READ afterwards to check the result, and the ghost verdict
## (green or red) is read just before the click so it can be compared with what really happened.
##
## Run through tools/ui_test.py (headless, for CI) or directly:
##   godot --path . --script res://tools/ui_test.gd -- out=C:/path/report.txt shots=C:/path/shots
## Windowed runs (no --headless) also take a screenshot of every failing case into shots=.
## Known failures live in tools/ui_expected.json (case id -> issue) and show as XFAIL.
##
## Statuses: PASS, FAIL, XFAIL (failed, and listed as a known issue), XPASS (listed but passed:
## the issue looks fixed, drop it from the list), SKIP (the game cannot build it yet).
## Exits with the number of FAIL rows.

const VC := preload("res://scripts/view/view_consts.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const SynergyLookScript := preload("res://scripts/view/synergy_look.gd")
const GhostScript := preload("res://scripts/view/placement_ghost.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const PeopleViewScript := preload("res://scripts/view/people_view.gd")
const ViewSettingsScript := preload("res://scripts/view/view_settings.gd")
const GraphicsStyleScript := preload("res://scripts/view/graphics_style.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const TowerCameraScript := preload("res://scripts/view/tower_camera.gd")
const EXPECTED_PATH := "res://tools/ui_expected.json"
const WAIT_FRAMES := 3  ## Frames after an input before the view has caught up.
const SETTLE_TICKS := 6  ## Sim ticks after a click: commands are due the tick after they are queued.
const PEOPLE_TICK_LIMIT := 30000  ## How long to run the sim waiting for the first person to appear.

var _main: Node
var _driver: SimDriver
var _tower: Tower
var _ghost: PlacementGhost
var _toolbar: Toolbar
var _camera: Camera2D
var _rows: Array[Dictionary] = []
var _expected: Dictionary = {}
var _mouse: Vector2 = Vector2.ZERO
var _out_path: String = ""
var _shots_dir: String = ""
var _headless: bool = DisplayServer.get_name() == "headless"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_path = arg.get_slice("=", 1)
		elif arg.begins_with("shots="):
			_shots_dir = arg.get_slice("=", 1)
	_load_expected()
	root.size = Vector2i(1920, 1080)  # A headless window is only 1024 x 600: too small for the wide drags.
	DemoMode.forced = true
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(2)
	_driver = _main.get_node("Hud/SimDriver")
	_tower = _driver.tower
	_ghost = _main.get_node("PlacementGhost")
	_toolbar = _main.get_node("Toolbar")
	_camera = _main.get_node("TowerCamera")
	_camera.set_zoom_index(0)  # Zoom 1: a cell is 8 x 32 px, so wide drags fit the window.
	_step(SETTLE_TICKS)
	await _run_all()
	_finish()


# ---------------------------------------------------------------- the plan

func _run_all() -> void:
	_record("demo.setup", "demo", "Demo tower: huge balance, 5 stars, unlock-all, HUD says DEMO", "-",
		_tower.ledger.balance >= DemoMode.FUNDS / 2 and _tower.stars == 5 and _tower.unlock_all and _hud_says_demo(),
		"balance %d, stars %d, unlock_all %s, HUD DEMO %s" % [_tower.ledger.balance, _tower.stars, str(_tower.unlock_all), str(_hud_says_demo())])
	await _toolbar_cases()
	await _structure_cases()
	await _room_cases()
	await _link_cases()
	await _shaft_cases()
	await _shaft_end_cases()
	await _car_and_stop_cases()
	await _zoom2_cases()
	await _bulldoze_cases()
	await _window_cases()
	await _news_cases()
	await _behind_cases()
	await _fill_cases()
	await _graphics_cases()
	await _synergy_cases()


func _toolbar_cases() -> void:
	for entry: Array in ToolbarScript.CATEGORIES:
		for id: String in entry[1]:
			var buildable := GhostScript.is_buildable(id)
			var before := _ghost.tool
			var picked := await _pick_tool(id)
			var ok := (_ghost.tool == id) if buildable else (_ghost.tool == before and not picked)
			var detail := "tool is now '%s'" % _ghost.tool
			if not buildable:
				detail = "not buildable yet; the toolbar item stays disabled (tool '%s')" % _ghost.tool
			_record("toolbar.%s" % id, "toolbar", "Toolbar: choose %s" % id, "-", ok, detail, "SKIP" if (ok and not buildable) else "")
			if _ghost.tool != "":
				await _key(KEY_ESCAPE)


func _structure_cases() -> void:
	# The lobby, then widened; then a tall strip of floors beside the rooms for links and shafts.
	await _drag_case("lobby.place", "structure", "lobby", 100, 1, 219, 1,
		func() -> bool: return _lobby_edges() == [100, 219], "Lobby drag on floor 1, columns 100 to 219")
	await _drag_case("lobby.widen", "structure", "lobby", 220, 1, 299, 1,
		func() -> bool: return _lobby_edges() == [100, 299], "Widen the lobby to column 299")
	await _click_case("lobby.widen1", "structure", "lobby", 1, 300,
		func() -> bool: return _lobby_edges() == [100, 300], "Plain click widens the lobby by one unit (column 300)")
	for level in range(2, 11):
		await _drag_case("floor.%d" % level, "structure", "floor", 100, level, 139, level,
			func() -> bool: return _tower.floors.has_floor(level, 100) and _tower.floors.has_floor(level, 139),
			"Floor tool drag on floor %d, columns 100 to 139" % level)


func _room_cases() -> void:
	var x := 140
	for kind: String in ["office", "condo", "fast_food", "restaurant", "retail", "housekeeping", "security", "medical", "hotel_single", "hotel_twin", "hotel_suite"]:
		await _room_case(kind, 2, x)
		x += CatalogueScript.field(kind, "width")
	x = 160
	for kind: String in ["gym", "daycare", "clinic"]:  # on floor 3, over the rooms of floor 2
		await _room_case(kind, 3, x)
		x += CatalogueScript.field(kind, "width")
	x = 160
	for kind: String in ["nightclub", "coworking"]:  # on floor 4, over the new kinds of floor 3
		await _room_case(kind, 4, x)
		x += CatalogueScript.field(kind, "width")
	await _room_case("parking_ramp", -1, 200)
	await _room_case("parking_space", -1, 204)
	await _room_case("recycling", -2, 210)
	await _room_case("metro", -1, 232)
	await _room_case("observation_deck", 5, 160)  # the top floor of the test tower
	x = 160
	for kind: String in ["grocery", "deli"]:  # on floor 6, over the top-floor deck
		await _room_case(kind, 6, x)
		x += CatalogueScript.field(kind, "width")
	for kind: String in CatalogueScript.IDS:
		if kind in RoomsScript.PLACEABLE or kind in ["lobby", "floor", "stairs", "escalator"]:
			continue
		if CatalogueScript.field(kind, "placement") in [CatalogueScript.PLACE_SHAFT, CatalogueScript.PLACE_CAR]:
			continue
		_record("place.%s" % kind, "rooms", "Place %s" % kind, "-", true, "not in the sim's PLACEABLE list; its toolbar item is disabled", "SKIP")


func _link_cases() -> void:
	await _click_case("stairs.single", "links", "stairs", 1, 102,
		func() -> bool: return _link_kind(1, 100) == "stairs", "Stairs at floors 1-2, columns 100-103")
	await _click_case("stairs.stacked", "links", "stairs", 2, 102,
		func() -> bool: return _link_kind(3, 100) == "stairs", "Second flight stacked above the first (floors 2-3)")
	await _click_case("stairs.stacked3", "links", "stairs", 3, 102,
		func() -> bool: return _link_kind(4, 100) == "stairs", "Third flight stacked (floors 3-4)")
	await _click_case("escalator.single", "links", "escalator", 1, 112,
		func() -> bool: return _link_kind(1, 108) == "escalator", "Escalator at floors 1-2, columns 108-115")
	await _click_case("escalator.stacked", "links", "escalator", 2, 112,
		func() -> bool: return _link_kind(3, 108) == "escalator", "Second escalator stacked above the first")


func _shaft_cases() -> void:
	# kind, tool, a column inside the shaft, bottom, top, top after resizing up, top after resizing down
	var plan: Array = [
		["local", "local_shaft", 122, 1, 5, 7, 4],
		["service", "service_shaft", 126, 1, 6, 8, 5],
		["express", "express_shaft", 131, 1, 8, 9, 7],
	]
	for p: Array in plan:
		var kind: String = p[0]
		var tool_id: String = p[1]
		var col: int = p[2]
		var bottom: int = p[3]
		var top: int = p[4]
		var up: int = p[5]
		var down: int = p[6]
		await _drag_case("shaft.%s.place" % kind, "shafts", tool_id, col, bottom, col, top,
			func() -> bool: return _shaft_span(col, bottom, top), "Drag a %s shaft from floor %d to %d" % [kind, bottom, top])
		await _drag_case("shaft.%s.resize_up" % kind, "shafts", tool_id, col, top, col, up,
			func() -> bool: return _shaft_span(col, bottom, up), "Drag the %s shaft's top end from %d up to %d" % [kind, top, up])
		await _drag_case("shaft.%s.resize_down" % kind, "shafts", tool_id, col, up, col, down,
			func() -> bool: return _shaft_span(col, bottom, down), "Drag the %s shaft's top end from %d down to %d" % [kind, up, down])


## The machine room above a shaft is its visible end: a player drags that to resize (#258).
func _shaft_end_cases() -> void:
	await _drag_case("shaft.cap.place", "shafts", "local_shaft", 136, 1, 136, 4,
		func() -> bool: return _shaft_span(136, 1, 4), "Place a spare local shaft (floors 1 to 4) to drag by its machine room")
	var top := _shaft_top(136)
	await _drag_case("shaft.cap.up", "shafts", "local_shaft", 136, top + 1, 136, top + 3,
		func() -> bool: return _shaft_top(136) > top, "Drag the machine room above the shaft up 2 floors: the shaft grows")
	var grown := _shaft_top(136)
	await _drag_case("shaft.cap.down", "shafts", "local_shaft", 136, grown + 1, 136, grown - 1,
		func() -> bool: return _shaft_top(136) < grown, "Drag the machine room down 2 floors: the shaft shrinks")


func _car_and_stop_cases() -> void:
	for kind: String in ["local", "service", "express"]:
		var col: int = {"local": 122, "service": 126, "express": 131}[kind]
		var before := _cars_at(3, col)
		await _click_case("car.%s" % kind, "cars", "%s_car" % kind, 3, col,
			func() -> bool: return _cars_at(3, col) == before + 1 and before >= 0,
			"Add a %s car by clicking the shaft at floor 3" % kind)
	var local_before := _cars_at(4, 122)
	await _click_case("car.local.second", "cars", "local_car", 4, 122,
		func() -> bool: return local_before >= 0 and _cars_at(4, 122) == local_before + 1, "Add a second local car")
	await _click_case("stop.off", "cars", "local_shaft", 2, 122,
		func() -> bool: return not _shaft_at(3, 122).get("stops", []).has(2), "Click a local shaft floor: its stop goes off")
	await _click_case("stop.on", "cars", "local_shaft", 2, 122,
		func() -> bool: return _shaft_at(3, 122).get("stops", []).has(2), "Click it again: the stop is back on")


## The game starts at zoom 2, so the player's clicks mostly land there: zoom with the wheel, as a player does.
func _zoom2_cases() -> void:
	await _wheel(true)
	_record("zoom2.camera", "zoom2", "Mouse wheel zooms the camera to 2", "-", _camera.zoom.x == 2.0, "camera zoom is %s" % str(_camera.zoom.x))
	await _click_case("zoom2.lobby.widen1", "zoom2", "lobby", 1, 301,
		func() -> bool: return _lobby_edges() == [100, 301], "At zoom 2: click widens the lobby by one unit (column 301)")
	await _drag_case("zoom2.lobby.widen_left", "zoom2", "lobby", 99, 1, 96, 1,
		func() -> bool: return _lobby_edges() == [96, 301], "At zoom 2: drag widens the lobby to the left")
	await _room_case("office", 3, 140, "zoom2.office")
	await _drag_case("zoom2.shaft.resize_up", "zoom2", "local_shaft", 122, 4, 122, 5,
		func() -> bool: return _shaft_span(122, 1, 5), "At zoom 2: drag the local shaft's top end from 4 up to 5")
	await _drag_case("zoom2.shaft.resize_down", "zoom2", "local_shaft", 122, 5, 122, 4,
		func() -> bool: return _shaft_span(122, 1, 4), "At zoom 2: drag the local shaft's top end from 5 down to 4")
	await _wheel(false)


func _bulldoze_cases() -> void:
	await _click_case("bulldoze.room", "bulldoze", GhostScript.BULLDOZE, 2, 144,
		func() -> bool: return _kind_at(2, 144) == "", "Bulldoze the office")
	var links_before := _link_count()  # floor 2 holds two escalators (#259): one goes, one stays
	await _click_case("bulldoze.escalator", "bulldoze", GhostScript.BULLDOZE, 2, 112,
		func() -> bool: return _link_count() == links_before - 2 and _link_kind(2, 108) == "escalator",
		"Bulldoze one of the two escalators sharing floor 2")
	await _click_case("bulldoze.stairs", "bulldoze", GhostScript.BULLDOZE, 1, 102,
		func() -> bool: return _link_kind(1, 100) == "", "Bulldoze the lowest stairs")


## Rooms behind transport (#272): a room goes behind a shaft, stairs and an escalator, and bulldoze
## takes the transport in front first, then the room. Floors 8 to 10 at columns 100 to 120 are free.
func _behind_cases() -> void:
	await _drag_case("behind.shaft.place", "behind", "local_shaft", 102, 8, 102, 9,
		func() -> bool: return _shaft_span(102, 8, 9), "Drag a shaft over floors 8 to 9, columns 100 to 103")
	await _room_case("office", 8, 100, "behind.shaft.room")
	await _click_case("behind.shaft.bulldoze_front", "behind", GhostScript.BULLDOZE, 8, 101,
		func() -> bool: return _shaft_at(8, 101).is_empty() and _kind_at(8, 101) == "office", "Bulldoze at the shaft takes the shaft, not the office")
	await _click_case("behind.shaft.bulldoze_room", "behind", GhostScript.BULLDOZE, 8, 101,
		func() -> bool: return _kind_at(8, 101) == "", "A second bulldoze takes the office behind")
	await _room_case("office", 9, 100, "behind.stairs.room")
	await _click_case("behind.stairs.place", "behind", "stairs", 8, 102,
		func() -> bool: return _link_kind(8, 100) == "stairs" and _kind_at(9, 100) == "office", "Stairs over floors 8 to 9 in front of the office")
	await _click_case("behind.stairs.bulldoze_front", "behind", GhostScript.BULLDOZE, 9, 101,
		func() -> bool: return _link_kind(8, 100) == "" and _kind_at(9, 101) == "office", "Bulldoze takes the stairs first")
	await _room_case("retail", 9, 112, "behind.escalator.room")
	await _click_case("behind.escalator.place", "behind", "escalator", 9, 116,
		func() -> bool: return _link_kind(9, 112) == "escalator" and _kind_at(9, 112) == "retail", "An escalator in front of the shop on floor 9")
	await _click_case("behind.escalator.bulldoze_front", "behind", GhostScript.BULLDOZE, 9, 114,
		func() -> bool: return _link_kind(9, 112) == "" and _kind_at(9, 112) == "retail", "Bulldoze takes the escalator first")
	await _click_case("behind.escalator.bulldoze_room", "behind", GhostScript.BULLDOZE, 9, 114,
		func() -> bool: return _kind_at(9, 112) == "", "A second bulldoze takes the shop behind")


## Auto-fill floor (#273): a shaft dragged a few cells off the floor edge closes the gap on each of its floors.
func _fill_cases() -> void:
	await _drag_case("fill.shaft", "fill", "local_shaft", 146, 3, 146, 4,
		func() -> bool: return _shaft_span(146, 3, 4) and _tower.floors.has_floor(3, 140) and _tower.floors.has_floor(4, 143),
		"Drag a shaft at columns 144 to 147 over floors 3 to 4, beside floor ending at column 139: the gap fills")


## Graphics setting (#301): choosing Detailed in the toolbar switches the style the renderer draws with, live,
## and Classic switches it back. The saved setting is restored afterwards.
func _graphics_cases() -> void:
	var picker := _toolbar.find_child("Graphics", true, false) as OptionButton
	var renderer := _main.find_child("TowerRenderer", true, false)
	var was := ViewSettingsScript.detailed_graphics
	var found := picker != null and renderer != null
	var live := false
	var back := false
	if found:
		picker.select(1)
		picker.item_selected.emit(1)
		await _frames(2)
		live = ViewSettingsScript.detailed_graphics and renderer._seen_style == GraphicsStyleScript.for_detailed(true)
		picker.select(0)
		picker.item_selected.emit(0)
		await _frames(2)
		back = not ViewSettingsScript.detailed_graphics and renderer._seen_style == GraphicsStyleScript.for_detailed(false)
	ViewSettingsScript.set_detailed_graphics(was)
	_record("graphics.toggle", "graphics", "Graphics: Detailed then Classic from the toolbar switches the renderer's style", "-", found and live and back,
		"picker found %s, Detailed live %s, Classic back %s" % [str(found), str(live), str(back)])


## Synergy overlay (#294): the toolbar's Synergies switch turns the overlay on and off live, in Classic and in
## Detailed. (That reading changes nothing in the tower is in tests/test_synergy_look.gd: here the sim runs.)
func _synergy_cases() -> void:
	var button := _toolbar.find_child("Synergies", true, false) as CheckButton
	var renderer := _main.find_child("TowerRenderer", true, false)
	var overlay: Node = null
	if renderer != null:
		for child: Node in renderer.get_children():
			if child is SynergyOverlay:
				overlay = child
	var was := ViewSettingsScript.detailed_graphics
	var found := button != null and overlay != null
	var results: Array[bool] = []
	if found:
		for detailed: bool in [false, true]:
			ViewSettingsScript.set_detailed_graphics(detailed)
			await _frames(2)
			button.button_pressed = true
			await _frames(2)
			var shown: bool = SynergyLookScript.on and overlay._shown_on
			button.button_pressed = false
			await _frames(2)
			results.append(shown and not SynergyLookScript.on and not overlay._shown_on)
	ViewSettingsScript.set_detailed_graphics(was)
	_record("synergy.toggle", "synergy", "Synergies from the toolbar shows and hides the overlay in Classic and Detailed", "-", found and results.size() == 2 and not results.has(false),
		"switch and overlay found %s, results %s" % [str(found), str(results)])


func _window_cases() -> void:
	await _key(KEY_ESCAPE)
	var room_window: Node = _main.get_node("RoomWindow")
	var elevator_window: Node = _main.get_node("ElevatorWindow")
	var person_window: Node = _main.get_node("PersonWindow")
	var restaurant := _tower.grid.cell_at(2, 170)
	await _window_case("window.room", "Click a room: the room window opens", 2, 170,
		func() -> bool: return restaurant != GridScript.EMPTY and room_window.room_id == restaurant, "RoomWindow.room_id is %d" % room_window.room_id)
	await _key(KEY_ESCAPE)
	var shaft := _shaft_at(4, 122)
	await _window_case("window.elevator", "Click a shaft: the elevator window opens", 4, 122,
		func() -> bool: return not shaft.is_empty() and elevator_window.shaft_id == shaft["id"], "ElevatorWindow.shaft_id is %d" % elevator_window.shaft_id)
	await _key(KEY_ESCAPE)
	# People appear once offices and condos fill: run the clock until there is a figure to click.
	var view := PeopleViewScript.new()
	var figures: Array[Dictionary] = []
	var waited := 0
	while figures.is_empty() and waited < PEOPLE_TICK_LIMIT:
		_step(100)
		waited += 100
		figures.assign(view.figures(_tower).filter(func(f: Dictionary) -> bool: return not f.get("staff", false)))  # cleaners are not people
	if figures.is_empty():
		_record("window.person", "windows", "Click a person: the person window opens", "-", false, "no person walked in within %d ticks" % waited, "SKIP")
		return
	_driver.set_paused(true)  # people walk in real time: hold the sim so the figure stays under the pointer
	var figure: Dictionary = figures[0]
	var centre := root.get_visible_rect().size / 2.0
	_camera.pan_by_screen(_figure_screen(figure) - centre)
	_camera.force_update_scroll()
	await _frames(1)
	var pos := _figure_screen(figure)
	await _move(pos)
	await _click_at(pos)
	await _frames(1)
	_finish_case("window.person", "windows", "Click a person: the person window opens (after %d ticks)" % waited, {},
		person_window.person_id == figure["id"], "PersonWindow.person_id is %d, clicked %d" % [person_window.person_id, figure["id"]])
	# Follow (#289): pan away, press Follow, and the camera returns to the person and stays on them.
	_camera.pan_by_screen(Vector2(300, 200))
	await _frames(2)
	var follow_button: Button = person_window.follow_button
	var button_at := follow_button.get_global_rect().get_center()
	await _move(button_at)
	await _click_at(button_at)
	await _frames(40)
	var want := TowerCameraScript.view_position(PersonInfo.figure_center(figure), root.get_visible_rect().size, int(_camera.zoom.x), VC.world_rect())
	var near := _camera.position.distance_to(want) <= 2.0
	_finish_case("window.follow", "windows", "Press Follow: the camera centres on the person", {},
		person_window.is_following() and near, "following %s, camera at %s, wanted %s" % [str(person_window.is_following()), str(_camera.position), str(want)])
	_camera.pan_by_screen(Vector2(40, 0))
	await _frames(1)
	_finish_case("window.follow_stop", "windows", "Panning stops following", {},
		not person_window.is_following() and not follow_button.button_pressed, "still following after a pan")
	_driver.set_paused(false)


## News ticker (#288): a story appears on the strip, and clicking it opens that person's window.
func _news_cases() -> void:
	await _key(KEY_ESCAPE)
	var ticker: Node = _main.get_node("NewsTicker")
	var person_window: Node = _main.get_node("PersonWindow")
	if _tower.people.count() == 0:
		_record("news.click", "windows", "Click a news story: the person's window opens", "-", false, "no people to tell a story about", "SKIP")
		return
	var id: int = _tower.people.id_at(0)
	_tower.life._record(_tower.tick, 3, id, -1, -1)  # a promotion story, planted by the harness
	await _frames(2)
	var button: Button = ticker.story_buttons[0]
	var shows := button.text.contains(_tower.names.name_of(id))
	await _move(button.get_global_rect().get_center())
	await _click_at(button.get_global_rect().get_center())
	await _frames(2)
	_finish_case("news.click", "windows", "Click a news story: the person's window opens", {},
		shows and person_window.person_id == id, "story text '%s', PersonWindow.person_id is %d, wanted %d" % [button.text, person_window.person_id, id])
	await _key(KEY_ESCAPE)


# ---------------------------------------------------------------- case runners

## One click with a tool at a cell: verdict read before the click, sim read after.
func _click_case(id: String, group: String, tool_id: String, floor_number: int, column: int, check: Callable, label: String) -> void:
	if not await _pick_tool(tool_id):
		_record(id, group, label, "-", false, "the toolbar would not select %s" % tool_id)
		return
	var pos := await _focus(floor_number, column)
	await _move(pos)
	var verdict := _verdict()
	await _click_at(pos)
	_step(SETTLE_TICKS)
	await _frames(1)
	_finish_case(id, group, label, verdict, check.call(), "the sim shows no change")


## A press, a drag and a release with a tool, from one cell to another.
func _drag_case(id: String, group: String, tool_id: String, col_a: int, floor_a: int, col_b: int, floor_b: int, check: Callable, label: String) -> void:
	if not await _pick_tool(tool_id):
		_record(id, group, label, "-", false, "the toolbar would not select %s" % tool_id)
		return
	await _focus(floor_a, (col_a + col_b) / 2)
	var a := _cell_screen(floor_a, col_a)
	var b := _cell_screen(floor_b, col_b)
	await _move(a)
	await _button(a, true)
	var steps := 8
	for i in range(1, steps + 1):
		await _move(a.lerp(b, float(i) / steps))
	var verdict := _verdict()
	await _button(b, false)
	_step(SETTLE_TICKS)
	await _frames(1)
	_finish_case(id, group, label, verdict, check.call(), "the sim shows no change")


func _room_case(kind: String, floor_number: int, x_left: int, id: String = "") -> void:
	var width: int = CatalogueScript.field(kind, "width")
	await _click_case(id if id != "" else "place.%s" % kind, "rooms", kind, floor_number, x_left + width / 2,
		func() -> bool: return _kind_at(floor_number, x_left) == kind, "Place %s at floor %d, column %d" % [kind, floor_number, x_left])


## A plain click (no tool) on a cell, then a check of which window opened.
func _window_case(id: String, label: String, floor_number: int, column: int, check: Callable, what: String) -> void:
	var pos := await _focus(floor_number, column)
	await _move(pos)
	await _click_at(pos)
	await _frames(1)
	_finish_case(id, "windows", label, {}, check.call(), what)


func _finish_case(id: String, group: String, label: String, verdict: Dictionary, built: bool, nothing: String) -> void:
	var ghost := "-"
	var detail := "ok" if built else nothing
	var ok := built
	if not verdict.is_empty():
		var green: bool = verdict.get("valid", false)
		ghost = "green" if green else "red"
		if built and green:
			detail = "built; ghost green"
		elif built:
			ok = false
			detail = "built although the ghost was red (%s)" % verdict.get("text", "")
		elif green:
			detail = "ghost green but the click did nothing"
		else:
			detail = "ghost red: %s" % verdict.get("text", "")
	_record(id, group, label, ghost, ok, detail)


# ---------------------------------------------------------------- input (the only way actions happen)

## Picks a tool by pressing the toolbar's category and item buttons. False if it is disabled.
func _pick_tool(id: String) -> bool:
	if id == _ghost.tool:
		return true
	var category := -1
	for c in ToolbarScript.CATEGORIES.size():
		if (ToolbarScript.CATEGORIES[c][1] as Array).has(id):
			category = c
	if category == -1:
		return false
	var button: Button = _toolbar._category_buttons[category]
	if _toolbar._open_category != category:
		await _click_at(button.get_global_rect().get_center())
		await _frames(WAIT_FRAMES)
	var item: Button = _toolbar._item_buttons[id]
	if not item.disabled:
		await _click_at(item.get_global_rect().get_center())
		await _frames(1)
	if _toolbar._open_category == category:  # close the menu so it never covers the tower
		await _click_at(button.get_global_rect().get_center())
		await _frames(1)
	return _ghost.tool == id


## Hands an event to the game the way the operating system does (Input.parse_input_event), which
## also moves the pointer, so the ghost's get_global_mouse_position follows it.
func _send(e: InputEvent) -> void:
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = pos - _mouse
	_mouse = pos
	_send(e)
	await _frames(1)


func _button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_send(e)
	await _frames(1)


func _click_at(pos: Vector2) -> void:
	await _move(pos)
	await _button(pos, true)
	await _button(pos, false)


## One notch of the mouse wheel at the middle of the screen (the camera zooms about the pointer).
func _wheel(up: bool) -> void:
	await _move(root.get_visible_rect().size / 2.0)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = pressed
		e.position = _mouse
		e.global_position = _mouse
		_send(e)
		await _frames(1)
	await _frames(WAIT_FRAMES)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		_send(e)
		await _frames(1)


# ---------------------------------------------------------------- cells, camera, reading the sim

## Screen position of the middle of a cell, through the camera as the renderer draws it.
func _cell_screen(floor_number: int, column: int) -> Vector2:
	var world := Vector2((column + 0.5) * VC.CELL_W, (VC.floor_to_row(floor_number) + 0.5) * VC.CELL_H)
	return root.get_canvas_transform() * world


func _figure_screen(f: Dictionary) -> Vector2:
	return root.get_canvas_transform() * PersonInfo.figure_center(f)  # where the figure is drawn, spot included


## Pans the camera (as a player would) so a cell is mid-screen; returns that cell's screen position.
func _focus(floor_number: int, column: int) -> Vector2:
	var centre := root.get_visible_rect().size / 2.0
	_camera.pan_by_screen(_cell_screen(floor_number, column) - centre)
	_camera.force_update_scroll()
	await _frames(1)
	return _cell_screen(floor_number, column)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Lets the sim run (harness time, not a player action): whole ticks through the driver.
func _step(ticks: int) -> void:
	for i in ticks:
		_driver.run_frame(1.0 / SimDriver.BASE_TICKS_PER_SECOND / SimDriver.SPEEDS[_driver.speed_index] + 0.0001)


func _verdict() -> Dictionary:
	return _ghost.result.duplicate() if not _ghost.result.is_empty() else {"valid": false, "text": "no verdict (no tool or no hover)"}


func _lobby_edges() -> Array:
	var span: Array = _tower.floors.lobby_span()
	return [] if span.is_empty() else [span[0], span[1]]


func _kind_at(floor_number: int, column: int) -> String:
	var id := _tower.grid.cell_at(floor_number, column)
	return "" if id == GridScript.EMPTY else _tower.rooms.kind_of(id)


## Stairs and escalator halves standing (two per flight), counting both link layers.
func _link_count() -> int:
	return _tower.rooms.links.occupant_count() + _tower.rooms.links_over.occupant_count()


func _link_kind(floor_number: int, column: int) -> String:
	var id := _tower.rooms.link_at(floor_number, column)
	if id == GridScript.EMPTY:
		return ""
	var kind := _tower.rooms.kind_of(id)
	return kind if kind != "" else _tower.rooms.kind_of(id - 1)


func _shaft_at(floor_number: int, column: int) -> Dictionary:
	var index := GridScript.floor_to_index(floor_number)
	for s: Dictionary in ElevatorView.shafts(_tower):
		if column >= s["x"] and column < s["x"] + s["width"] and index >= GridScript.floor_to_index(s["bottom"]) and index <= GridScript.floor_to_index(s["top"]):
			return s
	return {}


## Cars in the shaft at a cell, or -1 when there is no shaft there.
func _cars_at(floor_number: int, column: int) -> int:
	var s := _shaft_at(floor_number, column)
	return -1 if s.is_empty() else _tower.rooms.car_count(s["id"])


func _shaft_span(column: int, bottom: int, top: int) -> bool:
	for s: Dictionary in ElevatorView.shafts(_tower):
		if column >= s["x"] and column < s["x"] + s["width"]:
			return s["bottom"] == bottom and s["top"] == top
	return false


## Top floor of the shaft at a column on the first stop floor, or -1 when there is none.
func _shaft_top(column: int) -> int:
	for s: Dictionary in ElevatorView.shafts(_tower):
		if column >= s["x"] and column < s["x"] + s["width"]:
			return s["top"]
	return -1


func _hud_says_demo() -> bool:
	return (_main.get_node("Hud").get_node("%StarsLabel") as Label).text.contains("DEMO")


# ---------------------------------------------------------------- results

func _record(id: String, group: String, label: String, ghost: String, ok: bool, detail: String, force_status: String = "") -> void:
	var status := "PASS" if ok else "FAIL"
	if force_status != "":
		status = force_status
	var issue: String = _expected.get(id, "")
	if issue != "":
		if status == "FAIL":
			status = "XFAIL"
		elif status == "PASS":
			status = "XPASS"
	var row := {"id": id, "group": group, "label": label, "ghost": ghost, "status": status, "detail": detail, "issue": issue, "shot": ""}
	if status == "FAIL" or status == "XFAIL":
		row["shot"] = _screenshot(id)
	_rows.append(row)


func _screenshot(id: String) -> String:
	if _headless or _shots_dir == "":
		return ""
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	var path := "%s/%s.png" % [_shots_dir, id.replace(".", "_")]
	var image := root.get_texture().get_image()
	return path if image != null and image.save_png(path) == OK else ""


func _load_expected() -> void:
	var file := FileAccess.open(EXPECTED_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key: String in (parsed as Dictionary):
			if not key.begins_with("_"):
				_expected[key] = str(parsed[key])


func _finish() -> void:
	var counts := {"PASS": 0, "FAIL": 0, "XFAIL": 0, "XPASS": 0, "SKIP": 0}
	var lines: Array[String] = []
	lines.append("%-26s %-6s %-6s  %s" % ["case", "status", "ghost", "what happened"])
	lines.append("-".repeat(110))
	for row: Dictionary in _rows:
		counts[row["status"]] += 1
		var note: String = row["detail"]
		if row["issue"] != "":
			note += "  [%s]" % row["issue"]
		if row["shot"] != "":
			note += "  (screenshot %s)" % row["shot"]
		lines.append("%-26s %-6s %-6s  %s" % [row["id"], row["status"], row["ghost"], note])
	lines.append("-".repeat(110))
	if counts["XPASS"] > 0:
		lines.append("XPASS rows now pass: remove them from tools/ui_expected.json.")
	lines.append("UI TEST pass=%d fail=%d xfail=%d xpass=%d skip=%d of %d" % [counts["PASS"], counts["FAIL"], counts["XFAIL"], counts["XPASS"], counts["SKIP"], _rows.size()])
	var text := "\n".join(lines)
	print(text)
	if _out_path != "":
		DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(text + "\n")
			file.close()
	quit(counts["FAIL"])
