class_name Events
extends RefCounted
## The event scheduler (M9 9.1, #214): the sim core every M9 event builds on. Integers only.
##
## Own random stream: a PCG32 seeded from the tower seed XOR SEED_SALT, so rolling for events never
## shifts a draw anywhere else (and no other system shifts the events).
##
## Rolls: when a period begins (Clock.ticks_in_period() is 0) every kind in `kinds` rolls exactly
## once, in list order, drawing one number whether or not the roll can fire. A roll fires when
## the draw (0 to 999) is below the kind's "chance" and the rules allow it:
##   - the tower has the kind's "min_stars";
##   - fewer than MAX_OPEN events are open;
##   - a fire-class event and a threat-class event never fire within DAY_TICKS of each other
##     (the "at least a day between a fire and a threat" rule, read literally; our choice, #214).
##
## An event is data: [id, kind, floor, state, fired tick, deadline tick, choices]. State is OPEN
## while it awaits a choice. Choice 0 is always decline; 1 to choices - 1 are the kind's own. The
## only way a choice reaches the sim is the CHOOSE_EVENT command (Tower), which calls choose(). An
## open event whose deadline arrives with no choice times out to choice 0. An answered event leaves
## the open list and is logged in `resolved` ([id, kind, choice, tick], newest last, last
## MAX_RESOLVED kept) for the system that owns the kind to read; no real kinds exist yet.
##
## A kind is a Dictionary: {"id": int (1 up), "class": ORDINARY, FIRE or THREAT, "chance": per mille
## per period, "min_stars": 1 to 5, "choices": count including decline (at least 1), "timeout":
## ticks until the default (at least 1), "floor": the floor it names, 0 for none}. `kinds` is
## configuration, not saved: a system registers its kinds when the tower is built.
##
## A kind may also carry (all optional, #217 and #218): "chance_den", the draw's size (default 1000,
## so "chance" is per mille; 100000 gives finer odds); "chance_of", a Callable returning the chance
## now, which replaces "chance" (0 means cannot happen); "periods", the 1-based clock periods whose
## start may fire it (default all); "deadline_minute", a minute of the day the event must end by, which
## replaces "timeout" (the deadline is the next time the clock reaches it); and "costs", the dollars
## each choice charges (0 for decline), which the CHOOSE_EVENT command takes. A draw is always made.

const SEED_SALT := 0x45564E54  ## "EVNT".
const MAX_OPEN := 3
const MAX_RESOLVED := 16
const ORDINARY := 0
const FIRE := 1
const THREAT := 2
const OPEN := 0
const DECLINE := 0
const DAY_TICKS := 2550  ## One game day: the sum of Clock's PERIOD_n_TICKS.
const FIELDS := 7  ## Ints per open event.
const RESOLVED_FIELDS := 4

const Rng := preload("res://scripts/sim/sim_rng.gd")

var kinds: Array[Dictionary] = []
var rolls: int = 0  ## Rolls made so far, one per kind per period.
var _rng := Rng.new()
var _events: Array[Array] = []
var _resolved: Array[Array] = []
var _next_id: int = 1
var _last_fire: int = 0  ## Tick + 1 of the last fire-class event, 0 for none.
var _last_threat: int = 0  ## Tick + 1 of the last threat-class event, 0 for none.


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## Open events, oldest first, each [id, kind, floor, state, fired, deadline, choices].
func open_events() -> Array[Array]:
	var copy: Array[Array] = []
	for event in _events:
		copy.append(event.duplicate())
	return copy


func open_count() -> int:
	return _events.size()


## The event with this id, or [] if it is not open.
func event_of(id: int) -> Array:
	for event in _events:
		if event[0] == id:
			return event.duplicate()
	return []


## Answered and timed-out events, oldest first, each [id, kind, choice, tick].
func resolved() -> Array[Array]:
	var copy: Array[Array] = []
	for entry in _resolved:
		copy.append(entry.duplicate())
	return copy


