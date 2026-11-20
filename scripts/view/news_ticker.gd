class_name NewsTicker
extends CanvasLayer
## The tower news strip (12.4), along the top edge under the HUD bar: the newest stories as one-line
## buttons, newest first. Click a story about a person to open their window and follow them; a story
## about a room or floor jumps the camera there (and opens the room). The News button hides the strip.
## View only: it reads the sim through NewsFeed and sends no commands.

const TowerSim := preload("res://scripts/sim/tower.gd")
const NewsFeed := preload("res://scripts/view/news_feed.gd")

const SHOWN := 3  ## Stories on the strip.
const EMPTY_TEXT := "No news yet"

var tower: TowerSim = null
var camera: TowerCamera = null
var person_window: PersonWindow = null
var room_window: RoomWindow = null
var toggle_button: Button
var story_buttons: Array[Button] = []
var _items: Array[Dictionary] = []
var _root: HBoxContainer
var _strip: HBoxContainer
var _shown_key: String = ""


func _init() -> void:
	layer = 3
	_root = HBoxContainer.new()
	_root.name = "NewsRow"
	_root.anchor_right = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	toggle_button = Button.new()
	toggle_button.name = "NewsToggle"
	toggle_button.text = "News"
	toggle_button.toggle_mode = true
	toggle_button.button_pressed = true
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.toggled.connect(set_open)
	_root.add_child(toggle_button)
	_strip = HBoxContainer.new()
	_strip.name = "NewsStrip"
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_strip)
	for n in SHOWN:
		var button := Button.new()
		button.name = "Story%d" % n
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(120, 0)
		button.pressed.connect(activate.bind(n))
		_strip.add_child(button)
		story_buttons.append(button)


func bind(tower_value: TowerSim, camera_value: TowerCamera, person_value: PersonWindow, room_value: RoomWindow) -> void:
	tower = tower_value
	camera = camera_value
	person_window = person_value
	room_window = room_value
	_refresh(true)


func is_open() -> bool:
	return _strip.visible


func set_open(on: bool) -> void:
	if toggle_button.button_pressed != on:
		toggle_button.set_pressed_no_signal(on)
	_strip.visible = on


## The items on the strip now, newest first.
func items() -> Array[Dictionary]:
	return _items


func _process(_delta: float) -> void:
	_sit_below_hud()
	_refresh(false)


## Keeps the strip just under the HUD bar (a sibling node Hud with a Bar), whatever its height.
func _sit_below_hud() -> void:
	var bar := get_node_or_null("../Hud/Bar") as Control
	_root.offset_top = bar.size.y if bar != null else 0.0


## The logs are capped, so their counts stop changing when full: the key also holds the newest ticks.
func _key() -> String:
	var life_n: int = tower.life.story_count()
	var msg_n: int = tower.messages.count()
	var life_tick: int = tower.life.story(life_n - 1)[0] if life_n > 0 else -1
	var msg_tick: int = tower.messages.entry(msg_n - 1)[0] if msg_n > 0 else -1
	return "%d:%d:%d:%d" % [life_n, msg_n, life_tick, msg_tick]


func _refresh(force: bool) -> void:
	if tower == null:
		return
	var key := _key()
	if not force and key == _shown_key:
		return
	_shown_key = key
	_items = NewsFeed.latest(tower, SHOWN)
	for n in SHOWN:
		var button := story_buttons[n]
		if n < _items.size():
			button.text = _items[n]["text"]
			button.tooltip_text = _items[n]["text"]
			button.disabled = false
			button.visible = true
		else:
			button.text = EMPTY_TEXT if n == 0 else ""
			button.tooltip_text = ""
			button.disabled = true
			button.visible = n == 0


## Clicks story n: a person's story opens their window and follows them; any other story jumps the
## camera to its room or floor. Returns true when it went somewhere.
func activate(n: int) -> bool:
	if tower == null or n < 0 or n >= _items.size():
		return false
	var item := _items[n]
	for id: int in item["people"]:
		if tower.people.index_of(id) != -1 and person_window != null:
			person_window.open_person(id)
			person_window.set_following(true)
			return true
	var at := NewsFeed.place_of(tower, item)
	if at == Vector2.INF or camera == null:
		return false
	if at.x < 0.0:
		at.x = camera.position.x
	camera.jump_to(at)
	if room_window != null and item["room"] >= 0 and tower.rooms.kind_of(item["room"]) != "":
		room_window.show_room(item["room"], true)
	return true
