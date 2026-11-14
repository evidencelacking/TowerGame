class_name Tower
extends RefCounted
## The tower simulation state. Integers only; see CLAUDE.md.
##
## 1 tick = 1 frame. step() is the only thing that advances time. Input reaches the state
## only as Commands: queue them with enqueue(), and step() applies those due at the new
## tick, in queue order, at one fixed point (see step). Everything random comes from rng.

const Rng := preload("res://scripts/sim/sim_rng.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Grid := preload("res://scripts/sim/grid.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const WordOfMouthScript := preload("res://scripts/sim/word_of_mouth.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")

## The only way input changes the simulation. Queued for a tick and applied at one fixed
## point in that tick (see step). Integers only, so it saves and hashes exactly.
class Command:
	extends RefCounted
	## Command kinds. Add new kinds on their own line; Tower._apply_command handles each.
	const NOTE := 1  ## Foundation placeholder: adds args[0] to Tower.notes.
	const ROLL := 2  ## Foundation placeholder: adds a random draw below args[0] to Tower.notes.
	const PLACE := 3  ## Places an occupant on the grid: args are id, floor, column, length.
	const REMOVE := 4  ## Removes an occupant from the grid: args[0] is its id.
	const PURCHASE := 5  ## Spends money: args are cost, ref (room id). Refused if short.
	const REFUND := 6  ## Returns money: args are amount, ref. Always applies.
	const BUILD_FLOOR := 7  ## Builds a floor span: args are floor, x_start, x_end (inclusive).
	const BUILD_LOBBY := 8  ## Builds the ground lobby: args are floor (must be 1), x_start, x_end, height (1 to 3).
	const PLACE_ROOM := 9  ## Places a room: args are room_kind (index in RoomCatalogue.IDS), floor, x_left.
	const REPLACE_ROOM := 12  ## Bulldozes the room covering (floor, x_left) and places a room there, atomically: args are room_kind, floor, x_left. See Rooms.replace_room.
	const BULLDOZE := 10  ## Removes the room covering a cell, free: args are floor, x. See Rooms.bulldoze.
	const PLACE_STAIRS := 11  ## Places stairs between two floors: args are lower floor, x_left. See Rooms.place_stairs.
	const PLACE_SHAFT := 13  ## Places an elevator shaft: args are room_kind (index in RoomCatalogue.IDS), bottom floor, top floor, x_left. See Rooms.place_shaft.
	const RESIZE_SHAFT := 14  ## Grows or shrinks a shaft in place: args are shaft id, new bottom, new top. See Rooms.resize_shaft.
	const ADD_CAR := 16  ## Adds an elevator car: args are shaft id, home floor. See Rooms.add_car.
	const REMOVE_CAR := 17  ## Removes a shaft's newest car: args are shaft id. See Rooms.remove_car.
	const SET_SHAFT_STOP := 15  ## Turns a shaft's stop on a floor on or off: args are shaft id, floor, on (1 or 0). See Rooms.set_shaft_stop.

	var tick: int = 0  ## The tick this command applies at.
	var kind: int = 0
	var args: Array[int] = []

	static func make(for_tick: int, command_kind: int, command_args: Array[int] = []) -> Command:
		var command := Command.new()
		command.tick = for_tick
		command.kind = command_kind
		command.args = command_args.duplicate()
		return command


const SAVE_VERSION := 20
const START_STARS := 1  ## A new tower starts at 1 star (docs/gameplay-reference.md). The one source of truth; views read Tower.stars.
const HASH_OFFSET := -3750763034362895579  # FNV-1a 64-bit offset basis, as signed
const HASH_PRIME := 1099511628211

var tick: int = 0
var rng := Rng.new()
var clock := Clock.new()
var grid := Grid.new()
var ledger := LedgerScript.new()
var floors := FloorsScript.new()
var rooms := RoomsScript.new()
## Refusals and notable events, for the message log (see Messages).
var messages := MessagesScript.new()
## The people: home, work, day plan, trip and stress (see People).
var people := PeopleScript.new()
## Office tenancy: moves workers in (see Tenancy). Derived from people, so not saved.
var tenancy := TenancyScript.new()
## Trip executor: moves people along routes and charges travel stress (see Trips). Not saved.
var trips := TripsScript.new()
## Quality score and A/B/C grade of tenant rooms (see Grades). Saved: who has made a first trip.
var grades := GradesScript.new()
## Complaints from C rooms lower nearby tenants (see WordOfMouth). Derived from grades, so not saved.
var word_of_mouth := WordOfMouthScript.new()
## Result of the most recent PURCHASE, BUILD_FLOOR, BUILD_LOBBY, PLACE_ROOM, PLACE_STAIRS, BULLDOZE or REPLACE_ROOM command (OK or a refusal reason; see
## Ledger and Floors for the codes).
var last_refusal: int = 0
## Placeholder state that commands change, so tests can see them. Replaced as real state lands.
var notes: int = 0
## The tower's star rating, 1 to 5. Only promote_stars raises it and nothing lowers it. The HUD, toolbar and ghost read it.
var stars: int = START_STARS

var _queue: Array[Command] = []


func _init(seed_value: int = 0, starting_funds: int = LedgerScript.DEFAULT_STARTING_FUNDS) -> void:
	rng.reseed(seed_value)
	ledger = LedgerScript.new(starting_funds)
	word_of_mouth.attach(grades, rooms, grid, people)


## Queues a command for a future tick. Returns false (and queues nothing) if that tick has
## already happened or is the current one: a command must apply at its own tick.
func enqueue(command: Command) -> bool:
	if command.tick <= tick:
		return false
	_queue.append(command)
	return true


## Advances one tick. The order is fixed:
##   1. the tick counter increments
##   2. commands due at this tick apply, in queue order
##   3. systems run (clock #2, grid #3 and later systems hook in here, in a fixed order)
## People in the tower right now (derived from people, not saved).
func population() -> int:
	return people.in_tower_count()


func step() -> void:
	tick += 1
	_apply_due_commands()
	_run_systems()


func _apply_due_commands() -> void:
	var remaining: Array[Command] = []
	for command in _queue:
		if command.tick == tick:
			_apply_command(command)
		else:
			remaining.append(command)
	_queue = remaining


func _apply_command(command: Command) -> void:
	match command.kind:
		Command.NOTE:
			notes += command.args[0]
		Command.ROLL:
			notes += rng.next_below(command.args[0])
		Command.PLACE:
			if command.args.size() == 4:
				grid.place(command.args[0], command.args[1], command.args[2], command.args[3])
		Command.REMOVE:
			if command.args.size() == 1:
				grid.remove(command.args[0])
		Command.PURCHASE:
			if command.args.size() == 2:
				last_refusal = ledger.charge(tick, command.args[0], command.args[1])
				_note_refusal(MessagesScript.PURCHASE_REFUSED, command.args[1])
		Command.REFUND:
			if command.args.size() == 2:
				ledger.refund(tick, command.args[0], command.args[1])
		Command.BUILD_FLOOR:
			if command.args.size() == 3:
				last_refusal = floors.build_span(ledger, tick, command.args[0], command.args[1], command.args[2])
				if not _note_refusal(MessagesScript.FLOOR_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.FLOOR_BUILT, command.args[0])
		Command.BUILD_LOBBY:
			if command.args.size() == 4:
				last_refusal = floors.build_lobby(ledger, tick, command.args[0], command.args[1], command.args[2], command.args[3])
				if not _note_refusal(MessagesScript.LOBBY_REFUSED, 0):
					messages.add(tick, MessagesScript.LOBBY_BUILT, command.args[3])
		Command.PLACE_ROOM:
			if command.args.size() == 3:
				last_refusal = rooms.place_room(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2])
				if not _note_refusal(MessagesScript.ROOM_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_BUILT, command.args[0], command.args[1])
		Command.BULLDOZE:
			if command.args.size() == 2:
				var doomed := rooms.check_bulldoze(grid, floors, command.args[0], command.args[1])
				var doomed_kind := CatalogueScript.IDS.find(rooms.kind_of(doomed["room_id"]))
				last_refusal = rooms.bulldoze(grid, floors, ledger, tick, command.args[0], command.args[1])
				if last_refusal == RoomsScript.OK:
					people.remove_room(doomed["room_id"])
				if not _note_refusal(MessagesScript.BULLDOZE_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_REMOVED, doomed_kind, command.args[0])
					if doomed["refund"] > 0:
						messages.add(tick, MessagesScript.CONDO_REFUND, doomed["refund"])
		Command.REPLACE_ROOM:
			if command.args.size() == 3:
				var replaced := rooms.check_bulldoze(grid, floors, command.args[1], command.args[2])
				last_refusal = rooms.replace_room(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2])
				if last_refusal == RoomsScript.OK:
					people.remove_room(replaced["room_id"])
				if not _note_refusal(MessagesScript.REPLACE_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_REPLACED, command.args[0], command.args[1])
					if replaced["refund"] > 0:
						messages.add(tick, MessagesScript.CONDO_REFUND, replaced["refund"])
		Command.PLACE_STAIRS:
			if command.args.size() == 2:
				last_refusal = rooms.place_stairs(grid, floors, ledger, tick, command.args[0], command.args[1])
				if not _note_refusal(MessagesScript.STAIRS_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.STAIRS_BUILT, command.args[0])
		Command.PLACE_SHAFT:
			if command.args.size() == 4:
				last_refusal = rooms.place_shaft(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2], command.args[3])
				if not _note_refusal(MessagesScript.ROOM_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_BUILT, command.args[0], command.args[1])
		Command.RESIZE_SHAFT:
			if command.args.size() == 3:
				last_refusal = rooms.resize_shaft(grid, floors, command.args[0], command.args[1], command.args[2])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.SET_SHAFT_STOP:
			if command.args.size() == 3:
				last_refusal = rooms.set_shaft_stop(command.args[0], command.args[1], command.args[2] != 0)
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.ADD_CAR:
			if command.args.size() == 2:
				last_refusal = rooms.add_car(ledger, tick, stars, command.args[0], command.args[1])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.REMOVE_CAR:
			if command.args.size() == 1:
				last_refusal = rooms.remove_car(command.args[0])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		_:
			push_error("Unknown sim command kind %d" % command.kind)


