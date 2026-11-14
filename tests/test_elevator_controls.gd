extends RefCounted
## Elevator build controls (4.11): ghost and toolbar state for the shaft and car tools, the exact
## command each gesture queues, every refusal message, and a whole tower built through the ghost
## API alone (lobby, floors, a local shaft, a car, an office) in which people then ride.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const DragScript := preload("res://scripts/view/drag_gesture.gd")
const ElevatorTools := preload("res://scripts/view/elevator_tools.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")

const SHAFT_COLUMN := 102  ## Pointer column that puts a 4-wide shaft at columns 100 to 103.


## Picks a tool, presses on a cell, releases on another floor (shaft tools), and steps one tick
## so the command lands. Returns true if a command was queued.
static func _gesture(ghost: Ghost, tool_id: String, from_floor: int, column: int, to_floor: int) -> bool:
	ghost.set_tool(tool_id)
	var queued := ghost.press(from_floor, column)
	if ElevatorTools.is_shaft_tool(tool_id):
		queued = ghost.release(to_floor, column)
	ghost.tower.step()
	return queued


## A new game with a lobby on floor 1 (columns 100 to 119) and floors 2 to 3 over it, all placed
## with the ghost's own tools.
static func _built(funds: int = 5000000) -> Ghost:
	var ghost := Ghost.new()
	ghost.set_tower(TowerSim.new(1, funds))
	_gesture(ghost, "lobby", 1, 110, 1)
	for floor_number in [2, 3]:
		_gesture(ghost, "floor", floor_number, 105, floor_number)
		_gesture(ghost, "floor", floor_number, 115, floor_number)
	return ghost


static func _shaft_id(t: TowerSim) -> int:
	return t.rooms.shaft_ids()[0]


## The refusal text of a shaft-tool drag from one floor to another at a pointer column.
static func _drag_text(ghost: Ghost, from_floor: int, to_floor: int, column: int = SHAFT_COLUMN) -> String:
	ghost.press(from_floor, column)
	var verdict := ghost.hover(to_floor, column)
	ghost._drag.cancel()
	ghost._last_key = []
	return verdict["text"]


static func run(check: Callable) -> void:
	_run_drag(check)
	_run_toolbar(check)
	_run_place(check)
	_run_resize_and_stops(check)
	_run_cars(check)
	_run_refusals(check)
	_run_end_to_end(check)


static func _run_drag(check: Callable) -> void:
	var vertical := DragScript.new(DragScript.Axis.VERTICAL)
	vertical.begin(2, 50)
	vertical.update(7, 60)
	check.call(vertical.floor_now == 7 and vertical.column_now == 50, "a vertical drag follows the floor and locks the column")
	check.call(vertical.moved(), "a drag that left its cell has moved")
	var done := vertical.end(9, 70)
	check.call(done["start_floor"] == 2 and done["floor"] == 9 and done["column"] == 50 and not vertical.active, "ending a drag returns its cells and stops it")
	check.call(vertical.end(1, 1).is_empty(), "ending an idle drag returns nothing")
	var horizontal := DragScript.new(DragScript.Axis.HORIZONTAL)
	horizontal.begin(4, 10)
	horizontal.update(8, 30)
	check.call(horizontal.floor_now == 4 and horizontal.column_now == 30, "a horizontal drag follows the column and locks the floor")
	horizontal.cancel()
	check.call(not horizontal.active and not horizontal.moved(), "a cancelled drag is inactive")


static func _run_toolbar(check: Callable) -> void:
	for id in ["local_shaft", "local_car"]:
		var state := Toolbar.item_state(id, 1)
		check.call(state["enabled"] and not state["locked"], "%s is buildable at 1 star" % id)
	var locked := Toolbar.item_state("service_shaft", 1)
	check.call(not locked["enabled"] and locked["locked"], "the service shaft is locked at 1 star")
	for id in ["service_shaft", "service_car"]:
		check.call(Toolbar.item_state(id, 2)["enabled"], "%s is buildable at 2 stars" % id)
	for id in ["express_shaft", "express_car"]:
		var state := Toolbar.item_state(id, 5)
		check.call(not state["enabled"] and "Not buildable" in state["tooltip"], "%s stays greyed out" % id)
	var tip: String = Toolbar.item_state("local_shaft", 1)["tooltip"]
	check.call("Drag" in tip and "Click a floor of a shaft" in tip and "resize" in tip, "the shaft tooltip documents drag, resize and click-for-stop")
	check.call("Click a shaft to add a car" in Toolbar.item_state("local_car", 1)["tooltip"], "the car tooltip says how to add a car")
	check.call("[E]" in Toolbar.item_state("local_shaft", 1)["text"] and "[A]" in Toolbar.item_state("local_car", 1)["text"], "the shaft and car items show their hotkeys")
	var ghost := Ghost.new()
	var bar := Toolbar.new()
	bar.bind(ghost)
	check.call(bar.select("local_shaft") and ghost.tool == "local_shaft", "picking the local shaft sets the ghost tool")
	check.call(bar.select("local_car") and ghost.tool == "local_car", "picking the local car sets the ghost tool")
	check.call(not bar.select("express_shaft") and ghost.tool == "local_car", "the express shaft cannot be picked")
	for entry: Array in [[KEY_E, "local_shaft"], [KEY_A, "local_car"]]:
		ghost.set_tool("")
		var key := InputEventKey.new()
		key.keycode = entry[0]
		key.pressed = true
		ghost._unhandled_key_input(key)
		check.call(ghost.tool == entry[1], "the hotkey picks %s" % entry[1])
	ghost.free()
	bar.free()


