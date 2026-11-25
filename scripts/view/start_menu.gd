class_name StartMenu
extends CanvasLayer
## The menu shown when the game starts: New game, New demo, Continue (the latest save) and Load.
## The sim stays paused while it is open. View only.

const Driver := preload("res://scripts/view/sim_driver.gd")

## Shown once per run, so reloading the scene to switch mode does not bring it back.
static var shown: bool = false

var driver: Driver = null
var save_menu: SaveMenu = null
var continue_button: Button


func _init() -> void:
	layer = 20


## Builds the menu and pauses the sim. Both arguments must already be in the scene.
func bind(driver_value: Driver, save_menu_value: SaveMenu) -> void:
	driver = driver_value
	save_menu = save_menu_value
	shown = true
	driver.set_paused(true)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(260, 0)
	center.add_child(column)
	var title := Label.new()
	title.text = "Tower Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_add(column, "NewGame", "New game", new_game)
	_add(column, "NewDemo", "New demo", new_demo)
	continue_button = _add(column, "Continue", "Continue", continue_latest)
	continue_button.disabled = SaveFiles.latest().is_empty()
	_add(column, "Load", "Load", open_load)
	_add(column, "Settings", "Settings", func() -> void: get_tree().call_group("settings_window", "open"))


func _add(column: VBoxContainer, node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	column.add_child(button)
	return button


func new_game() -> void:
	_start(false)


func new_demo() -> void:
	_start(true)


## Starts a fresh tower in the chosen mode, reloading the scene when the mode changes.
func _start(want_demo: bool) -> void:
	# A new game takes the starting funds chosen in Settings (#248); the tower is built with them at scene
	# start, so a changed setting rebuilds the scene (the mode stays).
	var funds_moved: bool = not want_demo and (NewGameSettings.funds() != NewGameSettings.applied or NewGameSettings.difficulty() != NewGameSettings.applied_difficulty)
	if want_demo != DemoMode.active() or funds_moved:
		DemoMode.forced = want_demo
		get_tree().reload_current_scene()
		return
	_close()


func continue_latest() -> void:
	var latest := SaveFiles.latest()
	if latest.is_empty():
		return
	if save_menu._load(latest["path"], latest["demo"]):
		_close()


func open_load() -> void:
	save_menu.open_load(true)
	# The list applies the pick and hides itself; close this menu once that load succeeded.
	save_menu.panel.visibility_changed.connect(_after_panel, CONNECT_ONE_SHOT)


func _after_panel() -> void:
	if not save_menu.panel.visible and save_menu.status.text.begins_with("Loaded"):
		_close()


func _close() -> void:
	driver.set_paused(false)
	queue_free()
