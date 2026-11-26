extends RefCounted
## Scripted balance runs (#38): a greedy builder plays one strategy on a fixed seed and reports funds, population and
## stars at the end of every game year. It only measures; no sim number is changed here. Built through the sim's own
## placement calls between ticks (like tools/bench_*.gd), with events on, so the same seed gives the same report.
## Used by tools/balance_run.gd (`python tools/balance.py`) and tests/test_balance.gd (a 1-year run).
##
## Each day the builder places up to PER_DAY rooms. The next kind is the first pending service the stars have
## unlocked, else the next kind of the strategy's cycle. Short of funds it waits for the next day; with no spot it
## grows the tower (shaft reach, then a next lobby wing), and failing that tries the next kind. Floors are paid
## for by the room placed on them, like a player's.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const STRATEGIES: Array[String] = ["offices", "condos", "hotels", "mixed"]
const SEED := 42
const YEARS := 10
const DAY_TICKS := 2550  ## The sum of the six clock periods.
const DAYS_PER_YEAR := ClockScript.DAYS_PER_QUARTER * ClockScript.QUARTERS_PER_YEAR
const PER_DAY := 12  ## Rooms placed per game day at most.
const WING := 60  ## Lobby columns per wing (about $660,000 of lobby each); a wing opens when the last is full.
const MAX_WINGS := 3
const FIRST_TOP := 6  ## Floors the first shaft reaches (the lobby is floors 1 and 2).
const MAX_TOP := 29  ## A local shaft spans at most 30 floors: the builder never builds past one shaft's reach.
const CARS_PER_PEOPLE := 150  ## One car per this many people, per shaft, as far as the stars allow.
const RESERVE_BASE := 150000  ## Dollars kept back for quarterly running costs, plus RESERVE_PER_ROOM for each room built.
const RESERVE_PER_ROOM := 1000
const SKIP_LIMIT := 12  ## Kinds tried in a row that found no spot before the builder gives up for the day (pending services come first).
const STALL_DAYS := 24  ## Two game years with no placement and no population growth is reported as stalled.

## Services: [kind, how many, star that unlocks it, strategies that build it ("" = all)].
const SERVICES: Array = [
	["security", 1, 2, ""],
	["housekeeping", 1, 2, "hotels mixed"],
	["medical", 1, 3, ""],
	["recycling", 1, 3, ""],
	["parking_ramp", 1, 3, "hotels mixed"],
	["parking_space", 6, 3, "hotels mixed"],
	["hotel_suite", 2, 3, "hotels mixed"],
	["metro", 1, 3, "mixed"],
]

var _t: TowerSim
var _strategy: String = ""
var _top: int = FIRST_TOP
var _wings: int = 1
var _shafts: Array[int] = []
var _counts: Dictionary = {}
var _cycle_pos: int = 0  ## Rooms placed from the strategy's cycle so far (services do not count).
var _quiet_days: int = 0
var _last_pop: int = 0
var _notes: Array[String] = []


## Plays `strategy` for `years` game years from `seed_value` (funds < 0: the normal starting funds). Returns {"rows": [[year, funds, people, stars, status]],
## "notes": [String], "hash": int}. status is "ok", "bankrupt" (funds below zero: the run stops there) or "stalled".
static func play(strategy: String, years: int = YEARS, seed_value: int = SEED, funds: int = -1) -> Dictionary:
	var run: RefCounted = (load("res://tools/balance_play.gd") as GDScript).new()
	return run.call("_play", strategy, years, seed_value, funds)


func _play(strategy: String, years: int, seed_value: int, funds: int) -> Dictionary:
	_strategy = strategy
	_t = TowerSim.new(seed_value) if funds < 0 else TowerSim.new(seed_value, funds)
	_t.floors.build_lobby(_t.ledger, 0, 1, 0, WING - 1, 2)
	_add_shaft(WING / 2)
	var rows: Array = []
	for year in range(1, years + 1):
		var status := "ok"
		for _day in DAYS_PER_YEAR:
			_build_day()
			for _i in DAY_TICKS:
				_t.step()
			if _t.ledger.balance < 0:
				status = "bankrupt"
				break
		if status == "ok" and _quiet_days >= STALL_DAYS:
			status = "stalled"
		rows.append([year, _t.ledger.balance, _t.permanent_population(), _t.stars, status])
		if status == "bankrupt":
			_notes.append("bankrupt in year %d" % year)
			break
	return {"rows": rows, "notes": _notes, "hash": _t.state_hash()}


func _add_shaft(x: int) -> void:
	var kind := CatalogueScript.IDS.find("local_shaft")
	var before := _t.rooms.shaft_ids()
	if _t.rooms.place_shaft(_t.grid, _t.floors, _t.ledger, 0, kind, 1, _top, x) != Rooms.OK:
		return
	for id in _t.rooms.shaft_ids():
		if not before.has(id):
			_shafts.append(id)


