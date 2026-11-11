extends Node
## Autoload "DisplaySettings": windowed / full-screen setting, toggled with F11 or Alt+Enter.
## The choice is saved in user://settings.cfg. The first run starts full screen.
## Pixel scale is integer (project.godot stretch scale_mode), so pixels stay sharp.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "display"
const KEY_FULLSCREEN := "fullscreen"

var fullscreen: bool = true


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen = bool(config.get_value(SECTION, KEY_FULLSCREEN, true))
	_apply()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var is_f11: bool = key.keycode == KEY_F11
	var is_alt_enter: bool = key.alt_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
	if is_f11 or is_alt_enter:
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


## Sets full screen (true) or windowed (false), applies it and saves it.
func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	config.set_value(SECTION, KEY_FULLSCREEN, fullscreen)
	config.save(SETTINGS_PATH)


func _apply() -> void:
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