## Dollars the choice charges, 0 when the event is not open or the choice is free.
func cost_of(id: int, choice: int) -> int:
	for event in _events:
		if event[0] == id:
			var costs: Array = kind_def(event[1]).get("costs", [])
			return int(costs[choice]) if choice >= 0 and choice < costs.size() else 0
	return 0


func kind_def(kind: int) -> Dictionary:
	for def in kinds:
		if def["id"] == kind:
			return def
	return {}


## Answers an open event (the CHOOSE_EVENT command). False, and nothing changes, if the event is
## not open or the choice is out of range.
func choose(id: int, choice: int, at_tick: int) -> bool:
	for n in _events.size():
		var event: Array = _events[n]
		if event[0] != id:
			continue
		if choice < 0 or choice >= event[6]:
			return false
		_events.remove_at(n)
		_log(event, choice, at_tick)
		return true
	return false


## Called once a tick after the clock has advanced: times out due events, then rolls if a period
## just began.
func tick(clock: Object, stars: int, at_tick: int) -> void:
	var n := 0
	while n < _events.size():  # each pass removes an event or advances n, so it ends
		var event: Array = _events[n]
		if at_tick >= event[5]:
			_events.remove_at(n)
			_log(event, DECLINE, at_tick)
		else:
			n += 1
	if clock.ticks_in_period() == 0:
		_roll(clock, stars, at_tick)


func _roll(clock: Object, stars: int, at_tick: int) -> void:
	for def in kinds:
		rolls += 1
		var draw := _rng.next_below(int(def.get("chance_den", 1000)))
		var chance: int = def["chance_of"].call() if def.has("chance_of") else int(def["chance"])
		if draw >= chance or stars < int(def["min_stars"]) or _events.size() >= MAX_OPEN:
			continue
		if def.has("periods") and not (def["periods"] as Array).has(clock.period()):
			continue
		var cls: int = def["class"]
		if cls == THREAT and _last_fire != 0 and at_tick - (_last_fire - 1) < DAY_TICKS:
			continue
		if cls == FIRE and _last_threat != 0 and at_tick - (_last_threat - 1) < DAY_TICKS:
			continue
		var timeout: int = clock.ticks_until_minute(int(def["deadline_minute"])) if def.has("deadline_minute") else int(def["timeout"])
		_events.append([_next_id, def["id"], def["floor"], OPEN, at_tick, at_tick + timeout, def["choices"]])
		_next_id += 1
		if cls == FIRE:
			_last_fire = at_tick + 1
		elif cls == THREAT:
			_last_threat = at_tick + 1


func _log(event: Array, choice: int, at_tick: int) -> void:
	_resolved.append([event[0], event[1], choice, at_tick])
	if _resolved.size() > MAX_RESOLVED:
		_resolved.remove_at(0)


func state_ints() -> Array[int]:
	var ints: Array[int] = [_rng.state, rolls, _next_id, _last_fire, _last_threat, _events.size()]
	for event in _events:
		ints.append_array(event)
	ints.append(_resolved.size())
	for entry in _resolved:
		ints.append_array(entry)
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 7:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var open: int = ints[5]
	if ints[1] < 0 or ints[2] < 1 or ints[3] < 0 or ints[4] < 0 or open < 0 or open > MAX_OPEN:
		return false
	var at := 6 + open * FIELDS
	if ints.size() <= at:
		return false
	for n in open:
		var base := 6 + n * FIELDS
		if ints[base] < 1 or ints[base + 6] < 1 or ints[base + 3] != OPEN:
			return false
	var logged: int = ints[at]
	return logged >= 0 and logged <= MAX_RESOLVED and ints.size() == at + 1 + logged * RESOLVED_FIELDS


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	rolls = ints[1]
	_next_id = ints[2]
	_last_fire = ints[3]
	_last_threat = ints[4]
	_events = []
	var at := 6
	for _n in int(ints[5]):
		_events.append(ints.slice(at, at + FIELDS))
		at += FIELDS
	_resolved = []
	var logged: int = ints[at]
	at += 1
	for _n in logged:
		_resolved.append(ints.slice(at, at + RESOLVED_FIELDS))
		at += RESOLVED_FIELDS
