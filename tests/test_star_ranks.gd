extends RefCounted
## Star rules 3 to 5 as data (7.1, #166): every rank passes at its threshold and fails one below,
## and fails with each single requirement missing. Any open demand blocks star 4 (owner ruling),
## star 4 needs 2 suites, a star once earned is kept, and hotel guests count toward population.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Rules := preload("res://scripts/sim/star_rules.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")

## Facts that satisfy a rank exactly (every requirement at its threshold).
static func _facts(star: int) -> Dictionary:
	var facts := {"population": 0, "security": 0, "suites": 0, "metro": 0, "demands_met": false, "vip_good": false}
	for field: String in Rules.REQUIREMENTS[star]:
		facts[field] = Rules.REQUIREMENTS[star][field]
	return facts


static func _crowd(tower: TowerSim, n: int) -> void:
	for i in n:
		tower.people.add_person(0, People.NONE, tower.rng)


static func _tower_with(kind: String, count: int) -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	for i in count:
		var placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, 100 + 20 * i)
		assert(placed == 0, "fixture room places, refusal %d" % placed)
	return t


static func run(check: Callable) -> void:
	# The table itself.
	check.call(Rules.REQUIREMENTS[3]["population"] == 1000 and Rules.REQUIREMENTS[3]["security"] == 1, "star 3 needs population 1,000 and a security office")
	check.call(Rules.REQUIREMENTS[4]["population"] == 5000 and Rules.REQUIREMENTS[4]["suites"] == 2, "star 4 needs population 5,000 and 2 suites")
	check.call(Rules.REQUIREMENTS[4]["demands_met"] == true and Rules.REQUIREMENTS[4]["vip_good"] == true, "star 4 needs no open demand and a good VIP verdict")
	check.call(Rules.REQUIREMENTS[5]["population"] == 10000 and Rules.REQUIREMENTS[5]["metro"] == 1, "star 5 needs population 10,000 and a metro")

	# Each rank: met at the threshold, and not with any single requirement short.
	for star in [2, 3, 4, 5]:
		var ok := _facts(star)
		check.call(Rules.meets(star, ok), "star %d is met at every threshold" % star)
		for field: String in Rules.REQUIREMENTS[star]:
			var short := ok.duplicate()
			if typeof(ok[field]) == TYPE_BOOL:
				short[field] = false
			else:
				short[field] = int(ok[field]) - 1
			check.call(not Rules.meets(star, short), "star %d is not met with %s one short" % [star, field])
			var missing := ok.duplicate()
			missing.erase(field)
			check.call(not Rules.meets(star, missing), "star %d is not met with %s missing" % [star, field])
	check.call(not Rules.meets(6, _facts(5)) and not Rules.meets(1, _facts(5)), "there is no rank 6, and rank 1 is the start")
	check.call(Rules.meets(3, {"population": 5000, "security": 2}), "more than the threshold still qualifies")

	# Open demand (parking included) blocks star 4: the demands fact is the single switch.
	var demand := _facts(4)
	demand["demands_met"] = false
	check.call(not Rules.meets(4, demand), "an open demand blocks star 4")
	var one_suite := _facts(4)
	one_suite["suites"] = 1
	check.call(not Rules.meets(4, one_suite), "one suite is not enough for star 4")

	# rating_after climbs in order and never skips a rank.
	check.call(Rules.rating_after(1, _facts(5)) == 2, "a tower with no security office stops at 2 however big it is")
	var all := _facts(4)
	all["population"] = 10000
	all["security"] = 1
	all["metro"] = 1
	check.call(Rules.rating_after(1, all) == 5, "a tower that meets every rank climbs to 5 in order")
	check.call(Rules.rating_after(3, {}) == 3, "rating_after never lowers")

	# In a real tower: a security office and 1,000 people promote to 3; one short does not.
	var guarded := TowerSim.new(5)
	guarded.star_fixture = {"security": 1}
	guarded.stars = 2
	_crowd(guarded, 999)
	guarded.promote_stars()
	check.call(guarded.stars == 2, "999 people with a security office stays at 2 stars")
	_crowd(guarded, 1)
	guarded.promote_stars()
	check.call(guarded.stars == 3, "1,000 people with a security office reaches 3 stars")
	var bare := TowerSim.new(5)
	bare.stars = 2
	_crowd(bare, 1000)
	bare.promote_stars()
	check.call(bare.stars == 2, "1,000 people without a security office stays at 2 stars")

	# Star 4 stays out of reach until the demand and VIP systems exist, whatever else is built.
	var suites := _tower_with("hotel_suite", 2)
	suites.stars = 3
	_crowd(suites, 5000)
	check.call(suites.star_facts()["suites"] == 2 and suites.star_facts()["population"] == 5000, "the tower reports its suites and population")
	suites.promote_stars()
	check.call(suites.stars == 3, "star 4 waits on the demand and VIP checks")

	# Star 4 with every fact stood in for: promoted, then star 5 needs the metro and 10,000.
	var top := _tower_with("hotel_suite", 2)
	top.stars = 3
	top.star_fixture = {"demands_met": true, "vip_good": true}
	_crowd(top, 5000)
	top.promote_stars()
	check.call(top.stars == 4, "star 4 is reached with 5,000 people, 2 suites, no open demand and a good VIP")
	_crowd(top, 5000)
	top.promote_stars()
	check.call(top.stars == 4, "10,000 people without a metro stays at 4 stars")
	top.star_fixture["metro"] = 1
	top.promote_stars()
	check.call(top.stars == 5, "10,000 people and a metro reach 5 stars")
	var guests := TowerSim.new(5)
	guests.people.add_person(0, People.NONE, guests.rng)
	check.call(guests.star_facts()["population"] == 1, "a person in a room counts toward population")

	# Sticky: losing security and people keeps the star, at any tick.
	guarded.people.remove_room(0)
	guarded.tick += 7
	guarded.promote_stars()
	check.call(guarded.stars == 3, "a star is kept when the population drops")

	# Checks run on every CHECK_EVERY-th tick.
	check.call(Rules.is_check_tick(Rules.CHECK_EVERY * 3) and not Rules.is_check_tick(Rules.CHECK_EVERY * 3 + 1), "the promotion check runs on every 15th tick")
