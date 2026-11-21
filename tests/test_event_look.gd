extends RefCounted
## Event and service visuals (10.7): fire and smoke, guards, the rescue craft and the threat search each
## draw something while their sim state is active and nothing while it is not; the same moment draws the
## same; drawing never changes the sim; and elevator doors open as a car arrives and close as it leaves.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const EventLook := preload("res://scripts/view/event_look.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")

const DEVICE_MARK := Vector2i(9, 7)  ## The size of the device marker EventLook draws once a sweep finds it.


## Records draw_rect calls.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Rect2i, c: Color) -> void:
		calls.append([r, c])

	func has_size(size: Vector2i) -> bool:
		for call: Array in calls:
			if (call[0] as Rect2i).size == size:
				return true
		return false


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)
	return t.grid.cell_at(floor_number, x)


## Floors 3, 4 and 30 with an office on 3 and 4 and a security office on 3; no event running.
static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in [3, 4, 30]:
		t.floors.fill_span(f, 100, 163)
	_put(t, "office", 3, 100)
	_put(t, "office", 4, 100)
	_put(t, "security", 3, 120)
	t.stars = 3
	return t


static func _count(look: Callable, t: TowerSim, tick: int) -> int:
	var rec := Recorder.new()
	look.call(rec, t, tick)
	return rec.calls.size()


static func _drawn(look: Callable, t: TowerSim, tick: int) -> Recorder:
	var rec := Recorder.new()
	look.call(rec, t, tick)
	return rec


static func run(check: Callable) -> void:
	var t := _tower()
	var office := t.grid.cell_at(4, 100)
	var fire_look := Callable(EventLook, "draw_fire")
	var guard_look := Callable(EventLook, "draw_guards")
	var rescue_look := Callable(EventLook, "draw_rescue")
	var search_look := Callable(EventLook, "draw_search")
	for look: Callable in [fire_look, guard_look, rescue_look, search_look]:
		check.call(_count(look, t, 100) == 0, "event look: %s draws nothing with no event" % look.get_method())

	# Fire: the room on floor 4 burns, the guards arrive at tick 140.
	var ints := t.fire.state_ints().slice(0, 5)
	ints[3] = 0
	ints[4] = 1
	ints.append_array([office, 1, 140] as Array[int])
	t.fire.load_ints(ints)
	var hash_before := t.state_hash()
	check.call(_count(fire_look, t, 100) > 0, "event look: a burning room draws fire and smoke")
	check.call(_count(guard_look, t, 100) > 0, "event look: guards are drawn on their way to a fire")
	check.call(_count(rescue_look, t, 100) == 0, "event look: no rescue craft until one is called")
	check.call(_drawn(fire_look, t, 100).calls == _drawn(fire_look, t, 100).calls, "event look: the same moment draws the same fire")
	check.call(_drawn(fire_look, t, 104).calls != _drawn(fire_look, t, 100).calls, "event look: flames and smoke move with time")
	check.call(_drawn(guard_look, t, 101).calls != _drawn(guard_look, t, 139).calls, "event look: guards move toward the fire")
	check.call(t.state_hash() == hash_before, "event look: drawing leaves the sim unchanged")

	# A floor no office covers burns with no guards.
	var far := _put(t, "office", 30, 100)
	var uncovered := t.fire.state_ints()
	uncovered.resize(5)
	uncovered[4] = 1
	uncovered.append_array([far, 0, 0] as Array[int])
	t.fire.load_ints(uncovered)
	check.call(_count(fire_look, t, 100) > 0 and _count(guard_look, t, 100) == 0, "event look: an uncovered fire burns with no guards")

	# Rescue craft: drawn only in its last stretch, and nothing once the fire is out.
	var rescue := t.fire.state_ints()
	rescue[3] = 500
	t.fire.load_ints(rescue)
	check.call(_count(rescue_look, t, 100) == 0, "event look: the rescue craft is not drawn while far off")
	check.call(_count(rescue_look, t, 420) > 0, "event look: the rescue craft flies in before it arrives")
	rescue.resize(5)
	rescue[3] = 0
	rescue[4] = 0
	t.fire.load_ints(rescue)
	check.call(_count(fire_look, t, 420) == 0 and _count(rescue_look, t, 420) == 0, "event look: nothing is drawn once the fire is out")

	# Threat search: nothing before the owner answers, then a sweep, then the device once found.
	var threat := t.threat.state_ints()  # [rng, seen, read, active, device, search_from, deadline]
	threat[3] = 1
	threat[4] = 4
	threat[5] = 0
	t.threat.load_ints(threat)
	check.call(_count(search_look, t, 1000) == 0, "event look: no search before the owner answers")
	threat[5] = 1000
	t.threat.load_ints(threat)
	var step: int = t.threat.SEARCH_TICKS
	check.call(_count(search_look, t, 1000) > 0, "event look: the search draws the floor being swept")
	check.call(_drawn(search_look, t, 1000).calls != _drawn(search_look, t, 1000 + step).calls, "event look: the sweep moves floor by floor")
	var found_tick := 1000 + 4 * step
	check.call(t.threat.found(t.grid, found_tick) and not t.threat.found(t.grid, 1000 + step), "event look: the sweep reaches the device floor after a few floors")
	check.call(_drawn(search_look, t, found_tick).has_size(DEVICE_MARK) and not _drawn(search_look, t, 1000 + step).has_size(DEVICE_MARK), "event look: the device is marked once found, not before")
	threat[3] = 0
	t.threat.load_ints(threat)
	check.call(_count(search_look, t, 1000) == 0, "event look: no search once the threat is over")

	# Elevator doors: open at a floor, closing as the car leaves, shut between floors and when passing through.
	check.call(TransportLook.door_open(5.0) == 1.0, "doors: open when the car stands at a floor")
	check.call(TransportLook.door_open(5.5) == 0.0, "doors: closed between floors")
	var closing := TransportLook.door_open(5.07)
	check.call(closing > 0.0 and closing < 1.0, "doors: partly open while closing or opening (%.2f)" % closing)
	check.call(TransportLook.door_open(5.0, 8.0) == 0.0, "doors: shut for a car passing through")
	var shaft := Rect2i(0, 0, 24, 32)
	var open_rec := Recorder.new()
	var shut_rec := Recorder.new()
	var half_rec := Recorder.new()
	TransportLook.draw_door_gap(open_rec, shaft, 30, 1.0, Color.WHITE)
	TransportLook.draw_door_gap(shut_rec, shaft, 30, 0.0, Color.WHITE)
	TransportLook.draw_door_gap(half_rec, shaft, 30, 0.5, Color.WHITE)
	check.call(open_rec.calls.size() == 1 and shut_rec.calls.is_empty(), "doors: an open door draws a gap and a shut one nothing")
	check.call(half_rec.calls.size() == 1 and (half_rec.calls[0][0] as Rect2i).size.x < (open_rec.calls[0][0] as Rect2i).size.x, "doors: the gap widens as they open")
