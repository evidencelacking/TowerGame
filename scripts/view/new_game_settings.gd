class_name NewGameSettings
extends RefCounted
## New-game options (#248): the starting funds. Chosen in the Settings window, saved in user://settings.cfg
## (section "game") and read once when a new tower is built, which hands the number to Tower.new(). The sim
## never reads this file. The default is the sim's own starting funds; the other presets are our own.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"
const KEY_FUNDS := "starting_funds"
const DEFAULT_FUNDS: int = 2000000  ## Ledger.DEFAULT_STARTING_FUNDS (a test checks they match).

## [label, dollars]. Only the first is the sim's own default; the others are labelled as ours.
const PRESETS: Array = [
	["Default", 2000000],
	["Generous (our own option)", 5000000],
	["Sandbox (our own option)", 100000000],
]

static var funds_setting: int = DEFAULT_FUNDS
## The funds the tower now running was built with; the start menu rebuilds when the setting moved.
static var applied: int = DEFAULT_FUNDS
static var _loaded: bool = false


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		var config := ConfigFile.new()
		if config.load(SETTINGS_PATH) == OK:
			read(config)


static func funds() -> int:
	_ensure()
	return funds_setting


static func preset_index() -> int:
	for i in PRESETS.size():
		if (PRESETS[i] as Array)[1] == funds():
			return i
	return 0


static func set_preset(index: int) -> void:
	_ensure()
	funds_setting = (PRESETS[clampi(index, 0, PRESETS.size() - 1)] as Array)[1] as int
	save()


## Only a preset value is accepted; anything else (wrong type, edited file) is the default.
static func read(config: ConfigFile) -> void:
	_loaded = true
	funds_setting = DEFAULT_FUNDS
	var value: Variant = config.get_value(SECTION, KEY_FUNDS, "")
	if value is int:
		for preset: Array in PRESETS:
			if preset[1] == value:
				funds_setting = value as int


static func write(config: ConfigFile) -> void:
	config.set_value(SECTION, KEY_FUNDS, funds_setting)


static func save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	write(config)
	config.save(SETTINGS_PATH)
