class_name ElevatorWindow
extends CanvasLayer
## The elevator panel (#187). Click a shaft with no build tool active to open it: a row per floor
## with a stop on/off box, a column per car (up to 8) with its home floor marked, and buttons to
## add or remove a car. Every edit goes to the sim as a command (SET_SHAFT_STOP, SET_CAR_HOME,
## ADD_CAR, REMOVE_CAR); the panel shows what the sim says after the next tick, so a refused edit
## (fewer than 2 stops, an express stop on an ordinary floor) just springs back. Esc or a click on
## empty space closes it. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const ElevatorTools := preload("res://scripts/view/elevator_tools.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const VC := preload("res://scripts/view/view_consts.gd")

var tower: TowerSim = null
var ghost: Ghost = null  ## Read for the active build tool.
var shaft_id: int = -1  ## The shaft shown, or -1 when closed.
var panel: PanelContainer
var title: Label
var grid: GridContainer
var schedule_grid: GridContainer
var preview: Label  ## Plain-words summary of the shaft, its cars and its riders.
var _signature: String = ""


func _init() -> void:
	layer = 5
	panel = PanelContainer.new()
	panel.name = "ElevatorPanel"
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 16.0
	panel.offset_right = 16.0
	panel.visible = false
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title = Label.new()
	title.name = "Title"
	column.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.name = "CarButtons"
	column.add_child(buttons)
	var add := Button.new()
	add.name = "AddCar"
	add.text = "Add car"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(add_car)
	buttons.add_child(add)
	var remove := Button.new()
	remove.name = "RemoveCar"
	remove.text = "Remove car"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(remove_car)
	buttons.add_child(remove)
	preview = Label.new()
	preview.name = "Preview"
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(300, 0)
	column.add_child(preview)
	var scroll := ScrollContainer.new()
	scroll.name = "Floors"
	scroll.custom_minimum_size = Vector2(300, 320)
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "Grid"
	scroll.add_child(grid)
	var heading := Label.new()
	heading.text = "Schedule: mode, response floors (0 any), wait seconds (0 to 90)"
	column.add_child(heading)
	schedule_grid = GridContainer.new()
	schedule_grid.name = "Schedule"
	schedule_grid.columns = 4
	column.add_child(schedule_grid)


func bind(tower_value: TowerSim, ghost_value: Ghost) -> void:
	tower = tower_value
	ghost = ghost_value


func is_open() -> bool:
	return shaft_id != -1


## What the panel shows for a shaft, or {} if there is none:
## {"id", "label", "bottom", "top", "cars", "homes" (per car, oldest first), "stop_count",
## "rows" (top floor first): [{"floor", "label", "stop", "homes" (a bool per car)}]}.
static func describe(t: Object, id: int) -> Dictionary:
	for shaft: Dictionary in ElevatorView.shafts(t):
		if shaft["id"] != id:
			continue
		var homes: Array[int] = []
		for car: Array in t.rooms.cars_of(id):
			homes.append(car[CarsScript.HOME])
		var rows: Array[Dictionary] = []
		var first: int = GridScript.floor_to_index(shaft["bottom"])
		var last: int = GridScript.floor_to_index(shaft["top"])
		for index in range(last, first - 1, -1):  # last >= first, so this ends
			var floor_number: int = GridScript.index_to_floor(index)
			var marks: Array[bool] = []
			for home: int in homes:
				marks.append(home == floor_number)
			rows.append({"floor": floor_number, "label": ElevatorTools.floor_label(floor_number), "stop": t.rooms.is_stop(id, floor_number), "homes": marks})
		var kind: String = t.rooms.kind_of(id)
		var live: Array[Dictionary] = []
		var indexes: Array[int] = t.rooms.car_indexes_of(id)
		for car: Array in t.rooms.cars_of(id):
			live.append({"floor": car[CarsScript.FLOOR], "state": car[CarsScript.STATE], "riders": t.rooms.riders_of(indexes[live.size()]).size()})
		var waiting := 0
		for stop: int in t.rooms.stops_of(id):
			waiting += t.rooms.queue_at(id, stop).size()
		return {"live": live, "waiting": waiting, "capacity": t.rooms.car_capacity(id), "express": kind == "express_shaft",
			"id": id, "label": "%s, %s to %s" % [kind.replace("_", " "), ElevatorTools.floor_label(shaft["bottom"]), ElevatorTools.floor_label(shaft["top"])],
			"schedule": t.rooms.schedule_of(id), "bottom": shaft["bottom"], "top": shaft["top"], "cars": homes.size(), "homes": homes, "stop_count": shaft["stops"].size(), "rows": rows}
	return {}


