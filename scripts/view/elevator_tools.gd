extends RefCounted
## Elevator build tools (4.11): local and service shafts, and their cars. Judges a gesture with
## the sim's own rules by running the command on a throwaway copy of the tower, so the verdict
## and the refusal code are exactly what the sim would say. View only: reads the real tower,
## never writes it. The ghost (placement_ghost.gd) words the refusal codes and sends the command.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")

const SHAFT_TOOLS: Array[String] = ["local_shaft", "service_shaft"]
const CAR_TOOLS: Array[String] = ["local_car", "service_car"]

## Wording for the refusal codes only elevators raise (the shaft-span ones live in the ghost).
const TEXT: Dictionary = {
	RoomsScript.NOT_IN_SHAFT: "Not a floor of this shaft",
	RoomsScript.NOTHING_THERE: "No shaft here",
	RoomsScript.MAX_CARS: "A shaft holds at most 8 cars",
	RoomsScript.STAR_CAR_CAP: "More stars allow more cars",
	RoomsScript.BAD_HOME_FLOOR: "A car's home must be a stop",
	RoomsScript.NO_CARS_HERE: "Only local and service shafts take cars",
	RoomsScript.HOME_DROPPED: "Would drop a car's home floor",
	RoomsScript.HOME_STOP: "A car's home floor must stay a stop",
}


static func is_shaft_tool(tool_id: String) -> bool:
	return tool_id in SHAFT_TOOLS


static func is_car_tool(tool_id: String) -> bool:
	return tool_id in CAR_TOOLS


static func handles(tool_id: String) -> bool:
	return is_shaft_tool(tool_id) or is_car_tool(tool_id)


static func floor_label(floor_number: int) -> String:
	return "B%d" % -floor_number if floor_number < 0 else str(floor_number)


## A throwaway copy of the tower to try a command on.
static func _trial(t: TowerSim) -> TowerSim:
	var copy := TowerSim.new(0)
	copy.load_state(t.save())
	return copy


## The shaft (as ElevatorView.shafts describes it) covering a cell, or {}.
static func shaft_at(t: TowerSim, floor_number: int, column: int) -> Dictionary:
	var index := GridScript.floor_to_index(floor_number)
	for shaft: Dictionary in ElevatorView.shafts(t):
		if column >= shaft["x"] and column < shaft["x"] + shaft["width"] \
				and index >= GridScript.floor_to_index(shaft["bottom"]) and index <= GridScript.floor_to_index(shaft["top"]):
			return shaft
	return {}


## The stop closest to a floor (ties go down); the floor itself if the shaft has no stops.
static func nearest_stop(stops: Array[int], floor_number: int) -> int:
	var best := floor_number
	var best_gap := 1 << 30
	for stop in stops:
		var gap := absi(GridScript.floor_to_index(stop) - GridScript.floor_to_index(floor_number))
		if gap < best_gap:
			best = stop
			best_gap = gap
	return best


static func _blank(floor_number: int, x_left: int, width: int) -> Dictionary:
	return {"valid": false, "cost": 0, "text": "", "note": "", "code": 0, "permanent": false,
		"floor": floor_number, "x": x_left, "width": width, "height": 1, "mode": "",
		"command": -1, "args": [] as Array[int]}


## A shaft tool at the pointer. The gesture began at (start_floor, start_column) and is now at
## floor_number: on empty ground that places a shaft over the dragged floors; on a shaft's end it
## resizes; a click (no movement) on a shaft toggles that floor's stop.
## Returns the ghost verdict plus "code" (sim refusal, 0 if none), "note", "mode", "command", "args".
static func evaluate_shaft(t: TowerSim, tool_id: String, floor_number: int, start_floor: int, start_column: int, star_rating: int) -> Dictionary:
	var width: int = CatalogueScript.field(tool_id, "width")
	var out := _blank(start_floor, start_column - width / 2, width)
	var hit := shaft_at(t, start_floor, start_column)
	if hit.is_empty():
		return _evaluate_place(t, tool_id, floor_number, start_floor, out, star_rating)
	out["x"] = hit["x"]
	out["width"] = hit["width"]
	if floor_number == start_floor:
		return _evaluate_stop(t, hit, start_floor, out)
	return _evaluate_resize(t, hit, floor_number, start_floor, out)


