extends CanvasLayer
## Top bar: date, period, money, population, stars, plus pause and 3 speeds.
## Reads the sim read-only; pause and speed go to the SimDriver, never into the sim.

const Clock := preload("res://scripts/sim/clock.gd")
const DAY_NAMES: Array[String] = ["WD1", "WD2", "WE"]

@onready var _driver: SimDriver = $SimDriver
@onready var _date: Label = %DateLabel
@onready var _period: Label = %PeriodLabel
@onready var _money: Label = %MoneyLabel
@onready var _population: Label = %PopulationLabel
@onready var _stars: Label = %StarsLabel
@onready var _pause: Button = %PauseButton
@onready var _speed_buttons: Array[Button] = [%Speed1Button, %Speed2Button, %Speed3Button]


func _ready() -> void:
	_pause.pressed.connect(_toggle_pause)
	for i in _speed_buttons.size():
		_speed_buttons[i].pressed.connect(_driver.set_speed.bind(i))
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_1: _driver.set_speed(0)
		KEY_2: _driver.set_speed(1)
		KEY_3: _driver.set_speed(2)


func _toggle_pause() -> void:
	_driver.set_paused(not _driver.paused)


func _refresh() -> void:
	var clock := _driver.tower.clock
	_date.text = "Y%d Q%d %s  %02d:%02d" % [
		clock.year(), clock.quarter(), DAY_NAMES[clock.day_of_week()], clock.hour(), clock.minute()]
	_period.text = "Period %d" % clock.period()
	# No sim value yet for these (later issues); show 0 until they land.
	_money.text = "$0"
	_population.text = "Pop 0"
	_stars.text = "Stars 0"
	_pause.text = "Resume" if _driver.paused else "Pause"
	for i in _speed_buttons.size():
		_speed_buttons[i].disabled = i == _driver.speed_index
