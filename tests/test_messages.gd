extends RefCounted
## Message log tests (2.11): the sim records refusals and events with their tick, keeps at least
## 200 (oldest dropped past the cap), saves and loads them, and the view words and scrolls them.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Msg := preload("res://scripts/sim/messages.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Log := preload("res://scripts/view/message_log.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestBulldoze := preload("res://tests/test_bulldoze.gd")


static func _view(tower: TowerSim) -> Log:
	var view := Log.new()
	view._ready()
	view.set_tower(tower)
	return view


static func _last(t: TowerSim) -> Array[int]:
	return t.messages.entry(t.messages.count() - 1)


static func run(check: Callable) -> void:
	# Builds and refusals append entries with the tick they applied at.
	var t := TestBulldoze._wide()
	check.call(t.messages.count() == 1 and t.messages.entry(0)[1] == Msg.LOBBY_BUILT, "building the lobby is logged")
	TestRooms._room(t, TestRooms.OFFICE, 2, 100)
	var last := _last(t)
	check.call(last[0] == t.tick and last[1] == Msg.ROOM_BUILT and last[2] == TestRooms.OFFICE and last[3] == 2, "a room built is logged with its tick, kind and floor")
	TestRooms._room(t, TestRooms.OFFICE, 2, 100)
	last = _last(t)
	check.call(last[0] == t.tick and last[1] == Msg.ROOM_REFUSED and last[2] == RoomsScript.OVERLAPS_ROOM, "a refused room is logged with the sim's reason and its tick")
	TestBulldoze._dozer(t, 2, 100)
	last = _last(t)
	check.call(last[0] == t.tick and last[1] == Msg.ROOM_REMOVED and last[2] == TestRooms.OFFICE and last[3] == 2, "a bulldoze is logged with the room kind")
	TestBulldoze._dozer(t, 1, 104)
	last = _last(t)
	check.call(last[1] == Msg.BULLDOZE_REFUSED and last[2] == RoomsScript.PERMANENT, "a refused bulldoze is logged")
	TestRooms._room(t, TestRooms.CONDO, 2, 100)
	t.rooms.set_sold(t.grid.cell_at(2, 100), true)
	var before := t.messages.count()
	TestRooms._send(t, Command.REPLACE_ROOM, [TestRooms.OFFICE, 2, 100] as Array[int])
	check.call(t.messages.count() == before + 2, "replacing a sold condo logs the replace and the refund")
	check.call(t.messages.entry(before)[1] == Msg.ROOM_REPLACED and _last(t)[1] == Msg.CONDO_REFUND and _last(t)[2] == 80000, "the refund entry carries the amount")

	# The clock stamp matches a clock stepped tick by tick.
	var stepped := Clock.new()
	var matches := true
	for n in 6000:
		var jumped := Clock.new()
		jumped.set_to_tick(n)
		if jumped.state_ints().slice(0, 5) != stepped.state_ints().slice(0, 5):
			matches = false
		stepped.advance()
	check.call(matches, "set_to_tick matches a clock stepped one tick at a time")

	# 200+ messages are kept, in order, readable and scrollable in the view.
	var many := TestBulldoze._wide()
	for i in 249:
		TestRooms._send(many, Command.BUILD_FLOOR, [500, 100, 109] as Array[int])  # refused: not a floor
	check.call(many.messages.count() == 250, "250 messages are all kept")
	var view := _view(many)
	var lines := view.all_lines()
	check.call(lines.size() == 250, "the view reads all 250 entries")
	var stamped := true
	for line in lines:
		stamped = stamped and line.begins_with("Y1 Q1 ") and line.length() > 20
	check.call(stamped, "every line carries the game clock stamp and its text")
	check.call(lines[0].ends_with("Lobby built, 1 floor tall") and lines[249].ends_with("Refused: Not a floor"), "lines are worded, oldest first, nothing truncated")
	check.call(view._line.text == lines[249], "the message line shows the latest message")
	check.call(view.first_row == 250 - Log.ROWS and view.visible_lines().size() == Log.ROWS and view.visible_lines()[Log.ROWS - 1] == lines[249], "the open log follows the newest entries")
	var seen := {}
	view.scroll_by(-100000)
	check.call(view.first_row == 0 and view.visible_lines()[0] == lines[0], "scrolling up clamps at the oldest entry")
	for _step in 100:
		for line in view.visible_lines():
			seen[line] = true
		if view.first_row >= 250 - Log.ROWS:
			break
		view.scroll_by(Log.ROWS)
	check.call(view.visible_lines()[Log.ROWS - 1] == lines[249], "scrolling down reaches the newest entry")
	check.call(view.visible_lines().size() == Log.ROWS and view._bar.visible, "the window stays a fixed size with a scroll bar")
	check.call(seen.size() >= 2, "scrolling shows different entries")
	view.free()

	# Past the cap the oldest drop.
	var full := TowerSim.new(0)
	for i in Msg.CAP + 10:
		full.messages.add(i + 1, Msg.CONDO_REFUND, i)
	check.call(Msg.CAP >= 200, "the cap keeps at least 200")
	check.call(full.messages.count() == Msg.CAP, "the log never grows past its cap")
	check.call(full.messages.entry(0)[2] == 10 and full.messages.entry(Msg.CAP - 1)[2] == Msg.CAP + 9, "past the cap the oldest entries drop first")

	# Save and load round-trips the log, and a bad one is refused.
	var copy := TowerSim.new(0)
	check.call(copy.load_state(many.save()), "a tower with messages loads")
	check.call(copy.messages.state_ints() == many.messages.state_ints(), "the log survives save and load")
	check.call(copy.state_hash() == many.state_hash(), "the loaded tower hashes the same")
	var bad := many.save()
	bad["messages"] = [5, 1, 2]
	check.call(not TowerSim.new(0).load_state(bad), "a save with a malformed log is refused")
