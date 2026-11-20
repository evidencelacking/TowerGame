class_name Rooms
extends RefCounted
## Placed rooms (2.4). Integers only; see CLAUDE.md.
##
## A room is a grid occupant (its position lives in Grid) plus a kind, stored here as an index
## into RoomCatalogue.IDS. Only kinds in PLACEABLE can be placed for now; add a kind there once
## its rules are built. Rent and "condo sold once" (M3+) come later.
## Rules: floor 2 or higher (floor 1 is the lobby floor, basements are refused; UNVERIFIED: the
## reference only says "above ground"), no overlap with another room or the lobby (a shaft, stairs or escalator in front is fine: #272), inside
## the tower width, and every new floor unit under the room needs a floor directly below it (the
## same no-overhang rule as Floors). The room pays its price plus FLOOR_COST_PER_UNIT for each
## unit of floor under it that is not built yet, in one charge, and builds those units.

const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")

## Result codes. OK and SHORT_OF_FUNDS match Floors' and Ledger's; 10 to 19 belong to Floors.
const OK := 0
const SHORT_OF_FUNDS := 1
const BAD_FLOOR := 10  ## Not a real floor number (same code as Floors).
const UNKNOWN_KIND := 20  ## Not a room kind that can be placed yet.
const BELOW_GROUND := 21  ## Basements take no office or condo.
const LOBBY_FLOOR := 22  ## Floor 1 is the lobby floor (unverified).
const OFF_TOWER := 23  ## The room runs off the tower's width.
const OVERLAPS_ROOM := 24  ## Another room is in the way.
const OVERLAPS_LOBBY := 25  ## The ground lobby is in the way.
const OVER_SHAFT := 26  ## A shaft is in the way.
const NOTHING_BELOW := 27  ## No new floor unit has a floor to rest on.
const OVERHANG := 28  ## Some units rest on a floor, others hang past it.
const NO_FLOOR_FOR_STAIRS := 29  ## Stairs: one of the two floors is not built under the stairs.
const NOTHING_THERE := 30  ## Bulldoze: the cell is empty (or off the tower).
const PERMANENT := 31  ## Bulldoze: the lobby or another room the player cannot remove.
const NOT_A_ROOM := 32  ## Bulldoze: the cell holds an occupant that is not a placed room.

const STAIRS_LIMIT := 34  ## Stairs: the tower already holds the most stairs and escalators.
const MAX_SHAFT_FLOORS := 40  ## Shaft: spans more than 30 floors (basements count; express is exempt).
const MAX_SHAFTS := 41  ## Shaft: the tower already holds 24 shafts.
const NO_FLOOR_FOR_SHAFT := 42  ## Shaft: some floor it spans is not built under the shaft.
const BAD_SHAFT_SPAN := 43  ## Shaft: the top is not above the bottom.

const NOT_IN_SHAFT := 44  ## Shaft stop: the floor is not in the shaft's span (or the shaft is unknown).

const MAX_CARS := 45  ## Car: the shaft already holds MAX_CARS_PER_SHAFT cars.
const STAR_CAR_CAP := 46  ## Car: the tower's star rating allows no more cars in the shaft.
const BAD_HOME_FLOOR := 47  ## Car: the home floor is outside the shaft's span or is not a stop.
const NO_CARS_HERE := 48  ## Car: only local and service shafts take cars (so far).
const HOME_DROPPED := 49  ## Shaft resize: the new span would drop a car's home floor.
const HOME_STOP := 50  ## Shaft stop: the floor is a car's home floor, which must stay a stop.
const NOT_A_STOP := 51  ## Send car: the target is not a stop of the car's shaft.
const NO_SUCH_CAR := 52  ## Send car: there is no such car.
const BAD_CALL := 53  ## Place call: the direction is not UP or DOWN, or no car can go that way from the floor.
const OVERLAPS_LINK := 54  ## Stairs, escalator or shaft: another link (stairs, escalator or shaft) is in the way.
const NO_FLOOR_FOR_ESCALATOR := 55  ## Escalator: one of the two floors is not built under the escalator.
const ONE_STATION := 74  ## Metro: the tower already has its one station.
const NOT_TOP := 75  ## Observation deck: only on the tower's top floor, with no room above it (#318).
const ONE_DECK := 76  ## Observation deck: the tower already has its one deck.
const ONE_CASINO := 77  ## Casino: the tower already has its one casino (#319).
const NOT_UNDERGROUND := 60  ## A basement-only room (recycling) needs every one of its floors below ground.
const NOT_TOUCHING := 61  ## Recycling: a new centre must touch an existing centre.
const TALL_REPLACE := 62  ## Replace cannot put a two-floor room (recycling) in; bulldoze and place it.
const NOT_CHAINED := 63  ## Parking space: it must touch the ramp or a working space.
const RAMP_COLUMN := 64  ## Parking ramp: later ramps share the column of the first.
const RAMP_NOT_UNDER_LOBBY := 65  ## Parking ramp: the first goes on B1 under the ground lobby.
const RAMP_NOT_BELOW_RAMP := 66  ## Parking ramp: a later ramp goes directly below a ramp.
const NOT_BASEMENT := 67  ## Parking ramps and spaces go below ground.
const EXPRESS_NO_STOP := 68  ## Express stop: only lobbies and basements can be stops.
const TOO_FEW_STOPS := 72  ## Shaft stop: a shaft keeps at least MIN_STOPS stops (#187).
const NO_MACHINE_ROOM := 70  ## Shaft: no floor above the top stop (floor 100) or below the bottom stop (B10) for a machine room.
const MACHINE_ROOM := 71  ## A shaft's machine room is on the cell, so no room or link goes there.
const ESCALATOR_FLOOR := 69  ## Escalator: it stands only on commercial, lobby or empty floors (#185), never over an office, condo or the like.

## Schedules (#188): a shaft has a weekday and a weekend schedule, each over 3 periods (morning,
## midday, evening). A slot is day_type * SCHEDULE_PERIODS + period, and holds MODE, RESPONSE, WAIT.
const SCHEDULE_PERIODS := 3
const SCHEDULE_SLOTS := 6  ## 2 day types x 3 periods.
const SCHEDULE_FIELDS := 3
const SCHEDULE_INTS := SCHEDULE_SLOTS * SCHEDULE_FIELDS
const MODE_NORMAL := 0  ## Idle cars go home.
const MODE_TOP := 1  ## Express to top: an idle, empty car is sent to the top stop at once.
const MODE_BOTTOM := 2  ## Express to bottom: the same, to the bottom stop.
const MAX_WAIT := 90  ## Longest departure wait, in sim seconds. Larger values clamp to this.
const MAX_RESPONSE := 100  ## Response distance in floors; 0 is no limit.
const BAD_SCHEDULE := 73  ## Schedule: no such slot or mode.
const CAR_INTS := 9  ## Ints in one saved car (SHAFT to NEXT in cars.gd).
const MIN_STOPS := 2  ## A shaft needs at least this many stops (gameplay review of #187: yes).
const MAX_CARS_PER_SHAFT := 8  ## Cars in one shaft (reference).
const CAR_CAPACITY := 17  ## People a local (or service) car holds (reference); enforced in cars.gd (#94).
const EXPRESS_CAR_CAPACITY := 36  ## People an express car holds (owner ruling 2026-11-10).
## Cars allowed per shaft by star rating, index = stars - 1 (a guess, tunable).
const CARS_BY_STAR: Array[int] = [2, 4, 8, 8, 8]
const SHAFT_FLOOR_LIMIT := 30  ## Local and service shafts span at most this many floors (I, K).

const PLACEABLE: Array[String] = ["office", "condo", "fast_food", "restaurant", "retail", "housekeeping", "security", "medical", "recycling", "parking_ramp", "parking_space", "hotel_single", "hotel_twin", "hotel_suite", "gym", "daycare", "clinic", "nightclub", "coworking", "metro", "observation_deck", "casino", "cafe", "pizza", "sushi", "fine_dining", "bar", "grocery", "deli", "pool"]
## Rooms two floors tall, underground (recycling) or above ground (a kind whose placement is not underground,
## #328; see _check_place_tall). Their grid run is on the lower (deeper) floor under the room's id, and the
## upper floor is a second grid occupant under id + 1 that is not a room of its own (see room_of).
const TALL_KINDS: Array[String] = ["recycling", "pool"]
const FIRST_ID := 1000  ## Room occupant ids start here, clear of ids given to PLACE commands.

