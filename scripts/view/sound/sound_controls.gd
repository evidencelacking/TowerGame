class_name SoundControls
extends HBoxContainer
## The sound options row (#247): a mute switch (also the N key) and a volume slider per bus.
## It only edits SoundSettings, so it never touches the tower.

const SettingsScript := preload("res://scripts/view/sound/sound_settings.gd")
const CatalogScript := preload("res://scripts/view/sound/sound_catalog.gd")

var _mute: CheckButton


## Called by the Settings window when it closes: show the key now bound.
func refresh_key_labels() -> void:
	_mute.text = "Sound (%s)" % KeyBindings.key_name("mute")


func _ready() -> void:
	name = "SoundControls"
	add_to_group("key_labels")
	SettingsScript.load_settings()
	_mute = CheckButton.new()
	_mute.name = "SoundOn"
	_mute.text = "Sound (%s)" % KeyBindings.key_name("mute")
	_mute.tooltip_text = "Switch all game sound on or off. View option."
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.button_pressed = not SettingsScript.muted
	_mute.toggled.connect(func(on: bool) -> void: SettingsScript.set_muted(not on))
	add_child(_mute)
	for bus in CatalogScript.BUSES:
		var label := Label.new()
		label.text = String(bus)
		add_child(label)
		var slider := HSlider.new()
		slider.name = String(bus) + "Volume"
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(70, 0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		slider.tooltip_text = "%s volume. View option." % String(bus)
		slider.value = float(SettingsScript.volumes[bus])
		slider.value_changed.connect(func(value: float) -> void: SettingsScript.set_volume(bus, int(value)))
		add_child(slider)


## Keeps the switch in step when the N key changes the mute.
func _process(_delta: float) -> void:
	if _mute != null and _mute.button_pressed == SettingsScript.muted:
		_mute.set_pressed_no_signal(not SettingsScript.muted)
