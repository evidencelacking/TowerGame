class_name SaveMenu
extends CanvasLayer
## Save, Load and Load autosave buttons in the top-right corner, under the HUD bar. Saving and
## loading act on the SimDriver's tower in place; the sim is paused while a load applies.
## View only: file I/O goes through SaveFiles.

const Driver := preload("res://scripts/view/sim_driver.gd")

var driver: Driver = null
var status: Label
var _buttons: Dictionary = {}


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
	for entry in [["Save", save_manual], ["Load", load_manual], ["Load autosave", load_autosave]]:
		var button := Button.new()
		button.name = entry[0].replace(" ", "")
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		box.add_child(button)
		_buttons[entry[0]] = button


func bind(driver_value: Driver) -> void:
	driver = driver_value


func save_manual() -> bool:
	var ok := SaveFiles.write(driver.tower, SaveFiles.MANUAL_PATH)
	status.text = "Saved" if ok else "Save failed"
	return ok


func load_manual() -> bool:
	return _load(SaveFiles.MANUAL_PATH)


func load_autosave() -> bool:
	return _load(SaveFiles.newest_autosave())


func _load(path: String) -> bool:
	var ok := path != "" and SaveFiles.load_into(driver.tower, path)
	if ok:
		status.text = "Loaded"
	else:
		var why := SaveFiles.problem(path)
		status.text = "Load failed: " + (why if why != "" else "the save is damaged")
	return ok
