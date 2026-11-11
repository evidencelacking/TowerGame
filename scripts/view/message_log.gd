class_name MessageLog
extends CanvasLayer
## The message line (latest message) and the scrollable message log, bottom left. Click the line
## or press M to open the log; mouse wheel, PageUp/PageDown or the scroll bar move through it.
## View only: it reads Tower.messages, words each code in our own text and stamps each entry with
## the game clock as the HUD shows it. Wording for refusals is shared with the placement ghost.

const Ghost := preload("res://scripts/view/placement_ghost.gd")
const HudScript := preload("res://scripts/view/hud.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const ROWS: int = 12  ## Entries shown at once when the log is open.
const EMPTY_TEXT := "No messages yet"

var tower: TowerSim = null
var first_row: int = 0  ## Index of the first entry shown when open.
var _follow: bool = true  ## Stay on the newest entries until the player scrolls up.
var _line: Button
var _panel: PanelContainer
var _text: Label
var _bar: VScrollBar
var _root: VBoxContainer
var _shown_count: int = -1
var _shown_tick: int = -1


func _ready() -> void:
	layer = 4
	var root := VBoxContainer.new()
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.anchor_right = 0.5
	root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = root
	add_child(root)
	_panel = PanelContainer.new()
	var row := HBoxContainer.new()
	_text = Label.new()
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar = VScrollBar.new()
	_bar.value_changed.connect(_on_bar_changed)
	row.add_child(_text)
	row.add_child(_bar)
	_panel.add_child(row)
	_panel.visible = false
	root.add_child(_panel)
	_line = Button.new()
	_line.name = "MessageLine"
	_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_line.focus_mode = Control.FOCUS_NONE
	_line.pressed.connect(toggle)
	root.add_child(_line)
	_refresh(true)


func set_tower(value: TowerSim) -> void:
	tower = value
	_follow = true
	_refresh(true)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	_refresh(true)


func _process(_delta: float) -> void:
	_sit_above_toolbar()
	_refresh()


## Keeps the line and log just above the toolbar bar (a sibling node named Toolbar), whatever its height.
func _sit_above_toolbar() -> void:
	var bar := get_node_or_null("../Toolbar/Bar") as Control
	_root.offset_bottom = -bar.size.y if bar != null else 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_M: toggle()
		KEY_PAGEUP: if is_open(): scroll_by(-ROWS)
		KEY_PAGEDOWN: if is_open(): scroll_by(ROWS)


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or not is_open():
		return
	if not _panel.get_global_rect().has_point(button.position):
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_by(-3)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_by(3)


## Moves the window by delta entries, clamped. Reaching the end resumes following new messages.
func scroll_by(delta: int) -> void:
	var last := _max_offset()
	first_row = clampi(first_row + delta, 0, last)
	_follow = first_row >= last
	_refresh(true)


func _max_offset() -> int:
	return maxi(_count() - ROWS, 0)


func _count() -> int:
	return 0 if tower == null else tower.messages.count()


## "Y1 Q1 WD1  05:00": the game clock when the entry was logged, in the HUD's format. Commands
## apply after the tick counter increments and before the clock advances, so it is one tick back.
static func stamp(at_tick: int) -> String:
	var clock := Clock.new()
	clock.set_to_tick(at_tick - 1)
	return "Y%d Q%d %s  %02d:%02d" % [
		clock.year(), clock.quarter(), HudScript.DAY_NAMES[clock.day_of_week()], clock.hour(), clock.minute()]


static func _kind_name(kind_index: int) -> String:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return "room"
	return CatalogueScript.IDS[kind_index]


static func _floor_name(floor_number: int) -> String:
	return "B%d" % -floor_number if floor_number < 0 else str(floor_number)


## Our own wording for a message code and its integer args.
static func describe(code: int, a: int, b: int) -> String:
	match code:
		Msg.PURCHASE_REFUSED, Msg.FLOOR_REFUSED, Msg.LOBBY_REFUSED:
			return "Refused: " + Ghost.reason_text("floors", a)
		Msg.ROOM_REFUSED, Msg.REPLACE_REFUSED, Msg.STAIRS_REFUSED:
			return "Refused: " + _rooms_reason(a)
		Msg.BULLDOZE_REFUSED:
			return "Refused: " + Ghost.reason_text("bulldoze", a)
		Msg.FLOOR_BUILT: return "Floor built on %s" % _floor_name(a)
		Msg.LOBBY_BUILT: return "Lobby built, %d floor%s tall" % [a, "" if a == 1 else "s"]
		Msg.ROOM_BUILT: return "Built %s on floor %s" % [_kind_name(a), _floor_name(b)]
		Msg.STAIRS_BUILT: return "Stairs built from floor %s" % _floor_name(a)
		Msg.ROOM_REMOVED: return "Bulldozed %s on floor %s" % [_kind_name(a), _floor_name(b)]
		Msg.ROOM_REPLACED: return "Replaced with %s on floor %s" % [_kind_name(a), _floor_name(b)]
		Msg.CONDO_REFUND: return "Condo sale paid back $%d" % a
	return "Something happened"


## Room placement and replace can also pass on bulldoze refusals; use the table that knows the code.
static func _rooms_reason(code: int) -> String:
	if Ghost.ROOM_TEXT.has(code) or not Ghost.BULLDOZE_TEXT.has(code):
		return Ghost.reason_text("rooms", code)
	return Ghost.reason_text("bulldoze", code)


## Entry i (0 is the oldest) as one line, e.g. "Y1 Q1 WD1  05:00  Built office on floor 2".
func line_for(i: int) -> String:
	var e := tower.messages.entry(i)
	return "%s  %s" % [stamp(e[0]), describe(e[1], e[2], e[3])]


## Every entry as a line, oldest first. Nothing is shortened.
func all_lines() -> Array[String]:
	var lines: Array[String] = []
	for i in _count():
		lines.append(line_for(i))
	return lines


## The lines the open log shows now: the window of ROWS entries starting at first_row.
func visible_lines() -> Array[String]:
	var lines: Array[String] = []
	for i in range(first_row, mini(first_row + ROWS, _count())):
		lines.append(line_for(i))
	return lines


func _refresh(force: bool = false) -> void:
	if _line == null:
		return
	var count := _count()
	var newest := 0
	if count > 0:
		newest = tower.messages.entry(count - 1)[0]
	if not force and count == _shown_count and newest == _shown_tick:
		return
	_shown_count = count
	_shown_tick = newest
	_line.text = EMPTY_TEXT if count == 0 else line_for(count - 1)
	if _follow:
		first_row = _max_offset()
	first_row = clampi(first_row, 0, _max_offset())
	_text.text = "\n".join(visible_lines()) if count > 0 else EMPTY_TEXT
	_bar.max_value = count
	_bar.page = mini(ROWS, count)
	_bar.set_value_no_signal(first_row)
	_bar.visible = count > ROWS


func _on_bar_changed(value: float) -> void:
	scroll_by(roundi(value) - first_row)
