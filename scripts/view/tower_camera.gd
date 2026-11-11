extends Camera2D
## Pans (middle/right drag, WASD/arrows, screen edges) and zooms (wheel, +/-) in integer
## steps, always clamped so the view never leaves the tower's world.

const ViewConsts := preload("res://scripts/view/view_consts.gd")
const ZOOM_STEPS: Array[int] = [1, 2, 3, 4]
const KEY_SPEED_PX := 600.0  ## Screen pixels per second.
const EDGE_MARGIN_PX := 8
const EDGE_SPEED_PX := 500.0

var _zoom_index: int = 0
var _dragging: bool = false


## Clamp a camera centre so a view of view_px at integer zoom stays inside world.
## An axis where the world is smaller than the view is centred.
static func clamp_position(pos: Vector2, view_px: Vector2, zoom: int, world: Rect2) -> Vector2:
	var half: Vector2 = view_px / (2.0 * zoom)
	var out: Vector2 = pos
	if world.size.x <= half.x * 2.0:
		out.x = world.get_center().x
	else:
		out.x = clampf(pos.x, world.position.x + half.x, world.end.x - half.x)
	if world.size.y <= half.y * 2.0:
		out.y = world.get_center().y
	else:
		out.y = clampf(pos.y, world.position.y + half.y, world.end.y - half.y)
	return out


func _ready() -> void:
	# Start on the lobby, the centre of the tower's width.
	var row: int = ViewConsts.floor_to_row(1)
	position = Vector2(ViewConsts.world_rect().size.x / 2.0, (row + 0.5) * ViewConsts.CELL_PX)
	_apply()


func zoom_in() -> void:
	set_zoom_index(_zoom_index + 1)


func zoom_out() -> void:
	set_zoom_index(_zoom_index - 1)


func set_zoom_index(index: int) -> void:
	_zoom_index = clampi(index, 0, ZOOM_STEPS.size() - 1)
	_apply()


func pan_by_screen(delta_px: Vector2) -> void:
	position += delta_px / float(ZOOM_STEPS[_zoom_index])
	_apply()


func _apply() -> void:
	var z: int = ZOOM_STEPS[_zoom_index]
	zoom = Vector2(z, z)
	position = clamp_position(position, get_viewport_rect().size, z, ViewConsts.world_rect())
	position = position.round()  # whole pixels keep integer zoom sharp


func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	dir.x = Input.get_axis(&"ui_left", &"ui_right")
	dir.y = Input.get_axis(&"ui_up", &"ui_down")
	for pair: Array in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_key_pressed(pair[0] as Key):
			dir += pair[1] as Vector2
	var speed: float = KEY_SPEED_PX
	if dir == Vector2.ZERO and not _dragging and get_window().has_focus():
		dir = _edge_direction()
		speed = EDGE_SPEED_PX
	if dir != Vector2.ZERO:
		pan_by_screen(dir.limit_length(1.0) * speed * delta)
	elif get_viewport_rect().size != _last_view:
		_apply()
	_last_view = get_viewport_rect().size


var _last_view: Vector2 = Vector2.ZERO


func _edge_direction() -> Vector2:
	var vp: Viewport = get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	var m: Vector2 = vp.get_mouse_position()
	if m.x < 0.0 or m.y < 0.0 or m.x >= size.x or m.y >= size.y:
		return Vector2.ZERO
	var d: Vector2 = Vector2.ZERO
	if m.x < EDGE_MARGIN_PX:
		d.x = -1.0
	elif m.x > size.x - EDGE_MARGIN_PX:
		d.x = 1.0
	if m.y < EDGE_MARGIN_PX:
		d.y = -1.0
	elif m.y > size.y - EDGE_MARGIN_PX:
		d.y = 1.0
	return d


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
	elif event is InputEventMouseMotion and _dragging:
		pan_by_screen(-(event as InputEventMouseMotion).relative)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_EQUAL, KEY_KP_ADD:
				zoom_in()
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_out()
