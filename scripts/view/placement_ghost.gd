class_name PlacementGhost
extends Node2D
## The build-tool ghost: follows the mouse snapped to the grid and shows whether the build is
## valid, its total cost, a plain refusal reason, and a warning for rooms that cannot be removed.
## View only. Every verdict comes from the sim's read-only check_* functions; this file only
## words them. A left click enqueues the matching command. The toolbar (toolbar.gd) picks the
## tool too. Keys: L lobby, F floor, S stairs, O office, C condo, B bulldoze, R replace, Esc none.

const VC := preload("res://scripts/view/view_consts.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const GridScript := preload("res://scripts/sim/grid.gd")

const BULLDOZE := "bulldoze"  ## Tools that are not catalogue ids: BULLDOZE and REPLACE.
const REPLACE := "replace"  ## Bulldoze the room under the cursor and build last_room there.
const STAIRS := "stairs"
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
	RoomsScript.NO_FLOOR_FOR_STAIRS: "Needs a floor on both levels",
	RoomsScript.STAIRS_LIMIT: "Too many stairs and escalators",
	RoomsScript.MAX_SHAFT_FLOORS: "A shaft spans at most 30 floors",
	RoomsScript.MAX_SHAFTS: "The tower has the most shafts (24)",
	RoomsScript.NO_FLOOR_FOR_SHAFT: "Needs a built floor on every level",
	RoomsScript.BAD_SHAFT_SPAN: "The top must be above the bottom",
}
const BULLDOZE_TEXT: Dictionary = {
	RoomsScript.BAD_FLOOR: "Not a floor",
	RoomsScript.NOTHING_THERE: "Nothing to remove here",
	RoomsScript.PERMANENT: "Permanent: cannot be removed",
	RoomsScript.NOT_A_ROOM: "Not a room",
}

var tower: TowerSim = null
var tool: String = ""  ## "" (off), BULLDOZE, or a catalogue id.
var stars: int:  ## Current star rating, read from the sim.
	get:
		return tower.stars if tower != null else TowerSim.START_STARS
var last_room: String = "office"  ## The room the replace tool builds: the last room tool chosen.
var _last_key: Array = []  ## What result was computed for; check_* only reruns when it changes.
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
	if value in RoomsScript.PLACEABLE:
		last_room = value
	_last_key = []


## True for every tool the sim can build today (the rest show in the toolbar but cannot be picked).
static func is_buildable(tool_id: String) -> bool:
	return tool_id in [BULLDOZE, REPLACE, STAIRS, "lobby", "floor"] or tool_id in RoomsScript.PLACEABLE


## Wording for a sim refusal code. source is "floors", "rooms" or "bulldoze".
static func reason_text(source: String, code: int) -> String:
	var table: Dictionary = FLOOR_TEXT
	match source:
		"rooms": table = ROOM_TEXT
		"bulldoze": table = BULLDOZE_TEXT
		"replace": table = BULLDOZE_TEXT.merged(ROOM_TEXT)
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
static func evaluate(t: TowerSim, tool_id: String, floor_number: int, x_left: int, star_rating: int, kind: String = "") -> Dictionary:
	var out := {"valid": false, "cost": 0, "text": "", "permanent": false,
		"floor": floor_number, "x": x_left, "width": width_of(tool_id), "height": 1}
	if tool_id == BULLDOZE:
		return _evaluate_bulldoze(t, floor_number, x_left, out)
	if tool_id == REPLACE:
		return _evaluate_replace(t, kind if kind != "" else "office", floor_number, x_left, star_rating, out)
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
		STAIRS:
			var stairs := t.rooms.check_place_stairs(t.grid, t.floors, floor_number, x_left)
			code = stairs["reason"]
			out["cost"] = stairs["cost"]
			out["height"] = 2
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


