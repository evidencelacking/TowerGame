class_name SettingsWindow
extends CanvasLayer
## The Settings window (#248): Display, Sound, Keys and New game tabs. Opened from the toolbar or the start
## menu through the "settings_window" group (toggle), or with F10; Esc closes it. Every control saves at once
## into user://settings.cfg through the settings classes. Starting funds only apply to the next new game.
## View only.

const SoundSettingsScript := preload("res://scripts/view/sound/sound_settings.gd")
const HudScript := preload("res://scripts/view/hud.gd")
const NATIVE_ID: int = 0  ## Item 0 of the resolution list is the monitor's native size.

var panel: PanelContainer
var _tabs: TabContainer
var _keys_list: VBoxContainer
var _key_buttons: Dictionary = {}  ## action id -> Button
var _key_status: Label
var _capturing: String = ""  ## Action waiting for a key press; empty when not rebinding.
var _funds_note: Label
var _running_note: Label
var tower: Tower = null  ## The running tower, set by main; only read, to show its difficulty (#380).
var _display: Node = null


func _init() -> void:
	layer = 30
	name = "SettingsWindow"


func _ready() -> void:
	add_to_group("settings_window")
	_display = get_tree().root.get_node_or_null("DisplaySettings")
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 460)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_build_display()
	_build_sound()
	_build_keys()
	_build_game()
	var close := Button.new()
	close.name = "Close"
	close.text = "Close (Esc)"
	close.pressed.connect(close_window)
	column.add_child(close)
	var quit := Button.new()
	quit.name = "Quit"
	quit.text = "Quit game"
	quit.pressed.connect(func() -> void: get_tree().call_group("quit_confirm", "open"))
	column.add_child(quit)


func is_open() -> bool:
	return panel != null and panel.visible


func toggle() -> void:
	if is_open():
		close_window()
	else:
		open()


func open() -> void:
	panel.visible = true
	_running_note.text = _running_text()


func close_window() -> void:
	_stop_capture()
	panel.visible = false
	get_tree().call_group("key_labels", "refresh_key_labels")


## F10 opens or closes; Esc closes (and cancels a key capture first).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _capturing != "":
		_finish_capture(key)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F10:
		toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_open():
		close_window()
		get_viewport().set_input_as_handled()


func _tab(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	_tabs.add_child(box)
	return box


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	parent.add_child(row)
	return row


# --- Display ---

func _build_display() -> void:
	var box := _tab("Display")
	if _display == null:  # a tool run without the autoload
		var note := Label.new()
		note.text = "Display settings need the running game."
		box.add_child(note)
		return
	var mode := OptionButton.new()
	mode.name = "WindowMode"
	for i in _display.MODE_NAMES.size():
		mode.add_item(_display.MODE_NAMES[i], i)
	mode.selected = _display.window_mode
	mode.item_selected.connect(func(index: int) -> void: _display.set_window_mode(index))
	_row(box, "Window mode").add_child(mode)
	var res := OptionButton.new()
	res.name = "Resolution"
	res.tooltip_text = "Window size in Windowed mode. Full screen and Borderless use the whole monitor."
	var native: Vector2i = DisplayServer.screen_get_size(get_window().current_screen)
	res.add_item("Native (%d x %d)" % [native.x, native.y], NATIVE_ID)
	res.set_item_metadata(0, native)
	for i in _display.RESOLUTIONS.size():
		var size: Vector2i = _display.RESOLUTIONS[i]
		res.add_item("%d x %d" % [size.x, size.y], i + 1)
		res.set_item_metadata(i + 1, size)
	res.selected = _resolution_index(res)
	res.item_selected.connect(func(index: int) -> void: _display.set_resolution(res.get_item_metadata(index) as Vector2i))
	_row(box, "Resolution (windowed)").add_child(res)
	var ui := OptionButton.new()
	ui.name = "UiScale"
	ui.tooltip_text = "Makes the whole interface and the view bigger or smaller, on top of the automatic pixel scale."
	for i in _display.UI_SCALES.size():
		ui.add_item("%d%%" % _display.UI_SCALES[i], i)
	ui.selected = _display.UI_SCALES.find(_display.ui_scale)
	ui.item_selected.connect(func(index: int) -> void: _display.set_ui_scale(_display.UI_SCALES[index] as int))
	_row(box, "UI scale").add_child(ui)


func _resolution_index(res: OptionButton) -> int:
	for i in res.item_count:
		if (res.get_item_metadata(i) as Vector2i) == _display.resolution:
			return i
	return 0


# --- Sound ---

func _build_sound() -> void:
	var box := _tab("Sound")
	SoundSettingsScript.load_settings()
	var mute := CheckButton.new()
	mute.name = "SoundOn"
	mute.text = "Sound on"
	mute.button_pressed = not SoundSettingsScript.muted
	mute.toggled.connect(func(on: bool) -> void: SoundSettingsScript.set_muted(not on))
	box.add_child(mute)
	_slider(box, "MasterVolume", "Master volume", SoundSettingsScript.master,
		func(v: int) -> void: SoundSettingsScript.set_master(v))
	var names: Dictionary = {&"Events": "Effects volume", &"Ambience": "Ambience volume", &"UI": "Interface volume"}
	for bus: StringName in [&"Events", &"Ambience", &"UI"]:
		_slider(box, String(bus) + "Volume", names[bus] as String, SoundSettingsScript.volumes[bus] as int,
			func(v: int) -> void: SoundSettingsScript.set_volume(bus, v))


func _slider(box: Control, node_name: String, text: String, value: int, on_change: Callable) -> void:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = float(value)
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value_changed.connect(func(v: float) -> void: on_change.call(int(v)))
	_row(box, text).add_child(slider)


# --- Keys ---

func _build_keys() -> void:
	var box := _tab("Keys")
	var hint := Label.new()
	hint.text = "Click a key, then press the new one. Esc cancels; Esc, F10, F11 and Enter are reserved."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	box.add_child(scroll)
	_keys_list = VBoxContainer.new()
	_keys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_keys_list)
	_key_status = Label.new()
	_key_status.name = "KeyStatus"
	for row: Array in KeyBindings.ACTIONS:
		var id: String = row[0] as String
		var line := _row(_keys_list, row[1] as String)
		var button := Button.new()
		button.name = "Key_" + id
		button.custom_minimum_size = Vector2(150, 0)
		button.pressed.connect(_begin_capture.bind(id))
		line.add_child(button)
		_key_buttons[id] = button
	box.add_child(_key_status)
	var reset := Button.new()
	reset.name = "ResetKeys"
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(reset_keys)
	box.add_child(reset)
	_refresh_keys()


