extends RefCounted
## The mixed benchmark tower (#419): the owner's saves lag where the offices-only bench_tower never does, so
## this one holds the rooms that cost the most (condos, hotel singles, food, a sky lobby with its own local
## shafts, and deliberately cut-off offices). Built only through the sim's own placement calls with a fixed
## seed, so every run starts identically. Used by `python tools/perf.py mixed`.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const TOP := 24  ## Floors built; the top floor has offices but no shaft stop and no stairs, so they are cut off.
const SKY := 15  ## The sky lobby, on one of the floors a sky lobby may go (Floors.SKY_LOBBY_FLOORS): local shafts run 1 to SKY and SKY to TOP - 1, an express 1 to SKY.
const CUT_OFF_FLOORS: Array[int] = [TOP]
const SHAFTS_PER_ZONE := 2
const FILL_X := 200  ## Rooms stand in the left FILL_X columns of each floor, which sizes the tower at about 1,500 to 2,000 people.
const CARS_PER_SHAFT := 8
const START_TICK := 580  ## About 8:48 on a weekday, just before the morning arrivals.
## Floor kinds by floor number modulo the plan length. The sky lobby floor holds food instead.
const PLAN: Array[String] = ["office", "office", "office", "condo", "hotel_single", "office", "condo", "office"]


## The tower, with the clock at START_TICK. Every placement loop ends because x only grows.
static func build(seed_value: int) -> TowerSim:
	var t := TowerSim.new(seed_value, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, 0, 399, 2)
	for f in range(3, TOP + 1):
		t.floors.fill_span(f, 0, 399)
	assert(t.floors.build_lobby(t.ledger, 0, SKY, 0, 399, 1) == Floors.OK, "the sky lobby must build")
	var local := CatalogueScript.IDS.find("local_shaft")
	var express := CatalogueScript.IDS.find("express_shaft")
	var zones: Array[Vector2i] = [Vector2i(1, SKY), Vector2i(SKY, TOP - 1)]
	for z in zones.size():
		for i in SHAFTS_PER_ZONE:
			t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, local, zones[z].x, zones[z].y, 20 + 100 * i + 4 * z)
	for i in 2:
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, express, 1, SKY, 60 + 100 * i)
	for id in t.rooms.shaft_ids():
		var stops: Array[int] = t.rooms.stops_of(id)
		if stops.is_empty():
			continue
		for _car in CARS_PER_SHAFT:
			t.rooms.add_car(t.ledger, 0, 5, id, stops[0])
	for f in range(3, TOP + 1):
		if f == SKY:
			_fill(t, f, "fast_food")
		elif f in CUT_OFF_FLOORS:
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
