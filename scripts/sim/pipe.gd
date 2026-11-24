class_name Pipe
extends RefCounted
## Burst pipe (M9 9.10, #472): our own event, no original equivalent. Integers only.
##
## When it happens: its own PCG32 stream (seed XOR SEED_SALT), drawn twice at the start of every day whatever else is
## true, so it never shifts the shared Events stream nor any other system. A day rolls `one_in` for a burst when the
## tower has MIN_STARS stars, no burst is running and COOLDOWN_TICKS have passed since the last one. The second draw
## picks the room: a people-facing room (office, condo, hotel room, food or shop) on floor 3 or higher.
##
## The card (Events.open, manual kind 104): a pipe burst in that room. Choices (0 is the default, taken at the timeout):
##   0 ignore         nothing is done: each period the water drops one floor.
##   1 plumber        PLUMBER_COST dollars (the CHOOSE_EVENT command charges it): the water stops at once.
##   2 own maintenance free, only if a housekeeping room stands within MAINT_REACH floors of the burst: the water stops at the
##                     second period start after the choice (so it spreads once more). Without one in reach it acts as ignore.
##
## Water: it wets the burst room and then, at each period start, the rooms one floor below that share a column with the
## burst room, down to floor MIN_FLOOR. It stops on its own at a floor with no such room (END_DRY) or at the lobby (END_LOBBY).
## A wet room is closed to takings for one day (WET_TICKS) from the moment it got wet: Rooms.wet holds it, and Commerce
## (food and shop takings and customers) and Hotel (new bookings and the check-out payment) read that. Nothing else
## changes: office rent stays quarterly and untouched, a closed condo is never refunded or evicted, a closed room is not
## cut off and so is never a "no trip" stress source.
##
## Saved: the stream, whether water is flowing, the burst's floor and columns, the lowest wet floor, the periods until
## maintenance stops it (-1 for none), the open card's id, the tick + 1 of the last burst (0 for none) and the wet rooms
## as (room id, dry tick) pairs. All numbers are UNVERIFIED tunables except the plumber's price and the reach (gameplay review).