## Whole sim ticks for one car to make a full round trip: the travel up and down plus the doors at
## every stop it serves, assuming nobody holds it up.
static func round_trip_ticks(floors_spanned: int, stop_count: int, express: bool) -> int:
	var per_floor: int = CarsScript.EXPRESS_UNITS_PER_FLOOR if express else CarsScript.LOCAL_UNITS_PER_FLOOR
	var doors: int = CarsScript.DOOR_OPEN_UNITS + CarsScript.DOOR_HOLD_UNITS + CarsScript.DOOR_CLOSE_UNITS
	var units: int = 2 * floors_spanned * per_floor + 2 * maxi(stop_count - 1, 0) * doors
	return (units + CarsScript.TICK_UNITS - 1) / CarsScript.TICK_UNITS


## The preview text for a describe() result, in plain words.
static func preview_text(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var spanned: int = GridScript.floor_to_index(info["top"]) - GridScript.floor_to_index(info["bottom"])
	var ticks := round_trip_ticks(spanned, info["stop_count"], info["express"])
	var minutes: int = ticks * CarsScript.SECONDS_PER_TICK / 60
	var states: Array[String] = ["waiting", "moving", "opening its doors", "loading", "closing its doors"]
	var lines: Array[String] = []
	var cars: int = info["cars"]
	if cars == 0:
		lines.append("This shaft has no cars yet, so nobody can ride it. Add a car.")
	else:
		lines.append("%d %s serve %d stops. A full trip up and down takes about %d game minutes if nothing delays it." % [cars, "car" if cars == 1 else "cars", info["stop_count"], maxi(minutes, 1)])
	var n := 0
	for car: Dictionary in info["live"]:
		n += 1
		lines.append("Car %d: at %s, %s, carrying %d of %d." % [n, ElevatorTools.floor_label(car["floor"]), states[car["state"]], car["riders"], info["capacity"]])
	lines.append("%d %s waiting at its stops." % [info["waiting"], "person is" if info["waiting"] == 1 else "people are"])
	return "\n".join(lines)


func show_shaft(id: int) -> void:
	if tower == null or describe(tower, id).is_empty():
		return
	shaft_id = id
	_signature = ""
	_refresh()


func close() -> void:
	shaft_id = -1
	_signature = ""
	panel.visible = false


func _tool_active() -> bool:
	return ghost != null and ghost.tool != ""


## A click on a world point: opens the shaft there, or closes the panel when it lands on nothing.
## Returns true if a shaft is shown afterwards.
func click_at(world: Vector2) -> bool:
	if tower == null or _tool_active():
		return false
	var floor_number := RoomInfo.floor_at_y(world.y)
	if floor_number == 0 or world.x < 0.0:
		close()
		return false
	var hit := ElevatorTools.shaft_at(tower, floor_number, floori(world.x / VC.CELL_PX))
	if hit.is_empty():
		close()
	else:
		show_shaft(hit["id"])
	return is_open()


## Queues a command for the next tick. Returns true if it was queued.
func _send(kind: int, args: Array[int]) -> bool:
	if tower == null or not is_open():
		return false
	return tower.enqueue(TowerSim.Command.make(tower.tick + 1, kind, args))


func set_stop(floor_number: int, on: bool) -> bool:
	return _send(TowerSim.Command.SET_SHAFT_STOP, [shaft_id, floor_number, 1 if on else 0] as Array[int])


## Moves the nth car's home (0 is the oldest car) to a floor.
func set_home(nth: int, floor_number: int) -> bool:
	return _send(TowerSim.Command.SET_CAR_HOME, [shaft_id, nth, floor_number] as Array[int])


## Adds a car homed at the shaft's lowest stop.
func add_car() -> bool:
	if tower == null or not is_open():
		return false
	var stops: Array[int] = tower.rooms.stops_of(shaft_id)
	if stops.is_empty():
		return false
	return _send(TowerSim.Command.ADD_CAR, [shaft_id, stops[0]] as Array[int])


## Sets one schedule slot (0 to 5: weekday then weekend, morning, midday, evening).
func set_schedule(slot: int, mode: int, response: int, wait: int) -> bool:
	return _send(TowerSim.Command.SET_SCHEDULE, [shaft_id, slot, mode, response, wait] as Array[int])


func remove_car() -> bool:
	return _send(TowerSim.Command.REMOVE_CAR, [shaft_id] as Array[int])


func _process(_delta: float) -> void:
	if is_open():
		_refresh()


func _refresh() -> void:
	var info := describe(tower, shaft_id) if tower != null else {}
	if info.is_empty():  # bulldozed
		close()
		return
	panel.visible = true
	var signature := str(info)
	if signature == _signature:
		return
	_signature = signature
	preview.text = preview_text(info)
	title.text = "%s (%d stops, %d cars)" % [info["label"], info["stop_count"], info["cars"]]
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	_fill_schedule(info["schedule"])
	var cars: int = info["cars"]
	grid.columns = 2 + cars
	_label("Floor")
	_label("Stop")
	for n in cars:
		_label("Car %d" % (n + 1))
	for row: Dictionary in info["rows"]:
		var floor_number: int = row["floor"]
		_label(row["label"])
		var stop := CheckBox.new()
		stop.name = "Stop%d" % floor_number
		stop.button_pressed = row["stop"]
		stop.focus_mode = Control.FOCUS_NONE
		stop.toggled.connect(func(on: bool) -> void: set_stop(floor_number, on))
		grid.add_child(stop)
		for n in cars:
			var is_home: bool = row["homes"][n]
			var home := Button.new()
			home.name = "Home%d_%d" % [n, floor_number]
			home.text = "home" if is_home else "-"
			home.disabled = is_home or not row["stop"]
			home.focus_mode = Control.FOCUS_NONE
			home.pressed.connect(func() -> void: set_home(n, floor_number))
			grid.add_child(home)


func _fill_schedule(schedule: Array[int]) -> void:
	for child in schedule_grid.get_children():
		schedule_grid.remove_child(child)
		child.queue_free()
	var days: Array[String] = ["Weekday", "Weekend"]
	var parts: Array[String] = ["morning", "midday", "evening"]
	var modes: Array[String] = ["normal", "express top", "express bottom"]
	for slot in RoomsScript.SCHEDULE_SLOTS:
		var mode: int = schedule[slot * RoomsScript.SCHEDULE_FIELDS]
		var response: int = schedule[slot * RoomsScript.SCHEDULE_FIELDS + 1]
		var wait: int = schedule[slot * RoomsScript.SCHEDULE_FIELDS + 2]
		var name_label := Label.new()
		name_label.text = "%s %s" % [days[slot / RoomsScript.SCHEDULE_PERIODS], parts[slot % RoomsScript.SCHEDULE_PERIODS]]
		schedule_grid.add_child(name_label)
		var mode_button := Button.new()
		mode_button.name = "Mode%d" % slot
		mode_button.text = modes[mode]
		mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.pressed.connect(func() -> void: set_schedule(slot, (mode + 1) % modes.size(), response, wait))
		schedule_grid.add_child(mode_button)
		var response_box := SpinBox.new()
		response_box.name = "Response%d" % slot
		response_box.min_value = 0
		response_box.max_value = RoomsScript.MAX_RESPONSE
		response_box.value = response
		response_box.value_changed.connect(func(value: float) -> void: set_schedule(slot, mode, int(value), wait))
		schedule_grid.add_child(response_box)
		var wait_box := SpinBox.new()
		wait_box.name = "Wait%d" % slot
		wait_box.min_value = 0
		wait_box.max_value = RoomsScript.MAX_WAIT
		wait_box.value = wait
		wait_box.value_changed.connect(func(value: float) -> void: set_schedule(slot, mode, response, int(value)))
		schedule_grid.add_child(wait_box)


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if is_open() and panel.get_global_rect().has_point(click.position):
		return
	click_at(get_viewport().get_canvas_transform().affine_inverse() * click.position)
