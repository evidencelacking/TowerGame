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
const GridScript := preload("res://scripts/sim/grid.gd")

const STRATEGIES: Array[String] = ["offices", "condos", "hotels", "mixed"]
const SEED := 42
const YEARS := 10
const DAY_TICKS := 2550  ## The sum of the six clock periods.
const DAYS_PER_YEAR := ClockScript.DAYS_PER_QUARTER * ClockScript.QUARTERS_PER_YEAR
const PER_DAY := 12  ## Rooms placed per game day at most.
const WING := 36  ## Lobby columns per wing (a ground lobby column costs $5,000 a floor); the first wing is built at the start.
const LOBBY_HEIGHT := 1  ## Floors of ground lobby: one is the cheapest (the sim allows 1 to 2); rooms start on floor 2.
const FIRST_FLOOR := 2  ## The lowest floor the builder puts a room on.
const MAX_WINGS := 11  ## The grid is 400 columns wide.
const FIRST_TOP := 8  ## The highest floor rooms go on at the start.
const TOP_STEP := 4  ## Floors added to the building limit when the builder runs out of room.
const MAX_TOP := 29  ## A local shaft spans at most 30 floors: the builder never builds past one shaft's reach.
const SHAFT_TOP := MAX_TOP  ## Every shaft is built to its full reach at once: it costs the same at any height ($200,000 and $2,000 a floor).
const CARS_PER_PEOPLE := 120  ## One car per this many people, per shaft, as far as the stars allow.
const RESERVE_MARGIN := 20000  ## Dollars kept back on top of the next quarter's running costs.
const FOOD_COVER := 100  ## Lunch places are built while they cover under this percent of the office workers.
const WING_FUNDS := 500000  ## Spare funds needed before a wing is built: its lobby and local shaft, with a margin.
const BAY := 4  ## Columns kept free at the right end of each wing for its service shaft (hotel strategies), built at 2 stars.
const ROOMS_PER_STATION := 90  ## Hotel rooms one housekeeping station keeps clean (its six housekeepers clean about 18 a day each).
const SERVICE_COVER := 2  ## A service the stars do not need yet waits until the spare funds are this many times its price.
const SKIP_LIMIT := 12  ## Kinds tried in a row that found no spot before the builder gives up for the day (pending services come first).
const STALL_DAYS := 24  ## Two game years with no placement and no population growth is reported as stalled.

## Services: [kind, how many, star that unlocks it, strategies that build it ("" = all), demand id that asks for it (0 = none, build once)].
## A service with a demand is built while the demand is open; the others once. Security is built as soon as it is
## affordable (star 3 asks for it); the rest wait for spare funds (SERVICE_COVER) so they do not stop growth.
const SERVICES: Array = [
	["security", 1, 2, "", 0],
	["housekeeping", 1, 2, "hotels mixed", 0],
	["medical", 1, 3, "", 3],
	["recycling", 1, 3, "", 4],
	["parking_ramp", 1, 3, "hotels mixed", 0],
	["parking_space", 2, 3, "hotels mixed", 0],
	["hotel_suite", 2, 3, "hotels mixed", 0],
	["metro", 1, 3, "mixed", 0],
]

var _t: TowerSim
var _strategy: String = ""
var _top: int = FIRST_TOP
var _wings: int = 1
var _shafts: Array[int] = []
var _service: Array[int] = []  ## Service shaft ids (housekeepers ride these).
var _service_wings: int = 0  ## Wings that have a service shaft.
var _counts: Dictionary = {}
var _cycle_pos: int = 0  ## Rooms placed from the strategy's cycle so far (services do not count).
var _quiet_days: int = 0
var _last_pop: int = 0
var _notes: Array[String] = []
var _trace: Array[String] = []  ## One line per quarter: money in and out by kind, and why the builder stopped (see trace()).
var _line_at: int = 0  ## Ledger lines already summed into the trace.
var _stops: Dictionary = {}  ## Why building stopped, counted per quarter: cap, funds, nospot.
var _short_kind: Dictionary = {}  ## Kinds that were short of funds, counted per quarter.
var _last_day_end: String = ""


