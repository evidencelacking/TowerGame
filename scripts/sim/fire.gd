class_name Fire
extends RefCounted
## Fire (M9 9.2, #217): the first real event kind. Integers only; its own seeded stream.
##
## Gate (through Events): 3 stars or more, and at least one security office. Odds: [4%] a day, rolled
## each period (CHANCE per 100,000 per period, CHANCE_DEN), so about 4% over the six periods.
## When the event opens the fire starts in one random room, preferring a room people live or work in.
## The owner may pay $500,000 (choice 1) for a rescue craft: it arrives one period after the answer,
## puts out every fire, and the first two rooms that were burning (oldest first) are lost.
## Otherwise (decline, or no answer before the event times out) the fire is left to the guards.
##
## Each burning room:
##  - is put out when guards reach it: the nearest covering office's response time (Security) after
##    it ignited; a floor no office covers has no guards;
##  - each period start rolls [35%] to ignite the room on either side and the room above;
##  - is burned out [after 3 periods] of burning (#373): it stays standing but charred, uninhabitable (no
##    tenants, rent, sales or guests: Rooms.is_charred) until the owner pays to repair it (Tower.repair_room,
##    half its build cost) or bulldozes it. Fire never reignites a charred room.
## A newly charred room is handed to Tower (take_burned) so people, rent, shops and the hotel let go of it.
##
## Saved: the stream, the last event adopted and last answer read, the rescue tick, each burning
## room as [room id, periods burned, tick the guards arrive or 0], then the count and ids of charred rooms.

const ClockScript := preload("res://scripts/sim/clock.gd")
const EventsScript := preload("res://scripts/sim/events.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const KIND := 101  ## The event kind id in Events.kinds.
const SEED_SALT := 0x46495245  ## "FIRE".
const CHANCE := 670  ## Per period, out of CHANCE_DEN: about 4% over a day's six periods.
const CHANCE_DEN := 100000
const MIN_STARS := 3
const SPREAD_PERCENT := 35  ## Chance per period that a burning room ignites each neighbour.
const BURN_PERIODS := 3  ## Periods of burning before a room is destroyed.
const RESCUE_COST := 500000  ## Dollars.
const RESCUE_LOST := 2  ## Rooms already burning that the rescue craft cannot save.
const PAY := 1  ## The choice that calls the rescue craft.
const TIMEOUT := 600  ## Ticks the owner has to choose (one rush period).
const FIELDS := 3  ## Ints per burning room.
const HEADER := 5  ## Ints before the burning rooms.
const REPAIR_PERCENT := 50  ## Repairing a charred room costs this percent of its build cost (owner to confirm).

var _rooms: Rooms
var _rng := Rng.new()
var _seen: int = 0  ## Id of the last fire event started.
var _read: int = 0  ## Id of the last fire event whose answer was read.
var _rescue_at: int = 0  ## Tick the rescue craft arrives, 0 for none.
var _burning: Array[Array] = []  ## [room id, periods burned, guards arrive tick or 0], oldest first.
var _burned: Array[int] = []  ## Rooms charred since Tower last took them (not saved).


func _init(rooms: Rooms = null) -> void:
	_rooms = rooms


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The event kind to register in Events.kinds. Its chance is gated: 0 without a security office.
func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.FIRE, "chance": CHANCE, "chance_den": CHANCE_DEN, "chance_of": _gate,
		"min_stars": MIN_STARS, "choices": 2, "timeout": TIMEOUT, "floor": 0, "costs": [0, RESCUE_COST],
		"title": "Fire!",
		"text": "A fire has broken out in the tower. Guards from a security office within reach will put it out, but a floor no office covers has no guards. A burning room is burned out after three periods and stands charred, empty and earning nothing until you pay to repair it. The fire spreads to rooms beside and above.\nAn outside fire company costs $500,000: it arrives in about one period and puts out every fire, but the first two rooms that burned are lost.",
		"labels": ["Leave it to the guards", "Call the fire company ($500,000)"]}