## One day of building. Ends: placements are capped by PER_DAY, skips by SKIP_LIMIT, and growth by the floors and
## wings that exist.
func _build_day() -> void:
	var placed := 0
	var skipped := 0
	while placed < PER_DAY and skipped < SKIP_LIMIT:
		_cars()
		var kind := _next_kind(skipped)
		var result := _place(kind)
		if result == Rooms.OK:
			_counts[kind] = int(_counts.get(kind, 0)) + 1
			placed += 1
			if not _is_service(kind):
				_cycle_pos += 1
		elif result == Rooms.SHORT_OF_FUNDS:
			break
		elif not _grow():
			skipped += 1
	var pop := _t.permanent_population()
	if placed == 0 and pop <= _last_pop:
		_quiet_days += 1
	else:
		_quiet_days = 0
	_last_pop = pop


func _is_service(kind: String) -> bool:
	for row: Array in SERVICES:
		if row[0] == kind:
			return true
	return false


## The kind to build next; `skip` moves on past kinds that found no spot.
func _next_kind(skip: int) -> String:
	var stars := _t.unlocked_stars()
	for row: Array in SERVICES:
		var kind: String = row[0]
		if int(row[2]) <= stars and (str(row[3]) == "" or str(row[3]).contains(_strategy)) and int(_counts.get(kind, 0)) < int(row[1]):
			if skip == 0:
				return kind
			skip -= 1
	var cycle := _cycle(stars)
	return cycle[(_cycle_pos + skip) % cycle.size()]


## The repeating pattern of a strategy at this star rating.
func _cycle(stars: int) -> Array[String]:
	match _strategy:
		"offices":
			return ["office", "office", "office", "office", "office", "fast_food"] as Array[String]
		"condos":
			return ["condo", "condo", "condo", "fast_food"] as Array[String]
		"hotels":
			if stars < 2:
				return ["office", "office", "office", "fast_food"] as Array[String]
			return ["hotel_single", "hotel_single", "hotel_single", "hotel_single", "hotel_single", "hotel_single", "fast_food"] as Array[String]
		_:
			if stars < 2:
				return ["office", "condo", "office", "condo", "fast_food"] as Array[String]
			if stars < 3:
				return ["office", "condo", "hotel_single", "office", "condo", "hotel_single", "fast_food"] as Array[String]
			return ["office", "condo", "hotel_single", "hotel_twin", "office", "condo", "hotel_single", "fast_food", "retail"] as Array[String]


## Places the kind at the first spot that takes it: floors from the lowest up, or the basements for the kinds
## that sit there. Returns OK, SHORT_OF_FUNDS or the last refusal (no spot). The scans are bounded by floors x columns.
func _place(kind: String) -> int:
	var index := CatalogueScript.IDS.find(kind)
	if index < 0 or int(CatalogueScript.field(kind, "star")) > _t.unlocked_stars():
		return Rooms.UNKNOWN_KIND
	var floor_list: Array[int] = []
	if kind in ["parking_ramp", "parking_space", "metro"]:
		for f in range(-1, -6, -1):
			floor_list.append(f)
	else:
		for f in range(3, _top + 1):
			floor_list.append(f)
	var width: int = CatalogueScript.field(kind, "width")
	var limit := WING * _wings
	var worst := Rooms.UNKNOWN_KIND
	for f in floor_list:
		for x in range(0, limit - width + 1):
			var check := _t.rooms.check_place(_t.grid, _t.floors, kind, f, x, _t.unlocked_stars())
			if check["reason"] == Rooms.OK:
				if int(check["cost"]) > _spare():
					return Rooms.SHORT_OF_FUNDS
				return _t.rooms.place_room(_t.grid, _t.floors, _t.ledger, _t.tick, index, f, x, _t.unlocked_stars())
			worst = check["reason"]
	return worst


## Makes room: more shaft reach, else a next lobby wing with its own shaft. False when neither can be done.
func _grow() -> bool:
	if _top < MAX_TOP:
		var new_top := mini(_top + 2, MAX_TOP)
		for id in _shafts:
			if _t.rooms.resize_shaft(_t.grid, _t.floors, _t.ledger, _t.tick, id, 1, new_top) != Rooms.OK:
				return false
		_top = new_top
		return true
	if _wings < MAX_WINGS:
		var x0 := WING * _wings
		if _t.floors.build_lobby(_t.ledger, _t.tick, 1, x0, x0 + WING - 1, 2, _t.grid) != Floors.OK:
			return false
		_wings += 1
		_add_shaft(x0 + WING / 2)
		return true
	return false


## Funds the builder may spend: the balance less the reserve for running costs.
func _spare() -> int:
	var rooms_built := 0
	for n: int in _counts.values():
		rooms_built += n
	return _t.ledger.balance - RESERVE_BASE - RESERVE_PER_ROOM * rooms_built


## One car per CARS_PER_PEOPLE people on each shaft, as far as the stars let it.
func _cars() -> void:
	var want := 1 + _t.permanent_population() / (CARS_PER_PEOPLE * maxi(1, _shafts.size()))
	for id in _shafts:
		if _t.rooms.car_count(id) < want and _spare() > 80000:
			var stops: Array[int] = _t.rooms.stops_of(id)
			if not stops.is_empty():
				_t.rooms.add_car(_t.ledger, _t.tick, _t.unlocked_stars(), id, stops[0])
