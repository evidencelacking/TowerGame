class_name Tower
extends RefCounted
## The tower simulation state. Integers only; see CLAUDE.md.
##
## 1 tick = 1 frame. step() is the only thing that advances time. Input reaches the state
## only as Commands: queue them with enqueue(), and step() applies those due at the new
## tick, in queue order, at one fixed point (see step). Everything random comes from rng.

const Rng := preload("res://scripts/sim/sim_rng.gd")
const Clock := preload("res://scripts/sim/clock.gd")

## The only way input changes the simulation. Queued for a tick and applied at one fixed
## point in that tick (see step). Integers only, so it saves and hashes exactly.
class Command:
	extends RefCounted
	## Command kinds. Add new kinds on their own line; Tower._apply_command handles each.
	const NOTE := 1  ## Foundation placeholder: adds args[0] to Tower.notes.
	const ROLL := 2  ## Foundation placeholder: adds a random draw below args[0] to Tower.notes.

	var tick: int = 0  ## The tick this command applies at.
	var kind: int = 0
	var args: Array[int] = []

	static func make(for_tick: int, command_kind: int, command_args: Array[int] = []) -> Command:
		var command := Command.new()
		command.tick = for_tick
		command.kind = command_kind
		command.args = command_args.duplicate()
		return command


const SAVE_VERSION := 2
const HASH_OFFSET := -3750763034362895579  # FNV-1a 64-bit offset basis, as signed
const HASH_PRIME := 1099511628211

var tick: int = 0
var rng := Rng.new()
var clock := Clock.new()
## Placeholder state that commands change, so tests can see them. Replaced as real state lands.
var notes: int = 0

var _queue: Array[Command] = []


func _init(seed_value: int = 0) -> void:
	rng.reseed(seed_value)


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
	return {"version": SAVE_VERSION, "tick": tick, "rng_state": rng.state, "notes": notes, "clock": clock.state_ints(), "queue": queued}


## Replaces this tower's state with a save() result. Returns false, changing nothing, if
## the data is not a supported save.
func load_state(data: Dictionary) -> bool:
	if data.get("version", 0) != SAVE_VERSION:
		return false
	if not clock.load_ints(data["clock"]):
		return false
	tick = data["tick"]
	rng.state = data["rng_state"]
	notes = data["notes"]
	_queue.clear()
	for entry: Array in data["queue"]:
		var command_args: Array[int] = []
		command_args.assign(entry[2])
		_queue.append(Command.make(entry[0], entry[1], command_args))
	return true