## Plays `strategy` for `years` game years from `seed_value` (funds < 0: the normal starting funds). Returns {"rows": [[year, funds, people, stars, status]],
## "notes": [String], "hash": int}. status is "ok", "bankrupt" (funds below zero: the run stops there) or "stalled".
static func play(strategy: String, years: int = YEARS, seed_value: int = SEED, funds: int = -1) -> Dictionary:
	var run: RefCounted = (load("res://tools/balance_play.gd") as GDScript).new()
	return run.call("_play", strategy, years, seed_value, funds)


func _setup(strategy: String, seed_value: int, funds: int) -> void:
	_strategy = strategy
	_t = TowerSim.new(seed_value) if funds < 0 else TowerSim.new(seed_value, funds)
	_t.floors.build_lobby(_t.ledger, 0, 1, 0, WING - 1, LOBBY_HEIGHT)
	_add_shaft(WING / 2)


func _play(strategy: String, years: int, seed_value: int, funds: int) -> Dictionary:
	_setup(strategy, seed_value, funds)
	var rows: Array = []
	for year in range(1, years + 1):
		var status := "ok"
		for day in DAYS_PER_YEAR:
			_build_day()
			for _i in DAY_TICKS:
				_t.step()
			if day % ClockScript.DAYS_PER_QUARTER == ClockScript.DAYS_PER_QUARTER - 1:
				_trace_quarter(year, day / ClockScript.DAYS_PER_QUARTER + 1)
			if _t.ledger.balance < 0:
				status = "bankrupt"
				break
		if status == "ok" and _quiet_days >= STALL_DAYS:
			status = "stalled"
		rows.append([year, _t.ledger.balance, _t.permanent_population(), _t.stars, status])
		if status == "bankrupt":
			_notes.append("bankrupt in year %d" % year)
			break
	return {"rows": rows, "notes": _notes, "hash": _t.state_hash(), "trace": _trace}


func _add_shaft(x: int) -> void:
	var kind := CatalogueScript.IDS.find("local_shaft")
	var before := _t.rooms.shaft_ids()
	if _t.rooms.place_shaft(_t.grid, _t.floors, _t.ledger, _t.tick, kind, 1, SHAFT_TOP, x) != Rooms.OK:
		return
	for id in _t.rooms.shaft_ids():
		if not before.has(id):
			_shafts.append(id)


## One day of building. Ends: placements are capped by PER_DAY, skips by SKIP_LIMIT, and growth by the floors and
## wings that exist.
func _build_day() -> void:
	var placed := 0
	var skipped := 0
	var tried := {}  ## Kinds found short of funds today that were not worth waiting for.
	while placed < PER_DAY and skipped < SKIP_LIMIT:
		_cars()
		_service_shafts()
		var kind := _next_kind(skipped, tried)
		var result := _place(kind)
		if result == Rooms.OK:
			_counts[kind] = int(_counts.get(kind, 0)) + 1
			placed += 1
			if not _is_service(kind):
				_cycle_pos += 1
		elif result == Rooms.SHORT_OF_FUNDS:
			_short_kind[kind] = int(_short_kind.get(kind, 0)) + 1
			if _is_service(kind) and kind != "security":
				tried[kind] = true  # a big service does not hold the whole tower back
				skipped += 1
			else:
				break
		else:
			if kind == "fast_food" or _is_service(kind):
				tried[kind] = true  # no room for this one now: the strategy's own kinds decide when the tower grows
				skipped += 1
			elif not _grow():
				skipped += 1
	var why := "cap" if placed >= PER_DAY else ("nospot" if skipped >= SKIP_LIMIT else "funds")
	_stops[why] = int(_stops.get(why, 0)) + 1
	var pop := _t.permanent_population()
	if placed == 0 and pop <= _last_pop:
		_quiet_days += 1
	else:
		_quiet_days = 0
	_last_pop = pop


func _needs_service() -> bool:
	return _strategy == "hotels" or _strategy == "mixed"


## True when the span overlaps a wing's service bay.
func _in_bay(x: int, width: int) -> bool:
	if not _needs_service():
		return false
	for w in _wings:
		var bx := w * WING + WING - BAY
		if x < bx + BAY and x + width > bx:
			return true
	return false