const EventsScript := preload("res://scripts/sim/events.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const SEED_SALT := 0x50495045  ## "PIPE".
const KIND := 104  ## The event kind id (fire 101, threat 102, VIP 103).
const MIN_STARS := 2
const ONE_DAY_IN := 20  ## A day rolls 1 in this for a burst.
const COOLDOWN_TICKS := 3 * EventsScript.DAY_TICKS  ## At least one quarter between bursts.
const NOTICE_TICKS := 200  ## About 80 game minutes to answer; then the default (ignore) applies.
const PLUMBER_COST := 25000
const MAINT_PERIODS := 2
const MAINT_REACH := 5  ## Floors from the burst a housekeeping room may stand.
const MIN_FLOOR := 2  ## The lowest floor water reaches: the lobby floor and below stay dry.
const MIN_ORIGIN_FLOOR := 3
const WET_TICKS := EventsScript.DAY_TICKS  ## A soaked room is closed for a day.
const SOAK_KINDS: Array[String] = ["office", "condo", "hotel_single", "hotel_twin", "hotel_suite", "fast_food", "restaurant", "retail"]
const HOUSEKEEPING := "housekeeping"
const DEFAULT_STREAM := 0x2545F4914F6CDD1D  ## A mixed state (a tiny one draws 0 first): where a migrated old save starts its stream (save_migration.gd, v48 to v49).

## How a burst ended (the PIPE_STOPPED message's b).
const END_STOPPED := 0
const END_DRY := 1
const END_LOBBY := 2

const CHOICE_IGNORE := 0
const CHOICE_PLUMBER := 1
const CHOICE_MAINTENANCE := 2

var one_in: int = ONE_DAY_IN  ## A day's odds of a burst (a test sets 1 to force one).
var min_origin: int = MIN_ORIGIN_FLOOR  ## The lowest floor a burst may start on (a test raises it to choose the room).
var _rooms: RoomsScript
var _rng := Rng.new()
var _flowing: bool = false
var _origin_floor: int = 0
var _x_from: int = 0
var _x_to: int = 0
var _front: int = 0  ## The lowest floor the water has reached.
var _stop_in: int = -1  ## Period starts until maintenance stops the water, -1 for none under way.
var _event: int = 0
var _last_burst: int = 0  ## Tick + 1 of the last burst, 0 for none.
var _wet: Array[Array] = []  ## [room id, dry tick] pairs, oldest first.
var _reach: bool = false  ## A housekeeping room is in reach (derived each tick while flowing, for the card's labels).


func _init(rooms: RoomsScript) -> void:
	_rooms = rooms


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The save's ints for a tower where no burst has happened, with the stream at DEFAULT_STREAM (the migration step).
static func rest_ints() -> Array[int]:
	return [DEFAULT_STREAM, 0, 0, 0, 0, 0, -1, 0, 0, 0] as Array[int]


## True while water is still spreading.
func is_flowing() -> bool:
	return _flowing


## The floors that hold a wet room, lowest first (the view marks them).
func wet_floors(grid: GridScript) -> Array[int]:
	var floors: Array[int] = []
	for pair in _wet:
		var run := grid.run_of(pair[0])
		if not run.is_empty() and not floors.has(run[0]):
			floors.append(run[0])
	floors.sort()
	return floors


## The wet rooms' ids.
func wet_rooms() -> Array[int]:
	var ids: Array[int] = []
	for pair in _wet:
		ids.append(pair[0])
	return ids


## The floor the water will wet at the next period start, or 0 when it is not flowing or would stop (the view's "next").
func next_floor(grid: GridScript) -> int:
	if not _flowing or _stop_in == 1:
		return 0
	var below := _front - 1
	return below if below >= MIN_FLOOR and not _soaked_at(grid, below).is_empty() else 0


## The columns the water runs down, as [first, last], or [] when no burst has run (the view marks the next floor with it).
func columns() -> Array[int]:
	if _last_burst == 0:
		return [] as Array[int]
	return [_x_from, _x_to] as Array[int]


## The card's kind. Manual: Events never rolls it. Labels follow whether a housekeeping room is in reach.
func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.ORDINARY, "manual": true, "choices": 3, "timeout": NOTICE_TICKS, "floor": 0,
		"default": CHOICE_IGNORE, "costs": [0, PLUMBER_COST, 0], "title": "Burst pipe", "dynamic": _live_texts,
		"text": "A pipe burst in a room and the water is spreading down one floor each period. Wet rooms are closed to hotel, shop and food takings for a day. An emergency plumber ($25,000) stops it at once; your own maintenance (free) stops it in two periods but needs a housekeeping room within 5 floors; ignore it and it spreads until a floor with no rooms below, or the lobby.",
		"ignored": "The water keeps spreading down until a floor with no rooms, or the lobby."}


func _live_texts() -> Dictionary:
	return {"labels": ["Ignore it", "Emergency plumber ($25,000)", "Own maintenance (free)" if _reach else "Own maintenance (no housekeeping within 5 floors)"]}


