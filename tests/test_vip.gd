extends RefCounted
## VIP visit tests (7.8, #173): no visit before a suite, stars and parking exist; one reserved suite
## at a time that takes no ordinary guests; a good verdict unlocks star 4's VIP rule; a bad one
## schedules a retry; the verdict is deterministic; the state saves and loads.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const VipScript := preload("res://scripts/sim/vip.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const TestHotel := preload("res://tests/test_hotel.gd")


## A tower with one suite and a parking space, 3 stars. mood["stress"] is added to the suite's stress
## after its resident has made a trip, so the tower's quality is 300 minus it (the suite is the only
## graded room).
static func _tower(mood: Dictionary, parking: bool = true) -> TowerSim:
	var t := TestHotel._tower(1, "hotel_suite", true, parking)
	t.stars = 3
	var suite := TestHotel._room(t)
	var resident := t.people.add_person(suite, -1, t.rng)
	t.grades._tripped[resident] = true
	t.people.set_stress(0, 0)
	t.grades.add_modifier(func(_room: int) -> int: return int(mood["stress"]))
	return t


static func _facts_for_four(t: TowerSim) -> Dictionary:
	return {"population": 5000, "suites": 2, "demands_met": true, "vip_good": t.star_facts()["vip_good"]}


## Jumps half an hour before the minute, then steps to it (bounded).
static func _run_to(t: TowerSim, minute: int, day: int) -> void:
	TestHotel._jump(t, minute - 30, day)
	TestHotel._step_to(t, minute, day)


static func _has_message(t: TowerSim, code: int) -> bool:
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			return true
	return false


