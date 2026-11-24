class_name CheatSettings
extends RefCounted
## The Cheats setting (#39): off by default, saved in user://settings.cfg (section "game", key "cheats") like the other
## settings. While it is off the Cheats panel cannot open and no cheat command is sent. View only: the sim never reads it.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const KEY := "cheats"

static var enabled: bool = false
static var _loaded: bool = false


## Reads the saved option once.
static func load_settings() -> void:
	_loaded = true
	var config := ConfigFile.new()
	enabled = config.load(SETTINGS_PATH) == OK and config.get_value(SECTION, KEY, false) == true


static func is_enabled() -> bool:
	if not _loaded:
		load_settings()
	return enabled


## Sets and saves the option. Turning it off closes the Cheats panel.
static func set_enabled(value: bool) -> void:
	_loaded = true
	enabled = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	config.set_value(SECTION, KEY, value)
	config.save(SETTINGS_PATH)
	if not value:
		(Engine.get_main_loop() as SceneTree).call_group("cheats_panel", "close")
