extends Node
## Autoload "DisplaySettings": windowed / full-screen setting, toggled with F11 or Alt+Enter.
## The choice is saved in user://settings.cfg. The first run starts full screen.
## The window is never letterboxed or cropped: stretch is disabled and the whole window is the
## viewport, magnified by an integer pixel scale (Window.content_scale_factor), so pixels stay
## sharp and the world view simply shows more or less area. The scale is picked automatically
## from the window size (pixel_scale 0 = Auto) or forced to 1-4. Recomputed on every resize.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "display"
const KEY_FULLSCREEN := "fullscreen"
const KEY_PIXEL_SCALE := "pixel_scale"
const REF_SIZE := Vector2i(1920, 1080)  ## Window size that gets scale 1.
const MIN_SCALE := 1
const MAX_SCALE := 4
const MIN_WINDOW := Vector2i(1024, 600)

var fullscreen: bool = true
var pixel_scale: int = 0  ## 0 = Auto, 1-4 = forced.
var scale_in_use: int = 1


## Integer scale for a window size: 1080p and 1440p give 1, 4K gives 2. Never below 1.
## The size relative to 1920x1080 is rounded with a 0.6 threshold so 1440p stays at 1.
static func auto_scale(size: Vector2i) -> int:
	var ratio_milli: int = mini(size.x * 1000 / REF_SIZE.x, size.y * 1000 / REF_SIZE.y)
	return clampi((ratio_milli + 400) / 1000, MIN_SCALE, MAX_SCALE)


## The scale to use: the forced one (clamped to 1-4) or, for 0, the automatic one.
static func resolve_scale(setting: int, size: Vector2i) -> int:
	if setting <= 0:
		return auto_scale(size)
	return clampi(setting, MIN_SCALE, MAX_SCALE)


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen = bool(config.get_value(SECTION, KEY_FULLSCREEN, true))
		pixel_scale = clampi(int(config.get_value(SECTION, KEY_PIXEL_SCALE, 0)), 0, MAX_SCALE)
	var window := get_window()
	window.min_size = MIN_WINDOW
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.size_changed.connect(_update_scale)
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


## Sets the pixel scale (0 = Auto, 1-4 forced), applies it and saves it.
func set_pixel_scale(value: int) -> void:
	pixel_scale = clampi(value, 0, MAX_SCALE)
	_update_scale()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SECTION, KEY_PIXEL_SCALE, pixel_scale)
	config.save(SETTINGS_PATH)


func _apply() -> void:
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
	_update_scale()


func _update_scale() -> void:
	var window := get_window()
	scale_in_use = resolve_scale(pixel_scale, window.size)
	window.content_scale_factor = float(scale_in_use)