func _gate() -> int:
	return chance(_rooms)


## The chance now: the fire's odds with a security office, none without.
func chance(rooms: Rooms) -> int:
	return CHANCE if Security.threats_possible(rooms) else 0


func burning_rooms() -> Array[int]:
	var ids: Array[int] = []
	for entry in _burning:
		ids.append(entry[0])
	return ids


func is_burning(room: int) -> bool:
	for entry in _burning:
		if entry[0] == room:
			return true
	return false


## The tick the rescue craft arrives, or 0.
func rescue_at() -> int:
	return _rescue_at


## Rooms charred since the last call; Tower clears their other state.
func take_burned() -> Array[int]:
	var out := _burned
	_burned = []
	return out


## Charred rooms, lowest id first.
func charred_rooms() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _rooms.charred:
		ids.append(id)
	ids.sort()
	return ids


## What repairing a charred room of this kind costs, in whole dollars.
static func repair_cost(kind: String) -> int:
	return CatalogueScript.cost(kind) * REPAIR_PERCENT / 100


## True when any burning room has no guards on the way: nobody will put it out but the owner's rescue.
func has_unguarded_fire() -> bool:
	for entry in _burning:
		if entry[2] == 0:
			return true
	return false


## Called once a tick, after Events.tick.
func tick(clock: ClockScript, events: EventsScript, grid: GridScript, people: Object, messages: MessagesScript, at_tick: int) -> void:
	_forget_gone()
	if clock.ticks_in_period() == 0 and not _burning.is_empty():  # before a fire that starts this tick, which has burned no time yet
		_period(grid, messages, at_tick)
	for event in events.open_events():
		if event[1] == KIND and event[0] > _seen:
			_seen = event[0]
			_start(grid, people, messages, at_tick)
	for entry in events.resolved():
		if entry[1] == KIND and entry[0] > _read:
			_read = entry[0]
			if entry[2] == PAY and not _burning.is_empty():
				_rescue_at = at_tick + ClockScript.period_ticks(clock.period() - 1)
	# Guards put out the fires they have reached.
	var n := 0
	while n < _burning.size():
		var entry: Array = _burning[n]
		if entry[2] != 0 and at_tick >= entry[2]:
			_put_out(entry[0], grid, messages, at_tick)
			_burning.remove_at(n)
		else:
			n += 1
	if _rescue_at != 0 and at_tick >= _rescue_at:
		_rescue(grid, messages, at_tick)
	if _burning.is_empty():
		_rescue_at = 0
		for event in events.open_events():  # nothing left to pay for: close the choice
			if event[1] == KIND:
				events.choose(event[0], EventsScript.DECLINE, at_tick)


func _forget_gone() -> void:
	var n := 0
	while n < _burning.size():
		if _rooms.has_room(_burning[n][0]):
			n += 1
		else:
			_burning.remove_at(n)  # bulldozed or destroyed by something else
	for id in charred_rooms():
		if not _rooms.has_room(id):
			_rooms.charred.erase(id)  # a charred room that was bulldozed


## Links (stairs, escalators, shafts) do not burn, nor does the security office that answers fires.
func _burnable(id: int) -> bool:
	var kind := _rooms.kind_of(id)
	return kind != "" and not Rooms.is_link_kind(kind) and kind != "lobby" and kind != Security.OFFICE_KIND and not is_burning(id) and not _rooms.is_charred(id)


## Starts the fire in a random room, one that people live or work in if there is any.
func _start(grid: GridScript, people: Object, messages: MessagesScript, at_tick: int) -> void:
	var lived: Dictionary = {}
	for i in people.count():
		lived[people.home_of(i)] = true
		lived[people.work_of(i)] = true
	var occupied: Array[int] = []
	var any: Array[int] = []
	for id in _rooms.room_ids():
		if _burnable(id):
			any.append(id)
			if lived.has(id):
				occupied.append(id)
	var pool := occupied if not occupied.is_empty() else any
	if pool.is_empty():
		return
	_ignite(pool[_rng.next_below(pool.size())], grid, messages, at_tick)