## Logs the refusal in last_refusal, if it is one. Returns true if it was.
func _note_refusal(code: int, detail: int) -> bool:
	if last_refusal == 0:
		return false
	messages.add(tick, code, last_refusal, detail)
	return true


## Per-tick systems, in a fixed order: the clock first, then (later) the grid and the rest.
func _run_systems() -> void:
	clock.advance()
	tenancy.tick(clock, floors, rooms, grid, people, rng, ledger, tick)
	trips.tick(clock, floors, rooms, grid, people)
	grades.tick(people)
	CarsScript.tick(rooms)
	trips.collect_arrivals(floors, rooms, grid, people)
	people.tick(clock)
	if StarRulesScript.is_check_tick(clock):
		promote_stars()


## Raises stars to what the population now earns and logs one message per star gained. Never
## lowers. Runs once a day (StarRules.CHECK_MINUTE); public so tests can call it.
func promote_stars() -> void:
	var earned := StarRulesScript.rating_after(stars, population())
	while stars < earned:
		stars += 1
		messages.add(tick, MessagesScript.STAR_PROMOTED, stars)


## Quality score 0 to 300 of a graded room (office, condo, hotel), or -1. Read-only, for the view.
func quality(room: int) -> int:
	return grades.quality(rooms, people, room)


## GradesScript.GRADE_A, GRADE_B or GRADE_C for a graded room, or GRADE_NONE. Read-only.
func grade(room: int) -> int:
	return grades.grade(rooms, people, room)