## At 2 stars the hotel strategies build a service shaft with a car in each wing's bay: housekeepers ride nothing else,
## so without one no room is ever cleaned and the hotel stops earning.
func _service_shafts() -> void:
	if not _needs_service() or _t.unlocked_stars() < 2:
		return
	var kind := CatalogueScript.IDS.find("service_shaft")
	while _service_wings < _wings:
		var bx := _service_wings * WING + WING - BAY
		var before := _t.rooms.shaft_ids()
		if _spare() < 160000 or _t.rooms.place_shaft(_t.grid, _t.floors, _t.ledger, _t.tick, kind, 1, SHAFT_TOP, bx) != Rooms.OK:
			return
		for id in _t.rooms.shaft_ids():
			if not before.has(id):
				_service.append(id)
		_service_wings += 1


func _is_service(kind: String) -> bool:
	for row: Array in SERVICES:
		if row[0] == kind:
			return true
	return false


## The kind to build next; `skip` moves on past kinds that found no spot. Services come first, then lunch places
## while the food demand is open, then the strategy's cycle.
func _next_kind(skip: int, tried: Dictionary) -> String:
	var stars := _t.unlocked_stars()
	for row: Array in SERVICES:
		var kind: String = row[0]
		if tried.has(kind) or int(row[2]) > stars or not (str(row[3]) == "" or str(row[3]).contains(_strategy)):
			continue
		var want := int(row[1])
		if kind == "housekeeping":
			want = 1 + (int(_counts.get("hotel_single", 0)) + int(_counts.get("hotel_twin", 0))) / ROOMS_PER_STATION
		var demand := int(row[4])
		if demand > 0 and not _t.demands.is_open(demand):
			continue
		if int(_counts.get(kind, 0)) < want or demand > 0:
			if skip == 0:
				return kind
			skip -= 1
	if Commerce.lunch_coverage(_t.rooms) in range(0, FOOD_COVER):  # the demand flag only moves between days
		if not tried.has("fast_food"):
			if skip == 0:
				return "fast_food"
			skip -= 1
	var cycle := _cycle(stars)
	return cycle[(_cycle_pos + skip) % cycle.size()]


## The repeating pattern of a strategy at this star rating. Lunch places are not in it: the food demand asks for them.
func _cycle(stars: int) -> Array[String]:
	match _strategy:
		"offices":
			return ["office"] as Array[String]
		"condos":
			return ["condo", "condo", "condo", "condo", "office"] as Array[String]
		"hotels":
			if stars < 2:
				return ["office"] as Array[String]
			return ["hotel_single", "hotel_single", "hotel_single", "hotel_twin"] as Array[String]
		_:
			if stars < 2:
				return ["office", "condo", "office"] as Array[String]
			if stars < 3:
				return ["office", "condo", "hotel_single", "office"] as Array[String]
			return ["office", "condo", "hotel_single", "hotel_twin", "office", "retail"] as Array[String]


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
		for f in range(FIRST_FLOOR, _top + 1):
			floor_list.append(f)
	var width: int = CatalogueScript.field(kind, "width")
	var limit := WING * _wings
	var worst := Rooms.UNKNOWN_KIND
	for f in floor_list:
		for x in range(0, limit - width + 1):
			if f > 0 and (not _touches(f, x, width) or _in_bay(x, width)):
				continue
			var check := _t.rooms.check_place(_t.grid, _t.floors, kind, f, x)
			if check["reason"] == Rooms.OK:
				var cost := int(check["cost"])
				var need := cost
				if _is_service(kind) and kind != "security":
					need = cost * SERVICE_COVER
				if need > _spare():
					return Rooms.SHORT_OF_FUNDS
				return _t.rooms.place_room(_t.grid, _t.floors, _t.ledger, _t.tick, index, f, x)
			worst = check["reason"]
	return worst


## True when floor already runs beside the span (a shaft or a room is there), so the new room joins the
## walkway to the shaft. A room with a gap between it and the shaft would be cut off.
func _touches(f: int, x: int, width: int) -> bool:
	return (x > 0 and _t.floors.has_floor(f, x - 1)) or (x + width < GridScript.WIDTH_UNITS and _t.floors.has_floor(f, x + width))


