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

	var tick: int = 0  ## The tick this command applies at.
	var kind: int = 0
	var args: Array[int] = []

	static func make(for_tick: int, command_kind: int, command_args: Array[int] = []) -> Command:
		var command := Command.new()
		command.tick = for_tick
		command.kind = command_kind
		command.args = command_args.duplicate()
		return command


const SAVE_VERSION := 5
const HASH_OFFSET := -3750763034362895579  # FNV-1a 64-bit offset basis, as signed
const HASH_PRIME := 1099511628211

var tick: int = 0
var rng := Rng.new()
var clock := Clock.new()
var grid := Grid.new()
var ledger := LedgerScript.new()
var floors := FloorsScript.new()
## Result of the most recent PURCHASE, BUILD_FLOOR or BUILD_LOBBY command (OK or a refusal reason; see
## Ledger and Floors for the codes).
var last_refusal: int = 0
## Placeholder state that commands change, so tests can see them. Replaced as real state lands.
var notes: int = 0

var _queue: Array[Command] = []


func _init(seed_value: int = 0, starting_funds: int = LedgerScript.DEFAULT_STARTING_FUNDS) -> void:
	rng.reseed(seed_value)
	ledger = LedgerScript.new(starting_funds)


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
		Command.REFUND:
			if command.args.size() == 2:
				ledger.refund(tick, command.args[0], command.args[1])
		Command.BUILD_FLOOR:
			if command.args.size() == 3:
				last_refusal = floors.build_span(ledger, tick, command.args[0], command.args[1], command.args[2])
		Command.BUILD_LOBBY:
			if command.args.size() == 4:
				last_refusal = floors.build_lobby(ledger, tick, command.args[0], command.args[1], command.args[2], command.args[3])
		_:
			push_error("Unknown sim command kind %d" % command.kind)


## Per-tick systems, in a fixed order: the clock first, then (later) the grid and the rest.
func _run_systems() -> void:
	clock.advance()


## Deterministic 64-bit hash of the whole simulation state, RNG and queue included.
func state_hash() -> int:
	var h := HASH_OFFSET
	for value in _state_ints():
		h = _mix(h, value)
	return h


func _state_ints() -> Array[int]:
	var ints: Array[int] = [tick, rng.state, notes]
	ints.append_array(clock.state_ints())
	ints.append(grid.occupant_count())
	ints.append_array(grid.state_ints())
	ints.append_array(ledger.state_ints())
	ints.append_array(floors.state_ints())
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
	return {"version": SAVE_VERSION, "tick": tick, "rng_state": rng.state, "notes": notes, "clock": clock.state_ints(), "grid": grid.state_ints(), "ledger": ledger.state_ints(), "floors": floors.state_ints(), "last_refusal": last_refusal, "queue": queued}


## Replaces this tower's state with a save() result. Returns false, changing nothing, if
## the data is not a supported save: every part is validated before any field is assigned.
func load_state(data: Dictionary) -> bool:
	if data.get("version", 0) != SAVE_VERSION:
		return false
	for key in ["tick", "rng_state", "notes", "last_refusal"]:
		if typeof(data.get(key)) != TYPE_INT:
			return false
	var clock_ints: Variant = data.get("clock")
	var grid_ints: Variant = data.get("grid")
	var ledger_ints: Variant = data.get("ledger")
	var floors_ints: Variant = data.get("floors")
	var queue_data: Variant = data.get("queue")
	if not (clock_ints is Array and grid_ints is Array and ledger_ints is Array and floors_ints is Array and queue_data is Array):
		return false
	var loaded_grid := Grid.new()
	if not Clock.valid_ints(clock_ints) or not loaded_grid.load_ints(grid_ints) or not LedgerScript.valid_ints(ledger_ints) or not FloorsScript.valid_ints(floors_ints):
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
	last_refusal = data["last_refusal"]
	tick = data["tick"]
	rng.state = data["rng_state"]
	notes = data["notes"]
	_queue = loaded_queue
	return true
