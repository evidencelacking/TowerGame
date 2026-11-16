class_name RoomWindow
extends CanvasLayer
## Hover a room to see its info window; click it to pin the window so the rent buttons can be
## used. It shows occupants, the grade bar, rent and every complaint reason, worst first. Esc or
## a click on empty space closes a pinned window. It stays shut while a build tool is active and
## ignores clicks that land on a person (the person window takes those). Rent changes go to the
## sim as SET_RENT commands. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const RentScript := preload("res://scripts/sim/rent.gd")

var tower: TowerSim = null
var ghost: Ghost = null  ## Read for the active build tool.
var room_id: int = -1  ## The room shown, or -1 when closed.
var pinned: bool = false  ## True after a click: hover no longer changes the room.
var panel: InfoPanel
var bar: ProgressBar
var rent_row: HBoxContainer
var _view := PeopleView.new()
var _shown_tick: int = -1


func _init() -> void:
	layer = 5
	panel = InfoPanel.new()
	panel.name = "RoomPanel"
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 16.0
	panel.offset_right = 16.0
	add_child(panel)
	bar = ProgressBar.new()
	bar.name = "GradeBar"
	bar.max_value = RoomInfo.QUALITY_MAX
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	panel.add_control(bar)
	rent_row = HBoxContainer.new()
	rent_row.name = "RentRow"
	panel.add_control(rent_row)
	for level in RentScript.LEVELS:
		var button := Button.new()
		button.name = "Rent%d" % level
		button.text = RoomInfo.LEVEL_NAMES[level]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_rent.bind(level))
		rent_row.add_child(button)


func bind(tower_value: TowerSim, ghost_value: Ghost) -> void:
	tower = tower_value
	ghost = ghost_value


func is_open() -> bool:
	return room_id != -1


func _tool_active() -> bool:
	return ghost != null and ghost.tool != ""


## Shows a room's window, pinned or not. Does nothing for an id that is not a room.
func show_room(id: int, pin: bool) -> void:
	if tower == null or id == -1 or tower.rooms.kind_of(id) == "":
		return
	room_id = id
	pinned = pin
	_refresh()


## Hover over a world point: shows the room there unless the window is pinned, closes when the
## pointer is over nothing. Returns true if a room is shown afterwards.
func hover_at(world: Vector2) -> bool:
	if tower == null or pinned:
		return is_open()
	if _tool_active():
		close()
		return false
	var id := RoomInfo.room_at(tower, world)
	if id == -1:
		close()
	else:
		show_room(id, false)
	return is_open()


## A click on a world point (person_radius is the person pick radius in world pixels): pins the
## room there, or closes the window on empty space. A click on a person is left to the person window.
func click_at(world: Vector2, person_radius: float) -> void:
	if tower == null or _tool_active():
		return
	if PersonInfo.pick(_view.figures(tower), world, person_radius) != -1:
		return
	var id := RoomInfo.room_at(tower, world)
	if id == -1:
		close()
	else:
		show_room(id, true)


func close() -> void:
	room_id = -1
	pinned = false
	panel.visible = false


## Asks the sim to set the shown room's rent level (applies on the next tick). Returns true if queued.
func set_rent(level: int) -> bool:
	if tower == null or not is_open():
		return false
	var args: Array[int] = [room_id, level]
	return tower.enqueue(TowerSim.Command.make(tower.tick + 1, TowerSim.Command.SET_RENT, args))


func _process(_delta: float) -> void:
	if is_open() and tower != null and tower.tick != _shown_tick:
		_refresh()


func _refresh() -> void:
	if tower == null or tower.rooms.kind_of(room_id) == "":  # bulldozed
		close()
		return
	_shown_tick = tower.tick
	var info := RoomInfo.describe(tower, room_id)
	panel.show_info(info["label"], RoomInfo.lines_for(info))
	var value := RoomInfo.bar_value(info)
	bar.visible = value >= 0
	if value >= 0:
		bar.value = value
		var fill := StyleBoxFlat.new()
		fill.bg_color = RoomInfo.bar_color(info)
		bar.add_theme_stylebox_override("fill", fill)
	# Condos cannot change rent (the reference); only rentable kinds get the buttons.
	rent_row.visible = info["rentable"]
	for level in RentScript.LEVELS:
		var button := rent_row.get_child(level) as Button
		button.disabled = not pinned or level == info["rent_level"]


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and not (is_open() and panel.contains_point(motion.position)):
		hover_at(get_viewport().get_canvas_transform().affine_inverse() * motion.position)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var xform := get_viewport().get_canvas_transform()
	click_at(xform.affine_inverse() * click.position, PersonInfo.PICK_RADIUS_PX / maxf(xform.get_scale().x, 0.01))