static func _run_place(check: Callable) -> void:
	var ghost := _built()
	var t := ghost.tower
	check.call(t.floors.has_lobby() and t.floors.has_floor(3, 119), "fixture: lobby and floors built through the ghost")
	var before := t.ledger.balance
	# The live ghost: span, cost and note change as the drag moves.
	ghost.set_tool("local_shaft")
	ghost.press(1, SHAFT_COLUMN)
	var live := ghost.hover(3, SHAFT_COLUMN)
	check.call(live["valid"] and live["mode"] == "place" and live["floor"] == 1 and live["top"] == 3 and live["x"] == 100 and live["width"] == 4, "the drag ghost spans the dragged floors")
	check.call(live["cost"] == 200000 and Ghost.lines_for("local_shaft", live)[0] == "local_shaft: $200000", "the ghost shows the shaft price")
	check.call("Floors 1 to 3 (3)" in Ghost.lines_for("local_shaft", live), "the ghost label shows the span")
	var shorter := ghost.hover(2, SHAFT_COLUMN)
	check.call(shorter["floor"] == 1 and shorter["top"] == 2, "the ghost follows the pointer")
	# Dragging downward gives the same span the other way round.
	var down := ElevatorTools.evaluate_shaft(t, "local_shaft", 1, 3, SHAFT_COLUMN, 1)
	check.call(down["valid"] and down["floor"] == 1 and down["top"] == 3, "a downward drag places the same shaft")
	ghost.hover(3, SHAFT_COLUMN)
	check.call(ghost.release(3, SHAFT_COLUMN), "releasing a valid drag queues a command")
	check.call(t._queue.size() == 1, "one command waits in the queue")
	var command: TowerSim.Command = t._queue[0]
	var expected: Array[int] = [CatalogueScript.IDS.find("local_shaft"), 1, 3, 100]
	check.call(command.kind == Command.PLACE_SHAFT and command.args == expected, "the drag queues PLACE_SHAFT with kind, bottom, top and x")
	t.step()
	check.call(t.rooms.shaft_count() == 1 and t.ledger.balance == before - 200000, "the shaft is built and paid for")
	check.call(not ghost.release(3, SHAFT_COLUMN), "a release with no drag does nothing")
	ghost.free()


