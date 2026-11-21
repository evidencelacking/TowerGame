class_name Threat
extends RefCounted
## Threat (M9 9.3, #218): our own version. An anonymous notice says a device is hidden in the tower;
## there is no caller. Integers only; its own seeded stream.
##
## Gate (through Events): 3 stars or more, 3,000 people or more in the tower (Tower sets `population`),
## a security office, and no threat already running. Odds: [3%] a day, rolled at the start of each of
## the two morning periods (5:00 and 9:00), so the notice comes at a morning time; the per-roll odds
## are halved for each security office beyond the first. The deadline is 13:00 the same day, and the
## event panel shows the time left honestly.
##
## When the notice comes the device is put on a random floor that holds a room. The choice:
##  - pay $200,000 (choice 1): it ends;
##  - refuse (choice 0), or no answer by the deadline: guards search from their offices. Each office
##    sweeps one floor every SEARCH_TICKS, from its own floor outward (Security.search_rank), only as
##    far as its reach. Finding the device's floor ends it. Offices are counted as they stand, so more
##    offices search more floors in the same time.
## If the deadline comes first the device goes off: every room on the device's floor, the two floors
## above and the two below is destroyed (a stairs, escalator or shaft that touches them goes whole;
## the floors themselves stay). Rooms are handed to Tower (take_destroyed).
##
## Saved: the stream, the last event adopted and answer read, and the running threat as
## [event id or 0, device floor, tick the search began or 0, deadline].

const EventsScript := preload("res://scripts/sim/events.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const KIND := 102  ## The event kind id in Events.kinds.
const SEED_SALT := 0x54485254  ## "THRT".
const CHANCE := 1520  ## Per morning roll, out of CHANCE_DEN, with one office: about 3% over the day's two rolls.
const CHANCE_DEN := 100000
const MIN_STARS := 3
const MIN_POPULATION := 3000
const PAY_COST := 200000  ## Dollars.
const PAY := 1
const DEADLINE_MINUTE := 780  ## 13:00.
const TIMEOUT := 1200  ## Fallback only; the deadline is 13:00.
const MORNING_PERIODS: Array[int] = [1, 2]
const SEARCH_TICKS := 20  ## Ticks an office spends on each floor of its sweep.
const BLAST_FLOORS := 2  ## Floors destroyed above and below the device's floor.

var population: int = 0  ## People in the tower, set by Tower each tick (derived, not saved).
var _rooms: Rooms
var _rng := Rng.new()
var _seen: int = 0
var _read: int = 0
var _active: int = 0  ## Event id of the running threat, 0 for none.
var _device: int = 0  ## The floor the device is on.
var _search_from: int = 0  ## Tick the search began, 0 while the choice is open.
var _deadline: int = 0
var _destroyed: Array[int] = []  ## Rooms destroyed since Tower last took them (not saved).


func _init(rooms: Rooms = null) -> void:
	_rooms = rooms


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The event kind to register in Events.kinds.
func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.THREAT, "chance": CHANCE, "chance_den": CHANCE_DEN, "chance_of": _gate,
		"min_stars": MIN_STARS, "choices": 2, "timeout": TIMEOUT, "floor": 0, "costs": [0, PAY_COST],
		"periods": MORNING_PERIODS, "deadline_minute": DEADLINE_MINUTE,
		"title": "Anonymous notice",
		"ignored": "Security searches; if the floor is not found by 1:00 pm, about five floors are destroyed.",
		"text": "An unsigned note says a device is hidden somewhere in the tower and will go off at 1:00 pm today. Pay $200,000 and it ends. Refuse, and security will search floor by floor from their offices; if they have not found the right floor by 1:00 pm, about five floors are destroyed. More security offices search more floors.",
		"labels": ["Refuse and search", "Pay $200,000"]}


func _gate() -> int:
	return chance(_rooms, population, _active != 0)


## The chance per morning roll: none under 3,000 people, without an office or while a threat runs;
## halved for each office beyond the first.
static func chance(rooms: Rooms, people_inside: int, running: bool) -> int:
	var count := Security.offices(rooms).size()
	if people_inside < MIN_POPULATION or count == 0 or running:
		return 0
	return CHANCE >> (count - 1)


func is_active() -> bool:
	return _active != 0


func device_floor() -> int:
	return _device if _active != 0 else 0


## The first and last floor a device on this floor destroys (clipped to the tower).
static func blast_range(device: int) -> Array[int]:
	var index := GridScript.floor_to_index(device)
	var low := maxi(index - BLAST_FLOORS, 0)
	var high := mini(index + BLAST_FLOORS, GridScript.FLOOR_COUNT - 1)
	return [GridScript.index_to_floor(low), GridScript.index_to_floor(high)]


func take_destroyed() -> Array[int]:
	var out := _destroyed
	_destroyed = []
	return out


## True when some office's sweep has reached the device floor by this tick.
func found(grid: GridScript, at_tick: int) -> bool:
	if _active == 0 or _search_from == 0:
		return false
	var swept := (at_tick - _search_from) / SEARCH_TICKS
	for office in Security.offices(_rooms):
		var run := grid.run_of(office)
		if run.is_empty():
			continue
		var rank := Security.search_rank(run[0], _device)
		if rank >= 0 and rank < swept:
			return true
	return false


## Called once a tick, after Events.tick.
func tick(events: EventsScript, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	for event in events.open_events():
		if event[1] == KIND and event[0] > _seen:
			_seen = event[0]
			_notice(event, events, grid, messages, at_tick)
	for entry in events.resolved():
		if entry[1] == KIND and entry[0] > _read:
			_read = entry[0]
			if entry[0] == _active:
				if entry[2] == PAY:
					messages.add(at_tick, MessagesScript.THREAT_PAID)
					_active = 0
				else:
					_search_from = at_tick
	if _active == 0 or _search_from == 0:
		return
	if found(grid, at_tick):
		messages.add(at_tick, MessagesScript.THREAT_FOUND, _device)
		_active = 0
	elif at_tick >= _deadline:
		_explode(grid, messages, at_tick)
		_active = 0


func _notice(event: Array, events: EventsScript, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	var floors: Array[int] = []
	for id in _rooms.room_ids():
		for f in _rooms.floors_of(grid, id):
			if not floors.has(f):
				floors.append(f)
	floors.sort()
	if floors.is_empty():
		events.choose(event[0], EventsScript.DECLINE, at_tick)
		return
	_device = floors[_rng.next_below(floors.size())]
	_active = event[0]
	_search_from = 0
	_deadline = event[5]
	messages.add(at_tick, MessagesScript.THREAT_NOTICE)


func _explode(grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	var span := blast_range(_device)
	var low := GridScript.floor_to_index(span[0])
	var high := GridScript.floor_to_index(span[1])
	for id in _rooms.room_ids():
		for f in _rooms.floors_of(grid, id):
			var index := GridScript.floor_to_index(f)
			if index >= low and index <= high:
				_destroyed.append(id)
				break
	messages.add(at_tick, MessagesScript.THREAT_EXPLODED, span[0], span[1])


func state_ints() -> Array[int]:
	return [_rng.state, _seen, _read, _active, _device, _search_from, _deadline]


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints.size() == 7 and ints[1] >= 0 and ints[2] >= 0 and ints[3] >= 0 and ints[5] >= 0 and ints[6] >= 0


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_seen = ints[1]
	_read = ints[2]
	_active = ints[3]
	_device = ints[4]
	_search_from = ints[5]
	_deadline = ints[6]
