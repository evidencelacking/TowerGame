extends RefCounted
## Demand messages (7.3, #168): none before the trigger, raised once, cleared once, re-raised
## when lost, only for rooms that can be built, block star 4, and survive save/load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const Log := preload("res://scripts/view/message_log.gd")

const ALL: Array[String] = ["office", "hotel_suite", "security", "medical", "recycling", "parking_space"]


static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	return t


static func _add(t: TowerSim, kind: String, x: int) -> int:
	if Rooms.PLACEABLE.has(kind):
		return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
	# A kind the player cannot place yet: put it in directly, as a later issue's build will.
	var id := 900 + x
	t.floors.fill_span(3, x, x + int(Catalogue.field(kind, "width")) - 1)
	t.grid.place(id, 3, x, int(Catalogue.field(kind, "width")))
	t.rooms._kind_of[id] = Catalogue.IDS.find(kind)
	return 0


static func _count(t: TowerSim, code: int, id: int) -> int:
	var n := 0
	for i in t.messages.count():
		var e := t.messages.entry(i)
		if e[1] == code and e[2] == id:
			n += 1
	return n


static func run(check: Callable) -> void:
	var D := DemandsScript
	# Pure rules.
	var office := {"office": 1}
	check.call(D.compute(2, office, ALL) == 1 << (D.SECURITY - 1), "2 stars: only security is asked for")
	check.call(D.compute(1, office, ALL) == 0, "no demand before 2 stars")
	var three := D.compute(3, office, ALL)
	check.call(three == 31, "3 stars with an office: all five demands open")
	check.call(D.compute(3, {}, ALL) == (1 << (D.SECURITY - 1)) | (1 << (D.SUITE - 1)), "without offices the office-driven demands stay quiet")
	check.call(D.compute(3, {"office": 1, "security": 1, "hotel_suite": 2, "medical": 1, "recycling": 1, "parking_space": 1}, ALL) == 0, "each remedy clears its demand")
	check.call(D.compute(3, office, Rooms.PLACEABLE) == 1 << (D.SUITE - 1) | 0, "only demands whose remedy is buildable open (today: suite)")

	# On a tower: raised once, cleared once, re-raised after loss.
	var t := _tower()
	t.stars = 3
	_add(t, "office", 100)
	var avail: Array[String] = ALL
	t.demands.update(t.rooms, t.stars, t.messages, 10, avail)
	t.demands.update(t.rooms, t.stars, t.messages, 11, avail)
	check.call(_count(t, Msg.DEMAND_RAISED, D.SECURITY) == 1 and _count(t, Msg.DEMAND_RAISED, D.MEDICAL) == 1, "each demand is logged once, not every check")
	check.call(not t.demands.all_met() and not t.star_facts()["demands_met"], "open demands: demands_met is false")
	var sec := _add(t, "security", 120)
	t.demands.update(t.rooms, t.stars, t.messages, 12, avail)
	check.call(not t.demands.is_open(D.SECURITY) and _count(t, Msg.DEMAND_CLEARED, D.SECURITY) == 1, "building security clears its demand, logged once")
	check.call(sec == 0, "fixture: security placed")
	var rec := _add(t, "recycling", 140)
	t.demands.update(t.rooms, t.stars, t.messages, 13, avail)
	check.call(not t.demands.is_open(D.RECYCLING), "recycling built: its demand is closed")
	t.tick = 20
	t.enqueue(TowerSim.Command.make(21, TowerSim.Command.BULLDOZE, [3, 140] as Array[int]))
	t.step()
	t.step()
	t.demands.update(t.rooms, t.stars, t.messages, 22, avail)
	check.call(t.demands.is_open(D.RECYCLING) and _count(t, Msg.DEMAND_RAISED, D.RECYCLING) == 2 and rec == 0, "losing recycling re-raises its demand")
	check.call(Log.describe(Msg.DEMAND_RAISED, D.SECURITY, 0) == "Your tower needs security", "raised message is worded")
	check.call(Log.describe(Msg.DEMAND_CLEARED, D.PARKING, 0) == "Your tower no longer needs parking", "cleared message is worded")

	# Star 4 blocked by any open demand, allowed with none.
	var facts := {"population": 5000, "suites": 2, "demands_met": false, "vip_good": true}
	check.call(not StarRules.meets(4, facts), "an open demand blocks star 4")
	facts["demands_met"] = true
	check.call(StarRules.meets(4, facts), "no open demand lets star 4 through")

	# Save and load keep the open set.
	var live := _tower()
	live.stars = 3
	_add(live, "office", 100)
	live.promote_stars()
	check.call(live.demands.is_open(D.SUITE), "a live tower at 3 stars asks for suites (the buildable demand)")
	var copy := TowerSim.new(5)
	check.call(copy.load_state(live.save()) and copy.demands.state_ints() == live.demands.state_ints(), "the open demands save and load")
	check.call(not DemandsScript.valid_ints([99]) and DemandsScript.valid_ints([3]), "bad demand saves are refused")
