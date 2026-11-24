extends RefCounted
## The Quit buttons and the quit confirm: buttons exist, open the confirm, Cancel closes it, and
## Save and quit saves before quitting and stays open if the save fails. Quitting is stubbed.

var _quits: int = 0
var _saves: int = 0
var _save_ok: bool = true


static func run(check: Callable) -> void:
	var test := new()
	await test._run(check)


func _save() -> bool:
	_saves += 1
	return _save_ok


func _quit() -> void:
	_quits += 1


func _run(check: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame  # the root is still being set up on the first frame
	var root: Node = tree.root
	var confirm := QuitConfirm.new()
	confirm.save_callable = _save
	confirm.quit_callable = _quit
	root.add_child(confirm)
	var menu := SaveMenu.new()
	root.add_child(menu)
	var window := SettingsWindow.new()
	root.add_child(window)
	var menu_quit := menu.find_child("Quit", true, false) as Button
	var window_quit := window.find_child("Quit", true, false) as Button
	check.call(menu_quit != null and window_quit != null, "quit: the Quit button is in the save menu row and the settings window")
	if menu_quit != null:
		menu_quit.pressed.emit()
		check.call(confirm.is_open(), "quit: the save menu Quit button opens the confirm")
	confirm.close()
	if window_quit != null:
		window_quit.pressed.emit()
		check.call(confirm.is_open(), "quit: the settings Quit button opens the confirm")
	(confirm.find_child("Cancel", true, false) as Button).pressed.emit()
	check.call(not confirm.is_open() and _quits == 0, "quit: Cancel closes the confirm without quitting")
	confirm.open()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	confirm._input(esc)
	check.call(not confirm.is_open() and _quits == 0, "quit: Esc cancels")
	var ctrl_q := InputEventKey.new()
	ctrl_q.keycode = KEY_Q
	ctrl_q.ctrl_pressed = true
	ctrl_q.pressed = true
	root.push_input(ctrl_q)
	await tree.process_frame
	check.call(confirm.is_open(), "quit: Ctrl+Q opens the confirm")
	_save_ok = false
	confirm.save_and_quit()
	check.call(_saves == 1 and _quits == 0 and confirm.is_open() and confirm.status.text == "Save failed",
		"quit: a failed save does not quit and says so")
	_save_ok = true
	confirm.save_and_quit()
	check.call(_saves == 2 and _quits == 1, "quit: Save and quit saves, then quits")
	confirm.quit_now()
	check.call(_saves == 2 and _quits == 2, "quit: Quit without saving does not save")
	confirm.free()
	menu.free()
	window.free()
