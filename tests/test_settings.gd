extends RefCounted
## The Settings window's data (#248), headless: save and reload give the same values, bad files fall back
## to defaults, and the starting funds reach a new tower as a constructor argument.

const DS := preload("res://scripts/view/display_settings.gd")
const SoundSettingsScript := preload("res://scripts/view/sound/sound_settings.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const TowerScript := preload("res://scripts/sim/tower.gd")
const TEST_PATH := "user://test_settings_248.cfg"


## Writes every setting into one ConfigFile, saves it to a file and loads it back.
static func _roundtrip(display: Node) -> ConfigFile:
	var config := ConfigFile.new()
	display.write(config)
	KeyBindings.write(config)
	SoundSettingsScript.write(config)
	NewGameSettings.write(config)
	config.save(TEST_PATH)
	var back := ConfigFile.new()
	back.load(TEST_PATH)
	return back


## Writes text to a file and loads it as a config; null when it does not parse. Never feed it invalid
## config syntax: the engine logs an ERROR line, which fails the test run. (Never feed it text that
## is not valid config syntax: the engine logs an ERROR line, which fails the test run.)
static func _write_text(text: String) -> ConfigFile:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var config := ConfigFile.new()
	var err: int = config.load(TEST_PATH)
	return config if err == OK else null


## The tower's money: the ledger's lines sum to the balance.
static func _balance(t: TowerScript) -> int:
	return t.ledger.line_sum()


static func run(check: Callable) -> void:
	# Start from known state that never reads or writes the real settings file of this machine.
	KeyBindings.read(ConfigFile.new())
	NewGameSettings.read(ConfigFile.new())
	var saved_master: int = SoundSettingsScript.master
	var saved_volumes: Dictionary = SoundSettingsScript.volumes.duplicate()
	var saved_muted: bool = SoundSettingsScript.muted

	var display: Node = DS.new()
	check.call(display.window_mode == DS.FULLSCREEN and display.ui_scale == 100 and display.resolution == Vector2i.ZERO, "display defaults")
	check.call(NewGameSettings.DEFAULT_FUNDS == LedgerScript.DEFAULT_STARTING_FUNDS, "new-game default funds are the sim's default")

	# Save and reload: everything comes back the same.
	display.window_mode = DS.BORDERLESS
	display.resolution = Vector2i(1600, 900)
	display.ui_scale = 150
	display.pixel_scale = 2
	KeyBindings.bindings["pause"] = KEY_P
	KeyBindings.bindings["tool_office"] = KEY_Q
	SoundSettingsScript.muted = true
	SoundSettingsScript.master = 40
	SoundSettingsScript.volumes[&"Events"] = 25
	NewGameSettings.funds_setting = 5000000
	var back := _roundtrip(display)
	var reloaded: Node = DS.new()
	reloaded.read(back)
	KeyBindings.reset_all()
	SoundSettingsScript.muted = false
	SoundSettingsScript.master = 100
	SoundSettingsScript.volumes[&"Events"] = 70
	NewGameSettings.funds_setting = NewGameSettings.DEFAULT_FUNDS
	KeyBindings.read(back)
	SoundSettingsScript.read(back)
	NewGameSettings.read(back)
	check.call(reloaded.window_mode == DS.BORDERLESS and reloaded.resolution == Vector2i(1600, 900), "display mode and resolution survive a reload")
	check.call(reloaded.ui_scale == 150 and reloaded.pixel_scale == 2, "UI scale and pixel scale survive a reload")
	check.call(KeyBindings.bindings["pause"] == KEY_P and KeyBindings.bindings["tool_office"] == KEY_Q, "rebound keys survive a reload")
	check.call(KeyBindings.bindings["speed_1"] == KEY_1, "untouched keys keep their default after a reload")
	check.call(SoundSettingsScript.muted and SoundSettingsScript.master == 40 and SoundSettingsScript.volumes[&"Events"] == 25, "sound settings survive a reload")
	check.call(NewGameSettings.funds_setting == 5000000, "starting funds survive a reload")
	display.free()
	reloaded.free()

	# Old files only had the fullscreen bool.
	var old := ConfigFile.new()
	old.set_value("display", "fullscreen", false)
	var legacy: Node = DS.new()
	legacy.read(old)
	check.call(legacy.window_mode == DS.WINDOWED, "an old file with fullscreen=false means windowed")
	legacy.free()

	# Bad files: defaults, never an error.
	check.call(ConfigFile.new().load("user://no_such_settings_248.cfg") != OK, "a missing file fails to load, so the loaders keep defaults")
	var empty := _write_text("")
	check.call(empty != null and not empty.has_section("keys"), "an empty file loads with nothing in it")
	var missing: ConfigFile = empty if empty != null else ConfigFile.new()
	var fallback: Node = DS.new()
	fallback.read(missing)
	KeyBindings.read(missing)
	SoundSettingsScript.read(missing)
	NewGameSettings.read(missing)
	check.call(fallback.window_mode == DS.FULLSCREEN and fallback.ui_scale == 100 and fallback.resolution == Vector2i.ZERO, "a missing file gives display defaults")
	check.call(KeyBindings.bindings["pause"] == KEY_SPACE and SoundSettingsScript.master == 100 and not SoundSettingsScript.muted, "a missing file gives key and sound defaults")
	check.call(NewGameSettings.funds_setting == NewGameSettings.DEFAULT_FUNDS, "a missing file gives the default funds")
	var wrong := ConfigFile.new()
	wrong.set_value("display", "window_mode", "banana")
	wrong.set_value("display", "ui_scale", 9999)
	wrong.set_value("display", "resolution", Vector2i(5, 5))
	wrong.set_value("keys", "pause", "nope")
	wrong.set_value("keys", "speed_1", KEY_ESCAPE)
	wrong.set_value("sound", "master", "loud")
	wrong.set_value("sound", "UI", 500)
	wrong.set_value("game", "starting_funds", 7)
	fallback.read(wrong)
	KeyBindings.read(wrong)
	SoundSettingsScript.read(wrong)
	NewGameSettings.read(wrong)
	check.call(fallback.window_mode == DS.FULLSCREEN and fallback.ui_scale == 100 and fallback.resolution == Vector2i.ZERO, "wrong types and ranges give display defaults")
	check.call(KeyBindings.bindings["pause"] == KEY_SPACE and KeyBindings.bindings["speed_1"] == KEY_1, "a wrong or reserved key falls back to the default")
	check.call(SoundSettingsScript.master == 100 and SoundSettingsScript.volumes[&"UI"] == 100, "a wrong master falls back; a loud volume clamps to 100")
	check.call(NewGameSettings.funds_setting == NewGameSettings.DEFAULT_FUNDS, "funds that are no preset fall back to the default")
	fallback.free()

	# Keys: reserved keys are refused (nothing is saved), and shared keys are reported.
	KeyBindings.reset_all()
	check.call(not KeyBindings.set_binding("pause", KEY_ESCAPE) and KeyBindings.keycode("pause") == KEY_SPACE, "Esc cannot be bound")
	check.call(KeyBindings.shared_with("tool_stairs").has("Camera down"), "the shared S key is reported")

	# Starting funds reach a new tower as a constructor argument; the default stays the default.
	for preset: Array in NewGameSettings.PRESETS:
		NewGameSettings.funds_setting = preset[1] as int
		var tower := TowerScript.new(0, NewGameSettings.funds())
		check.call(_balance(tower) == preset[1], "a new tower starts with the %s funds" % preset[0])
	check.call(_balance(TowerScript.new()) == NewGameSettings.DEFAULT_FUNDS, "a tower built without the setting has the default funds")

	DirAccess.remove_absolute(TEST_PATH)
	NewGameSettings.funds_setting = NewGameSettings.DEFAULT_FUNDS
	KeyBindings.reset_all()
	SoundSettingsScript.master = saved_master
	SoundSettingsScript.volumes = saved_volumes
	SoundSettingsScript.muted = saved_muted
