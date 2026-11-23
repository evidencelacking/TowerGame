class_name SimDriver
extends Node
## Fixed-tick driver: owns the Tower and steps it from real frame time. Speed and pause only
## change how many fixed sim ticks run per frame; the sim never sees a float or the clock.

const Tower := preload("res://scripts/sim/tower.gd")

const BASE_TICKS_PER_SECOND := 30.0
const SPEEDS: Array[int] = [1, 2, 3]  ## Multipliers of the base rate; index 0 is speed 1.
const MAX_TICKS_PER_FRAME := 4  ## Caps catch-up after a stall so a hitch can't spiral (top speed needs 1.5 a frame at 60 fps).
const FRAME_BUDGET_USEC := 8000  ## Stops stepping once the frame's sim work has spent this long (#417).

var tower: Tower = Tower.new()
var paused: bool = false
var speed_index: int = 0
## Off by default so tests never write files; the game scene turns it on. Saves the tower at the
## start of every quarter (see SaveFiles).
var autosave_enabled: bool = false

## Per-frame limits; tests set them so nothing depends on wall-clock speed. A negative budget means no time limit.
var max_ticks_per_frame: int = MAX_TICKS_PER_FRAME
var budget_usec: int = FRAME_BUDGET_USEC

var _accumulator: float = 0.0
var _dropping: bool = false
var _slow: bool = false
var _drop_score: float = 0.0  ## Seconds of net dropping, 0..SLOW_HOLD_SECONDS; drop frames add their delta, clean frames subtract it.
var _calm_time: float = 0.0  ## Seconds since the last dropped frame.

const SLOW_HOLD_SECONDS := 1.0  ## Dropping this long turns the slow flag on; this long without a drop turns it off.


## True when the last frame dropped sim time because of the tick cap or the time budget. Flips frame to frame, so
## the HUD uses running_slow() instead.
func dropping_now() -> bool:
	return _dropping


## True once dropping has gone on for about a second, until about a second passes with no drops. Measured by the
## frame deltas, not the clock, so it is steady enough to show in the HUD.
func running_slow() -> bool:
	return _slow


func _process(delta: float) -> void:
	run_frame(delta)


## Steps the sim for delta real seconds. Returns the number of ticks run.
func run_frame(delta: float) -> int:
	if paused:
		_dropping = false
		_slow = false
		_drop_score = 0.0
		_calm_time = 0.0
		return 0
	_accumulator += delta * BASE_TICKS_PER_SECOND * SPEEDS[speed_index]
	var due := int(_accumulator)
	var ticks := mini(due, max_ticks_per_frame)
	var started := Time.get_ticks_usec()
	var run := 0
	while run < ticks:
		tower.step()
		run += 1
		if autosave_enabled and tower.clock.quarter_started:
			SaveFiles.autosave(tower)
		if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
	# Debt the frame could not pay is dropped, not carried, so a slow frame never snowballs into the next.
	_dropping = run < due
	_update_slow(delta)
	_accumulator = _accumulator - run if run == due else 0.0
	return run


func _update_slow(delta: float) -> void:
	if _dropping:
		_calm_time = 0.0
		_drop_score = minf(_drop_score + delta, SLOW_HOLD_SECONDS)
		if _drop_score >= SLOW_HOLD_SECONDS:
			_slow = true
	else:
		_calm_time += delta
		_drop_score = maxf(_drop_score - delta, 0.0)
		if _slow and _calm_time >= SLOW_HOLD_SECONDS:
			_slow = false
			_drop_score = 0.0


func set_paused(value: bool) -> void:
	paused = value


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
