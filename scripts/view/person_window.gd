class_name PersonWindow
extends CanvasLayer
## Click a person to open their info window: name, where they came from and are going to, stress
## and its band, and a rename field. Esc or a click outside closes it. It stays shut while a build
## tool is active, so clicks on people never fight the placement ghost. Renames go to the sim as
## RENAME_PERSON commands. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const NamesScript := preload("res://scripts/sim/names.gd")

var tower: TowerSim = null
var ghost: Ghost = null  ## Read for the active build tool.
var person_id: int = -1  ## The person shown, or -1 when closed.
var panel: InfoPanel
var _view := PeopleView.new()
var _shown_tick: int = -1


func _init() -> void:
	layer = 6
	panel = InfoPanel.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -16.0
	panel.offset_right = -16.0
	panel.rename_submitted.connect(rename)
	add_child(panel)


func bind(tower_value: TowerSim, ghost_value: Ghost) -> void:
	tower = tower_value
	ghost = ghost_value


func is_open() -> bool:
	return person_id != -1


## Opens the window on the figure nearest to a world point, within radius world pixels. Returns
## false, changing nothing, if a build tool is active or no figure is close enough.
func open_at(world: Vector2, radius: float) -> bool:
	if tower == null or (ghost != null and ghost.tool != ""):
		return false
	var id := PersonInfo.pick(_view.figures(tower), world, radius)
	if id == -1:
		return false
	open_person(id)
	return true


func open_person(id: int) -> void:
	if tower == null or tower.people.index_of(id) == -1:
		return
	person_id = id
	_refresh(true)


func close() -> void:
	person_id = -1
	panel.visible = false


## Asks the sim to rename the shown person (applies on the next tick). Returns true if queued.
func rename(text: String) -> bool:
	if tower == null or not is_open():
		return false
	var command := TowerSim.Command.make(tower.tick + 1, TowerSim.Command.RENAME_PERSON, NamesScript.args_for(person_id, text))
	return tower.enqueue(command)


func _process(_delta: float) -> void:
	if is_open() and tower != null and tower.tick != _shown_tick:
		_refresh(false)


func _refresh(reset_field: bool) -> void:
	var i := tower.people.index_of(person_id) if tower != null else -1
	if i == -1:  # the person is gone (their room was bulldozed)
		close()
		return
	_shown_tick = tower.tick
	var info := PersonInfo.describe(tower, i)
	panel.show_info(info["name"], PersonInfo.lines_for(info), info["name"], reset_field)


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and not panel.contains_point(click.position):
		close()  # a click on another person reopens in _unhandled_input


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var to_world := get_viewport().get_canvas_transform().affine_inverse()
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	open_at(to_world * click.position, PersonInfo.PICK_RADIUS_PX / maxf(zoom, 0.01))