## Called once a tick after the clock. Acts at day and period starts, when the card is answered, and as rooms dry.
func tick(clock: ClockScript, stars: int, grid: GridScript, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	_dry_out(at_tick)
	if clock.day_started:
		var rolled := _rng.next_below(maxi(1, one_in))  # both draws, always: the stream never depends on the tower
		var pick := _rng.next_below(1000)
		if rolled == 0 and not _flowing and stars >= MIN_STARS and (_last_burst == 0 or at_tick - (_last_burst - 1) >= COOLDOWN_TICKS):
			_burst(pick, grid, events, messages, at_tick)
	if not _flowing:
		return
	_reach = _housekeeping_near(grid)
	_read_answer(events, messages, at_tick)
	if _flowing and clock.ticks_in_period() == 0 and _last_burst != at_tick + 1:  # a burst on a period's first tick spreads from the next one
		_period(grid, events, messages, at_tick)


func _burst(pick: int, grid: GridScript, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	var candidates: Array[int] = []
	for id in _rooms.room_ids():  # a finite list
		var run := grid.run_of(id)
		if SOAK_KINDS.has(_rooms.kind_of(id)) and not run.is_empty() and run[0] >= min_origin and not _rooms.is_charred(id):
			candidates.append(id)
	if candidates.is_empty():
		return
	var origin: int = candidates[pick % candidates.size()]
	var run := grid.run_of(origin)
	var card := events.open(KIND, run[0], at_tick)
	if card == 0:
		return  # the event list is full: no burst today
	_event = card
	_flowing = true
	_origin_floor = run[0]
	_front = run[0]
	_x_from = run[1]
	_x_to = run[1] + run[2] - 1
	_stop_in = -1
	_last_burst = at_tick + 1
	_wet.append([origin, at_tick + WET_TICKS])
	_sync()
	_reach = _housekeeping_near(grid)
	messages.add(at_tick, MessagesScript.PIPE_BURST, CatalogueScript.IDS.find(_rooms.kind_of(origin)), run[0])


## Reads the player's answer (or the timeout's default) once the card has left the open list.
func _read_answer(events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	if _event == 0 or not events.event_of(_event).is_empty():
		return
	var choice := CHOICE_IGNORE
	for entry in events.resolved():  # a finite log
		if entry[0] == _event:
			choice = entry[2]
	_event = 0
	if choice == CHOICE_PLUMBER:
		_finish(END_STOPPED, events, messages, at_tick)  # at once
	elif choice == CHOICE_MAINTENANCE and _reach:
		_stop_in = MAINT_PERIODS


func _period(grid: GridScript, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	if _stop_in > 0:
		_stop_in -= 1
		if _stop_in == 0:
			_finish(END_STOPPED, events, messages, at_tick)
			return
	var below := _front - 1
	if below < MIN_FLOOR:
		_finish(END_LOBBY, events, messages, at_tick)
		return
	var soaked := _soaked_at(grid, below)
	if soaked.is_empty():
		_finish(END_DRY, events, messages, at_tick)
		return
	for id in soaked:
		_wet.append([id, at_tick + WET_TICKS])
	_front = below
	_sync()


func _finish(how: int, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	_flowing = false
	_stop_in = -1
	if _event != 0:
		events.withdraw(_event)  # it ended by itself while the card was still open
		_event = 0
	messages.add(at_tick, MessagesScript.PIPE_STOPPED, _front, how)


## The soakable rooms on a floor that share a column with the burst room.
func _soaked_at(grid: GridScript, floor_number: int) -> Array[int]:
	var found: Array[int] = []
	for id in _rooms.room_ids():  # a finite list
		var run := grid.run_of(id)
		if run.is_empty() or run[0] != floor_number or not SOAK_KINDS.has(_rooms.kind_of(id)) or _rooms.is_charred(id):
			continue
		if run[1] <= _x_to and run[1] + run[2] - 1 >= _x_from:
			found.append(id)
	return found


func _housekeeping_near(grid: GridScript) -> bool:
	for id in _rooms.room_ids():  # a finite list
		if _rooms.kind_of(id) == HOUSEKEEPING and not _rooms.is_charred(id):
			var run := grid.run_of(id)
			if not run.is_empty() and absi(run[0] - _origin_floor) <= MAINT_REACH:
				return true
	return false


func _dry_out(at_tick: int) -> void:
	var changed := false
	var n := _wet.size() - 1
	while n >= 0:  # n steps down every pass, so it ends
		if at_tick >= _wet[n][1] or not _rooms.has_room(_wet[n][0]):
			_wet.remove_at(n)
			changed = true
		n -= 1
	if changed:
		_sync()


func _sync() -> void:
	_rooms.wet = {}
	for pair in _wet:
		_rooms.wet[pair[0]] = true


func state_ints() -> Array[int]:
	var ints: Array[int] = [_rng.state, 1 if _flowing else 0, _origin_floor, _x_from, _x_to, _front, _stop_in, _event, _last_burst, _wet.size()]
	for pair in _wet:
		ints.append_array(pair)
	return ints


## What the state hash takes: nothing while no burst has ever happened (the stream only follows the seed and the day count).
func hash_ints() -> Array[int]:
	if not _flowing and _wet.is_empty() and _last_burst == 0:
		return [] as Array[int]
	return state_ints().slice(1)


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 10:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var wet: int = ints[9]
	if wet < 0 or ints.size() != 10 + 2 * wet or (ints[1] != 0 and ints[1] != 1) or ints[6] < -1 or ints[7] < 0 or ints[8] < 0:
		return false
	for n in wet:
		if ints[10 + 2 * n] < 1:
			return false
	return true


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_flowing = ints[1] == 1
	_origin_floor = ints[2]
	_x_from = ints[3]
	_x_to = ints[4]
	_front = ints[5]
	_stop_in = ints[6]
	_event = ints[7]
	_last_burst = ints[8]
	_wet = []
	for n in int(ints[9]):
		_wet.append([ints[10 + 2 * n], ints[11 + 2 * n]])
	_sync()
