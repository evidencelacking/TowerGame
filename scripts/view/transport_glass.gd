extends RefCounted
## The "see-through transport" view option (#367): in Detailed, elevator shafts are a tinted glass column and
## stairs and escalators are outline structures, so the rooms and people behind them show. On by default.
## Detailed only (Classic has its own outline option, TransportLook.see_through). View state only: kept in
## user://settings.cfg with the other display settings; its key is the KeyBindings action "transport_glass" (U), never in the tower or a save. A settings window can
## show it with `on` and set_on().

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "display"
const KEY := "transport_see_through"

static var on: bool = true


## Reads the saved option; the renderer calls it once when it starts (before the first draw).
static func load_setting() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		on = bool(config.get_value(SECTION, KEY, true))


## Sets the option and keeps it for the next run.
static func set_on(value: bool) -> void:
	on = value
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	config.set_value(SECTION, KEY, value)
	config.save(SETTINGS_PATH)


static func toggle() -> void:
	set_on(not on)
