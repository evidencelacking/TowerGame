extends RefCounted
## Star promotion tests (5.11): 299 people stays at 1 star, 300 promotes to 2 once with one
## message, a later dip never demotes, the check runs once a day at a fixed time, and the
## toolbar unlocks star 2 items on promotion. Fake people stand in room 0 so they count as inside.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const Log := preload("res://scripts/view/message_log.gd")

const CHECK_TICK := 600 + 300 + 600  ## First tick of period 4 (14:00) on day 1.


static func _crowd(tower: TowerSim, n: int) -> void:
	for i in n:
		tower.people.add_person(0, People.NONE, tower.rng)


static func _promotions(tower: TowerSim) -> int:
	var n := 0
	for i in tower.messages.count():
		if tower.messages.entry(i)[1] == Msg.STAR_PROMOTED:
			n += 1
	return n


## A tower with n people inside and the clock one tick short of the day-1 check.
static func _before_check(n: int) -> TowerSim:
	var t := TowerSim.new(42)
	_crowd(t, n)
	t.tick = CHECK_TICK - 1
	t.clock.set_to_tick(CHECK_TICK - 1)
	return t


static func run(check: Callable) -> void:
	check.call(StarRulesScript.REQUIREMENTS[2]["population"] == 300, "star 2 needs population 300 in the data table")

	var t := TowerSim.new(1)
	_crowd(t, 299)
	check.call(t.population() == 299, "fixture: 299 people are in the tower")
	t.promote_stars()
	check.call(t.stars == 1 and _promotions(t) == 0, "299 people stays at 1 star with no message")
	_crowd(t, 1)
	t.promote_stars()
	check.call(t.stars == 2, "300 people promotes to 2 stars")
	check.call(_promotions(t) == 1 and t.messages.entry(t.messages.count() - 1)[2] == 2, "promotion logs one message naming star 2")
	t.promote_stars()
	check.call(_promotions(t) == 1, "promotion happens once")
	check.call(Log.describe(Msg.STAR_PROMOTED, 2, 0) == "Your tower has grown to 2 stars. New buildings are open to you.", "the promotion message is worded")

	# A dip below 300 never demotes.
	t.people.remove_room(0)
	check.call(t.population() == 0, "fixture: everyone left")
	t.promote_stars()
	check.call(t.stars == 2 and _promotions(t) == 1, "dropping below 300 keeps 2 stars")

	# Toolbar unlocks change at 2 stars.
	check.call(Toolbar.item_state("service_shaft", 1)["locked"] and not Toolbar.item_state("service_shaft", t.stars)["locked"], "a star 2 item unlocks on promotion")
	check.call(Toolbar.item_state("hotel_single", 1)["locked"] and not Toolbar.item_state("hotel_single", t.stars)["locked"], "hotel_single unlocks at 2 stars")
	check.call(Toolbar.item_state("escalator", t.stars)["locked"], "a star 3 item stays locked at 2 stars")

	# Timed check: stepping to 14:00 with 300 inside promotes on that tick, not the tick before.
	var timed := _before_check(300)
	check.call(timed.population() == 300 and timed.stars == 1, "fixture: 300 inside, still 1 star before 14:00")
	timed.step()
	check.call(timed.tick == CHECK_TICK and timed.stars == 2, "the 14:00 check promotes a 300 tower")
	check.call(_promotions(timed) == 1, "the timed promotion emits one event")

	# 299 at 14:00 stays; the same setup gives the same state.
	var short := _before_check(299)
	short.step()
	check.call(short.stars == 1, "299 people at 14:00 stays at 1 star")
	var again := _before_check(300)
	again.step()
	check.call(again.state_hash() == timed.state_hash(), "the same setup gives the same state after promotion")
