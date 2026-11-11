class_name PlacementGhost
extends Node2D
## The build-tool ghost: follows the mouse snapped to the grid and shows whether the build is
## valid, its total cost, a plain refusal reason, and a warning for rooms that cannot be removed.
## View only. Every verdict comes from the sim's read-only check_* functions; this file only
## words them. Keys: L lobby, F floor, O office, C condo, B bulldoze, Esc none.

const VC := preload("res://scripts/view/view_consts.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const GridScript := preload("res://scripts/sim/grid.gd")

const BULLDOZE := "bulldoze"  ## The one tool that is not a catalogue id.
const FLOOR_SPAN_WIDTH: int = 10  ## Ghost width for the floor tool (view tunable).
const LOBBY_SPAN_WIDTH: int = 20  ## Ghost width for the lobby tool (view tunable).
const PERMANENT_TEXT := "Permanent: cannot be removed once built"
const VALID_TINT := Color(0.2, 0.9, 0.3, 0.45)
const INVALID_TINT := Color(0.95, 0.2, 0.2, 0.45)

## Refusal code -> our own short wording, one table per sim source (codes overlap across them).
const FLOOR_TEXT: Dictionary = {
	FloorsScript.BAD_FLOOR: "Not a floor",
	FloorsScript.BAD_SPAN: "Runs off the tower's edge",
	FloorsScript.NOTHING_BELOW: "Nothing below to rest on",
	FloorsScript.WIDER_THAN_BELOW: "Too wide for the floor below",
	FloorsScript.OVER_SHAFT: "Over a shaft",
	FloorsScript.ALREADY_BUILT: "Already built",
	FloorsScript.OCCUPIED_BY_LOBBY: "Overlaps the lobby",
	FloorsScript.LOBBY_BAD_FLOOR: "The lobby goes on floor 1",
	FloorsScript.LOBBY_BAD_HEIGHT: "Lobby must be 1 to 3 floors tall",
	FloorsScript.LOBBY_EXISTS: "The lobby is already built",
	FloorsScript.SHORT_OF_FUNDS: "Not enough money",
}
const ROOM_TEXT: Dictionary = {
	RoomsScript.SHORT_OF_FUNDS: "Not enough money",
	RoomsScript.BAD_FLOOR: "Not a floor",
	RoomsScript.UNKNOWN_KIND: "Cannot be built yet",
	RoomsScript.BELOW_GROUND: "Above ground only",
	RoomsScript.LOBBY_FLOOR: "Floor 1 is for the lobby",
	RoomsScript.OFF_TOWER: "Runs off the tower's edge",
	RoomsScript.OVERLAPS_ROOM: "Overlaps another room",
	RoomsScript.OVERLAPS_LOBBY: "Overlaps the lobby",
	RoomsScript.OVER_SHAFT: "Over a shaft",
	RoomsScript.NOTHING_BELOW: "Nothing below to rest on",
	RoomsScript.OVERHANG: "Too wide for the floor below",
	RoomsScript.NO_FLOOR_FOR_STAIRS: "No floor to stand the stairs on",
	RoomsScript.STAIRS_LIMIT: "Too many stairs already",
}
const BULLDOZE_TEXT: Dictionary = {
	RoomsScript.BAD_FLOOR: "Not a floor",
	RoomsScript.NOTHING_THERE: "Nothing to remove here",
	RoomsScript.PERMANENT: "Permanent: cannot be removed",
	RoomsScript.NOT_A_ROOM: "Not a room",
}

var tower: TowerSim = null
var tool: String = ""  ## "" (off), BULLDOZE, or a catalogue id.
var stars: int = 1  ## Current star rating. The sim has no stars yet (view stub until it does).
var result: Dictionary = {}  ## Last evaluate() verdict, for the label and the tests.
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	layer.add_child(_panel)
	_panel.visible = false


func set_tower(value: TowerSim) -> void:
	tower = value


func set_tool(value: String) -> void:
	tool = value


## Wording for a sim refusal code. source is "floors", "rooms" or "bulldoze".
static func reason_text(source: String, code: int) -> String:
	var table: Dictionary = FLOOR_TEXT
	match source:
		"rooms": table = ROOM_TEXT
		"bulldoze": table = BULLDOZE_TEXT
	return table.get(code, "Cannot build here")


## True when the catalogue marks the row as not removable.
static func is_permanent(kind: String) -> bool:
	return CatalogueScript.has(kind) and not CatalogueScript.is_removable(kind)


## Footprint width in cells of a tool's ghost.
static func width_of(tool_id: String) -> int:
	match tool_id:
		"lobby": return LOBBY_SPAN_WIDTH
		"floor": return FLOOR_SPAN_WIDTH
	if CatalogueScript.has(tool_id):
		return CatalogueScript.field(tool_id, "width")
	return 1


## Judges a tool at (floor_number, x_left) by asking the sim's check_* functions. Returns
## {valid, cost, text, permanent, floor, x, width, height}. Reads only; never changes the tower.
static func evaluate(t: TowerSim, tool_id: String, floor_number: int, x_left: int, star_rating: int) -> Dictionary:
	var out := {"valid": false, "cost": 0, "text": "", "permanent": false,
		"floor": floor_number, "x": x_left, "width": width_of(tool_id), "height": 1}
	if tool_id == BULLDOZE:
		return _evaluate_bulldoze(t, floor_number, x_left, out)
	out["permanent"] = is_permanent(tool_id)
	if not CatalogueScript.has(tool_id):
		out["text"] = reason_text("rooms", RoomsScript.UNKNOWN_KIND)
		return out
	var code: int = 0
	var source := "rooms"
	match tool_id:
		"lobby":
			source = "floors"
			var lobby := t.floors.check_lobby(floor_number, x_left, x_left + LOBBY_SPAN_WIDTH - 1, 1)
			code = lobby["reason"]
			out["cost"] = lobby["cost"]
		"floor":
			source = "floors"
			var span := t.floors.check_span(floor_number, x_left, x_left + FLOOR_SPAN_WIDTH - 1)
			code = span["reason"]
			out["cost"] = span["cost"]
		_:
			var placed := t.rooms.check_place(t.grid, t.floors, tool_id, floor_number, x_left)
			code = placed["reason"]
			out["cost"] = placed["cost"]
	if CatalogueScript.star(tool_id) > star_rating:
		out["text"] = "Needs %d stars" % CatalogueScript.star(tool_id)
	elif code != 0:
		out["text"] = reason_text(source, code)
	elif out["cost"] > t.ledger.balance:
		out["text"] = reason_text("rooms", RoomsScript.SHORT_OF_FUNDS)
	else:
		out["valid"] = true
	return out


static func _evaluate_bulldoze(t: TowerSim, floor_number: int, x: int, out: Dictionary) -> Dictionary:
	var checked := t.rooms.check_bulldoze(t.grid, t.floors, floor_number, x)
	out["width"] = 1
	if checked["reason"] != 0:
		out["text"] = reason_text("bulldoze", checked["reason"])
		out["permanent"] = checked["reason"] == RoomsScript.PERMANENT
		return out
	var run := t.grid.run_of(checked["room_id"])
	out["x"] = run[1]
	out["width"] = run[2]
	out["valid"] = true
	var text := "Remove %s (free)" % t.rooms.kind_of(checked["room_id"])
	if checked["refund"] > 0:
		text += ", pays back $%d" % checked["refund"]
	if checked["occupants"] > 0:
		text += ", %d people leave" % checked["occupants"]
	out["text"] = text
	return out


## Text lines for the label: kind and cost, the refusal if any, the permanent warning.
static func lines_for(tool_id: String, verdict: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if tool_id == BULLDOZE:
		lines.append(verdict["text"])
		return lines
	if verdict["cost"] > 0:
		lines.append("%s: $%d" % [tool_id, verdict["cost"]])
	else:
		lines.append(tool_id)
	if not verdict["valid"]:
		lines.append(verdict["text"])
	if verdict["permanent"]:
		lines.append(PERMANENT_TEXT)
	return lines


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_L: set_tool("lobby")
		KEY_F: set_tool("floor")
		KEY_O: set_tool("office")
		KEY_C: set_tool("condo")
		KEY_B: set_tool(BULLDOZE)
		KEY_ESCAPE: set_tool("")


func _process(_delta: float) -> void:
	if tower == null or tool == "" or _panel == null:
		if _panel != null:
			_panel.visible = false
		if not result.is_empty():
			result = {}
			queue_redraw()
		return
	var world := get_global_mouse_position()
	var column := floori(world.x / VC.CELL_PX)
	var row := floori(world.y / VC.CELL_PX)
	var floor_number := GridScript.index_to_floor(GridScript.FLOOR_COUNT - 1 - row)
	var x_left := column if tool == BULLDOZE else column - width_of(tool) / 2
	result = evaluate(tower, tool, floor_number, x_left, stars)
	_label.text = "\n".join(lines_for(tool, result))
	_panel.visible = true
	_panel.position = get_viewport().get_mouse_position() + Vector2(18, 18)
	queue_redraw()


func _draw() -> void:
	if result.is_empty() or not GridScript.is_valid_floor(result["floor"]):
		return
	var rect := Rect2i(result["x"] * VC.CELL_PX, VC.floor_to_row(result["floor"]) * VC.CELL_PX,
		result["width"] * VC.CELL_PX, result["height"] * VC.CELL_PX)
	var tint := VALID_TINT if result["valid"] else INVALID_TINT
	draw_rect(rect, tint)
	draw_rect(rect, Color(tint, 1.0), false, 1.0)