static func _evaluate_place(t: TowerSim, tool_id: String, floor_number: int, start_floor: int, out: Dictionary, star_rating: int) -> Dictionary:
	var a := GridScript.floor_to_index(start_floor)
	var b := GridScript.floor_to_index(floor_number)
	var bottom := start_floor if a <= b else floor_number
	var top := floor_number if a <= b else start_floor
	out["mode"] = "place"
	out["floor"] = bottom
	out["top"] = top
	var checked := t.rooms.check_place_shaft(t.grid, t.floors, tool_id, bottom, top, out["x"])
	out["cost"] = checked["cost"]
	out["code"] = checked["reason"]
	if CatalogueScript.star(tool_id) > star_rating:
		out["text"] = "Needs %d stars" % CatalogueScript.star(tool_id)
	elif checked["reason"] == 0 and checked["cost"] > t.ledger.balance:
		out["code"] = RoomsScript.SHORT_OF_FUNDS
	elif checked["reason"] == 0:
		out["valid"] = true
		out["note"] = "Floors %s to %s (%d)" % [floor_label(bottom), floor_label(top), checked["span"]]
		out["command"] = TowerSim.Command.PLACE_SHAFT
		out["args"] = [CatalogueScript.IDS.find(tool_id), bottom, top, out["x"]] as Array[int]
	return out


static func _evaluate_stop(t: TowerSim, shaft: Dictionary, floor_number: int, out: Dictionary) -> Dictionary:
	var on_now: bool = shaft["stops"].has(floor_number)
	out["mode"] = "stop"
	out["floor"] = floor_number
	var trial := _trial(t)
	out["code"] = trial.rooms.set_shaft_stop(shaft["id"], floor_number, not on_now)
	if out["code"] == 0:
		out["valid"] = true
		out["note"] = "Click: stop %s at %s" % ["off" if on_now else "on", floor_label(floor_number)]
		out["command"] = TowerSim.Command.SET_SHAFT_STOP
		out["args"] = [shaft["id"], floor_number, 0 if on_now else 1] as Array[int]
	return out


static func _evaluate_resize(t: TowerSim, shaft: Dictionary, floor_number: int, start_floor: int, out: Dictionary) -> Dictionary:
	var bottom: int = shaft["bottom"]
	var top: int = shaft["top"]
	out["mode"] = "resize"
	out["floor"] = bottom
	out["top"] = top
	var above := GridScript.floor_to_index(floor_number) > GridScript.floor_to_index(start_floor)
	if start_floor == top and (above or start_floor != bottom):
		top = floor_number
	elif start_floor == bottom:
		bottom = floor_number
	else:
		out["text"] = "Drag from the top or bottom end to resize"
		return out
	out["floor"] = bottom
	out["top"] = top
	var trial := _trial(t)
	out["code"] = trial.rooms.resize_shaft(trial.grid, trial.floors, shaft["id"], bottom, top)
	if out["code"] == 0:
		out["valid"] = true
		out["note"] = "Resize to floors %s to %s (free)" % [floor_label(bottom), floor_label(top)]
		out["command"] = TowerSim.Command.RESIZE_SHAFT
		out["args"] = [shaft["id"], bottom, top] as Array[int]
	return out


## A car tool at a cell: a click on a shaft of the matching kind adds a car homed at the stop
## nearest the clicked floor.
static func evaluate_car(t: TowerSim, tool_id: String, floor_number: int, column: int, star_rating: int) -> Dictionary:
	var width: int = CatalogueScript.field(tool_id, "width")
	var out := _blank(floor_number, column - width / 2, width)
	out["mode"] = "car"
	var hit := shaft_at(t, floor_number, column)
	if hit.is_empty():
		out["text"] = "Click on a shaft"
		return out
	out["x"] = hit["x"]
	out["width"] = hit["width"]
	var shaft_kind := tool_id.replace("_car", "_shaft")
	if t.rooms.kind_of(hit["id"]) != shaft_kind:
		out["text"] = "Needs a %s shaft" % shaft_kind.replace("_shaft", "")
		return out
	var home := nearest_stop(hit["stops"], floor_number)
	out["floor"] = home
	out["cost"] = CatalogueScript.cost(tool_id)
	if CatalogueScript.star(tool_id) > star_rating:
		out["text"] = "Needs %d stars" % CatalogueScript.star(tool_id)
		return out
	var trial := _trial(t)
	out["code"] = trial.rooms.add_car(trial.ledger, trial.tick, star_rating, hit["id"], home)
	if out["code"] == 0:
		out["valid"] = true
		out["note"] = "Home floor %s" % floor_label(home)
		out["command"] = TowerSim.Command.ADD_CAR
		out["args"] = [hit["id"], home] as Array[int]
	return out