static func run(check: Callable) -> void:
	check.call(VipScript.GOOD_FROM == 150 and VipScript.RETRY_DAYS == 3 and VipScript.VISIT_STARS == 3, "the VIP verdict line is the B line and the retry is 3 days")

	# No visit before a suite, 3 stars, or a parking space exists.
	var bare := TowerSim.new(1, 100000000)
	bare.stars = 3
	TestHotel._jump(bare, 17 * 60, 0)
	TestHotel._step_to(bare, 19 * 60, 0)
	check.call(not bare.vip.is_visiting() and bare.vip.visits() == 0 and not bare.vip.is_good(), "no visit before a suite exists")
	var mood := {"stress": 0}
	var low := _tower(mood)
	low.stars = 2
	_run_to(low, 19 * 60, 0)
	check.call(not low.vip.is_visiting(), "no visit below 3 stars")
	var no_car := _tower(mood, false)
	_run_to(no_car, 19 * 60, 0)
	check.call(not no_car.vip.is_visiting(), "no visit without a free parking space")

	# A good visit: reserved at 18:00, the suite takes no ordinary guests, verdict at 10:00 next day.
	var t := _tower(mood)
	var suite := TestHotel._room(t)
	_run_to(t, 18 * 60 + 30, 0)
	check.call(t.vip.is_visiting() and t.vip.reserved_suite() == suite, "a VIP is reserved into the suite at 18:00")
	check.call(_has_message(t, Messages.VIP_ARRIVED), "the arrival is logged")
	TestHotel._step_to(t, 23 * 60 + 30, 0)
	check.call(t.hotel.state_of(suite) == HotelScript.VACANT, "the reserved suite takes no ordinary guests")
	check.call(not t.star_facts()["vip_good"] and not StarRulesScript.meets(4, _facts_for_four(t)), "no verdict yet: star 4 is blocked")
	TestHotel._jump(t, 9 * 60 + 30, 1)
	TestHotel._step_to(t, 10 * 60 + 10, 1)
	check.call(t.vip.verdict() == VipScript.GOOD and t.vip.is_good() and t.vip.visits() == 1, "good quality gives a good verdict")
	check.call(not t.vip.is_visiting() and t.vip.reserved_suite() == -1 and _has_message(t, Messages.VIP_GOOD), "the VIP leaves and the suite is free")
	check.call(t.star_facts()["vip_good"] and StarRulesScript.meets(4, _facts_for_four(t)), "a good verdict unlocks star 4's VIP rule")
	TestHotel._jump(t, 17 * 60 + 30, 4)
	TestHotel._step_to(t, 19 * 60, 4)
	check.call(not t.vip.is_visiting() and t.vip.visits() == 1, "a good verdict is final: no more visits")

	# The B line itself passes: quality 150 is good, 149 is the neighbour that is not (#212).
	var edge := _tower({"stress": 150})
	_run_to(edge, 18 * 60 + 30, 0)
	TestHotel._jump(edge, 9 * 60 + 30, 1)
	TestHotel._step_to(edge, 10 * 60 + 10, 1)
	check.call(VipScript.tower_quality(edge.rooms, edge.people, edge.grades) == 150 and edge.vip.is_good(), "a tower at quality exactly 150 gets a good verdict")
	var below := _tower({"stress": 151})
	_run_to(below, 18 * 60 + 30, 0)
	TestHotel._jump(below, 9 * 60 + 30, 1)
	TestHotel._step_to(below, 10 * 60 + 10, 1)
	check.call(VipScript.tower_quality(below.rooms, below.people, below.grades) == 149 and not below.vip.is_good(), "quality 149 gets a bad verdict")

	# A bad visit: a retry three days after the verdict, and a later good visit unlocks star 4.
	var mood2 := {"stress": 200}
	var b := _tower(mood2)
	_run_to(b, 18 * 60 + 30, 0)
	TestHotel._jump(b, 9 * 60 + 30, 1)
	TestHotel._step_to(b, 10 * 60 + 10, 1)
	check.call(b.vip.verdict() == VipScript.BAD and not b.vip.is_good() and _has_message(b, Messages.VIP_BAD), "poor quality gives a bad verdict")
	check.call(not b.star_facts()["vip_good"] and not StarRulesScript.meets(4, _facts_for_four(b)), "a bad verdict keeps star 4 blocked")
	check.call(b.vip.next_day() == 1 + VipScript.RETRY_DAYS, "the next VIP is due three days after the verdict")
	TestHotel._jump(b, 17 * 60 + 30, 3)
	TestHotel._step_to(b, 19 * 60, 3)
	check.call(not b.vip.is_visiting(), "no new VIP before the retry day")
	mood2["stress"] = 0
	b.hotel.remove_room(TestHotel._room(b))  # forget any ordinary booking of the suite, so it is vacant again
	TestHotel._jump(b, 17 * 60 + 30, 4)
	TestHotel._step_to(b, 19 * 60, 4)
	check.call(b.vip.is_visiting(), "a new VIP comes on the retry day")
	TestHotel._jump(b, 9 * 60 + 30, 5)
	TestHotel._step_to(b, 10 * 60 + 10, 5)
	check.call(b.vip.is_good() and b.vip.visits() == 2 and StarRulesScript.meets(4, _facts_for_four(b)), "a later good visit unlocks star 4")

	# A suite that needs cleaning is not chosen.
	var d := _tower(mood)
	var dirty := TestHotel._room(d)
	var record: Array[int] = [HotelScript.VACANT, -1, -1, HotelScript.CHECK_OUT_FROM, -1, 0, 5, 0]
	d.hotel._records[dirty] = record
	_run_to(d, 19 * 60, 0)
	check.call(not d.vip.is_visiting(), "a dirty suite does not take the VIP")

	# One reserved suite at a time: with two suites only the lowest id is held.
	var two := _tower(mood)
	var second := two.rooms.place_room(two.grid, two.floors, two.ledger, 0, CatalogueScript.IDS.find("hotel_suite"), 3, 100)
	check.call(second == Rooms.OK and two.hotel.suites().size() == 2, "a second suite goes in")
	_run_to(two, 18 * 60 + 30, 0)
	var ids: Array[int] = two.hotel.suites()
	check.call(ids.size() == 2 and two.vip.reserved_suite() == ids[0], "only the lowest-id suite is reserved")

	# Bulldozing the reserved suite calls the visit off, with no verdict.
	var gone := _tower(mood)
	_run_to(gone, 18 * 60 + 30, 0)
	check.call(gone.vip.is_visiting(), "the visit started before the bulldozer came")
	gone.rooms.bulldoze(gone.grid, gone.floors, gone.ledger, gone.tick, 3, 110)
	TestHotel._step_to(gone, 20 * 60, 0)
	check.call(not gone.vip.is_visiting() and gone.vip.visits() == 0 and gone.vip.reserved_suite() == -1, "bulldozing the suite calls the visit off with no verdict")

	# Deterministic and saved: a replay gives the same VIP state, a reload the same state.
	var again := _tower({"stress": 0})
	_run_to(again, 18 * 60 + 30, 0)
	TestHotel._jump(again, 9 * 60 + 30, 1)
	TestHotel._step_to(again, 10 * 60 + 10, 1)
	check.call(again.vip.state_ints().slice(0, 6) == t.vip.state_ints().slice(0, 6), "the same tower gives the same VIP state")
	var mid := _tower(mood)
	_run_to(mid, 18 * 60 + 30, 0)
	var loaded := TowerSim.new(1, 100000000)
	check.call(loaded.load_state(mid.save()) and loaded.state_hash() == mid.state_hash() and loaded.vip.reserved_suite() == mid.vip.reserved_suite(), "a visit in progress survives a save and load")
	var damaged := mid.save()
	damaged["vip"] = [9, 0, 0, 0, 0, 0]
	check.call(not TowerSim.new(1, 100000000).load_state(damaged), "a damaged VIP record is refused")