func _refresh_keys() -> void:
	for id: String in _key_buttons:
		var button: Button = _key_buttons[id]
		button.text = "Press a key..." if id == _capturing else KeyBindings.key_name(id)


func _begin_capture(id: String) -> void:
	_capturing = id
	_key_status.text = "Press the new key for: %s" % KeyBindings.label_of(id)
	_refresh_keys()


func _stop_capture() -> void:
	_capturing = ""
	if _key_status != null:
		_key_status.text = ""
		_refresh_keys()


## Applies the key the player pressed to the action being rebound. Esc cancels.
func _finish_capture(key: InputEventKey) -> void:
	var id: String = _capturing
	if key.keycode == KEY_ESCAPE:
		_stop_capture()
		return
	if not KeyBindings.set_binding(id, key.keycode):
		_key_status.text = "%s cannot be used. Press another key, or Esc to cancel." % OS.get_keycode_string(key.keycode)
		return
	_capturing = ""
	var shared: Array[String] = KeyBindings.shared_with(id)
	_key_status.text = "" if shared.is_empty() else "Also used by: %s" % ", ".join(shared)
	_refresh_keys()


func reset_keys() -> void:
	KeyBindings.reset_and_save()
	_stop_capture()


# --- New game ---

func _build_game() -> void:
	var box := _tab("Game")
	var info := Label.new()
	info.text = "Starting funds apply when you start a new game; they never change a tower already running."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	_funds_note = Label.new()
	_funds_note.text = _funds_text()
	_funds_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var funds := OptionButton.new()
	funds.name = "StartingFunds"
	for i in NewGameSettings.PRESETS.size():
		var preset: Array = NewGameSettings.PRESETS[i]
		funds.add_item("%s: %s" % [preset[0], HudScript.format_money(preset[1] as int)], i)
	funds.selected = NewGameSettings.preset_index()
	funds.item_selected.connect(func(index: int) -> void:
		NewGameSettings.set_preset(index)
		_funds_note.text = _funds_text())
	_row(box, "Starting funds").add_child(funds)
	box.add_child(_funds_note)
	var difficulty := OptionButton.new()
	difficulty.name = "Difficulty"
	for i in Difficulty.NAMES.size():
		difficulty.add_item(Difficulty.NAMES[i], i)
	difficulty.selected = NewGameSettings.difficulty()
	difficulty.item_selected.connect(func(index: int) -> void: NewGameSettings.set_difficulty(index))
	_row(box, "Difficulty (new game)").add_child(difficulty)
	_running_note = Label.new()
	_running_note.name = "RunningDifficulty"
	_running_note.text = _running_text()
	_running_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_running_note)
	var cheats := CheckBox.new()
	cheats.name = "Cheats"
	cheats.text = "Cheats (our own; marks the tower and its saves)"
	cheats.button_pressed = CheatSettings.is_enabled()
	cheats.toggled.connect(CheatSettings.set_enabled)
	box.add_child(cheats)


## Read-only: the difficulty of the tower now running. It is fixed when a tower is built and cannot change mid-game.
func _running_text() -> String:
	var preset: int = tower.difficulty if tower != null else NewGameSettings.applied_difficulty
	return "This tower: %s difficulty (fixed for the life of the tower). Your pick above applies to the next new game." % Difficulty.label(preset)


func _funds_text() -> String:
	if NewGameSettings.funds() == NewGameSettings.DEFAULT_FUNDS:
		return ""
	return "Not the standard start: this is our own option."
