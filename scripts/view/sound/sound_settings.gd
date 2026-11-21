class_name SoundSettings
extends RefCounted
## Sound options (#247), kept in user://settings.cfg with the other view settings. Volumes are 0 to 100.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "sound"
const DEFAULT_VOLUME := 70

static var muted: bool = false
static var volumes: Dictionary = {&"Ambience": DEFAULT_VOLUME, &"Events": DEFAULT_VOLUME, &"UI": DEFAULT_VOLUME}
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	muted = bool(config.get_value(SECTION, "muted", false))
	for bus: StringName in volumes.keys():
		volumes[bus] = clampi(int(config.get_value(SECTION, String(bus), DEFAULT_VOLUME)), 0, 100)


static func set_volume(bus: StringName, percent: int) -> void:
	volumes[bus] = clampi(percent, 0, 100)
	_save()
	apply()


static func set_muted(value: bool) -> void:
	muted = value
	_save()
	apply()


static func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other sections; a missing file is fine
	config.set_value(SECTION, "muted", muted)
	for bus: StringName in volumes.keys():
		config.set_value(SECTION, String(bus), volumes[bus])
	config.save(SETTINGS_PATH)


## Makes the three buses if they do not exist yet.
static func ensure_buses() -> void:
	for bus in SoundCatalog.BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")


## Pushes the volumes and the mute switch onto the buses.
static func apply() -> void:
	ensure_buses()
	for bus in SoundCatalog.BUSES:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, linear_to_db(float(volumes[bus]) / 100.0))
		AudioServer.set_bus_mute(index, muted)
