class_name QuitConfirm
extends CanvasLayer
## The "Quit to desktop?" confirm. One instance, found through the "quit_confirm" group: the Quit buttons
## (save menu, settings window) and Ctrl+Q call open(). Save and quit saves first and only quits if the
## save worked. Esc cancels. The OS close button / Alt+F4 keep Godot's default (quit). View only.

var panel: PanelContainer
var status: Label
## Writes the quick save and returns whether it worked. Set by main.gd (the save menu's quick_save).
var save_callable: Callable = Callable()
## What quitting does; tests replace it so they do not exit.
var quit_callable: Callable = Callable()


func _init() -> void:
	layer = 40
	name = "QuitConfirm"
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var text := Label.new()
	text.text = "Quit to desktop? Progress since your last save is lost unless you save now."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(360, 0)
	column.add_child(text)
	status = Label.new()
	status.name = "Status"
	column.add_child(status)
	_button(column, "SaveAndQuit", "Save and quit", save_and_quit)
	_button(column, "QuitWithoutSaving", "Quit without saving", quit_now)
	_button(column, "Cancel", "Cancel", close)


func _ready() -> void:
	add_to_group("quit_confirm")


func _button(column: Control, node_name: String, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(handler)
	column.add_child(button)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	status.text = ""
	panel.visible = true


func close() -> void:
	panel.visible = false


func save_and_quit() -> void:
	if save_callable.is_valid() and save_callable.call() as bool:
		quit_now()
	else:
		status.text = "Save failed"


func quit_now() -> void:
	if quit_callable.is_valid():
		quit_callable.call()
	else:
		get_tree().quit()


## Ctrl+Q opens; Esc cancels.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed and key.keycode == KEY_Q:
		open()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()