## Replace: the room under column x goes and kind is built from that room's left edge.
static func _evaluate_replace(t: TowerSim, kind: String, floor_number: int, x: int, star_rating: int, out: Dictionary) -> Dictionary:
	out["permanent"] = is_permanent(kind)
	out["width"] = width_of(kind)
	var hit := t.rooms.check_bulldoze(t.grid, t.floors, floor_number, x)
	if hit["reason"] != 0:
		out["text"] = reason_text("replace", hit["reason"])
		return out
	out["x"] = t.grid.run_of(hit["room_id"])[1]
	var checked := t.rooms.check_replace(t.grid, t.floors, t.ledger.balance, kind, floor_number, out["x"])
	out["cost"] = checked["net"]
	if CatalogueScript.star(kind) > star_rating:
		out["text"] = "Needs %d stars" % CatalogueScript.star(kind)
	elif checked["reason"] != 0:
		out["text"] = reason_text("replace", checked["reason"])
	else:
		out["valid"] = true
		out["text"] = "Replace with %s: net $%d" % [kind, checked["net"]]
	return out


## The command a click sends for a valid verdict, due the tick after `tick`; null if invalid.
static func command_for(tool_id: String, verdict: Dictionary, tick: int, kind: String = "") -> TowerSim.Command:
	if not verdict["valid"]:
		return null
	var floor_number: int = verdict["floor"]
	var x: int = verdict["x"]
	var due := tick + 1
	var Cmd := TowerSim.Command
	match tool_id:
		BULLDOZE: return Cmd.make(due, Cmd.BULLDOZE, [floor_number, x] as Array[int])
		REPLACE: return Cmd.make(due, Cmd.REPLACE_ROOM, [CatalogueScript.IDS.find(kind), floor_number, x] as Array[int])
		STAIRS: return Cmd.make(due, Cmd.PLACE_STAIRS, [floor_number, x] as Array[int])
		"lobby": return Cmd.make(due, Cmd.BUILD_LOBBY, [1, x, x + LOBBY_SPAN_WIDTH - 1, 1] as Array[int])
		"floor": return Cmd.make(due, Cmd.BUILD_FLOOR, [floor_number, x, x + FLOOR_SPAN_WIDTH - 1] as Array[int])
	if CatalogueScript.has(tool_id):
		return Cmd.make(due, Cmd.PLACE_ROOM, [CatalogueScript.IDS.find(tool_id), floor_number, x] as Array[int])
	return null


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
	if tool_id == BULLDOZE or tool_id == REPLACE:
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
		KEY_S: set_tool(STAIRS)
		KEY_O: set_tool("office")
		KEY_C: set_tool("condo")
		KEY_B: set_tool(BULLDOZE)
		KEY_R: set_tool(REPLACE)
		KEY_ESCAPE: set_tool("")


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		commit()


## Sends the current verdict to the sim as a command. Returns true if one was queued.
func commit() -> bool:
	if tower == null or tool == "" or result.is_empty():
		return false
	var command := command_for(tool, result, tower.tick, last_room)
	_last_key = []  ## The build changes the verdict: recompute on the next frame.
	return command != null and tower.enqueue(command)


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
	var x_left := column if tool in [BULLDOZE, REPLACE] else column - width_of(tool) / 2
	var key: Array = [tool, last_room, floor_number, x_left, stars, tower.ledger.balance]
	if key != _last_key:  ## check_replace copies the grid, so only judge when something changed.
		_last_key = key
		result = evaluate(tower, tool, floor_number, x_left, stars, last_room)
		_label.text = "\n".join(lines_for(tool, result))
		queue_redraw()
	_panel.visible = true
	_panel.position = get_viewport().get_mouse_position() + Vector2(18, 18)


func _draw() -> void:
	if result.is_empty() or not GridScript.is_valid_floor(result["floor"]):
		return
	var top: int = result["floor"]
	if result["height"] > 1:
		top = RoomsScript.floor_above(top)  ## Stairs span two floors: draw from the upper one.
	var rect := Rect2i(result["x"] * VC.CELL_PX, VC.floor_to_row(top) * VC.CELL_PX,
		result["width"] * VC.CELL_PX, result["height"] * VC.CELL_PX)
	var tint := VALID_TINT if result["valid"] else INVALID_TINT
	draw_rect(rect, tint)
	draw_rect(rect, Color(tint, 1.0), false, 1.0)
