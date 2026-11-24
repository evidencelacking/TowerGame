class_name BulkRent
extends CanvasLayer
## Bulk rent (#28): set the rent level of many rooms with one SET_RENT_MANY command. Open it from the
## room window's "Bulk..." button, the toolbar or its key; then drag over rooms to select them. The
## scope picks what a level button applies to: the dragged selection, the clicked room's floor, its
## room type (whole tower) or every rentable room in the tower (that one asks first). A mixed selection
## shows a count per level. Condos and rooms without rent levels are skipped by the sim and counted.
## One instance, found through the "bulk_rent" group. View only: it reads the sim and queues commands.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")

enum Scope { SELECTION, FLOOR, TYPE, TOWER }
const SCOPE_NAMES: Array[String] = ["Selection", "This floor", "This room type", "Whole tower"]

var tower: TowerSim = null
var ghost: Ghost = null
var scope: Scope = Scope.SELECTION
var anchor: int = -1  ## The clicked room that the floor and type scopes read, or -1.
var selection: Array[int] = []  ## Room ids under the dragged rectangle (or the clicked room).
var panel: PanelContainer
var summary: Label
var status: Label
var confirm_box: VBoxContainer
var confirm_text: Label
var pending_level: int = -1  ## The level waiting on the whole-tower confirm, or -1.
var _scope_buttons: Array[Button] = []
var _level_buttons: Array[Button] = []
var _dragging: bool = false
var _drag_from := Vector2i.ZERO  ## (floor, column) where the drag began.
var _queued_tick: int = -1  ## The tick the last command applies at, until its report is shown.


