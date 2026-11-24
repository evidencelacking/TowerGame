class_name AlertMarkers
extends CanvasLayer
## Alert markers (M9 9.8, #223): for each alert on the sim's list (Alerts.list) that has a floor outside the view, a
## button at the top or bottom screen edge says what it is and which way it lies; a click jumps the camera to the
## floor. Alerts with no floor (a threat's device is secret) and alerts already in view get no marker. View only:
## it reads the sim's list and moves the camera, and never writes to the sim.

const AlertsScript := preload("res://scripts/sim/alerts.gd")
const ViewConsts := preload("res://scripts/view/view_consts.gd")
const EDGE_GAP := 76.0  ## Screen pixels between a marker and the screen edge (clear of the toolbar and news ticker).
const SPACING := 8.0  ## Screen pixels between markers on the same edge.
const KIND_COLORS := {1: Color(1.0, 0.45, 0.35), 2: Color(1.0, 0.8, 0.3), 3: Color(0.6, 0.85, 1.0), 4: Color(0.35, 0.65, 1.0), 5: Color(0.9, 0.9, 0.5)}  ## Fire, threat, event, wet floor, stalled car.

var tower: Object = null
var camera: Camera2D = null
var root: Control
var _signature: String = ""
var _buttons: Array[Button] = []
var _sides: Array[int] = []  ## The edge each button sits on, in step with _buttons.


func _init() -> void:
	layer = 5
	root = Control.new()
	root.name = "Markers"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)


func bind(tower_value: Object, camera_value: Camera2D) -> void:
	tower = tower_value
	camera = camera_value


## The world y at the middle of a floor.
static func world_y_of(floor_number: int) -> float:
	return (ViewConsts.floor_to_row(floor_number) + 0.5) * ViewConsts.CELL_H


## -1 if the world y lies above the view, 1 if below, 0 if inside it.
static func side_of(world_y: float, cam_y: float, zoom: float, view_h: float) -> int:
	var screen_y := (world_y - cam_y) * zoom + view_h * 0.5
	if screen_y < 0.0:
		return -1
	if screen_y > view_h:
		return 1
	return 0


## The markers to show: one per located alert whose floor is out of view, in list order, each
## {"index" (into the list), "side" (-1 above, 1 below), "floor", "kind"}.
static func markers(alerts: Array, cam_y: float, zoom: float, view_h: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in alerts.size():
		var alert: Array = alerts[n]
		if alert[1] == 0:
			continue
		var side := side_of(world_y_of(alert[1]), cam_y, zoom, view_h)
		if side != 0:
			out.append({"index": n, "side": side, "floor": alert[1], "kind": alert[0]})
	return out


static func _floor_text(floor_number: int) -> String:
	return "B%d" % -floor_number if floor_number < 0 else str(floor_number)


func _process(_delta: float) -> void:
	refresh()


## Brings the buttons in line with the sim and camera. Rebuilt only when the set of markers changes, so a click is
## never lost to a rebuild; placed every frame so a resize or a camera move keeps them on the edge.
func refresh() -> void:
	if tower == null or camera == null or not is_inside_tree():
		return
	show_for(AlertsScript.list(tower), camera.position.y, camera.zoom.y, get_viewport().get_visible_rect().size.y)


## Shows the markers for a list of alerts seen by a camera at world y `cam_y`, zoom `zoom`, in a view `view_h` tall.
func show_for(alerts: Array, cam_y: float, zoom: float, view_h: float) -> void:
	var shown := markers(alerts, cam_y, zoom, view_h)
	var parts: Array[String] = []
	for marker in shown:
		parts.append("%d:%d:%d:%d" % [marker["index"], marker["side"], marker["floor"], marker["kind"]])
	var signature := "|".join(parts)
	if signature != _signature:
		_signature = signature
		_rebuild(shown, alerts)
	if is_inside_tree():
		_place()


func _rebuild(shown: Array[Dictionary], alerts: Array) -> void:
	for button in _buttons:
		root.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_sides.clear()
	for marker in shown:
		var alert: Array = alerts[marker["index"]]
		var button := Button.new()
		button.name = "Alert%d" % marker["index"]
		button.text = "%s %s: floor %s" % ["^" if marker["side"] < 0 else "v", AlertsScript.label_of(alert, tower), _floor_text(marker["floor"])]
		button.tooltip_text = "Click to go there."
		button.focus_mode = Control.FOCUS_NONE
		button.modulate = KIND_COLORS.get(alert[0], Color.WHITE)
		var floor_number: int = marker["floor"]
		button.pressed.connect(func() -> void: jump_to_floor(floor_number))
		root.add_child(button)
		_buttons.append(button)
		_sides.append(marker["side"])


## Jumps the camera to a floor, keeping its column.
func jump_to_floor(floor_number: int) -> void:
	if camera != null and camera.has_method("jump_to"):
		camera.call("jump_to", Vector2(camera.position.x, world_y_of(floor_number)))


## Lines the buttons up along the top and bottom edges, centred, side by side.
func _place() -> void:
	if _buttons.is_empty():
		return
	var view := get_viewport().get_visible_rect().size
	var widths: Dictionary = {-1: -SPACING, 1: -SPACING}
	for n in _buttons.size():
		widths[_sides[n]] += _buttons[n].get_combined_minimum_size().x + SPACING
	var next_x: Dictionary = {-1: (view.x - widths[-1]) * 0.5, 1: (view.x - widths[1]) * 0.5}
	for n in _buttons.size():
		var side: int = _sides[n]
		var need := _buttons[n].get_combined_minimum_size()
		_buttons[n].position = Vector2(next_x[side], EDGE_GAP if side < 0 else view.y - EDGE_GAP - need.y)
		next_x[side] += need.x + SPACING
