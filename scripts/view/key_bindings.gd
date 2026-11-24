class_name KeyBindings
extends RefCounted
## Rebindable keys (#248). One table of the game's main actions with their default keys; the Settings
## window edits it and it is saved in user://settings.cfg, section "keys". Handlers ask is_key(event, id)
## instead of comparing a fixed keycode. Keys the game reserves (Esc, F10, F11, Enter) cannot be bound.
## View only: the sim never sees a key.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "keys"
const RESERVED: Array[int] = [KEY_ESCAPE, KEY_F10, KEY_F11, KEY_ENTER, KEY_KP_ENTER, KEY_NONE]

## [id, label, default keycode], in the order the window lists them.
const ACTIONS: Array = [
	["pause", "Pause / resume", KEY_SPACE],
	["speed_1", "Speed 1", KEY_1],
	["speed_2", "Speed 2", KEY_2],
	["speed_3", "Speed 3", KEY_3],
	["tool_lobby", "Tool: lobby", KEY_L],
	["tool_floor", "Tool: floor", KEY_F],
	["tool_stairs", "Tool: stairs", KEY_S],
	["tool_escalator", "Tool: escalator", KEY_X],
	["tool_office", "Tool: office", KEY_O],
	["tool_condo", "Tool: condo", KEY_C],
	["tool_shaft", "Tool: local elevator shaft", KEY_E],
	["tool_car", "Tool: local elevator car", KEY_A],
	["tool_bulldoze", "Tool: bulldoze", KEY_B],
	["tool_replace", "Tool: replace", KEY_R],
	["cam_left", "Camera left", KEY_A],
	["cam_right", "Camera right", KEY_D],
	["cam_up", "Camera up", KEY_W],
	["cam_down", "Camera down", KEY_S],
	["see_through", "Elevators see-through", KEY_V],
	["transport_glass", "Transport see-through (Detailed)", KEY_U],
	["synergies", "Synergy overlay", KEY_Y],
	["heat", "Heat map overlay", KEY_H],
	["bulk_rent", "Bulk rent", KEY_K],
	["messages", "Message log", KEY_M],
	["finance", "Finance window", KEY_T],
	["stars", "Star window", KEY_G],
	["mute", "Sound on / off", KEY_N],
]

## action id -> keycode, every action always present.
static var bindings: Dictionary = {}
static var _loaded: bool = false


static func default_key(id: String) -> int:
	for row: Array in ACTIONS:
		if row[0] == id:
			return row[2] as int
	return KEY_NONE


static func label_of(id: String) -> String:
	for row: Array in ACTIONS:
		if row[0] == id:
			return row[1] as String
	return id


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		reset_all()
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK:
			read(config)


static func keycode(id: String) -> int:
	_ensure()
	return bindings.get(id, default_key(id)) as int


static func key_name(id: String) -> String:
	return OS.get_keycode_string(keycode(id) as Key)


## True when the event's key is the one bound to the action (modifiers are the caller's concern).
static func is_key(key: InputEventKey, id: String) -> bool:
	return key.keycode == keycode(id)


## Binds an action to a key and saves. Returns false for a reserved or unknown key and changes nothing.
static func set_binding(id: String, code: int) -> bool:
	_ensure()
	if default_key(id) == KEY_NONE or code in RESERVED:
		return false
	bindings[id] = code
	save()
	return true


static func reset_all() -> void:
	bindings = {}
	for row: Array in ACTIONS:
		bindings[row[0]] = row[2]


## Back to the default keys, saved.
static func reset_and_save() -> void:
	_loaded = true
	reset_all()
	save()


## Other actions on the same key, as labels: shown as a note, never blocked (A and S are shared between
## a tool and the camera by default).
static func shared_with(id: String) -> Array[String]:
	var out: Array[String] = []
	var mine: int = keycode(id)
	for row: Array in ACTIONS:
		if row[0] != id and keycode(row[0] as String) == mine:
			out.append(row[1] as String)
	return out


## Fills the bindings from a ConfigFile; a missing, wrongly typed, reserved or unknown entry keeps the default.
static func read(config: ConfigFile) -> void:
	_loaded = true
	reset_all()
	for row: Array in ACTIONS:
		var id: String = row[0] as String
		var value: Variant = config.get_value(SECTION, id, "")
		if value is int and (value as int) > 0 and not ((value as int) in RESERVED):
			bindings[id] = value as int


static func write(config: ConfigFile) -> void:
	for row: Array in ACTIONS:
		config.set_value(SECTION, row[0] as String, bindings.get(row[0], row[2]))


static func save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	write(config)
	config.save(SETTINGS_PATH)