static func _run_resize_and_stops(check: Callable) -> void:
	var ghost := _built()
	var t := ghost.tower
	check.call(_gesture(ghost, "local_shaft", 1, SHAFT_COLUMN, 3), "fixture: a shaft over floors 1 to 3")
	var id := _shaft_id(t)
	# Stops: a click on a floor of the shaft toggles it.
	ghost.set_tool("local_shaft")
	ghost.press(2, SHAFT_COLUMN)
	var stop := ghost.hover(2, SHAFT_COLUMN)
	check.call(stop["mode"] == "stop" and stop["valid"] and "stop off at 2" in stop["note"], "a click on a shaft floor previews turning its stop off")
	check.call(ghost.release(2, SHAFT_COLUMN), "releasing the click queues a command")
	var command: TowerSim.Command = t._queue[0]
	var off_args: Array[int] = [id, 2, 0]
	check.call(command.kind == Command.SET_SHAFT_STOP and command.args == off_args, "the click queues SET_SHAFT_STOP off")
	t.step()
	check.call(not t.rooms.is_stop(id, 2), "the stop is now off")
	var again := ElevatorTools.evaluate_shaft(t, "local_shaft", 2, 2, SHAFT_COLUMN, 1)
	var on_args: Array[int] = [id, 2, 1]
	check.call(again["valid"] and again["args"] == on_args and "stop on at 2" in again["note"], "a second click turns the stop back on")
	# Resize: growing over unbuilt floors is refused, then over a built floor it is queued.
	check.call(not _gesture(ghost, "local_shaft", 3, SHAFT_COLUMN, 5), "growing a shaft over unbuilt floors queues nothing")
	_gesture(ghost, "floor", 4, 105, 4)
	ghost.set_tool("local_shaft")
	ghost.press(3, SHAFT_COLUMN)
	var grow := ghost.hover(4, SHAFT_COLUMN)
	check.call(grow["mode"] == "resize" and grow["valid"] and grow["floor"] == 1 and grow["top"] == 4, "dragging the top end up previews a taller shaft")
	check.call(ghost.release(4, SHAFT_COLUMN), "releasing queues the resize")
	command = t._queue[0]
	var grow_args: Array[int] = [id, 1, 4]
	check.call(command.kind == Command.RESIZE_SHAFT and command.args == grow_args, "the drag queues RESIZE_SHAFT with the new span")
	t.step()
	check.call(ElevatorTools.shaft_at(t, 4, 101).get("top", 0) == 4, "the shaft now reaches floor 4")
	# Dragging the bottom end up shrinks it from below.
	var shrink := ElevatorTools.evaluate_shaft(t, "local_shaft", 2, 1, SHAFT_COLUMN, 1)
	var shrink_args: Array[int] = [id, 2, 4]
	check.call(shrink["valid"] and shrink["args"] == shrink_args, "dragging the bottom end up queues a shorter span")
	# A drag that starts in the middle is not a resize.
	var middle := ElevatorTools.evaluate_shaft(t, "local_shaft", 4, 2, SHAFT_COLUMN, 1)
	check.call(not middle["valid"] and middle["text"] == "Drag from the top or bottom end to resize", "a drag from the middle of a shaft says to use an end")
	ghost.free()


static func _run_cars(check: Callable) -> void:
	var ghost := _built()
	var t := ghost.tower
	_gesture(ghost, "local_shaft", 1, SHAFT_COLUMN, 3)
	var id := _shaft_id(t)
	t.rooms.set_shaft_stop(id, 2, false)
	ghost.set_tool("local_car")
	var hover := ghost.hover(2, SHAFT_COLUMN)
	check.call(hover["valid"] and hover["mode"] == "car" and hover["cost"] == 80000, "the car ghost shows the car price over a shaft")
	check.call(hover["floor"] == 1 and "Home floor 1" in Ghost.lines_for("local_car", hover), "a click on a disabled stop homes the car at the nearest stop (ties go down)")
	var before := t.ledger.balance
	check.call(ghost.press(3, SHAFT_COLUMN), "pressing on the shaft queues a command")
	var command: TowerSim.Command = t._queue[0]
	var car_args: Array[int] = [id, 3]
	check.call(command.kind == Command.ADD_CAR and command.args == car_args, "the click queues ADD_CAR with the clicked stop as home")
	t.step()
	check.call(t.rooms.car_count(id) == 1 and t.ledger.balance == before - 80000, "the car is added and paid for")
	check.call(not ghost.hover(2, 40)["valid"] and ghost.result["text"] == "Click on a shaft", "a car click off any shaft says to click a shaft")
	check.call(not ghost.press(2, 40), "a car click off a shaft queues nothing")
	ghost.free()