## Deterministic 64-bit hash of the whole simulation state, RNG and queue included.
func state_hash() -> int:
	var h := HASH_OFFSET
	for value in _state_ints():
		h = _mix(h, value)
	return h


func _state_ints() -> Array[int]:
	var ints: Array[int] = [tick, rng.state, notes, stars]
	ints.append_array(clock.state_ints())
	ints.append(grid.occupant_count())
	ints.append_array(grid.state_ints())
	ints.append_array(ledger.state_ints())
	ints.append_array(floors.state_ints())
	ints.append_array(rooms.state_ints())
	ints.append_array(messages.state_ints())
	ints.append_array(people.state_ints())
	ints.append_array(grades.state_ints())
	ints.append(last_refusal)
	ints.append(_queue.size())
	for command in _queue:
		ints.append(command.tick)
		ints.append(command.kind)
		ints.append(command.args.size())
		ints.append_array(command.args)
	return ints


func _mix(h: int, value: int) -> int:
	for byte_index in 8:
		h = (h ^ ((value >> (byte_index * 8)) & 0xFF)) * HASH_PRIME
	return h


## Everything needed to resume the run exactly, including the RNG state.
func save() -> Dictionary:
	var queued: Array = []
	for command in _queue:
		queued.append([command.tick, command.kind, command.args.duplicate()])
	return {"version": SAVE_VERSION, "tick": tick, "rng_state": rng.state, "notes": notes, "stars": stars, "clock": clock.state_ints(), "grid": grid.state_ints(), "ledger": ledger.state_ints(), "floors": floors.state_ints(), "rooms": rooms.state_ints(), "messages": messages.state_ints(), "people": people.state_ints(), "grades": grades.state_ints(), "last_refusal": last_refusal, "queue": queued}


