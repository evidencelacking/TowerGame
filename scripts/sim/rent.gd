class_name Rent
extends RefCounted
## Rent levels (5.3). A rentable room (office) has four rent levels, set per unit by the SET_RENT
## command. Each level has a rent in the catalogue row ("rent": four dollar amounts, lowest to
## highest) and a stress offset below. A higher rent adds stress to the room's average, so the same
## real stress gives a worse grade (docs/gameplay-reference.md: higher rent, harsher evaluation).
## Rent is collected once a quarter from each rentable room that has workers (offices) or, for an apartment, residents. Condos cannot
## have their rent changed (the reference). Hotel rooms also have the four levels, but their amount is
## the nightly price, paid at check-out by Hotel (never by collect); shops are not rented by level.
##
## The levels run lowest (blue), green, yellow (default, "average"), highest (red). The lowest
## level is meant to make tenants effectively never leave (never_leaves); nothing moves tenants out
## yet, so that is a query for later work (#36, review in M12).
##
## All amounts here and in the catalogue are UNVERIFIED tunables: the reference gives no per-level
## rents (only $15,000 for an office at the top level), and no stress numbers.
##
## Saved state: the rooms whose level was changed from the default, as (room id, level) pairs.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const LEVELS := 4
const LEVEL_LOW := 0  ## Blue.
const LEVEL_GREEN := 1
const LEVEL_YELLOW := 2  ## The default.
const LEVEL_HIGH := 3  ## Red.
const DEFAULT_LEVEL := LEVEL_YELLOW

## Extra stress added to a room's average at each level (negative relieves it). Tunable.
const STRESS_OFFSET: Array[int] = [-30, -15, 0, 30]

## Results of set_rent().
const OK := 0
const NO_SUCH_ROOM := 1
const NOT_RENTABLE := 2  ## The room kind has no rent levels.
const CONDO_LOCKED := 3  ## Condo rent cannot be changed after purchase.
const BAD_LEVEL := 4  ## Not 0 to 3.

var _rooms: RoomsScript  ## For the grade modifier. Not a back-reference to Tower: that would be a leak cycle.
var _levels: Dictionary = {}  ## Room id -> level, only for rooms set to a non-default level.


func _init(rooms: RoomsScript = null) -> void:
	_rooms = rooms


## The grade modifier registered with Grades: stress_offset for this tower's rooms.
func grade_modifier(room: int) -> int:
	return stress_offset(_rooms, room)


## True if the kind has rent levels (a "rent" list in its catalogue row).
static func is_rentable(kind: String) -> bool:
	var rents: Array = CatalogueScript.row(kind).get("rent", [])
	return not rents.is_empty()


## The level of the room: its set level, or the default.
func level_of(room: int) -> int:
	return _levels.get(room, DEFAULT_LEVEL)


## Dollars per quarter at the room's level, or 0 if the room is not rentable.
func rent_of(rooms: RoomsScript, room: int) -> int:
	var rents: Array = CatalogueScript.row(rooms.kind_of(room)).get("rent", [])
	if rents.is_empty():
		return 0
	return rents[level_of(room)]


## Extra stress for the room from its rent level; 0 for rooms that are not rentable.
func stress_offset(rooms: RoomsScript, room: int) -> int:
	if not is_rentable(rooms.kind_of(room)):
		return 0
	return STRESS_OFFSET[level_of(room)]


## True if the room is at the lowest rent level, whose tenants never leave (reference).
func never_leaves(rooms: RoomsScript, room: int) -> bool:
	return is_rentable(rooms.kind_of(room)) and level_of(room) == LEVEL_LOW


## Sets the room's level. Returns OK or a refusal reason; changes nothing on a refusal.
func set_rent(rooms: RoomsScript, room: int, level: int) -> int:
	if not rooms.has_room(room):
		return NO_SUCH_ROOM
	var kind := rooms.kind_of(room)
	if kind == "condo":
		return CONDO_LOCKED
	if not is_rentable(kind):
		return NOT_RENTABLE
	if level < 0 or level >= LEVELS:
		return BAD_LEVEL
	if level == DEFAULT_LEVEL:
		_levels.erase(room)
	else:
		_levels[room] = level
	return OK


## Forgets a room's level (it was bulldozed or replaced).
func remove_room(room: int) -> void:
	_levels.erase(room)


## One day's share of a quarterly rent (#261): a third each day, and the last day of the quarter
## takes the rest, so a tenant who stays all quarter pays exactly the quarterly figure.
static func day_share(quarterly: int, last_day: bool) -> int:
	var third := quarterly / ClockScript.DAYS_PER_QUARTER
	return quarterly - third * (ClockScript.DAYS_PER_QUARTER - 1) if last_day else third


## Credits one day's rent for every rentable room that has tenants (last_day: the quarter's
## closing day, which pays the remainder). A tenant who has left pays nothing from then on.
## Returns the total.
func collect(rooms: RoomsScript, people: PeopleScript, ledger: LedgerScript, at_tick: int, last_day: bool = true, bonus_percent: int = 0) -> int:
	var total := 0
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if is_rentable(kind) and not rooms.is_charred(id) and not rooms.is_cut_off(id) and (people.homes_in(id) if kind == "apartment" else people.workers_in(id)) > 0:
			var amount := day_share(rent_of(rooms, id), last_day)
			if kind != "apartment":  # the metro bonus is for offices; an apartment pays its level's rent (#379)
				amount += amount * bonus_percent / 100  # a connected tower (a metro station) rents for more (synergy.gd)
			ledger.income(at_tick, amount, id)
			total += amount
	return total


func state_ints() -> Array[int]:
	var ids: Array = _levels.keys()
	ids.sort()
	var ints: Array[int] = [ids.size()]
	for id: int in ids:
		ints.append(id)
		ints.append(_levels[id])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.is_empty() or typeof(ints[0]) != TYPE_INT or ints[0] < 0 or ints.size() != 1 + 2 * ints[0]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for k in range(2, ints.size(), 2):
		if ints[k] < 0 or ints[k] >= LEVELS:
			return false
	return true


func load_ints(ints: Array) -> void:
	_levels.clear()
	for k in range(1, ints.size(), 2):
		_levels[ints[k]] = ints[k + 1]
