class_name FireDialog
extends CanvasLayer
## The fire prompt (#373): while a fire event is open, a centred panel says what is burning and whether any
## guards are coming, and offers the two answers: pay the outside fire company (cost shown) or let it burn.
## A button queues a CHOOSE_EVENT command; the panel hides once the sim has applied it. It pauses nothing
## (the event times out to "let it burn"). View only: it reads the sim and never writes to it. The general
## decision cards are #374; this is only the fire's own dialog.

const TowerSim := preload("res://scripts/sim/tower.gd")
const EventsScript := preload("res://scripts/sim/events.gd")
const FireScript := preload("res://scripts/sim/fire.gd")
const EventWindow := preload("res://scripts/view/event_window.gd")

var tower: TowerSim = null
var panel: PanelContainer
var title: Label
var body: Label
var time: Label
var pay_button: Button
var burn_button: Button
var _event_id: int = 0  ## The open fire event the buttons answer; 0 while the panel is hidden.


func _init() -> void:
	layer = 8
	panel = PanelContainer.new()
	panel.name = "FirePanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(380, 0)
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.05, 0.04, 0.96)
	style.border_color = Color(0.95, 0.35, 0.10)
	style.set_border_width_all(3)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)
	title = Label.new()
	title.name = "Title"
	title.text = "FIRE!"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	list.add_child(title)
	body = Label.new()
	body.name = "Text"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(350, 0)
	list.add_child(body)
	time = Label.new()
	time.name = "Time"
	list.add_child(time)
	var row := HBoxContainer.new()
	row.name = "Choices"
	list.add_child(row)
	pay_button = Button.new()
	pay_button.name = "PayButton"
	pay_button.focus_mode = Control.FOCUS_NONE
	pay_button.pressed.connect(func() -> void: choose(FireScript.PAY))
	row.add_child(pay_button)
	burn_button = Button.new()
	burn_button.name = "BurnButton"
	burn_button.text = "Let it burn"
	burn_button.focus_mode = Control.FOCUS_NONE
	burn_button.pressed.connect(func() -> void: choose(EventsScript.DECLINE))
	row.add_child(burn_button)


func bind(tower_value: TowerSim) -> void:
	tower = tower_value


## What the prompt shows, or an empty Dictionary while no fire choice is open:
## {"id", "unguarded", "cost", "can_pay", "ticks_left", "time", "text", "rooms"}.
static func describe(t: Object) -> Dictionary:
	for event: Array in t.events.open_events():
		if event[1] != FireScript.KIND:
			continue
		var cost: int = t.events.cost_of(event[0], FireScript.PAY)
		var unguarded: bool = t.fire.has_unguarded_fire()
		var burning: Array[int] = t.fire.burning_rooms()
		var names: Array[String] = []
		for id in burning:
			names.append(str(t.rooms.kind_of(id)).replace("_", " "))
		var text := "Burning now: %s.\n" % ", ".join(names)
		if unguarded:
			text += "No security office reaches this fire. It will spread and burn rooms out, leaving them charred and earning nothing until you pay to repair them.\n"
		else:
			text += "Security guards are on their way, but the fire may spread before they arrive.\n"
		text += "An outside fire company costs $%d and puts every fire out, though the first two rooms to burn are still lost." % cost
		var ignored: String = str(t.events.kind_def(event[1]).get("ignored", ""))
		if ignored != "":
			text += "
If ignored: " + ignored
		var left: int = event[5] - t.tick
		return {"id": event[0], "unguarded": unguarded, "cost": cost, "can_pay": t.ledger.balance >= cost, "ticks_left": left, "time": EventWindow.time_text(left), "text": text, "rooms": burning.size()}
	return {}


## Queues the answer for the next tick. Returns true if it was queued.
func choose(choice: int) -> bool:
	if tower == null or _event_id == 0:
		return false
	return tower.enqueue(TowerSim.Command.make(tower.tick + 1, TowerSim.Command.CHOOSE_EVENT, [_event_id, choice] as Array[int]))


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var info: Dictionary = describe(tower) if tower != null else {}
	panel.visible = not info.is_empty()
	if info.is_empty():
		_event_id = 0
		return
	_event_id = info["id"]
	title.text = "FIRE! No guards can reach it" if info["unguarded"] else "FIRE!"
	body.text = info["text"]
	time.text = "Decide: %s (otherwise it burns)" % info["time"]
	pay_button.text = "Pay the fire company ($%d)" % info["cost"]
	pay_button.disabled = not info["can_pay"]
	pay_button.tooltip_text = "" if info["can_pay"] else "Not enough funds"