static func _run_refusals(check: Callable) -> void:
	var ghost := _built()
	var t := ghost.tower
	ghost.set_tool("local_shaft")
	check.call(_drag_text(ghost, 1, 3, 5) == "Needs a built floor on every level", "a shaft off the built floors is refused")
	check.call(_drag_text(ghost, 1, 6) == "Needs a built floor on every level", "a shaft over unbuilt floors is refused")
	check.call(_drag_text(ghost, -3, 40) == "A shaft spans at most 30 floors", "a shaft over 30 floors is refused")
	check.call(_drag_text(ghost, 1, 3, 1) == "Runs off the tower's edge", "a shaft over the left edge is refused")
	check.call(_drag_text(ghost, 1, 3, GridScript.WIDTH_UNITS - 1) == "Runs off the tower's edge", "a shaft over the right edge is refused")
	ghost.set_tool("service_shaft")
	check.call(_drag_text(ghost, 1, 3) == "Needs 2 stars", "a service shaft is star locked at 1 star")
	# Money.
	var broke := _built(3000000)
	TestRooms._send(broke.tower, Command.PURCHASE, [broke.tower.ledger.balance - 100000, 1] as Array[int])
	broke.set_tool("local_shaft")
	check.call(_drag_text(broke, 1, 3) == "Not enough money", "a shaft that costs more than the balance reads as no money")
	broke.free()
	# Cars: a shaft with two cars at 1 star is full.
	_gesture(ghost, "local_shaft", 1, SHAFT_COLUMN, 3)
	var id := _shaft_id(t)
	_gesture(ghost, "local_car", 1, SHAFT_COLUMN, 1)
	_gesture(ghost, "local_car", 1, SHAFT_COLUMN, 1)
	check.call(t.rooms.car_count(id) == 2, "fixture: two cars at 1 star")
	ghost.set_tool("local_car")
	check.call(ghost.hover(2, SHAFT_COLUMN)["text"] == "More stars allow more cars", "a third car at 1 star is refused for the star cap")
	t.stars = 5
	for n in 6:
		_gesture(ghost, "local_car", 1, SHAFT_COLUMN, 1)
	check.call(t.rooms.car_count(id) == 8, "fixture: eight cars at 5 stars")
	ghost.set_tool("local_car")
	check.call(ghost.hover(2, SHAFT_COLUMN)["text"] == "A shaft holds at most 8 cars", "a ninth car is refused")
	ghost.set_tool("service_car")
	check.call(ghost.hover(2, SHAFT_COLUMN)["text"] == "Needs a service shaft", "a service car on a local shaft says it needs a service shaft")
	# A car's home floor must stay a stop and stay in the shaft.
	var gesture := {"start_floor": 1, "start_column": SHAFT_COLUMN}
	check.call(Ghost.evaluate(t, "local_shaft", 1, 100, 5, "", gesture)["text"] == "A car's home floor must stay a stop", "turning off a car's home stop is refused")
	var dropped := Ghost.evaluate(t, "local_shaft", 3, 100, 5, "", gesture)
	check.call(not dropped["valid"] and dropped["text"] == "Would drop a car's home floor", "a resize past a car's home floor is refused")
	var unbuilt := Ghost.evaluate(t, "local_shaft", 9, 100, 5, "", {"start_floor": 3, "start_column": SHAFT_COLUMN})
	check.call(unbuilt["text"] == "Needs a built floor on every level", "growing a shaft over unbuilt floors is refused")
	# A shaft with every stop off has nowhere to home a car.
	var bare := _built()
	_gesture(bare, "local_shaft", 1, SHAFT_COLUMN, 3)
	for floor_number in [1, 2, 3]:
		bare.tower.rooms.set_shaft_stop(_shaft_id(bare.tower), floor_number, false)
	bare.set_tool("local_car")
	check.call(bare.hover(2, SHAFT_COLUMN)["text"] == "A car's home must be a stop", "a car on a shaft with no stops is refused")
	bare.free()
	# Words for the codes a gesture cannot reach today.
	var words := {RoomsScript.NOT_IN_SHAFT: "Not a floor of this shaft", RoomsScript.NOTHING_THERE: "No shaft here",
		RoomsScript.NO_CARS_HERE: "Only local and service shafts take cars", RoomsScript.BAD_SHAFT_SPAN: "The top must be above the bottom",
		RoomsScript.MAX_SHAFTS: "The tower has the most shafts (24)", RoomsScript.SHORT_OF_FUNDS: "Not enough money"}
	for code: int in words:
		check.call(Ghost.reason_text("elevator", code) == words[code], "refusal %d reads '%s'" % [code, words[code]])
	ghost.free()


static func _run_end_to_end(check: Callable) -> void:
	var ghost := _built()
	var t := ghost.tower
	check.call(_gesture(ghost, "local_shaft", 1, SHAFT_COLUMN, 3), "end to end: the shaft is dragged out")
	check.call(_gesture(ghost, "local_car", 1, SHAFT_COLUMN, 1), "end to end: a car is added")
	check.call(_gesture(ghost, "office", 3, 110, 3), "end to end: an office goes on floor 3")
	check.call(t.rooms.shaft_count() == 1 and t.rooms.car_count(_shaft_id(t)) == 1 and t.rooms.kind_of(t.rooms.room_ids()[-1]) == "office", "the tower holds a shaft, a car and an office")
	var office: int = t.rooms.room_ids()[-1]
	t.clock.set_to_tick(TestOfficeDay._tick_at(PeopleScript.ARRIVE - 5, 0))
	check.call(TestElevatorRoutes._until_riding(t, 3000) != -1, "people ride the elevator built through the ghost")
	var arrived := 0
	for _n in 1500:
		t.step()
		arrived = 0
		for i in t.people.count():
			if t.people.location_of(i) == office and t.people.trip_state(i) == PeopleScript.TRIP_IDLE:
				arrived += 1
		if arrived == 6:
			break
	check.call(arrived == 6, "all six workers reach the office on floor 3 by the elevator")
	ghost.free()
