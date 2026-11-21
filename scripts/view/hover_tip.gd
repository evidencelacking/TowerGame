class_name HoverTip
extends CanvasLayer
## A small tooltip after the pointer rests 5 seconds over a person or a room (#375): kind, status,
## income or mood. It hides as soon as the pointer moves. Shows nothing while a build tool is active.
## View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")

const DELAY_SEC := 5.0
const MOVE_SLOP_PX := 2.0  ## Jitter smaller than this does not count as a move.

var tower: TowerSim = null
var ghost: Ghost = null
var panel: PanelContainer
var label: Label
var still_sec: float = 0.0
var _view := PeopleView.new()
var _last_mouse: Vector2 = Vector2(-1, -1)


## The tooltip text for a world point: a person wins over the room behind them. "" if nothing there.
static func text_at(t: Object, figures: Array[Dictionary], world: Vector2, person_radius: float) -> String:
	var person_id := PersonInfo.pick(figures, world, person_radius)
	if person_id != -1:
		var i: int = t.people.index_of(person_id)
		if i != -1:
			var info := PersonInfo.describe(t, i)
			return "%s\nPerson\n%s" % [info["name"], PersonInfo.mood_line(info)]
	var room := RoomInfo.room_at(t, world)
	if room == -1:
		return ""
	var d := RoomInfo.describe(t, room)
	var lines: Array[String] = [d["label"], "Status: %s" % ("vacant" if d["vacant"] else "in use")]
	if d["rentable"]:
		lines.append("Income: $%d a quarter" % d["rent"])
	if d["capacity"] > 0:
		lines.append("Occupants: %d of %d" % [d["occupants"].size(), d["capacity"]])
	return "\n".join(lines)


func _init() -> void:
	layer = 7
	panel = PanelContainer.new()
	panel.name = "HoverPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.visible = false
	add_child(panel)


func bind(tower_value: TowerSim, ghost_value: Ghost) -> void:
	tower = tower_value
	ghost = ghost_value


func is_showing() -> bool:
	return panel.visible


## Called with the screen position each frame: advances the still timer, hides on a move, and
## shows the tip once the pointer has rested DELAY_SEC. Returns true if the tip is showing.
func advance(delta: float, screen: Vector2, world: Vector2, radius: float) -> bool:
	if screen.distance_to(_last_mouse) > MOVE_SLOP_PX:
		_last_mouse = screen
		still_sec = 0.0
		panel.visible = false
		return false
	still_sec += delta
	if still_sec >= DELAY_SEC and not panel.visible and tower != null and (ghost == null or ghost.tool == ""):
		var text := text_at(tower, _view.figures(tower), world, radius)
		if text != "":
			label.text = text
			panel.position = screen + Vector2(14, 18)
			panel.visible = true
	return panel.visible


func _process(delta: float) -> void:
	var vp := get_viewport()
	var screen := vp.get_mouse_position()
	var xform := vp.get_canvas_transform()
	advance(delta, screen, xform.affine_inverse() * screen, PersonInfo.PICK_RADIUS_PX / maxf(xform.get_scale().x, 0.01))
