extends Node
## Autoload "DisplaySettings": window mode (windowed, full screen, borderless), window resolution and UI
## scale (#248), saved in user://settings.cfg. F11 or Alt+Enter toggles full screen. The first run starts full screen.
## The window is never letterboxed or cropped: stretch is disabled and the whole window is the
## viewport, magnified by an integer pixel scale (Window.content_scale_factor), so pixels stay
## sharp and the world view simply shows more or less area. The scale is picked automatically
## from the window size (pixel_scale 0 = Auto) or forced to 1-4. Recomputed on every resize.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "display"
const KEY_FULLSCREEN := "fullscreen"
const KEY_PIXEL_SCALE := "pixel_scale"
const KEY_MODE := "window_mode"
const KEY_RESOLUTION := "resolution"
const KEY_UI_SCALE := "ui_scale"
const WINDOWED := 0
const FULLSCREEN := 1
const BORDERLESS := 2
const MODE_NAMES: Array[String] = ["Windowed", "Full screen", "Borderless window"]
## Window sizes offered in windowed mode, besides the monitor's native size.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const UI_SCALES: Array[int] = [75, 100, 125, 150, 175, 200]  ## Percent, on top of the pixel scale.
const REF_SIZE := Vector2i(1920, 1080)  ## Window size that gets scale 1.
const MIN_SCALE := 1
const MAX_SCALE := 4
const MIN_WINDOW := Vector2i(1024, 600)

var window_mode: int = FULLSCREEN
var resolution: Vector2i = Vector2i.ZERO  ## Windowed size; ZERO = not chosen, keep the window as it is.
var ui_scale: int = 100  ## Percent: 75 to 200, multiplies the pixel scale.
var pixel_scale: int = 0  ## 0 = Auto, 1-4 = forced.
var scale_in_use: int = 1
var fullscreen: bool:  ## Read-only convenience for the F11 toggle and old callers.
	get:
		return window_mode == FULLSCREEN


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


## A window size the game accepts: not below the minimum window, not absurdly large.
static func valid_resolution(size: Vector2i) -> bool:
	return size.x >= MIN_WINDOW.x and size.y >= MIN_WINDOW.y and size.x <= 16384 and size.y <= 16384


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		read(config)
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


## Fills the settings from a ConfigFile. A missing, wrongly typed or out-of-range entry keeps its default,
## so a corrupt file never breaks the game. Old files only had "fullscreen" (a bool).
func read(config: ConfigFile) -> void:
	window_mode = FULLSCREEN
	resolution = Vector2i.ZERO
	ui_scale = 100
	pixel_scale = 0
	var mode: Variant = config.get_value(SECTION, KEY_MODE, "")
	var old_full: Variant = config.get_value(SECTION, KEY_FULLSCREEN, "")
	if mode is int and (mode as int) >= WINDOWED and (mode as int) <= BORDERLESS:
		window_mode = mode as int
	elif old_full is bool:
		window_mode = FULLSCREEN if old_full else WINDOWED
	var res: Variant = config.get_value(SECTION, KEY_RESOLUTION, "")
	if res is Vector2i and valid_resolution(res as Vector2i):
		resolution = res as Vector2i
	var ui: Variant = config.get_value(SECTION, KEY_UI_SCALE, "")
	if ui is int and (ui as int) in UI_SCALES:
		ui_scale = ui as int
	var px: Variant = config.get_value(SECTION, KEY_PIXEL_SCALE, "")
	if px is int:
		pixel_scale = clampi(px as int, 0, MAX_SCALE)


func write(config: ConfigFile) -> void:
	config.set_value(SECTION, KEY_MODE, window_mode)
	config.set_value(SECTION, KEY_FULLSCREEN, fullscreen)
	config.set_value(SECTION, KEY_RESOLUTION, resolution)
	config.set_value(SECTION, KEY_UI_SCALE, ui_scale)
	config.set_value(SECTION, KEY_PIXEL_SCALE, pixel_scale)


func save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	write(config)
	config.save(SETTINGS_PATH)


## Sets full screen (true) or windowed (false), applies it and saves it.
func set_fullscreen(value: bool) -> void:
	set_window_mode(FULLSCREEN if value else WINDOWED)


func set_window_mode(value: int) -> void:
	window_mode = clampi(value, WINDOWED, BORDERLESS)
	_apply()
	save()


## Windowed size (a listed one or the monitor's native size); anything else clears the choice.
func set_resolution(value: Vector2i) -> void:
	resolution = value if valid_resolution(value) else Vector2i.ZERO
	_apply()
	save()


func set_ui_scale(value: int) -> void:
	ui_scale = value if value in UI_SCALES else 100
	_update_scale()
	save()


## Sets the pixel scale (0 = Auto, 1-4 forced), applies it and saves it.
func set_pixel_scale(value: int) -> void:
	pixel_scale = clampi(value, 0, MAX_SCALE)
	_update_scale()
	save()


func _apply() -> void:
	var window := get_window()
	window.borderless = window_mode == BORDERLESS
	if window_mode == FULLSCREEN:
		window.mode = Window.MODE_FULLSCREEN
		_update_scale()
		return
	window.mode = Window.MODE_WINDOWED
	var screen: int = window.current_screen
	var native: Vector2i = DisplayServer.screen_get_size(screen)
	var origin: Vector2i = DisplayServer.screen_get_position(screen)
	if window_mode == BORDERLESS:
		window.size = native
		window.position = origin
	elif resolution != Vector2i.ZERO:
		window.size = resolution
		window.position = origin + (native - resolution) / 2
	_update_scale()


func _update_scale() -> void:
	var window := get_window()
	scale_in_use = resolve_scale(pixel_scale, window.size)
	window.content_scale_factor = float(scale_in_use) * float(ui_scale) / 100.0