## The link layer (#126): stairs, escalators and elevator shafts. Links sit in front of rooms and
## coexist with them, so they hold their occupant cells here and not in the room grid. Ids come
## from the same counter as rooms, so an id is unique across both grids.
var links := GridScript.new()
## Stacked flights (#259): a cell holds one id, so when two flights of one kind share a floor (one's
## top is the other's bottom) the half that finds the cell taken sits here instead. Mostly empty.
var links_over := GridScript.new()
var _kind_of: Dictionary = {}  # occupant id -> index in RoomCatalogue.IDS
var _sold: Dictionary = {}  # condo occupant id -> true once sold (sales come in M3; tests set it)
var _next_id: int = FIRST_ID
## Stairs hold two grid occupants, one per floor: the room id (lower floor) and id + 1 (upper).
## Running total of workers and residents removed by
## bulldozing. A room holds RoomCatalogue "people" of them.
var occupants_removed: int = 0
## Shafts hold one grid occupant per floor, ids base .. base + span - 1 from the bottom up.
var _shafts: Dictionary = {}  # shaft id (stable) -> [span, bottom floor, x_left, stops off (floors, ascending), first grid occupant id]
var _cars: Array = []  # a car is SHAFT..NEXT in cars.gd (9 ints), oldest first
var _riders: Array = []  # per car: its riders, each [person id, destination floor], boarding order
var _stops: Array = []  # per car: floors it still has to stop at for its riders
var _heading: Array[int] = []  # per car: the direction it is serving (UP, DOWN or 0)
var _queue: Array = []  # people waiting for a car: [person id, shaft id, floor, destination], arrival order
var alighted: Array = []  # [person id, floor] of recent alighters until #95 takes them with take_alighted()
## Set by Tower so an express shaft can tell which floors are lobbies (its only stops above ground).
var floors: FloorsScript = null
var _schedules: Dictionary = {}  # shaft id -> SCHEDULE_INTS ints (slot * SCHEDULE_FIELDS + MODE, RESPONSE, WAIT); absent = all defaults
var schedule_slot: int = 0  ## The slot now in force, set by the tower each tick from the clock (derived, not saved).
var _calls: Array = []  # hall calls [shaft id, floor, dir, car index or -1] in arrival order (see cars.gd)


func room_count() -> int:
	return _kind_of.size()


func has_room(id: int) -> bool:
	return _kind_of.has(id)


## Ids of every placed room, ascending.
func room_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_kind_of.keys())
	ids.sort()
	return ids


## The catalogue id ("office", "condo") of a placed room, or "" if id is not a room.
func kind_of(id: int) -> String:
	if not _kind_of.has(id):
		return ""
	return CatalogueScript.IDS[_kind_of[id]]


## Checks a placement without changing anything. Returns {"reason", "cost", "floor_units"}:
## cost is the room price plus the missing floor units; floor_units is how many it would build.
## The placement ghost (#13) uses this. kind is a catalogue id such as "office".
func check_place(grid: GridScript, floors: FloorsScript, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "floor_units": 0}
	if not PLACEABLE.has(kind):
		result["reason"] = UNKNOWN_KIND
		return result
	if not GridScript.is_valid_floor(floor_number):
		result["reason"] = BAD_FLOOR
		return result
	var parking := Parking.is_parking(kind)
	if parking and floor_number > 0:
		result["reason"] = NOT_BASEMENT
		return result
	if TALL_KINDS.has(kind):
		return _check_place_tall(grid, floors, kind, floor_number, x_left)
	if kind == "metro":  # one station, in a basement (#325)
		if floor_number > 0:
			result["reason"] = NOT_BASEMENT
			return result
		if _has_kind(kind):
			result["reason"] = ONE_STATION
			return result
	elif floor_number < 0 and not parking and CatalogueScript.field(kind, "placement") != CatalogueScript.PLACE_ANYWHERE:
		result["reason"] = BELOW_GROUND
		return result
	if kind == "casino" and _has_kind(kind):  # one casino (#319)
		result["reason"] = ONE_CASINO
		return result
	if kind == "observation_deck":  # one deck, on the top floor (#318)
		if _has_kind(kind):
			result["reason"] = ONE_DECK
			return result
		if floor_number < highest_room_floor(grid):
			result["reason"] = NOT_TOP
			return result
	if floor_number == 1:
		result["reason"] = LOBBY_FLOOR
		return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	if kind == Parking.RAMP_KIND:
		result["reason"] = Parking.check_ramp(self, grid, floors, floor_number, x_left, width)
	elif kind == Parking.SPACE_KIND:
		result["reason"] = Parking.check_space(self, grid, floor_number, x_left, width)
	if result["reason"] != OK:
		return result
	if _blocked_by_escalator(kind, floor_number, x_left, width):
		result["reason"] = ESCALATOR_FLOOR
		return result
	var new_units := 0
	var supported := 0
	for column in range(x_left, x_left + width):
		if grid.cell_at(floor_number, column) != GridScript.EMPTY:
			result["reason"] = OVERLAPS_ROOM
			return result
		if floors.has_lobby_at(floor_number, column):
			result["reason"] = OVERLAPS_LOBBY
			return result
		if floors.has_floor(floor_number, column):
			continue
		new_units += 1
		if floors.has_floor(floor_above(floor_number) if floor_number < 0 else floor_number - 1, column):  # basements rest on the floor above
			supported += 1
	if new_units > 0 and supported == 0:
		result["reason"] = NOTHING_BELOW
	elif supported < new_units:
		result["reason"] = OVERHANG
	result["floor_units"] = new_units
	result["cost"] = CatalogueScript.cost(kind) + new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	return result


