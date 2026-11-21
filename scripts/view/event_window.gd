class_name EventWindow
extends CanvasLayer
## The event dialogs (#215): a panel at the top right that lists every open event with its text, a
## button per choice and the time left before the default (decline). It pauses nothing and has no
## modal. A button queues a CHOOSE_EVENT command for the next tick; the event leaves the list once
## the sim has applied it. The panel hides itself when no event is open. View only: it reads the
## sim and never writes to it.
##
## Each open event is a card (#374): title, text, one button per choice (with its cost), the time
## left and an "If ignored:" line. Texts come from the kind in Events.kinds: optional "title", "text",
## "labels" (one per choice, choice 0 being decline) and "ignored". Missing ones fall back to plain
## defaults or are left out.

const TowerSim := preload("res://scripts/sim/tower.gd")
const EventsScript := preload("res://scripts/sim/events.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const FireScript := preload("res://scripts/sim/fire.gd")

var tower: TowerSim = null
var panel: PanelContainer
var list: VBoxContainer
var _signature: String = ""
var _time_labels: Dictionary = {}  ## Event id to its time-left Label.


func _init() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.name = "EventPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -16.0
	panel.offset_right = -16.0
	panel.offset_top = 60.0
	panel.custom_minimum_size = Vector2(280, 0)
	panel.visible = false
	add_child(panel)
	list = VBoxContainer.new()
	list.name = "Events"
	panel.add_child(list)


func bind(tower_value: TowerSim) -> void:
	tower = tower_value


## The time left until the default, in plain words (game minutes, rounded up).
static func time_text(ticks_left: int) -> String:
	var minutes := (maxi(ticks_left, 0) * CarsScript.SECONDS_PER_TICK + 59) / 60
	if minutes <= 0:
		return "No time left"
	if minutes >= 60:
		return "%d h %d min left" % [minutes / 60, minutes % 60]
	return "%d min left" % minutes


## What the panel shows: one entry per open event, oldest first:
## {"id", "kind", "title", "text", "ignored", "ticks_left", "time", "labels" (one per choice, 0 declines),
## "costs" (dollars per choice)}.
static func describe(t: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Array in t.events.open_events():
		var def: Dictionary = t.events.kind_def(event[1])
		var labels: Array[String] = []
		var costs: Array[int] = []
		var given: Array = def.get("labels", [])
		for n in int(event[6]):
			var label := str(given[n]) if n < given.size() else ("Decline" if n == EventsScript.DECLINE else "Option %d" % n)
			var cost: int = t.events.cost_of(event[0], n)
			costs.append(cost)
			if cost > 0 and not label.contains("$"):
				label += " ($%d)" % cost
			labels.append(label)
		var left: int = event[5] - t.tick
		result.append({"id": event[0], "kind": event[1], "title": str(def.get("title", "Event")), "text": str(def.get("text", "")), "ignored": str(def.get("ignored", "")), "ticks_left": left, "time": time_text(left), "labels": labels, "costs": costs})
	return result


## Queues the choice for the next tick. Returns true if it was queued.
func choose(event_id: int, choice: int) -> bool:
	if tower == null:
		return false
	return tower.enqueue(TowerSim.Command.make(tower.tick + 1, TowerSim.Command.CHOOSE_EVENT, [event_id, choice] as Array[int]))


func _process(_delta: float) -> void:
	refresh()


## Brings the panel in line with the sim. The buttons are rebuilt only when the events change, so a
## click is never lost to a rebuild; the time left is updated in place.
func refresh() -> void:
	var entries: Array[Dictionary] = []
	if tower != null:
		for entry in describe(tower):
			if entry["kind"] != FireScript.KIND:  # a fire has its own dialog (fire_dialog.gd)
				entries.append(entry)
	panel.visible = not entries.is_empty()
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%d:%s:%s:%s:%s" % [entry["id"], entry["title"], entry["text"], entry["ignored"], ",".join(entry["labels"])])
	var signature := "|".join(parts)
	if signature != _signature:
		_signature = signature
		_rebuild(entries)
	for entry in entries:
		var label: Label = _time_labels.get(entry["id"])
		if label != null:
			label.text = entry["time"]


func _rebuild(entries: Array[Dictionary]) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	_time_labels.clear()
	for entry in entries:
		var event_id: int = entry["id"]
		var card := PanelContainer.new()
		card.name = "Card%d" % event_id
		list.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		var title := Label.new()
		title.name = "Title%d" % event_id
		title.text = entry["title"]
		box.add_child(title)
		if entry["text"] != "":
			var body := Label.new()
			body.name = "Text%d" % event_id
			body.text = entry["text"]
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size = Vector2(260, 0)
			box.add_child(body)
		var time := Label.new()
		time.name = "Time%d" % event_id
		box.add_child(time)
		_time_labels[event_id] = time
		if entry["ignored"] != "":
			var ignored := Label.new()
			ignored.name = "Ignored%d" % event_id
			ignored.text = "If ignored: " + str(entry["ignored"])
			ignored.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ignored.custom_minimum_size = Vector2(260, 0)
			box.add_child(ignored)
		var row := HFlowContainer.new()
		row.name = "Choices%d" % event_id
		box.add_child(row)
		var labels: Array[String] = entry["labels"]
		for n in labels.size():
			var button := Button.new()
			button.name = "Choice%d_%d" % [event_id, n]
			button.text = labels[n]
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: choose(event_id, n))
			row.add_child(button)
