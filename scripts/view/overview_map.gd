class_name OverviewMap
extends CanvasLayer
## Overview map (#489): the whole tower small, in a corner panel. One coloured block per room (an Image of one pixel per
## floor-unit column and floor, shown scaled), a filter row (Off for room-kind colours, the six heat modes of heat_look,
## and Problems from disruption_look), the #223 alerts as pins, and a rectangle for what the camera sees. A click jumps
## the camera there and a drag scrolls it. View only: it reads the tower and moves the camera, never writes the sim.
## Cheap: the image is rebuilt only when the layout or the filter changes, or on the filter's own refresh interval, so a
## frame with no change costs a few comparisons.

const HeatLook := preload("res://scripts/view/heat_look.gd")
const DisruptionLook := preload("res://scripts/view/disruption_look.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const AlertsScript := preload("res://scripts/sim/alerts.gd")
const AlertMarkers := preload("res://scripts/view/alert_markers.gd")

## The filters. 0 to 6 are HeatLook's modes (Off shows room-kind colours), so a heat mode is its own filter.
const PROBLEMS := 7
const FILTER_NAMES: Array[String] = ["Off", "Income", "Mood", "Traffic", "Rent", "Grade", "Hotel", "Problems"]
const COLS := GridScript.WIDTH_UNITS
const ROWS := GridScript.FLOOR_COUNT
const DISPLAY := Vector2(200.0, 220.0)  ## On-screen size of the map; the image is COLS x ROWS and is scaled to it.
const BACKGROUND := Color(0.16, 0.17, 0.2)
const DIM := 0.4  ## Unpainted rooms of a filter keep their kind colour at this brightness.
const VIEW_EDGE := Color(1.0, 1.0, 1.0, 0.95)
const PIN_RADIUS := 3.0
const PIN_EDGE := Color(0.0, 0.0, 0.0, 0.9)
const PIN_REFRESH_TICKS := 10  ## How often the sim's alert list is read.
const NEVER := 1 << 30  ## An interval that never passes (the Off filter changes only with the layout).

## The view option: whether the map is open. Session state only: never saved, in the tower or elsewhere.
static var open: bool = false

var tower: Object = null
var camera: Camera2D = null
var filter: int = HeatLook.OFF
var image_builds: int = 0  ## Times the image was rebuilt (tests count them to prove a quiet frame costs nothing).
var mark_draws: int = 0  ## Times the rectangle and pins were redrawn.
var view_size: Vector2 = Vector2(1920.0, 1080.0)  ## The game view in screen pixels; follows the viewport once in the tree.
var panel: PanelContainer
var map_view: Control
var _image: Image
var _texture: ImageTexture
var _marks: Control
var _filter_buttons: Array[Button] = []
var _built_filter: int = -1
var _built_tick: int = -NEVER
var _built_rooms: int = -1
var _built_floors: int = -1
var _seen_heat: int = HeatLook.OFF
var _seen_disruptions: bool = false
var _pins: Array[Dictionary] = []
var _pins_tick: int = -NEVER
var _mark_key: String = ""
var _dragging: bool = false


func _init() -> void:
	layer = 3
	_image = Image.create(COLS, ROWS, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -DISPLAY.x - 24.0
	panel.offset_right = -8.0
	panel.offset_top = 44.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var flow := HFlowContainer.new()
	flow.name = "Filters"
	flow.custom_minimum_size = Vector2(DISPLAY.x, 0.0)
	flow.add_theme_constant_override("h_separation", 2)
	flow.add_theme_constant_override("v_separation", 2)
	column.add_child(flow)
	for n: int in FILTER_NAMES.size():
		var button := Button.new()
		button.name = FILTER_NAMES[n]
		button.text = FILTER_NAMES[n]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 11)
		button.tooltip_text = "Room-kind colours." if n == 0 else "Colour the map by %s." % FILTER_NAMES[n].to_lower()
		button.pressed.connect(set_filter.bind(n))
		flow.add_child(button)
		_filter_buttons.append(button)
	map_view = Control.new()
	map_view.name = "Map"
	map_view.custom_minimum_size = DISPLAY
	map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	map_view.gui_input.connect(_on_gui_input)
	column.add_child(map_view)
	var backing := ColorRect.new()
	backing.color = BACKGROUND
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.add_child(backing)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = _texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.add_child(picture)
	_marks = Control.new()
	_marks.name = "Marks"
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	map_view.add_child(_marks)
	panel.visible = false
	_sync_buttons()


func bind(tower_value: Object, camera_value: Camera2D) -> void:
	tower = tower_value
	camera = camera_value


# ---- geometry (static, so tests and the click handler share it) ----

## The floor a map row shows: the inverse of ViewConsts.floor_to_row.
static func row_to_floor(row: int) -> int:
	return GridScript.FLOOR_MAX - row if row < GridScript.FLOOR_MAX else GridScript.FLOOR_MAX - 1 - row


## The world point (native px) under a point of the map control; clamped to the tower.
static func map_to_world(p: Vector2) -> Vector2:
	var world := VC.world_rect().size
	return Vector2(clampf(p.x / DISPLAY.x, 0.0, 1.0) * world.x, clampf(p.y / DISPLAY.y, 0.0, 1.0) * world.y)


static func world_to_map(world_point: Vector2) -> Vector2:
	var world := VC.world_rect().size
	return Vector2(world_point.x / world.x * DISPLAY.x, world_point.y / world.y * DISPLAY.y)


## The floor and column under a point of the map control, as Vector2i(column, floor).
static func cell_at(p: Vector2) -> Vector2i:
	var world := map_to_world(p)
	var col := clampi(int(world.x / VC.CELL_W), 0, COLS - 1)
	var row := clampi(int(world.y / VC.CELL_H), 0, ROWS - 1)
	return Vector2i(col, row_to_floor(row))


## The camera's view as a rectangle of the map control.
static func view_rect(cam_position: Vector2, cam_zoom: float, size_px: Vector2) -> Rect2:
	var half := size_px / (2.0 * maxf(cam_zoom, 0.01))
	var top_left := world_to_map(cam_position - half)
	var bottom_right := world_to_map(cam_position + half)
	return Rect2(top_left, bottom_right - top_left)


## The pins for a list of alerts (Alerts.list): [{"pos" (map control), "kind", "floor"}]. A burning room pins at its
## column; the other alerts know only a floor and pin at the map's right edge. An alert with no floor has no pin.
static func pins_for(alerts: Array, tower_value: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for alert: Array in alerts:
		var floor_number: int = alert[1]
		if floor_number == 0:
			continue
		var x := DISPLAY.x - PIN_RADIUS - 2.0
		if alert[0] == AlertsScript.FIRE and tower_value != null and tower_value.grid.has_occupant(alert[3]):
			var run: Array[int] = tower_value.grid.run_of(alert[3])
			x = world_to_map(Vector2((float(run[1]) + float(run[2]) * 0.5) * VC.CELL_W, 0.0)).x
		var y := world_to_map(Vector2(0.0, AlertMarkers.world_y_of(floor_number))).y
		out.append({"pos": Vector2(x, y), "kind": alert[0], "floor": floor_number})
	return out


# ---- colours ----

## The colour of a room kind with the Off filter: the room's own base colour where the renderer has one.
static func kind_colour(kind: String) -> Color:
	if RoomLook.handles(kind):
		return RoomLook.base_color(kind)
	match kind:
		"office": return Color(0.45, 0.58, 0.78)
		"condo": return Color(0.78, 0.66, 0.5)
		"lobby": return Color(0.85, 0.85, 0.8)
	return Color.from_hsv(float(kind.hash() % 360) / 360.0, 0.35, 0.7)


## How often a filter's colours are read again, in ticks (the heat overlay's own intervals; Problems is as slow as rent).
static func refresh_ticks(which: int) -> int:
	if which == PROBLEMS:
		return HeatOverlay.SLOW_REFRESH_TICKS
	if which == HeatLook.OFF:
		return NEVER
	return HeatOverlay.refresh_ticks(which)


## What a filter paints over the dimmed rooms: [{"rect" (pixels), "colour"}]. The heat modes are HeatLook's own list, so
## a cell matches the main view's overlay exactly; Problems tints each suffering room as the Disruptions view does.
static func painted(tower_value: Object, which: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if which == PROBLEMS:
		for room: Dictionary in DisruptionLook.suffering_rooms(tower_value):
			found.append({"rect": room["rect"], "colour": DisruptionLook.tint(room["points"])})
	elif which != HeatLook.OFF:
		for room: Dictionary in HeatLook.painted_rooms(tower_value, which):
			found.append({"rect": room["rect"], "colour": room["colour"]})
	return found


## Paints the whole map into `image`: every room in its kind colour (dimmed under a filter), then the filter's cells.
static func paint(image: Image, tower_value: Object, which: int) -> void:
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shade := 1.0 if which == HeatLook.OFF else DIM
	for id: int in tower_value.rooms.room_ids():
		if not tower_value.grid.has_occupant(id):
			continue
		var c := kind_colour(tower_value.rooms.kind_of(id))
		var rect := SynergyLook.rect_of(tower_value.grid.run_of(id))
		image.fill_rect(_cells(rect), Color(c.r * shade, c.g * shade, c.b * shade, 1.0))
	for cell: Dictionary in painted(tower_value, which):
		image.fill_rect(_cells(cell["rect"]), cell["colour"])


static func _cells(rect: Rect2i) -> Rect2i:
	return Rect2i(rect.position.x / VC.CELL_W, rect.position.y / VC.CELL_H, maxi(rect.size.x / VC.CELL_W, 1), maxi(rect.size.y / VC.CELL_H, 1))


# ---- the filter ----

func set_filter(which: int) -> void:
	filter = clampi(which, 0, FILTER_NAMES.size() - 1)
	_sync_buttons()


func _sync_buttons() -> void:
	for n: int in _filter_buttons.size():
		_filter_buttons[n].set_pressed_no_signal(n == filter)


## The default filter follows the main view: when a heat mode (or the Disruptions view) is switched on or changes, so
## does the map's filter; with nothing on, the player's own choice stands.
func _follow_main_view() -> void:
	if HeatLook.mode != _seen_heat:
		_seen_heat = HeatLook.mode
		if _seen_heat != HeatLook.OFF:
			set_filter(_seen_heat)
	if DisruptionLook.on != _seen_disruptions:
		_seen_disruptions = DisruptionLook.on
		if _seen_disruptions and HeatLook.mode == HeatLook.OFF:
			set_filter(PROBLEMS)


# ---- frame work ----

func _process(_delta: float) -> void:
	panel.visible = open
	if not open or tower == null:
		return
	if is_inside_tree():
		view_size = get_viewport().get_visible_rect().size
	refresh()


## Brings the map in line with the tower, filter and camera. The image is rebuilt only when the layout or filter changed
## or the filter's interval passed; the marks are redrawn only when the rectangle or a pin moved.
func refresh() -> void:
	if tower == null:
		return
	_follow_main_view()
	var tick: int = tower.tick
	var rooms_rev: int = tower.rooms.layout_revision
	var floors_rev: int = tower.floors.revision
	if filter != _built_filter or rooms_rev != _built_rooms or floors_rev != _built_floors or tick - _built_tick >= refresh_ticks(filter) or tick < _built_tick:
		_built_filter = filter
		_built_rooms = rooms_rev
		_built_floors = floors_rev
		_built_tick = tick
		paint(_image, tower, filter)
		_texture.update(_image)
		image_builds += 1
	if absi(tick - _pins_tick) >= PIN_REFRESH_TICKS:
		_pins_tick = tick
		_pins = pins_for(AlertsScript.list(tower), tower)
	var key := _marks_key()
	if key != _mark_key:
		_mark_key = key
		mark_draws += 1
		_marks.queue_redraw()


## The map's image, for tests.
func image() -> Image:
	return _image


func _camera_rect() -> Rect2:
	if camera == null:
		return Rect2()
	return view_rect(camera.position, camera.zoom.x, view_size)


func _marks_key() -> String:
	var rect := _camera_rect()
	var parts: Array[String] = ["%d,%d,%d,%d" % [roundi(rect.position.x * 4.0), roundi(rect.position.y * 4.0), roundi(rect.size.x * 4.0), roundi(rect.size.y * 4.0)]]
	for pin: Dictionary in _pins:
		parts.append("%d:%d:%d" % [pin["kind"], pin["floor"], roundi(pin["pos"].x)])
	return "|".join(parts)


func _draw_marks() -> void:
	if camera != null:
		_marks.draw_rect(_camera_rect().intersection(Rect2(Vector2.ZERO, DISPLAY)), VIEW_EDGE, false, 1.0)
	for pin: Dictionary in _pins:
		var colour: Color = AlertMarkers.KIND_COLORS.get(pin["kind"], Color.WHITE)
		_marks.draw_circle(pin["pos"], PIN_RADIUS + 1.0, PIN_EDGE)
		_marks.draw_circle(pin["pos"], PIN_RADIUS, colour)


## The alert pins now shown, for tests.
func pins() -> Array[Dictionary]:
	return _pins


# ---- input ----

func _on_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if button.pressed:
			jump_to_map_point(button.position)
		_accept()
	elif event is InputEventMouseMotion and _dragging:
		jump_to_map_point((event as InputEventMouseMotion).position)
		_accept()


func _accept() -> void:
	if map_view.is_inside_tree():
		map_view.accept_event()


## Moves the camera to the world point under a point of the map control.
func jump_to_map_point(p: Vector2) -> void:
	if camera != null and camera.has_method("jump_to"):
		camera.call("jump_to", map_to_world(p))
