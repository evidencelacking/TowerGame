class_name TutorialPanel
extends CanvasLayer
## The tutorial's small panel (#503): the step title, one hint line and a Skip button. The sim keeps running
## underneath. View only: it reads the tower through a Tutorial and never writes to it. It ends itself on Skip,
## on Done after the last step, and when a save is loaded (the loaded game is a normal one).

const Driver := preload("res://scripts/view/sim_driver.gd")

var tutorial: Tutorial = Tutorial.new()
var driver: Driver = null
var panel: PanelContainer
var title_label: Label
var hint_label: Label
var skip_button: Button
var _loads_at_start: int = 0
var _last_tick: int = -1


func _init() -> void:
	layer = 8


func bind(driver_value: Driver) -> void:
	driver = driver_value
	_loads_at_start = SaveFiles.loads
	panel = PanelContainer.new()
	panel.name = "TutorialBox"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 56.0
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title_label = Label.new()
	title_label.name = "Title"
	column.add_child(title_label)
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)
	skip_button = Button.new()
	skip_button.name = "Skip"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.pressed.connect(skip)
	column.add_child(skip_button)
	_refresh()


func _process(_delta: float) -> void:
	poll()


## Reads the tower once per tick. Public so tests can drive it without frames.
func poll() -> void:
	if driver == null or not tutorial.is_active():
		return
	if SaveFiles.loads != _loads_at_start:
		skip()  # a loaded save is a normal game
		return
	if driver.tower.tick == _last_tick:
		return
	_last_tick = driver.tower.tick
	tutorial.update(driver.tower)
	_refresh()


## The Skip button: ends the tutorial and leaves a normal game. After the last step the same button reads Done.
func skip() -> void:
	tutorial.skip()
	queue_free()


func _refresh() -> void:
	title_label.text = "Tutorial: " + tutorial.title()
	hint_label.text = tutorial.hint()
	skip_button.text = "Done" if tutorial.finished else "Skip tutorial"