## Makes room: more shaft reach, else a next lobby wing with its own shaft. False when neither can be done.
func _grow() -> bool:
	if _top < MAX_TOP:
		_top = mini(_top + TOP_STEP, MAX_TOP)
		return true
	if _wings < MAX_WINGS:
		var x0 := WING * _wings
		if x0 + WING > GridScript.WIDTH_UNITS or _spare() < WING_FUNDS:
			return false  # a wing without its shaft would be cut off: save up for both first
		if _t.floors.build_lobby(_t.ledger, _t.tick, 1, x0, x0 + WING - 1, LOBBY_HEIGHT, _t.grid) != Floors.OK:
			return false
		_wings += 1
		_add_shaft(x0 + WING / 2)
		return true
	return false


## Funds the builder may spend: the balance less the next quarter's running costs and a margin.
func _spare() -> int:
	return _t.ledger.balance - RunningCosts.quarterly_total(_t.rooms, _t.floors) - RESERVE_MARGIN


## One car per CARS_PER_PEOPLE people on each shaft, as far as the stars let it.
func _cars() -> void:
	for id in _service:
		if _t.rooms.car_count(id) < 1 and _spare() > 50000:
			var stops: Array[int] = _t.rooms.stops_of(id)
			if not stops.is_empty():
				_t.rooms.add_car(_t.ledger, _t.tick, _t.unlocked_stars(), id, stops[0])
	var want := 1 + _t.permanent_population() / (CARS_PER_PEOPLE * maxi(1, _shafts.size()))
	for id in _shafts:
		if _t.rooms.car_count(id) < want and _spare() > 80000:
			var stops: Array[int] = _t.rooms.stops_of(id)
			if not stops.is_empty():
				_t.rooms.add_car(_t.ledger, _t.tick, _t.unlocked_stars(), id, stops[0])


## Sums the ledger lines since the last quarter into one trace line: build (charges), rent and sales in, running
## costs out, then the balance, people, rooms, and why building stopped on the days of the quarter.
func _trace_quarter(year: int, quarter: int) -> void:
	var sums := {}
	for i in range(_line_at, _t.ledger.lines.size()):
		var line: Array = _t.ledger.lines[i]
		sums[line[2]] = int(sums.get(line[2], 0)) + int(line[1])
	_line_at = _t.ledger.lines.size()
	var income := 0
	for k: int in [Ledger.INCOME, Ledger.SALE, Ledger.HOTEL, Ledger.SHOP, Ledger.WINDFALL]:
		income += int(sums.get(k, 0))
	var other := int(sums.get(Ledger.REFUND, 0)) + int(sums.get(Ledger.PAYOUT, 0))
	_trace.append("y%dq%d build=%d income=%d (rent %d sale %d hotel %d shop %d) upkeep=%d other=%d bal=%d pop=%d stars=%d rooms=%d top=%d cut=%d vacant=%d built=%s stops=%s short=%s" % [
		year, quarter, -int(sums.get(Ledger.CHARGE, 0)), income, int(sums.get(Ledger.INCOME, 0)), int(sums.get(Ledger.SALE, 0)),
		int(sums.get(Ledger.HOTEL, 0)), int(sums.get(Ledger.SHOP, 0)), -int(sums.get(Ledger.COST, 0)), other, _t.ledger.balance,
		_t.permanent_population(), _t.stars, _t.rooms.room_count(), _top, _cut_off(), _vacant(), str(_counts), str(_stops), str(_short_kind)])
	_stops = {}
	_short_kind = {}


## Rooms the lobby's routes do not reach.
func _cut_off() -> int:
	var n := 0
	for id in _t.rooms.room_ids():
		if _t.rooms.is_cut_off(id):
			n += 1
	return n


## Offices with no workers.
func _vacant() -> int:
	var workers := _t.people.worker_counts()
	var n := 0
	for id in _t.rooms.room_ids():
		if _t.rooms.kind_of(id) == "office" and int(workers.get(id, 0)) == 0:
			n += 1
	return n
