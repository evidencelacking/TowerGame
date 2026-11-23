extends RefCounted
## The huge benchmark tower (#447): about 100 floors and 5,000+ people, to show what a late-game tower costs.
## Within the game's limits: floors run to Grid.FLOOR_MAX (100), a local shaft spans at most 30 floors, an
## express shaft stops only at lobbies, and the tower holds 24 shafts of 8 cars each. So the ground lobby and
## six sky lobbies (Floors.SKY_LOBBY_FLOORS) split the tower into zones of 15 floors; each zone has two or
## three local shafts, and four express shafts run from the ground to the floor-90 sky lobby. Built only
## through the sim's own placement calls with a fixed seed, like bench_mixed.gd. Used by `perf.py big`.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const TOP := 100  ## The top floor holds offices but no shaft stops there, so they are cut off.
const SKIES: Array[int] = [15, 30, 45, 60, 75, 90]
const FILL_X := 164  ## Rooms stand in the left FILL_X columns of each floor.
const EXPRESS_XS: Array[int] = [72, 192, 312, 380]
const CARS_PER_SHAFT := 8
const START_TICK := 580  ## About 8:48 on a weekday, just before the morning arrivals.
## Floor kinds by floor number modulo the plan length. Sky lobby floors hold food or shops.
const PLAN: Array[String] = ["office", "office", "condo", "hotel_single", "office", "apartment", "office", "condo", "retail", "office"]
const SKY_PLAN: Array[String] = ["fast_food", "retail", "restaurant"]


## The tower, with the clock at START_TICK. Every placement loop ends because x only grows.
static func build(seed_value: int) -> TowerSim:
	var t := TowerSim.new(seed_value, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, 0, 399, 2)
	for f in range(3, TOP + 1):
		t.floors.fill_span(f, 0, 399)
	for sky in SKIES:
		assert(t.floors.build_lobby(t.ledger, 0, sky, 0, 399, 1) == Floors.OK, "sky lobby %d must build" % sky)
	var local := CatalogueScript.IDS.find("local_shaft")
	var express := CatalogueScript.IDS.find("express_shaft")
	var bounds: Array[int] = [1]
	bounds.append_array(SKIES)
	bounds.append(TOP - 1)
	# Local zones: 1-15, 15-30, ..., 75-90, 90-99. The lowest four zones carry the most traffic: three shafts (24 shafts in all, the limit).
	for z in bounds.size() - 1:
		var per_zone := 3 if z < 4 else 2
		for i in per_zone:
			var result := t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, local, bounds[z], bounds[z + 1], 12 + 120 * i + 8 * z)
			assert(result == Rooms.OK, "local shaft zone %d: reason %d" % [z, result])
	for i in 4:
		var result := t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, express, 1, 90, EXPRESS_XS[i])
		assert(result == Rooms.OK, "express %d: reason %d" % [i, result])
	for id in t.rooms.shaft_ids():
		var stops: Array[int] = t.rooms.stops_of(id)
		if stops.is_empty():
			continue
		for _car in CARS_PER_SHAFT:
			t.rooms.add_car(t.ledger, 0, 5, id, stops[0])
	for f in range(3, TOP + 1):
		if SKIES.has(f):
			_fill(t, f, SKY_PLAN[(f / 15) % SKY_PLAN.size()])
		elif f == TOP:
			_fill(t, f, "office")
		else:
			_fill(t, f, PLAN[f % PLAN.size()])
	t.clock.set_to_tick(START_TICK)
	return t


## Rooms of one kind, side by side along floor f.
static func _fill(t: TowerSim, f: int, kind: String) -> void:
	var index := CatalogueScript.IDS.find(kind)
	var width: int = CatalogueScript.field(kind, "width")
	var x := 0
	while x + width <= FILL_X:
		if t.rooms.place_room(t.grid, t.floors, t.ledger, 0, index, f, x) == 0:
			x += width
		else:
			x += 1
