extends RefCounted
## View settings kept in user://settings.cfg with the display settings, never in the tower or a save.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "view"
const KEY_AUTO_FILL := "auto_fill_floor"
const KEY_DETAILED := "graphics_detailed"

## Auto-fill floor (#273): building on a level fills the floor gap between the new item and the
## nearest floor beside it. On by default.
static var auto_fill: bool = true

## Graphics (#301): false = Classic, true = Detailed. Read through GraphicsStyle.current().
static var detailed_graphics: bool = false


## Reads the saved options; the toolbar calls it once when it starts.
static func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		auto_fill = bool(config.get_value(SECTION, KEY_AUTO_FILL, true))
		detailed_graphics = bool(config.get_value(SECTION, KEY_DETAILED, false))


static func set_auto_fill(value: bool) -> void:
	auto_fill = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	config.set_value(SECTION, KEY_AUTO_FILL, value)
	config.save(SETTINGS_PATH)


static func set_detailed_graphics(value: bool) -> void:
	detailed_graphics = value
	UiSkin.apply(value)  # the toolbar and windows take the G Lit skin with the Detailed art (#307)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SECTION, KEY_DETAILED, value)
	config.save(SETTINGS_PATH)