## Places a room by catalogue index (the PLACE_ROOM command's first arg). Returns OK or a reason
## code, and changes nothing on a refusal. One ledger charge; its ref is the catalogue index.
func place_room(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, floor_number: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_place(grid, floors, kind, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var width: int = CatalogueScript.field(kind, "width")
	floors.fill_span(floor_number, x_left, x_left + width - 1)
	if TALL_KINDS.has(kind):
		var upper := floor_above(floor_number)
		floors.fill_span(upper, x_left, x_left + width - 1)
		while _id_taken(grid, _next_id) or _id_taken(grid, _next_id + 1):
			_next_id += 1
		grid.place(_next_id + 1, upper, x_left, width)
		grid.place(_next_id, floor_number, x_left, width)
		_kind_of[_next_id] = kind_index
		_next_id += 2
		return OK
	while _id_taken(grid, _next_id):
		_next_id += 1
	grid.place(_next_id, floor_number, x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 1
	return OK


## Placement of a two-floor basement room: floor_number is the lower (deeper) floor and the upper is
## the floor above it, both below ground. Upper floor units rest on the floor above them and the
## lower on the upper, as basements do (Floors). A centre after the first must touch another centre.
func _check_place_tall(grid: GridScript, floors: FloorsScript, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "floor_units": 0}
	var upper := floor_above(floor_number)
	var underground: bool = CatalogueScript.field(kind, "placement") == CatalogueScript.PLACE_UNDERGROUND
	if underground and floor_number > -2:
		result["reason"] = NOT_UNDERGROUND
		return result
	if not underground:
		var above_reason := _tall_above_ground_reason(kind, floor_number)
		if above_reason != OK:
			result["reason"] = above_reason
			return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	if _blocked_by_escalator(kind, floor_number, x_left, width) or _blocked_by_escalator(kind, upper, x_left, width):
		result["reason"] = ESCALATOR_FLOOR
		return result
	var new_units := 0
	var upper_new := 0
	var upper_supported := 0
	var lower_supported := 0
	for level in [upper, floor_number]:
		for column in range(x_left, x_left + width):
			if grid.cell_at(level, column) != GridScript.EMPTY:
				result["reason"] = OVERLAPS_ROOM
				return result
			if floors.has_lobby_at(level, column):
				result["reason"] = OVERLAPS_LOBBY
				return result
			if floors.has_floor(level, column):
				continue
			new_units += 1
			if level == upper:
				upper_new += 1
				if underground and floors.has_floor(floor_above(upper), column):
					upper_supported += 1
			elif not underground and floors.has_floor(floor_number - 1, column):
				lower_supported += 1  # above ground the lower floor rests on the floor below it
	result["floor_units"] = new_units
	result["cost"] = CatalogueScript.cost(kind) + new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	if underground:
		if upper_new > 0 and upper_supported == 0:
			result["reason"] = NOTHING_BELOW
			return result
		if upper_supported < upper_new:
			result["reason"] = OVERHANG
			return result
	else:  # the upper floor rests on the lower one, which this placement fills, so only the lower needs support
		var lower_new := new_units - upper_new
		if lower_new > 0 and lower_supported == 0:
			result["reason"] = NOTHING_BELOW
			return result
		if lower_supported < lower_new:
			result["reason"] = OVERHANG
			return result
		if kind == "casino" and _has_kind(kind):
			result["reason"] = ONE_CASINO
			return result
	if _has_kind(kind) and not _touches_centre(grid, kind, floor_number, x_left, width):
		result["reason"] = NOT_TOUCHING
	return result


## Why a two-floor room cannot stand on lower floor floor_number above ground, or OK: the lower floor
## cannot be the lobby floor or underground, and the upper must be a real floor below the top.
func _tall_above_ground_reason(_kind: String, floor_number: int) -> int:
	if floor_number == 1:
		return LOBBY_FLOOR
	if floor_number < 1:
		return BELOW_GROUND
	if floor_above(floor_number) == 0:  # the top floor has no floor above it
		return BAD_FLOOR
	return OK


## The highest floor above ground that holds a room, or 0 for a tower with none (#318).
func highest_room_floor(grid: GridScript) -> int:
	var top := 0
	for id in _kind_of:
		if grid.has_occupant(id):
			var run_top: int = grid.run_of(id)[0]
			if TALL_KINDS.has(kind_of(id)) and floor_above(run_top) > run_top:
				run_top = floor_above(run_top)
			top = maxi(top, run_top)
	return top


## True for an observation deck with a room above it: the tower has grown past it, so it is closed until moved.
func is_closed_up(grid: GridScript, id: int) -> bool:
	return kind_of(id) == "observation_deck" and grid.has_occupant(id) and grid.run_of(id)[0] < highest_room_floor(grid)


## True when at least one room of the kind is placed.
func _has_kind(kind: String) -> bool:
	for id in _kind_of:
		if kind_of(id) == kind:
			return true
	return false


## True when a cell next to or above or below the room's footprint belongs to a room of the same kind.
func _touches_centre(grid: GridScript, kind: String, floor_number: int, x_left: int, width: int) -> bool:
	var upper := floor_above(floor_number)
	for level in [floor_number, upper]:
		for column in [x_left - 1, x_left + width]:
			if _same_kind_cell(grid, kind, level, column):
				return true
	for column in range(x_left, x_left + width):
		if _same_kind_cell(grid, kind, floor_above(upper), column) or _same_kind_cell(grid, kind, _floor_below(floor_number), column):
			return true
	return false


func _same_kind_cell(grid: GridScript, kind: String, floor_number: int, column: int) -> bool:
	return floor_number != 0 and kind_of(room_of(grid.cell_at(floor_number, column))) == kind


static func _floor_below(floor_number: int) -> int:
	return floor_number - 1  # Only called for basements, where the floor below is one deeper.


## The room an occupant id belongs to: the id itself, or the lower id for the upper half of a
## two-floor room, or 0 for EMPTY and for an occupant that is no room.
func room_of(id: int) -> int:
	if _kind_of.has(id):
		return id
	if _kind_of.has(id - 1) and TALL_KINDS.has(kind_of(id - 1)):
		return id - 1
	return 0


## True when id is the upper-floor half of a two-floor room.
func is_tall_upper(id: int) -> bool:
	return not _kind_of.has(id) and _kind_of.has(id - 1) and TALL_KINDS.has(kind_of(id - 1))


## True when id is placed in the room grid or in the link layer.
func _id_taken(grid: GridScript, id: int) -> bool:
	return grid.has_occupant(id) or _has_link(id)


## True when id is placed in either link layer.
func _has_link(id: int) -> bool:
	return links.has_occupant(id) or links_over.has_occupant(id)


## True for the kinds that live in the link layer: stairs, escalators and shafts.
static func is_link_kind(kind: String) -> bool:
	if not CatalogueScript.IDS.has(kind):
		return false
	var placement: int = CatalogueScript.field(kind, "placement")
	return placement == CatalogueScript.PLACE_BETWEEN_FLOORS or placement == CatalogueScript.PLACE_SHAFT or placement == CatalogueScript.PLACE_ESCALATOR


## The link id at a cell (stairs and escalators have a lower and an upper half), or EMPTY.
func link_at(floor_number: int, column: int) -> int:
	return links.cell_at(floor_number, column)


## [floor, column, length] of a placed room or link occupant, or an empty array.
func run_of(grid: GridScript, id: int) -> Array[int]:
	if links.has_occupant(id):
		return links.run_of(id)
	return links_over.run_of(id) if links_over.has_occupant(id) else grid.run_of(id)


## The floor above floor_number, or 0 when there is none (floor 100; there is no floor 0).
static func floor_above(floor_number: int) -> int:
	if floor_number == -1:
		return 1
	if floor_number == GridScript.FLOOR_MAX:
		return 0
	return floor_number + 1


## The floor below floor_number, or 0 when there is none (B10). B1 is under floor 1; basements run down.
static func floor_below(floor_number: int) -> int:
	if floor_number == 1:
		return -1
	if floor_number == GridScript.FLOOR_MIN:
		return 0
	return floor_number - 1


## How many stairs and escalators the tower holds (they share one limit).
func _stairs_and_escalators() -> int:
	var count := 0
	for id: int in _kind_of:
		if CatalogueScript.field(kind_of(id), "limit_group") == "stairs_escalators":
			count += 1
	return count


## Checks stairs linking floor_number and the floor above, x_left being the left column. Returns
## {"reason", "cost"}. Needs a built floor (a lobby counts) under all columns on both floors, no
## other link (stairs, escalator or shaft) on either, and room under the 64 stairs and escalators
## limit. Rooms behind the stairs are fine: links sit in front of them (#126). The placement ghost
## (#13) uses this. The grid is not read; it stays so callers keep one signature.
func check_place_stairs(grid: GridScript, floors: FloorsScript, floor_number: int, x_left: int) -> Dictionary:
	return _check_place_link(grid, floors, "stairs", floor_number, x_left)


## The same check for an escalator (#125): 8 wide, otherwise the rules of stairs.
func check_place_escalator(grid: GridScript, floors: FloorsScript, floor_number: int, x_left: int) -> Dictionary:
	return _check_place_link(grid, floors, "escalator", floor_number, x_left)


## Kinds an escalator may stand over (#185): commercial rooms. Lobbies and empty floor have no room.
const ESCALATOR_KINDS: Array[String] = ["fast_food", "restaurant", "retail", "movie_theatre", "party_hall"]


## The id that carries a room's kind: a two-floor room's upper half is id + 1 of its base.
func _room_base(id: int) -> int:
	return id if _kind_of.has(id) else id - 1


## True when an escalator (either half) is in the link layer at the cell.
func _escalator_at(floor_number: int, column: int) -> bool:
	var id := links.cell_at(floor_number, column)
	if id == GridScript.EMPTY:
		return false
	return kind_of(id) == "escalator" or (not _kind_of.has(id) and kind_of(id - 1) == "escalator")


## True when a room of kind may not stand under an escalator, and one does in the columns on level.
## Placing the room first or the escalator first gives the same answer: the rule is on the pair.
func _blocked_by_escalator(kind: String, level: int, x_left: int, width: int) -> bool:
	if ESCALATOR_KINDS.has(kind):
		return false
	for column in range(x_left, x_left + width):
		if _escalator_at(level, column):
			return true
	return false


## True when a flight of kind with its lower floor at floor_number and left column x_left may share
## the cell at (level, column) with the flight already there (#259): the same kind, in the same
## columns, meeting at exactly one floor (the new flight's bottom is the other's top, or its top is
## the other's bottom), and that cell holds only the one flight so far.
func _stacks_on(kind: String, level: int, floor_number: int, x_left: int, column: int) -> bool:
	if links_over.cell_at(level, column) != GridScript.EMPTY:
		return false
	var id := links.cell_at(level, column)
	var base := _room_base(id)
	if not _kind_of.has(base) or kind_of(base) != kind:
		return false
	var run := links.run_of(id)
	if run[1] != x_left:
		return false
	if id == base:  ## The other flight's bottom: the new one must end on this floor.
		return level != floor_number
	return level == floor_number  ## The other flight's top: the new one must start here.


func _check_place_link(grid: GridScript, floors: FloorsScript, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0}
	var upper := floor_above(floor_number)
	if not GridScript.is_valid_floor(floor_number) or upper == 0:
		result["reason"] = BAD_FLOOR
		return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	for column in range(x_left, x_left + width):
		for level: int in [floor_number, upper]:
			if floors.has_shaft(level, column):
				result["reason"] = OVER_SHAFT
				return result
			if machine_room_at(level, column) or (links.cell_at(level, column) != GridScript.EMPTY and not _stacks_on(kind, level, floor_number, x_left, column)):
				result["reason"] = OVERLAPS_LINK
				return result
	for column in range(x_left, x_left + width):
		if not floors.has_floor(floor_number, column) or not floors.has_floor(upper, column):
			result["reason"] = NO_FLOOR_FOR_ESCALATOR if kind == "escalator" else NO_FLOOR_FOR_STAIRS
			return result
	if kind == "escalator":
		for column in range(x_left, x_left + width):
			for level: int in [floor_number, upper]:
				var room := grid.cell_at(level, column)
				if room != GridScript.EMPTY and not ESCALATOR_KINDS.has(kind_of(_room_base(room))):
					result["reason"] = ESCALATOR_FLOOR
					return result
	if _stairs_and_escalators() >= int(CatalogueScript.field(kind, "limit")):
		result["reason"] = STAIRS_LIMIT
		return result
	result["cost"] = CatalogueScript.cost(kind)
	return result


## Places stairs (the PLACE_STAIRS command): args are the lower floor and the left column. One
## ledger charge, ref = the catalogue index of "stairs". Returns OK or a reason code.
func place_stairs(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, floor_number: int, x_left: int) -> int:
	return _place_link(grid, floors, ledger, at_tick, "stairs", floor_number, x_left)


## Places an escalator (the PLACE_ESCALATOR command): the lower floor and the left column.
func place_escalator(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, floor_number: int, x_left: int) -> int:
	return _place_link(grid, floors, ledger, at_tick, "escalator", floor_number, x_left)


func _place_link(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind: String, floor_number: int, x_left: int) -> int:
	var checked := _check_place_link(grid, floors, kind, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	var kind_index: int = CatalogueScript.IDS.find(kind)
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var width: int = CatalogueScript.field(kind, "width")
	while _id_taken(grid, _next_id) or _id_taken(grid, _next_id + 1):
		_next_id += 1
	_put_link(_next_id, floor_number, x_left, width)
	_put_link(_next_id + 1, floor_above(floor_number), x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 2
	return OK


## Places a link half in the front layer, or in the stacked layer when another flight has the cells.
func _put_link(id: int, floor_number: int, x_left: int, width: int) -> void:
	if not links.place(id, floor_number, x_left, width):
		links_over.place(id, floor_number, x_left, width)


## Removes a stairs or escalator half from whichever layer holds it, then lets a stacked half take
## the front layer if the cells are free now.
func _unlink(id: int) -> void:
	if not links.remove(id):
		links_over.remove(id)
	var held := links_over.state_ints()
	for i in range(0, held.size(), 4):
		var run: Array[int] = [held[i + 1], held[i + 2], held[i + 3]]
		if links.place(held[i], run[0], run[1], run[2]):
			links_over.remove(held[i])


## Index of a floor counting upward with no floor 0, so spans count basements: B1 is -1, 1 is 0.
static func _level(floor_number: int) -> int:
	return floor_number if floor_number < 0 else floor_number - 1


## Floors a shaft from bottom to top covers (inclusive; basements count), or 0 if top is not above.
static func shaft_span(bottom: int, top: int) -> int:
	if not GridScript.is_valid_floor(bottom) or not GridScript.is_valid_floor(top):
		return 0
	return maxi(0, _level(top) - _level(bottom) + 1)


func shaft_count() -> int:
	return _shafts.size()


## Shaft id owning grid occupant id, or 0 if it is not a shaft cell.
func _shaft_base(id: int) -> int:
	for shaft: int in _shafts:
		var first: int = _shafts[shaft][4]
		if id >= first and id < first + int(_shafts[shaft][0]):
			return shaft
	return 0


## Floors holding a shaft's machine rooms (#228): the one above the top stop and the one below the
## bottom stop, on the shaft's columns. A shaft whose bottom stop is floor 1 has its lower machine
## room in the ground, so it takes no cell (and no B1). The result leaves out a floor that does not exist.
static func machine_floors(bottom: int, top: int) -> Array[int]:
	var out: Array[int] = []
	var below := floor_below(bottom) if bottom != 1 else 0
	if below != 0:
		out.append(below)
	var above := floor_above(top)
	if above != 0:
		out.append(above)
	return out


## True when a shaft's machine room stands on the cell. Links keep off it; rooms may stand behind it (#272).
func machine_room_at(floor_number: int, column: int) -> bool:
	for shaft: int in _shafts:
		var info: Array = _shafts[shaft]
		var width: int = CatalogueScript.field(kind_of(shaft), "width")
		if column < int(info[2]) or column >= int(info[2]) + width:
			continue
		var top := _floor_at_offset(int(info[1]), int(info[0]) - 1)
		if machine_floors(int(info[1]), top).has(floor_number):
			return true
	return false


## The floor offset floors above bottom (basements count, floor 1 follows B1).
static func _floor_at_offset(bottom: int, offset: int) -> int:
	var level := bottom
	for i in offset:
		level = floor_above(level)
	return level


## Checks a shaft: kind is a catalogue id with the shaft placement, bottom and top are floor
## numbers (inclusive). Returns {"reason", "cost", "span", "floor_units"}. Needs 1 to 30 floors
## (express: any height), fewer than 24 shafts, a machine room cell above the top and below the
## bottom (see machine_floors) free of links (rooms and the lobby may stand behind, #272), nothing else in the way (rooms on the
## shaft's own floors are fine, as for stairs), and floor to rest on. Floor units missing under
## the shaft or its machine rooms are built at FLOOR_COST_PER_UNIT each, which the cost includes
## (with the shaft's price when priced; a resize passes false). A missing unit with nothing to
## rest on, even once the others are built, is NO_FLOOR_FOR_SHAFT.
func check_place_shaft(grid: GridScript, floors: FloorsScript, kind: String, bottom: int, top: int, x_left: int, priced: bool = true) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "span": 0, "floor_units": 0}
	if not CatalogueScript.IDS.has(kind) or CatalogueScript.field(kind, "placement") != CatalogueScript.PLACE_SHAFT:
		result["reason"] = UNKNOWN_KIND
		return result
	if not GridScript.is_valid_floor(bottom) or not GridScript.is_valid_floor(top):
		result["reason"] = BAD_FLOOR
		return result
	var span := shaft_span(bottom, top)
	result["span"] = span
	if span == 0:
		result["reason"] = BAD_SHAFT_SPAN
		return result
	if kind != "express_shaft" and span > SHAFT_FLOOR_LIMIT:
		result["reason"] = MAX_SHAFT_FLOORS
		return result
	if _shafts.size() >= int(CatalogueScript.field(kind, "limit")):
		result["reason"] = MAX_SHAFTS
		return result
	if (bottom != 1 and floor_below(bottom) == 0) or floor_above(top) == 0:
		result["reason"] = NO_MACHINE_ROOM
		return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	var stops: Array[int] = []
	var level := bottom
	for i in span:
		stops.append(level)
		level = floor_above(level)
	var machines := machine_floors(bottom, top)
	for column in range(x_left, x_left + width):
		for stop: int in stops:
			if floors.has_shaft(stop, column):
				result["reason"] = OVER_SHAFT
				return result
			if links.cell_at(stop, column) != GridScript.EMPTY or machine_room_at(stop, column):
				result["reason"] = OVERLAPS_LINK
				return result
		for machine: int in machines:
			if floors.has_shaft(machine, column):
				result["reason"] = OVER_SHAFT
				return result
			if links.cell_at(machine, column) != GridScript.EMPTY or machine_room_at(machine, column):
				result["reason"] = OVERLAPS_LINK
				return result
	var cells: Array[int] = []
	cells.append_array(stops)
	cells.append_array(machines)
	var new_units := 0
	for column in range(x_left, x_left + width):
		for cell: int in cells:
			if floors.has_floor(cell, column):
				continue
			new_units += 1
			if not _rests_on_floor(floors, cells, cell, column):
				result["reason"] = NO_FLOOR_FOR_SHAFT
				return result
	result["floor_units"] = new_units
	result["cost"] = (CatalogueScript.cost(kind) if priced else 0) + new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	return result


## True when the floor unit at (cell, column), not built yet, would rest on floor: the ground
## floor always does, floors above it rest on the floor below, basements on the floor above (B1 on
## floor 1). What it rests on may be built or be another cell of the same shaft.
func _rests_on_floor(floors: FloorsScript, cells: Array[int], cell: int, column: int) -> bool:
	if cell == 1:
		return true
	var support := floor_below(cell) if cell > 1 else floor_above(cell)
	return floors.has_floor(support, column) or cells.has(support)


## Places a shaft (the PLACE_SHAFT command): kind_index, bottom, top, x_left. One ledger charge
## (the catalogue price, however tall, plus any floor built under the shaft and its machine
## rooms), ref = the catalogue index. Returns OK or a reason code.
func place_shaft(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, bottom: int, top: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_place_shaft(grid, floors, kind, bottom, top, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var span: int = checked["span"]
	var width: int = CatalogueScript.field(kind, "width")
	_fill_shaft_floors(floors, bottom, top, x_left, width)
	var clear := false
	while not clear:  # _next_id only grows, so this ends once a free run of span ids is found
		clear = true
		for i in span:
			if _id_taken(grid, _next_id + i):
				_next_id += i + 1
				clear = false
				break
	var level := bottom
	for i in span:
		links.place(_next_id + i, level, x_left, width)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column)
		level = floor_above(level)
	_kind_of[_next_id] = kind_index
	_shafts[_next_id] = [span, bottom, x_left, [] as Array[int], _next_id]
	_next_id += span
	return OK


## Builds the floor units missing under a shaft's stops and machine rooms (already priced).
func _fill_shaft_floors(floors: FloorsScript, bottom: int, top: int, x_left: int, width: int) -> void:
	var cells: Array[int] = machine_floors(bottom, top)
	var level := bottom
	for i in shaft_span(bottom, top):
		cells.append(level)
		level = floor_above(level)
	for cell: int in cells:
		floors.fill_span(cell, x_left, x_left + width - 1)


## Occupant cells and marks of a shaft: base id, span floors from bottom, x_left, width.
func _put_shaft_cells(grid: GridScript, floors: FloorsScript, base: int, bottom: int, span: int, x_left: int, width: int) -> void:
	var level := bottom
	for i in span:
		links.place(base + i, level, x_left, width)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column)
		level = floor_above(level)


func _clear_shaft_cells(grid: GridScript, floors: FloorsScript, base: int, bottom: int, span: int, x_left: int, width: int) -> void:
	var level := bottom
	for i in span:
		links.remove(base + i)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column, false)
		level = floor_above(level)


## True when floor lies within the shaft's span.
func _in_shaft_span(info: Array, floor_number: int) -> bool:
	if not GridScript.is_valid_floor(floor_number):
		return false
	var offset := _level(floor_number) - _level(info[1])
	return offset >= 0 and offset < int(info[0])


## Resizes a shaft in place (the RESIZE_SHAFT command): shaft id, new bottom, new top, same
## column. Same rules as placement, but nothing is charged for the shaft itself: only floor units
## missing under the new stops or machine rooms are built, at the floor price (#228). Stop flags of floors that
## remain are kept; new floors are stops. The occupant ids move to a new base when the old one
## has no room to grow. Calls and cars (#93, #94) must drop the removed floors here.
func resize_shaft(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, id: int, bottom: int, top: int) -> int:
	if not _shafts.has(id):
		return NOTHING_THERE
	var info: Array = _shafts[id]
	var kind: String = kind_of(id)
	var width: int = CatalogueScript.field(kind, "width")
	var old_span: int = info[0]
	var old_bottom: int = info[1]
	var x_left: int = info[2]
	var old_base: int = info[4]
	_clear_shaft_cells(grid, floors, old_base, old_bottom, old_span, x_left, width)
	_shafts.erase(id)
	var checked := check_place_shaft(grid, floors, kind, bottom, top, x_left, false)
	var reason: int = checked["reason"]
	if reason == OK and checked["cost"] > ledger.balance:
		reason = SHORT_OF_FUNDS
	if reason == OK:
		for car: Array in _cars:
			if car[CarsScript.SHAFT] == id and not _in_shaft_span([checked["span"], bottom], car[CarsScript.HOME]):
				reason = HOME_DROPPED
	if reason != OK:
		_put_shaft_cells(grid, floors, old_base, old_bottom, old_span, x_left, width)
		_shafts[id] = info
		return reason
	if checked["cost"] > 0:
		ledger.charge(at_tick, checked["cost"], _kind_of[id])
	_fill_shaft_floors(floors, bottom, top, x_left, width)
	var span: int = checked["span"]
	var base := old_base
	var clear := false
	while not clear:
		clear = true
		for i in span:
			if _id_taken(grid, base + i):
				base = _next_id
				_next_id += span
				clear = false
				break
	_put_shaft_cells(grid, floors, base, bottom, span, x_left, width)
	var off: Array[int] = []
	for floor_number: int in info[3]:
		if _in_shaft_span([span, bottom], floor_number):
			off.append(floor_number)
	_shafts[id] = [span, bottom, x_left, off, base]
	for n in _cars.size():
		var car: Array = _cars[n]
		if car[CarsScript.SHAFT] == id and (not _in_shaft_span([span, bottom], car[CarsScript.FLOOR]) or (car[CarsScript.STATE] != CarsScript.IDLE and not _in_shaft_span([span, bottom], car[CarsScript.TARGET]))):
			car[CarsScript.FLOOR] = car[CarsScript.HOME]
			car[CarsScript.LOAD] = 0
			_riders[n] = []
			_stops[n] = []
			CarsScript.idle(car)
	for n in range(_queue.size() - 1, -1, -1):
		if _queue[n][1] == id and not is_stop(id, _queue[n][2]):
			_queue.remove_at(n)
	for n in range(_calls.size() - 1, -1, -1):
		if _calls[n][CarsScript.CALL_SHAFT] == id:
			_calls[n][CarsScript.CALL_CAR] = -1
			if not is_stop(id, _calls[n][CarsScript.CALL_FLOOR]):
				_calls.remove_at(n)
	return OK


## Cars in a shaft.
func car_count(shaft_id: int) -> int:
	var total := 0
	for car: Array in _cars:
		if car[CarsScript.SHAFT] == shaft_id:
			total += 1
	return total


## People a car holds; the 18th boarder waits for the next car.
## Pass a shaft id for an express shaft's 36.
func car_capacity(shaft_id: int = 0) -> int:
	return EXPRESS_CAR_CAPACITY if _shafts.has(shaft_id) and kind_of(shaft_id) == "express_shaft" else CAR_CAPACITY


## Cars of a shaft, oldest first: each an array indexed by the CarsScript constants (SHAFT to NEXT).
func cars_of(shaft_id: int) -> Array:
	var result: Array = []
	for car: Array in _cars:
		if car[CarsScript.SHAFT] == shaft_id:
			result.append(car.duplicate())
	return result


## Indexes (as for riders_of) of a shaft's cars, oldest first.
func car_indexes_of(shaft_id: int) -> Array[int]:
	var result: Array[int] = []
	for n in _cars.size():
		if _cars[n][CarsScript.SHAFT] == shaft_id:
			result.append(n)
	return result


## Adds a car (the ADD_CAR command): shaft id, home floor. Local and service shafts only; at most
## MAX_CARS_PER_SHAFT and the star cap; home must be a stop. Charges the catalogue car price.
func add_car(ledger: LedgerScript, at_tick: int, stars: int, shaft_id: int, home: int) -> int:
	if not _shafts.has(shaft_id):
		return NOTHING_THERE
	var shaft_kind: String = kind_of(shaft_id)
	if not shaft_kind.ends_with("_shaft"):
		return NO_CARS_HERE
	var count := car_count(shaft_id)
	if count >= MAX_CARS_PER_SHAFT:
		return MAX_CARS
	if count >= CARS_BY_STAR[clampi(stars, 1, 5) - 1]:
		return STAR_CAR_CAP
	if not is_stop(shaft_id, home):
		return BAD_HOME_FLOOR
	var car_index: int = CatalogueScript.IDS.find(shaft_kind.replace("_shaft", "_car"))
	if ledger.charge(at_tick, int(CatalogueScript.field(CatalogueScript.IDS[car_index], "cost")), car_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	_cars.append([shaft_id, home, home, 0, 0, 0, 0, 0, 0])
	_riders.append([])
	_stops.append([])
	_heading.append(0)
	return OK


## Removes the shaft's newest car (the REMOVE_CAR command). No refund.
func remove_car(shaft_id: int) -> int:
	for n in range(_cars.size() - 1, -1, -1):
		if _cars[n][CarsScript.SHAFT] == shaft_id:
			_drop_car(n)
			return OK
	return NOTHING_THERE


## Moves a car's home floor (the SET_CAR_HOME command): shaft id, the car's place among the shaft's
## cars (0 is the oldest), the new home, which must be a stop. An idle car heads there after IDLE_DWELL.
func set_car_home(shaft_id: int, nth: int, home: int) -> int:
	var seen := 0
	for car: Array in _cars:
		if car[CarsScript.SHAFT] != shaft_id:
			continue
		if seen == nth:
			if not is_stop(shaft_id, home):
				return BAD_HOME_FLOOR
			car[CarsScript.HOME] = home
			return OK
		seen += 1
	return NO_SUCH_CAR


## The slot (0 to 5) for a day type and the clock's 1-based period (1 to 6): weekday 0, weekend 1;
## the 6 clock periods fall in morning (1, 2), midday (3, 4) and evening (5, 6).
static func slot_for(weekend: bool, clock_period: int) -> int:
	return (SCHEDULE_PERIODS if weekend else 0) + clampi((clock_period - 1) >> 1, 0, SCHEDULE_PERIODS - 1)


## A shaft's schedule: SCHEDULE_INTS ints, defaults (all zero) when never set.
func schedule_of(shaft_id: int) -> Array[int]:
	var out: Array[int] = []
	if _schedules.has(shaft_id):
		out.append_array(_schedules[shaft_id] as Array[int])
	else:
		out.resize(SCHEDULE_INTS)
		out.fill(0)
	return out


## One field (MODE 0, RESPONSE 1, WAIT 2) of a shaft's schedule slot.
func schedule_field(shaft_id: int, slot: int, field: int) -> int:
	if not _schedules.has(shaft_id) or slot < 0 or slot >= SCHEDULE_SLOTS or field < 0 or field >= SCHEDULE_FIELDS:
		return 0
	return _schedules[shaft_id][slot * SCHEDULE_FIELDS + field]


## Sets a slot (the SET_SCHEDULE command): shaft id, slot, mode, response distance, departure wait
## in sim seconds. The wait clamps to MAX_WAIT and the distance to 0..MAX_RESPONSE.
func set_schedule(shaft_id: int, slot: int, mode: int, response: int, wait: int) -> int:
	if not _shafts.has(shaft_id):
		return NOTHING_THERE
	if slot < 0 or slot >= SCHEDULE_SLOTS or mode < MODE_NORMAL or mode > MODE_BOTTOM:
		return BAD_SCHEDULE
	var values: Array[int] = schedule_of(shaft_id)
	values[slot * SCHEDULE_FIELDS] = mode
	values[slot * SCHEDULE_FIELDS + 1] = clampi(response, 0, MAX_RESPONSE)
	values[slot * SCHEDULE_FIELDS + 2] = clampi(wait, 0, MAX_WAIT)
	var plain := true
	for value in values:
		plain = plain and value == 0
	if plain:
		_schedules.erase(shaft_id)
	else:
		_schedules[shaft_id] = values
	return OK


## Turns a shaft's stop on a floor on or off (the SET_SHAFT_STOP command). Refused if the floor
## is outside the span, or if switching it off would leave fewer than MIN_STOPS stops. A disabled floor is passed, not stopped at.
func set_shaft_stop(id: int, floor_number: int, on: bool) -> int:
	if not _shafts.has(id) or not _in_shaft_span(_shafts[id], floor_number):
		return NOT_IN_SHAFT
	if on and not _express_ok(id, floor_number):
		return EXPRESS_NO_STOP
	var off: Array[int] = _shafts[id][3]
	if not on and is_stop(id, floor_number) and stops_of(id).size() <= MIN_STOPS:
		return TOO_FEW_STOPS
	if not on:
		for car: Array in _cars:
			if car[CarsScript.SHAFT] == id and car[CarsScript.HOME] == floor_number:
				return HOME_STOP
	off.erase(floor_number)
	if not on:
		off.append(floor_number)
		off.sort()
		for n in range(_calls.size() - 1, -1, -1):
			if _calls[n][CarsScript.CALL_SHAFT] == id and _calls[n][CarsScript.CALL_FLOOR] == floor_number:
				_calls.remove_at(n)
		for n in range(_queue.size() - 1, -1, -1):
			if _queue[n][1] == id and _queue[n][2] == floor_number:
				_queue.remove_at(n)
	return OK


## Sends a car to a floor (the seam for dispatch, #93). The car must be idle; the floor a stop.
## Returns OK, NO_SUCH_CAR (bad index or the car is busy) or NOT_A_STOP. See cars.gd.
func send_car(car_index: int, floor_number: int) -> int:
	if car_index < 0 or car_index >= _cars.size() or _cars[car_index][CarsScript.STATE] != CarsScript.IDLE:
		return NO_SUCH_CAR
	if not is_stop(_cars[car_index][CarsScript.SHAFT], floor_number):
		return NOT_A_STOP
	CarsScript.start(_cars[car_index], floor_number, CarsScript.units_per_floor(kind_of(_cars[car_index][CarsScript.SHAFT])))
	return OK


## Removes car n, unassigning its calls and renumbering the others' assignments.
func _drop_car(n: int) -> void:
	_cars.remove_at(n)
	_riders.remove_at(n)
	_stops.remove_at(n)
	_heading.remove_at(n)
	for call: Array in _calls:
		if call[CarsScript.CALL_CAR] == n:
			call[CarsScript.CALL_CAR] = -1
		elif call[CarsScript.CALL_CAR] > n:
			call[CarsScript.CALL_CAR] -= 1


## Places a hall call (the seam for #94/#95): a shaft, a floor and a direction (CarsScript.UP or
## DOWN). Refuses a non-stop floor (NOT_A_STOP), and UP at the top stop or DOWN at the bottom stop
## (BAD_CALL). A duplicate of a pending call is merged: OK, nothing added. See cars.gd.
func place_call(shaft_id: int, floor_number: int, dir: int) -> int:
	if not is_stop(shaft_id, floor_number):
		return NOT_A_STOP
	var stops := stops_of(shaft_id)
	if (dir != CarsScript.UP and dir != CarsScript.DOWN) or (dir == CarsScript.UP and floor_number == stops[-1]) or (dir == CarsScript.DOWN and floor_number == stops[0]):
		return BAD_CALL
	for call: Array in _calls:
		if call[CarsScript.CALL_SHAFT] == shaft_id and call[CarsScript.CALL_FLOOR] == floor_number and call[CarsScript.CALL_DIR] == dir:
			return OK
	_calls.append([shaft_id, floor_number, dir, -1])
	return OK


## Puts a person in the hall queue of a shaft at a floor, bound for dest_floor (a person counts
## per head), and places a hall call that way. Refuses a non-stop floor or destination
## (NOT_A_STOP), the same floor, or a person already queued (BAD_CALL). Bulldozing a shaft drops
## its queues and riders; those people stay in People and #95 decides where they end up.
func join_queue(person_id: int, shaft_id: int, floor_number: int, dest_floor: int) -> int:
	if not is_stop(shaft_id, floor_number) or not is_stop(shaft_id, dest_floor):
		return NOT_A_STOP
	if floor_number == dest_floor:
		return BAD_CALL
	for entry: Array in _queue:
		if entry[0] == person_id:
			return BAD_CALL
	var result := place_call(shaft_id, floor_number, CarsScript.dir_to(floor_number, dest_floor))
	if result == OK:
		_queue.append([person_id, shaft_id, floor_number, dest_floor])
	return result


## Makes a floor a stop for car n's riders (no duplicates). Refuses a bad car or a non-stop.
func add_car_stop(car_index: int, floor_number: int) -> int:
	if car_index < 0 or car_index >= _cars.size():
		return NO_SUCH_CAR
	if not is_stop(_cars[car_index][CarsScript.SHAFT], floor_number):
		return NOT_A_STOP
	if not _stops[car_index].has(floor_number):
		_stops[car_index].append(floor_number)
	return OK


## Hook called when a rider gets off; #95 connects it to trips. For now it records the event.
func on_alight(person_id: int, floor_number: int) -> void:
	alighted.append([person_id, floor_number])
	if alighted.size() > 256:
		alighted.pop_front()


## Returns and clears the recorded alighters, each [person id, floor].
func take_alighted() -> Array:
	var result := alighted
	alighted = []
	return result


## Ids of people waiting in hall queues, in arrival order.
func queued_ids() -> Array[int]:
	var ids: Array[int] = []
	for entry: Array in _queue:
		ids.append(entry[0])
	return ids


## People waiting at a shaft's floor, in arrival order.
func queue_at(shaft_id: int, floor_number: int) -> Array[int]:
	var ids: Array[int] = []
	for entry: Array in _queue:
		if entry[1] == shaft_id and entry[2] == floor_number:
			ids.append(entry[0])
	return ids


## Person ids riding car n, in boarding order.
func riders_of(car_index: int) -> Array[int]:
	var ids: Array[int] = []
	for rider: Array in _riders[car_index]:
		ids.append(rider[0])
	return ids


## Pending hall calls in arrival order: each [shaft id, floor, dir, assigned car index or -1].
func calls() -> Array:
	return _calls.duplicate(true)


## Number of cars in the tower; car_index in send_car counts them oldest first.
func total_cars() -> int:
	return _cars.size()


## True when the shaft's cars stop at floor (in the span and not disabled).
func is_stop(id: int, floor_number: int) -> bool:
	if not _shafts.has(id) or not _in_shaft_span(_shafts[id], floor_number):
		return false
	var off: Array[int] = _shafts[id][3]
	return not off.has(floor_number) and _express_ok(id, floor_number)


## False for a floor an express shaft never stops at: only lobbies (ground and sky) and basements
## are stops (8.2). Every other shaft kind accepts any floor.
func _express_ok(id: int, floor_number: int) -> bool:
	if kind_of(id) != "express_shaft":
		return true
	return floor_number < 0 or (floors != null and floors.is_lobby_floor(floor_number))


## Ids of every shaft, ascending (routing reads them).
func shaft_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _shafts:
		ids.append(id)
	ids.sort()
	return ids


## The left column of a shaft, or -1 for an unknown shaft. People wait and board here.
func shaft_x(id: int) -> int:
	return int(_shafts[id][2]) if _shafts.has(id) else -1


## True when a car of the shaft is waiting at the floor (#96): idle there, or heading there
## (target, doors at it included) with room inside. A car returning home (#109) is moving, not waiting. A full car passes without stopping.
func car_waiting_at(shaft_id: int, floor_number: int) -> bool:
	for n in _cars.size():
		var car: Array = _cars[n]
		if car[CarsScript.SHAFT] != shaft_id:
			continue
		if car[CarsScript.STATE] == CarsScript.IDLE:
			if car[CarsScript.FLOOR] == floor_number:
				return true
		elif car[CarsScript.TARGET] == floor_number and car[CarsScript.LOAD] < car_capacity(car[CarsScript.SHAFT]) and not CarsScript.going_home(self, n):
			return true
	return false


## Which (shaft, floor) pairs car_waiting_at answers true for, as sorted keys shaft * 1000 + floor + 100.
## One pass over the cars, so a caller asking about many floors can compare two moments cheaply.
func waiting_keys() -> Array[int]:
	var keys: Array[int] = []
	for n in _cars.size():
		var car: Array = _cars[n]
		var floor_number := -1000
		if car[CarsScript.STATE] == CarsScript.IDLE:
			floor_number = car[CarsScript.FLOOR]
		elif car[CarsScript.LOAD] < car_capacity(car[CarsScript.SHAFT]) and not CarsScript.going_home(self, n):
			floor_number = car[CarsScript.TARGET]
		if floor_number != -1000:
			keys.append(int(car[CarsScript.SHAFT]) * 1000 + floor_number + 100)
	keys.sort()
	return keys


## True when the person is queued for a car or riding one.
func in_elevator(person_id: int) -> bool:
	return car_floor_of(person_id) != 0 or queued_ids().has(person_id)


## The floor of the car this person rides, or 0 when they are not riding.
func car_floor_of(person_id: int) -> int:
	for n in _cars.size():
		for rider: Array in _riders[n]:
			if rider[0] == person_id:
				return _cars[n][CarsScript.FLOOR]
	return 0


## Floors the shaft stops at, bottom to top. Car motion (#92) uses this to skip disabled floors.
func stops_of(id: int) -> Array[int]:
	var stops: Array[int] = []
	if not _shafts.has(id):
		return stops
	var off: Array[int] = _shafts[id][3]
	var level: int = _shafts[id][1]
	for i in int(_shafts[id][0]):
		if not off.has(level) and _express_ok(id, level):
			stops.append(level)
		level = floor_above(level)
	return stops


## Removes a room's grid occupants (stairs have two, a shaft one per floor) and clears shaft marks.
func _remove_occupants(grid: GridScript, floors: FloorsScript, id: int) -> void:
	if not is_link_kind(kind_of(id)):
		grid.remove(id)
	if TALL_KINDS.has(kind_of(id)):
		grid.remove(id + 1)
	if is_stair_kind(kind_of(id)):
		_unlink(id)
		_unlink(id + 1)
	if _shafts.has(id):
		var info: Array = _shafts[id]
		var width: int = CatalogueScript.field(kind_of(id), "width")
		var level: int = info[1]
		for i in int(info[0]):
			links.remove(int(info[4]) + i)
		for n in range(_cars.size() - 1, -1, -1):
			if _cars[n][CarsScript.SHAFT] == id:
				_drop_car(n)
		for n in range(_calls.size() - 1, -1, -1):
			if _calls[n][CarsScript.CALL_SHAFT] == id:
				_calls.remove_at(n)
		for n in range(_queue.size() - 1, -1, -1):
			if _queue[n][1] == id:
				_queue.remove_at(n)
		for i in int(info[0]):
			for column in range(info[2], info[2] + width):
				floors.mark_shaft(level, column, false)
			level = floor_above(level)
		_shafts.erase(id)
		_schedules.erase(id)


## True when id is the upper-floor half of a stairs or escalator (not a link of its own).
func is_stairs_upper(id: int) -> bool:
	return _has_link(id) and not _kind_of.has(id) and is_stair_kind(kind_of(id - 1))


## True for the kinds that join a floor to the one above with two grid halves: stairs, escalators.
static func is_stair_kind(kind: String) -> bool:
	return kind == "stairs" or kind == "escalator"


## Marks a room sold (or not). Only a condo can be sold; returns false otherwise. Sales
## themselves come in M3; this lets tests and later code set the flag.
func set_sold(id: int, sold: bool) -> bool:
	if kind_of(id) != "condo":
		return false
	if sold:
		_sold[id] = true
	else:
		_sold.erase(id)
	return true


func is_sold(id: int) -> bool:
	return _sold.has(id)


## Workers or residents a room holds when full (the catalogue's "people"; tenancy fills it).
func people_in(id: int) -> int:
	var kind := kind_of(id)
	if kind == "":
		return 0
	return int(CatalogueScript.row(kind).get("people", 0))


## Checks a bulldoze without changing anything. Returns {"reason", "refund", "room_id",
## "occupants"}: refund is what a sold condo pays back to its buyer (0 otherwise). The ghost (#13)
## uses this.
func check_bulldoze(grid: GridScript, floors: FloorsScript, floor_number: int, x: int) -> Dictionary:
	return _check_remove(grid, floors, floor_number, x, true)


## Which thing a click at a cell picks (#126). A link sits in front of the room behind it, so for
## bulldoze the link wins: bulldoze it first, then click again for the room behind. Replace
## (links_first false) swaps rooms, so it picks the room if there is one and a link only where
## no room is. Returns the same as check_bulldoze.
func _check_remove(grid: GridScript, floors: FloorsScript, floor_number: int, x: int, links_first: bool) -> Dictionary:
	var result := {"reason": OK, "refund": 0, "room_id": 0, "occupants": 0}
	if not GridScript.is_valid_floor(floor_number):
		result["reason"] = BAD_FLOOR
		return result
	var link_id := links.cell_at(floor_number, x)
	var id := grid.cell_at(floor_number, x)
	if link_id != GridScript.EMPTY and (links_first or id == GridScript.EMPTY):
		id = link_id
	if id == GridScript.EMPTY:
		# Links can stand inside a lobby, so only an empty lobby cell is the lobby itself.
		result["reason"] = PERMANENT if floors.has_lobby_at(floor_number, x) else NOTHING_THERE
		return result
	if is_stairs_upper(id) or is_tall_upper(id):
		id -= 1
	if _shaft_base(id) != 0:
		id = _shaft_base(id)
	if not _kind_of.has(id):
		result["reason"] = NOT_A_ROOM
		return result
	var kind := kind_of(id)
	if not CatalogueScript.field(kind, "removable"):
		result["reason"] = PERMANENT
		return result
	result["room_id"] = id
	result["occupants"] = people_in(id)
	if _sold.has(id):
		result["refund"] = CatalogueScript.cost(kind)
	return result


## Removes the room covering the cell, free. Its occupants go (counted in occupants_removed), and
## a sold condo pays its sale price back as a PAYOUT ledger line, even into a negative balance.
## The floor units under the room stay, so a room stacked above keeps its support. Returns OK or
## a reason code, changing nothing on a refusal.
func bulldoze(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, floor_number: int, x: int) -> int:
	var checked := check_bulldoze(grid, floors, floor_number, x)
	if checked["reason"] != OK:
		return checked["reason"]
	var id: int = checked["room_id"]
	occupants_removed += checked["occupants"]
	if checked["refund"] > 0:
		ledger.payout(at_tick, checked["refund"], id)
	_remove_occupants(grid, floors, id)
	_kind_of.erase(id)
	_sold.erase(id)
	return OK


## Destroys a room by disaster (fire, #217; a threat, #218): like a bulldoze but free, whatever the
## kind (security and the like included), and with no refund. A stairs, escalator or shaft goes whole.
## The floor under it stays. The caller clears what other systems hold for the room (Tower.destroy_room).
## Returns false when id is not a room.
func destroy(grid: GridScript, floors: FloorsScript, id: int) -> bool:
	if not _kind_of.has(id):
		return false
	occupants_removed += people_in(id)
	_remove_occupants(grid, floors, id)
	_kind_of.erase(id)
	_sold.erase(id)
	return true


## The floors a room occupies, lowest first: one, two for a stairs, escalator or tall room, every stop
## floor for a shaft. Empty for an id that is not a room.
func floors_of(grid: GridScript, id: int) -> Array[int]:
	var out: Array[int] = []
	if not _kind_of.has(id):
		return out
	if _shafts.has(id):
		var level: int = _shafts[id][1]
		for _i in int(_shafts[id][0]):
			out.append(level)
			level = floor_above(level)
		return out
	var run := run_of(grid, id)
	if run.is_empty():
		return out
	out.append(run[0])
	if is_stair_kind(kind_of(id)) or TALL_KINDS.has(kind_of(id)):
		var above := floor_above(run[0])
		if above != 0:
			out.append(above)
	return out


## Checks a replace without changing anything: the room covering (floor_number, x_left) goes and
## a new room of kind (a catalogue id) takes its place with its left edge at x_left. Returns
## {"reason", "cost", "refund", "net", "room_id", "floor_units"}: cost is the new room's price plus
## missing floor units, refund is a sold condo's payback, and net is cost + refund, the one amount
## the replace charges. The new placement is judged on a copy of the grid with the old room gone.
func check_replace(grid: GridScript, floors: FloorsScript, balance: int, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "refund": 0, "net": 0, "room_id": 0, "floor_units": 0}
	if TALL_KINDS.has(kind):
		result["reason"] = TALL_REPLACE
		return result
	var removal := _check_remove(grid, floors, floor_number, x_left, false)
	if removal["reason"] != OK:
		result["reason"] = removal["reason"]
		return result
	var id: int = removal["room_id"]
	result["room_id"] = id
	result["refund"] = removal["refund"]
	var after: GridScript = GridScript.new()
	after.load_ints(grid.state_ints())
	if not is_link_kind(kind_of(id)):
		after.remove(id)
	if TALL_KINDS.has(kind_of(id)):
		after.remove(id + 1)
	var placed := check_place(after, floors, kind, floor_number, x_left)
	result["cost"] = placed["cost"]
	result["floor_units"] = placed["floor_units"]
	result["net"] = placed["cost"] + removal["refund"]
	if placed["reason"] != OK:
		result["reason"] = placed["reason"]
	elif result["net"] > balance:
		result["reason"] = SHORT_OF_FUNDS
	return result


## Replaces a room in one step (the REPLACE_ROOM command): bulldoze the room covering
## (floor_number, x_left), then place kind_index there. All or nothing: on any refusal the old room
## stays and money is unchanged. The sold-condo payback and the new cost are one CHARGE line.
func replace_room(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, floor_number: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_replace(grid, floors, ledger.balance, kind, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	var id: int = checked["room_id"]
	if ledger.charge(at_tick, checked["net"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	occupants_removed += people_in(id)
	_remove_occupants(grid, floors, id)
	_kind_of.erase(id)
	_sold.erase(id)
	var width: int = CatalogueScript.field(kind, "width")
	floors.fill_span(floor_number, x_left, x_left + width - 1)
	while _id_taken(grid, _next_id):
		_next_id += 1
	grid.place(_next_id, floor_number, x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 1
	return OK


## Flat ints for hashing and saving: next id, count, then (id, kind index, sold) triples ordered
## by id, then occupants_removed.
func state_ints() -> Array[int]:
	var ids: Array = _kind_of.keys()
	ids.sort()
	var ints: Array[int] = [_next_id, ids.size()]
	for id: int in ids:
		ints.append_array([id, _kind_of[id], 1 if _sold.has(id) else 0] as Array[int])
	ints.append(occupants_removed)
	var bases: Array = _shafts.keys()
	bases.sort()
	ints.append(bases.size())
	for base: int in bases:
		ints.append_array([base, _shafts[base][0], _shafts[base][1], _shafts[base][2], _shafts[base][4], _shafts[base][3].size()] as Array[int])
		ints.append_array(_shafts[base][3] as Array[int])
	ints.append(_cars.size())
	for car: Array in _cars:
		ints.append_array(car as Array[int])
	ints.append(_calls.size())
	for call: Array in _calls:
		ints.append_array(call as Array[int])
	ints.append(_queue.size())
	for entry: Array in _queue:
		ints.append_array(entry as Array[int])
	for n in _cars.size():
		ints.append_array([_heading[n], _stops[n].size()] as Array[int])
		ints.append_array(_stops[n] as Array[int])
		ints.append(_riders[n].size())
		for rider: Array in _riders[n]:
			ints.append_array(rider as Array[int])
	var scheduled: Array = _schedules.keys()
	scheduled.sort()
	ints.append(scheduled.size())
	for shaft_id: int in scheduled:
		ints.append(shaft_id)
		ints.append_array(_schedules[shaft_id] as Array[int])
	var link_ints := links.state_ints()
	ints.append(link_ints.size())
	ints.append_array(link_ints)
	var over_ints := links_over.state_ints()
	ints.append(over_ints.size())
	ints.append_array(over_ints)
	return ints


## Restores state_ints(). Returns false, changing nothing, for data that is not valid.
func load_ints(ints: Array) -> bool:
	if not valid_ints(ints, null):
		return false
	_kind_of = {}
	_sold = {}
	for i in range(ints[1]):
		_kind_of[ints[2 + 3 * i]] = ints[3 + 3 * i]
		if ints[4 + 3 * i] == 1:
			_sold[ints[2 + 3 * i]] = true
	occupants_removed = ints[2 + 3 * ints[1]]
	_shafts = {}
	var at: int = 4 + 3 * ints[1]
	for i in range(ints[at - 1]):
		var off: Array[int] = []
		for j in range(ints[at + 5]):
			off.append(ints[at + 6 + j])
		_shafts[ints[at]] = [ints[at + 1], ints[at + 2], ints[at + 3], off, ints[at + 4]]
		at += 6 + ints[at + 5]
	_cars = []
	for i in range(ints[at]):
		_cars.append(ints.slice(at + 1 + CAR_INTS * i, at + 1 + CAR_INTS * (i + 1)))
	at += 1 + CAR_INTS * _cars.size()
	_calls = []
	for i in range(ints[at]):
		_calls.append(ints.slice(at + 1 + 4 * i, at + 5 + 4 * i))
	at += 1 + 4 * _calls.size()
	_queue = []
	for i in range(ints[at]):
		_queue.append(ints.slice(at + 1 + 4 * i, at + 5 + 4 * i))
	at += 1 + 4 * _queue.size()
	_riders = []
	_stops = []
	_heading = []
	for n in _cars.size():
		_heading.append(ints[at])
		_stops.append(ints.slice(at + 2, at + 2 + ints[at + 1]))
		at += 2 + ints[at + 1]
		var riders: Array = []
		for i in range(ints[at]):
			riders.append(ints.slice(at + 1 + 2 * i, at + 3 + 2 * i))
		_riders.append(riders)
		at += 1 + 2 * riders.size()
	_schedules = {}
	for i in range(ints[at]):
		_schedules[ints[at + 1]] = ints.slice(at + 2, at + 2 + SCHEDULE_INTS)
		at += 1 + SCHEDULE_INTS
	at += 1
	links.load_ints(ints.slice(at + 1, at + 1 + ints[at]))
	at += 1 + ints[at]
	links_over.load_ints(ints.slice(at + 1, at + 1 + ints[at]))
	alighted = []
	_next_id = ints[0]
	return true


## True when ints is a valid state_ints() result. With a grid, every room must be placed in it.
static func valid_ints(ints: Array, grid: GridScript) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 2 or ints[1] < 0 or ints.size() < 4 + 3 * ints[1] or ints[0] < 1 or ints[2 + 3 * ints[1]] < 0:
		return false
	var shaft_total: int = ints[3 + 3 * ints[1]]
	if shaft_total < 0:
		return false
	var at: int = 4 + 3 * ints[1]
	var shaft_ids: Dictionary = {}
	var shaft_tops: Array[int] = []
	for i in range(shaft_total):
		if at + 6 > ints.size() or ints[at + 5] < 0 or at + 6 + ints[at + 5] > ints.size():
			return false
		var base: int = ints[at + 4]
		var span: int = ints[at + 1]
		if ints[at] < 1 or base < 1 or span < 1 or span > GridScript.FLOOR_COUNT or not GridScript.is_valid_floor(ints[at + 2]):
			return false
		shaft_tops.append(base + span - 1)
		shaft_ids[ints[at]] = true
		at += 6 + ints[at + 5]
	if at >= ints.size() or ints[at] < 0 or at + 1 + CAR_INTS * ints[at] >= ints.size():
		return false
	var car_total: int = ints[at]
	at += 1 + CAR_INTS * ints[at]
	if ints[at] < 0 or at + 1 + 4 * ints[at] >= ints.size():
		return false
	at += 1 + 4 * ints[at]
	if ints[at] < 0 or at + 1 + 4 * ints[at] > ints.size():
		return false
	at += 1 + 4 * ints[at]
	for n in range(car_total):
		if at + 2 > ints.size() or ints[at + 1] < 0 or at + 3 + ints[at + 1] > ints.size():
			return false
		at += 2 + ints[at + 1]
		if ints[at] < 0 or at + 1 + 2 * ints[at] > ints.size():
			return false
		at += 1 + 2 * ints[at]
	if at >= ints.size() or ints[at] < 0 or at + 1 + (1 + SCHEDULE_INTS) * ints[at] >= ints.size():
		return false
	var schedule_total: int = ints[at]
	for i in range(schedule_total):
		if not shaft_ids.has(ints[at + 1 + (1 + SCHEDULE_INTS) * i]):
			return false
		for k in SCHEDULE_INTS:
			var value: int = ints[at + 2 + (1 + SCHEDULE_INTS) * i + k]
			var field: int = k % SCHEDULE_FIELDS
			if value < 0 or (field == 0 and value > MODE_BOTTOM) or (field == 1 and value > MAX_RESPONSE) or (field == 2 and value > MAX_WAIT):
				return false
	at += 1 + (1 + SCHEDULE_INTS) * schedule_total
	if at >= ints.size() or ints[at] < 0 or at + 1 + ints[at] >= ints.size():
		return false
	var link_end: int = at + 1 + ints[at]
	if ints[link_end] < 0 or link_end + 1 + ints[link_end] != ints.size():
		return false
	var link_grid := GridScript.new()
	if not link_grid.load_ints(ints.slice(at + 1, link_end)):
		return false
	var over_grid := GridScript.new()
	if not over_grid.load_ints(ints.slice(link_end + 1)):
		return false
	if grid != null:
		for top in shaft_tops:
			if not link_grid.has_occupant(top):
				return false
	for i in range(ints[1]):
		var id: int = ints[2 + 3 * i]
		var kind_index: int = ints[3 + 3 * i]
		var sold: int = ints[4 + 3 * i]
		if id < 1 or kind_index < 0 or kind_index >= CatalogueScript.IDS.size() or (sold != 0 and sold != 1):
			return false
		var is_link := is_link_kind(CatalogueScript.IDS[kind_index])
		if grid != null and not shaft_ids.has(id) and not ((link_grid.has_occupant(id) or over_grid.has_occupant(id)) if is_link else grid.has_occupant(id)):
			return false
		if grid != null and is_stair_kind(CatalogueScript.IDS[kind_index]) and not (link_grid.has_occupant(id + 1) or over_grid.has_occupant(id + 1)):
			return false
		if grid != null and TALL_KINDS.has(CatalogueScript.IDS[kind_index]) and not grid.has_occupant(id + 1):
			return false
	return true
