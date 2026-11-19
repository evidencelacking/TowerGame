extends RefCounted
## The event dialogs, #215: a fake event shown by the panel, with its texts, choices and time left;
## a choice button queues the command; the panel follows the sim and hides when nothing is open.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const EventWindow := preload("res://scripts/view/event_window.gd")
const TestEvents := preload("res://tests/test_events.gd")


static func run(check: Callable) -> void:
	var kind := TestEvents._kind(1, 1000, 0, 1000)
	kind["title"] = "Test notice"
	kind["text"] = "Something happened."
	kind["labels"] = ["Ignore", "Act"]
	var t := TestEvents._tower(11, [kind] as Array[Dictionary])
	var w := EventWindow.new()
	w.bind(t)
	w.refresh()
	check.call(not w.panel.visible, "the panel is hidden while no event is open")
	TestEvents._run(t, 650)
	var entries := EventWindow.describe(t)
	check.call(entries.size() == 1 and entries[0]["title"] == "Test notice" and entries[0]["text"] == "Something happened.", "the panel describes the open event's texts")
	check.call(entries[0]["labels"] == (["Ignore", "Act", "Option 2"] as Array[String]), "a button per choice, the missing label falling back to a plain one")
	check.call(entries[0]["ticks_left"] > 0 and entries[0]["ticks_left"] <= 1000 and entries[0]["time"].ends_with("left"), "the time left is shown")
	check.call(EventWindow.time_text(0) == "No time left" and EventWindow.time_text(25) == "10 min left" and EventWindow.time_text(150) == "1 h 0 min left", "time left reads in game minutes")
	w.refresh()
	var id: int = entries[0]["id"]
	check.call(w.panel.visible and w.list.find_child("Choice%d_1" % id, true, false) != null and w.list.find_child("Choice%d_2" % id, true, false) != null, "the panel shows the event with its choice buttons")

	# Time ticks down in place, and the buttons survive the refresh.
	var button := w.list.find_child("Choice%d_1" % id, true, false) as Button
	var label := w.list.find_child("Time%d" % id, true, false) as Label
	var before := label.text
	TestEvents._run(t, 100)
	w.refresh()
	check.call(w.list.find_child("Choice%d_1" % id, true, false) == button and label.text != before, "the time left counts down without rebuilding the buttons")

	# A button queues the command; the sim applies it next tick.
	check.call(t.events.resolved().is_empty(), "nothing is answered before the click")
	button.pressed.emit()
	check.call(not t.events.event_of(id).is_empty(), "a click only queues: the event is open until the tick")
	t.step()
	var answered := t.events.resolved()
	check.call(answered.size() == 1 and answered[0][0] == id and answered[0][2] == 1, "the click's command answers the event with that choice")
	w.refresh()
	check.call(w.list.find_child("Choice%d_1" % id, true, false) == null, "the answered event leaves the panel")

	# Without a bound tower nothing is queued.
	var loose := EventWindow.new()
	check.call(not loose.choose(1, 0), "an unbound panel queues nothing")
	loose.free()
	w.free()
