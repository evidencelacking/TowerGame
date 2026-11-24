extends CanvasLayer
## Top bar: date, period, money, population, stars, plus pause and 3 speeds.
## Reads the sim read-only; pause and speed go to the SimDriver, never into the sim.

const Clock := preload("res://scripts/sim/clock.gd")
const Driver := preload("res://scripts/view/sim_driver.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")
const DEMAND_NAMES: Dictionary = {1: "security", 2: "suite", 3: "medical", 4: "recycling", 5: "parking", 6: "food"}
const DAY_NAMES: Array[String] = ["WD1", "WD2", "WE"]

@onready var _driver: Driver = $SimDriver
@onready var _date: Label = %DateLabel
@onready var _period: Label = %PeriodLabel
@onready var _money: Label = %MoneyLabel
@onready var _population: Label = %PopulationLabel
@onready var _stars: Label = %StarsLabel
@onready var _demands: Label = %DemandsLabel
@onready var _slow: Label = %SlowLabel
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
	if KeyBindings.is_key(key, "pause"):
		_toggle_pause()
	elif KeyBindings.is_key(key, "speed_1"):
		_driver.set_speed(0)
	elif KeyBindings.is_key(key, "speed_2"):
		_driver.set_speed(1)
	elif KeyBindings.is_key(key, "speed_3"):
		_driver.set_speed(2)


func _toggle_pause() -> void:
	_driver.set_paused(not _driver.paused)


## Whole dollars with thousands separators: 2000000 -> "$2,000,000", -500 -> "-$500".
static func format_money(dollars: int) -> String:
	var digits := str(absi(dollars))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if dollars < 0 else "") + "$" + digits + grouped


## The open demands for the top bar: "" when none, else "Needs: security, parking".
static func format_demands(demands: DemandsScript) -> String:
	if demands.open_count() == 0:
		return ""
	var names: Array[String] = []
	for id: int in DemandsScript.IDS:
		if demands.is_open(id):
			names.append(DEMAND_NAMES[id])
	return "Needs: " + ", ".join(names)


## The permanent population: registered people, who change only on move-in and move-out (#456). The
## "per day" figure is gone: it counted outside visitors, who are not part of it.
static func format_population(count: int) -> String:
	return "Pop %d" % count


## Tooltip text: the permanent population split by group (Tower.population_breakdown "overall", no visitors).
static func population_tooltip(breakdown: Dictionary) -> String:
	var overall: Dictionary = breakdown["overall"]
	var total := int(overall["residents"]) + int(overall["workers"]) + int(overall["guests"])
	return "Permanent population: %d
  Residents %d, workers %d, hotel guests %d" % [total, overall["residents"], overall["workers"], overall["guests"]]


## The group split loops over every person, so it is rebuilt only when the tower or the head count changes.
var _pop_tower: Object = null
var _pop_count: int = -1


func _refresh() -> void:
	var clock := _driver.tower.clock
	_date.text = "Y%d Q%d %s  %02d:%02d" % [
		clock.year(), clock.quarter(), DAY_NAMES[clock.day_of_week()], clock.hour(), clock.minute()]
	_period.text = "Period %d" % clock.period()
	_money.text = format_money(_driver.tower.ledger.balance)
	_stars.text = "Stars %d" % _driver.tower.stars + ("  \u2605 Top rank" if _driver.tower.wedding.top_rank() else "") + ("   DEMO" if DemoMode.active() else "")
	var count: int = _driver.tower.people.count()
	if _driver.tower != _pop_tower or count != _pop_count:
		_pop_tower = _driver.tower
		_pop_count = count
		_population.text = format_population(count)
		_population.tooltip_text = population_tooltip(_driver.tower.population_breakdown())
	var needs := format_demands(_driver.tower.demands)
	_demands.text = needs
	_demands.visible = needs != ""
	# The label always takes its space (toggling visible would reflow the speed buttons); only its alpha changes.
	var slow := _driver.running_slow()
	_slow.modulate.a = 1.0 if slow else 0.0
	_slow.mouse_filter = Control.MOUSE_FILTER_STOP if slow else Control.MOUSE_FILTER_IGNORE
	_pause.text = "Resume" if _driver.paused else "Pause"
	for i in _speed_buttons.size():
		_speed_buttons[i].disabled = i == _driver.speed_index
