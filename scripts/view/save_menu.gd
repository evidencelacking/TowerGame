class_name SaveMenu
extends CanvasLayer
## Save, Load and Load autosave buttons in the top-right corner, under the HUD bar, plus a slot
## list for named saves and Ctrl+S quick save. Saving and loading act on the SimDriver's tower in
## place. Demo mode saves to its own files, marked demo. View only: file I/O goes through SaveFiles.

const Driver := preload("res://scripts/view/sim_driver.gd")

var driver: Driver = null
var status: Label
var panel: PanelContainer
var _buttons: Dictionary = {}
var _list: VBoxContainer
var _title: Label
var _name_edit: LineEdit
var _saving: bool = false
var _show_all: bool = false  ## List both modes' saves (the start menu's Load).


func _init() -> void:
	layer = 5
	var box := HBoxContainer.new()
	box.name = "Row"
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_top = 48.0
	box.offset_right = -8.0
	add_child(box)
	status = Label.new()
	status.name = "Status"
	box.add_child(status)
	for entry in [["Save", open_save], ["Load", open_load], ["Load autosave", load_autosave]]:
		var button := Button.new()
		button.name = entry[0].replace(" ", "")
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		box.add_child(button)
		_buttons[entry[0]] = button
	_build_panel()


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "SlotPanel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_title = Label.new()
	column.add_child(_title)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Name for this save"
	column.add_child(_name_edit)
	_list = VBoxContainer.new()
	_list.name = "Slots"
	column.add_child(_list)
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.pressed.connect(close_panel)
	column.add_child(close)


func bind(driver_value: Driver) -> void:
	driver = driver_value


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_S:
		quick_save()
		get_viewport().set_input_as_handled()


func open_save() -> void:
	_open(true, false)


func open_load(show_all: bool = false) -> void:
	_open(false, show_all)


func close_panel() -> void:
	panel.visible = false


func _open(saving: bool, show_all: bool) -> void:
	_saving = saving
	_show_all = show_all
	_title.text = "Save game: pick a slot" if saving else "Load game: pick a save"
	_name_edit.visible = saving
	_refresh()
	panel.visible = true


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var modes: Array = [false, true] if _show_all else [SaveFiles.demo]
	for is_demo in modes:
		for entry in SaveFiles.entries(is_demo):
			var is_slot: bool = entry["label"].begins_with("Slot")
			if _saving and not is_slot:
				continue  # Manual saves go to the named slots; autosaves and the quick save are the game's.
			var button := Button.new()
			button.text = ("[DEMO] " if is_demo else "") + SaveFiles.describe(entry)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.disabled = not _saving and (not entry["exists"] or entry["problem"] != "")
			button.pressed.connect(_pick.bind(entry))
			_list.add_child(button)


func _pick(entry: Dictionary) -> void:
	if _saving:
		save_slot(entry["path"], _name_edit.text.strip_edges())
	else:
		_load(entry["path"], entry["demo"])
	panel.visible = false


func save_slot(path: String, slot_name: String) -> bool:
	var ok := SaveFiles.write(driver.tower, path, slot_name, SaveFiles.demo)
	status.text = "Saved" if ok else "Save failed"
	return ok


func quick_save() -> bool:
	var ok := SaveFiles.write(driver.tower, SaveFiles.quick_path(SaveFiles.demo), "Quick save", SaveFiles.demo)
	status.text = "Quick saved" if ok else "Quick save failed"
	return ok


func load_autosave() -> bool:
	return _load(SaveFiles.newest_autosave(), SaveFiles.demo)


func _load(path: String, is_demo: bool) -> bool:
	if path != "" and is_demo != SaveFiles.demo and SaveFiles.problem(path) == "":
		# A save from the other mode: restart the scene in that mode, then apply it (see main.gd).
		SaveFiles.pending_load = path
		DemoMode.forced = is_demo
		get_tree().reload_current_scene()
		return true
	var ok := path != "" and SaveFiles.load_into(driver.tower, path)
	if ok:
		status.text = "Loaded"
	else:
		var why := SaveFiles.problem(path)
		status.text = "Load failed: " + (why if why != "" else "the save is damaged")
	return ok