## Replaces this tower's state with a save() result. Returns false, changing nothing, if
## the data is not a supported save: every part is validated before any field is assigned.
func load_state(data: Dictionary) -> bool:
	if data.get("version", 0) != SAVE_VERSION:
		return false
	for key in ["tick", "rng_state", "notes", "last_refusal"]:
		if typeof(data.get(key)) != TYPE_INT:
			return false
	# "stars" is absent in saves from before the sim held it: those load at the start rating.
	var loaded_stars: Variant = data.get("stars", START_STARS)
	if typeof(loaded_stars) != TYPE_INT or loaded_stars < 1 or loaded_stars > 5:
		return false
	var clock_ints: Variant = data.get("clock")
	var grid_ints: Variant = data.get("grid")
	var ledger_ints: Variant = data.get("ledger")
	var floors_ints: Variant = data.get("floors")
	var rooms_ints: Variant = data.get("rooms")
	var messages_ints: Variant = data.get("messages")
	var people_ints: Variant = data.get("people")
	var grades_ints: Variant = data.get("grades")
	var queue_data: Variant = data.get("queue")
	if not (clock_ints is Array and grid_ints is Array and ledger_ints is Array and floors_ints is Array and rooms_ints is Array and messages_ints is Array and people_ints is Array and grades_ints is Array and queue_data is Array):
		return false
	var loaded_grid := Grid.new()
	if not Clock.valid_ints(clock_ints) or not loaded_grid.load_ints(grid_ints) or not LedgerScript.valid_ints(ledger_ints) or not FloorsScript.valid_ints(floors_ints):
		return false
	if not RoomsScript.valid_ints(rooms_ints, loaded_grid):
		return false
	if not MessagesScript.valid_ints(messages_ints):
		return false
	if not PeopleScript.valid_ints(people_ints):
		return false
	if not GradesScript.valid_ints(grades_ints):
		return false
	var loaded_queue: Array[Command] = []
	for entry in queue_data:
		if not (entry is Array and entry.size() == 3 and entry[2] is Array):
			return false
		if typeof(entry[0]) != TYPE_INT or typeof(entry[1]) != TYPE_INT:
			return false
		var command_args: Array[int] = []
		for arg in entry[2]:
			if typeof(arg) != TYPE_INT:
				return false
			command_args.append(arg)
		loaded_queue.append(Command.make(entry[0], entry[1], command_args))
	clock.load_ints(clock_ints)
	grid = loaded_grid
	var loaded_ledger := LedgerScript.new()
	loaded_ledger.load_ints(ledger_ints)
	ledger = loaded_ledger
	floors.load_ints(floors_ints)
	rooms.load_ints(rooms_ints)
	messages.load_ints(messages_ints)
	people.load_ints(people_ints)
	grades.load_ints(grades_ints)
	last_refusal = data["last_refusal"]
	tick = data["tick"]
	rng.state = data["rng_state"]
	notes = data["notes"]
	stars = loaded_stars
	_queue = loaded_queue
	trips.resume(clock)
	return true