func _ignite(id: int, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	var floors := _rooms.floors_of(grid, id)
	var response := Security.response_ticks(_rooms, grid, floors[0])
	_burning.append([id, 0, at_tick + response if response > 0 else 0])
	messages.add(at_tick, MessagesScript.FIRE_STARTED, CatalogueScript.IDS.find(_rooms.kind_of(id)), floors[0])


func _put_out(id: int, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	messages.add(at_tick, MessagesScript.FIRE_OUT, CatalogueScript.IDS.find(_rooms.kind_of(id)), _rooms.floors_of(grid, id)[0])


func _burn_down(id: int, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	messages.add(at_tick, MessagesScript.ROOM_BURNED, CatalogueScript.IDS.find(_rooms.kind_of(id)), _rooms.floors_of(grid, id)[0])
	_rooms.charred[id] = true
	_burned.append(id)


## The rescue craft arrives: the first RESCUE_LOST rooms that were burning are lost, the rest saved.
func _rescue(grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	var lost := mini(RESCUE_LOST, _burning.size())
	for n in lost:
		_burn_down(_burning[n][0], grid, messages, at_tick)
	messages.add(at_tick, MessagesScript.RESCUE_ARRIVED, _burning.size() - lost, lost)
	_burning = []
	_rescue_at = 0


## A period began: every burning room may spread to the rooms beside and above it, then burns a period
## longer and falls once it has burned BURN_PERIODS.
func _period(grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	var before: Array[int] = burning_rooms()
	for id in before:
		for neighbour in _neighbours(id, grid):
			if _rng.next_below(100) < SPREAD_PERCENT and _burnable(neighbour):
				_ignite(neighbour, grid, messages, at_tick)
	var n := 0
	while n < _burning.size():
		var entry: Array = _burning[n]
		if before.has(entry[0]):
			entry[1] += 1
			if entry[1] >= BURN_PERIODS:
				_burn_down(entry[0], grid, messages, at_tick)
				_burning.remove_at(n)
				continue
		n += 1


## The rooms beside (left, right) and above a room, as room ids (0 for none).
func _neighbours(id: int, grid: GridScript) -> Array[int]:
	var found: Array[int] = []
	var run := grid.run_of(id)
	if run.is_empty():
		return found
	var floors := _rooms.floors_of(grid, id)
	found.append(_rooms.room_of(grid.cell_at(run[0], run[1] - 1)))
	found.append(_rooms.room_of(grid.cell_at(run[0], run[1] + run[2])))
	var above := Rooms.floor_above(floors[floors.size() - 1])
	found.append(_rooms.room_of(grid.cell_at(above, run[1])) if above != 0 else 0)
	return found


func state_ints() -> Array[int]:
	var ints: Array[int] = [_rng.state, _seen, _read, _rescue_at, _burning.size()]
	for entry in _burning:
		ints.append_array(entry)
	var charred := charred_rooms()
	ints.append(charred.size())
	ints.append_array(charred)
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 5 or ints[1] < 0 or ints[2] < 0 or ints[3] < 0 or ints[4] < 0:
		return false
	var after: int = HEADER + FIELDS * ints[4]
	return ints.size() > after and ints[after] >= 0 and ints.size() == after + 1 + ints[after]


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_seen = ints[1]
	_read = ints[2]
	_rescue_at = ints[3]
	_burning = []
	for n in int(ints[4]):
		_burning.append(ints.slice(HEADER + n * FIELDS, HEADER + (n + 1) * FIELDS))
	var after: int = HEADER + FIELDS * int(ints[4])
	_rooms.charred = {}
	var charred_count: int = int(ints[after]) if ints.size() > after else 0  # a hand-built array may stop before the list
	for n in charred_count:
		_rooms.charred[ints[after + 1 + n]] = true