func _init() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 48.0
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "Bulk rent: drag over rooms, then pick a level"
	column.add_child(title)
	var scopes := HBoxContainer.new()
	column.add_child(scopes)
	for i in SCOPE_NAMES.size():
		var button := Button.new()
		button.name = "Scope%d" % i
		button.text = SCOPE_NAMES[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(set_scope.bind(i))
		scopes.add_child(button)
		_scope_buttons.append(button)
	summary = Label.new()
	summary.name = "Summary"
	column.add_child(summary)
	var levels := HBoxContainer.new()
	column.add_child(levels)
	for level in RentScript.LEVELS:
		var button := Button.new()
		button.name = "Level%d" % level
		button.text = RoomInfo.LEVEL_NAMES[level]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(choose.bind(level))
		levels.add_child(button)
		_level_buttons.append(button)
	confirm_box = VBoxContainer.new()
	confirm_box.name = "Confirm"
	confirm_box.visible = false
	column.add_child(confirm_box)
	confirm_text = Label.new()
	confirm_text.name = "ConfirmText"
	confirm_box.add_child(confirm_text)
	var yes := Button.new()
	yes.name = "ConfirmYes"
	yes.text = "Yes, set them all"
	yes.focus_mode = Control.FOCUS_NONE
	yes.pressed.connect(confirm)
	confirm_box.add_child(yes)
	var no := Button.new()
	no.name = "ConfirmNo"
	no.text = "Cancel"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(cancel_confirm)
	confirm_box.add_child(no)
	status = Label.new()
	status.name = "Status"
	column.add_child(status)
	var done := Button.new()
	done.name = "Done"
	done.text = "Done"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	column.add_child(done)


func _ready() -> void:
	add_to_group("bulk_rent")


func bind(tower_value: TowerSim, ghost_value: Ghost) -> void:
	tower = tower_value
	ghost = ghost_value


func is_open() -> bool:
	return panel.visible


## Opens the mode, optionally on a clicked room (which the floor and type scopes read).
func open(room: int = -1) -> void:
	panel.visible = true
	anchor = room
	selection.clear()
	if room != -1:
		selection.append(room)
	scope = Scope.SELECTION
	status.text = ""
	cancel_confirm()
	if ghost != null:
		ghost.set_tool("")
	_refresh()


func close() -> void:
	panel.visible = false
	_dragging = false
	cancel_confirm()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func set_scope(value: int) -> void:
	scope = value as Scope
	cancel_confirm()
	_refresh()


## True for a room that can take a rent level: not a condo, and with rent levels in its catalogue row.
func eligible(id: int) -> bool:
	var kind := tower.rooms.kind_of(id)
	return kind != "" and not CatalogueScript.is_condo(kind) and RentScript.is_rentable(kind)


## The room ids the current scope covers, ascending. Floor and tower scopes list only rentable kinds;
## a dragged selection lists everything it touched, so the sim's skipped count is honest.
func target_ids() -> Array[int]:
	var out: Array[int] = []
	if tower == null:
		return out
	var anchored := anchor != -1 and tower.rooms.has_room(anchor)
	match scope:
		Scope.SELECTION:
			out.assign(selection)
		Scope.FLOOR:
			if anchored:
				var floors_here := tower.rooms.floors_of(tower.grid, anchor)
				for id in tower.rooms.room_ids():
					if RentScript.is_rentable(tower.rooms.kind_of(id)) and _shares_floor(id, floors_here):
						out.append(id)
		Scope.TYPE:
			if anchored:
				var kind := tower.rooms.kind_of(anchor)
				for id in tower.rooms.room_ids():
					if tower.rooms.kind_of(id) == kind:
						out.append(id)
		Scope.TOWER:
			for id in tower.rooms.room_ids():
				if RentScript.is_rentable(tower.rooms.kind_of(id)):
					out.append(id)
	out.sort()
	return out


func _shares_floor(id: int, floors_here: Array[int]) -> bool:
	for f in tower.rooms.floors_of(tower.grid, id):
		if f in floors_here:
			return true
	return false


## Rooms per current level among the targets that can take one: [count of level 0, ..., level 3].
func level_counts() -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for id in target_ids():
		if eligible(id):
			counts[tower.rent.level_of(id)] += 1
	return counts


## "3 lowest, 5 average", or why there is nothing to set.
func summary_text() -> String:
	var counts := level_counts()
	var parts: Array[String] = []
	var total := 0
	for level in RentScript.LEVELS:
		total += counts[level]
		if counts[level] > 0:
			parts.append("%d %s" % [counts[level], RoomInfo.LEVEL_NAMES[level].to_lower()])
	var skipped := target_ids().size() - total
	var text := ", ".join(parts) if total > 0 else "No rooms with rent levels"
	if skipped > 0:
		text += " (%d cannot change)" % skipped
	return text


## A level button: applies to the scope, or asks first when the scope is the whole tower.
func choose(level: int) -> void:
	if tower == null:
		return
	var total := 0
	for n in level_counts():
		total += n
	if total == 0:
		status.text = "Nothing to set"
		return
	if scope == Scope.TOWER:
		pending_level = level
		confirm_text.text = "Set rent for %d rooms across the tower?" % total
		confirm_box.visible = true
		return
	_send(level)


func confirm() -> void:
	if pending_level != -1:
		var level := pending_level
		cancel_confirm()
		_send(level)


func cancel_confirm() -> void:
	pending_level = -1
	confirm_box.visible = false


## Queues the command; the report appears once the sim has applied it.
func _send(level: int) -> bool:
	var args: Array[int] = [level]
	args.append_array(target_ids())
	_queued_tick = tower.tick + 1
	status.text = "Setting rent..."
	return tower.enqueue(TowerSim.Command.make(_queued_tick, TowerSim.Command.SET_RENT_MANY, args))


## Selects the rooms touched by a rectangle of cells, given as (floor, column) corners in either order.
## The first room found becomes the anchor of the floor and type scopes.
func select_rect(a: Vector2i, b: Vector2i) -> void:
	var found: Dictionary = {}
	for f in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		if f == 0:
			continue
		for c in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			var id: int = tower.grid.cell_at(f, c)
			var room: int = tower.rooms.room_of(id)
			if id > GridScript.EMPTY and room != 0:
				found[room] = true
	selection.assign(found.keys())
	selection.sort()
	if not selection.is_empty():
		anchor = selection[0]
	scope = Scope.SELECTION
	_refresh()


func _refresh() -> void:
	if tower == null:
		return
	for i in _scope_buttons.size():
		_scope_buttons[i].button_pressed = i == scope
		_scope_buttons[i].disabled = (i == Scope.FLOOR or i == Scope.TYPE) and anchor == -1
	summary.text = summary_text()


func _process(_delta: float) -> void:
	if tower != null and _queued_tick != -1 and tower.last_bulk_rent[2] >= _queued_tick:
		_queued_tick = -1
		status.text = report()
		_refresh()


## "Rent set for 8 rooms, 2 skipped" from the last bulk command the sim applied.
func report() -> String:
	var done: int = tower.last_bulk_rent[0]
	var text := "Rent set for %d room%s" % [done, "" if done == 1 else "s"]
	if tower.last_bulk_rent[1] > 0:
		text += ", %d skipped" % tower.last_bulk_rent[1]
	return text


func _cell_at(world: Vector2) -> Vector2i:
	return Vector2i(RoomInfo.floor_at_y(world.y), floori(world.x / VC.CELL_W))


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and is_open():
		if confirm_box.visible:
			cancel_confirm()
		else:
			close()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and KeyBindings.is_key(key, "bulk_rent") \
			and not key.ctrl_pressed and not key.alt_pressed:
		toggle()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or tower == null or (ghost != null and ghost.tool != ""):
		return
	var xform := get_viewport().get_canvas_transform().affine_inverse()
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_dragging = true
			_drag_from = _cell_at(xform * click.position)
			select_rect(_drag_from, _drag_from)
		elif _dragging:
			_dragging = false
			select_rect(_drag_from, _cell_at(xform * click.position))
		get_viewport().set_input_as_handled()
	elif _dragging and event is InputEventMouseMotion:
		select_rect(_drag_from, _cell_at(xform * (event as InputEventMouseMotion).position))
