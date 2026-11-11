class_name SimDriver
extends Node
## Fixed-tick driver: owns the Tower and steps it from real frame time. Speed and pause only
## change how many fixed sim ticks run per frame; the sim never sees a float or the clock.

const Tower := preload("res://scripts/sim/tower.gd")

const BASE_TICKS_PER_SECOND := 30.0
const SPEEDS: Array[int] = [1, 2, 3]  ## Multipliers of the base rate; index 0 is speed 1.
const MAX_TICKS_PER_FRAME := 20  ## Caps catch-up after a stall so a hitch can't spiral.

var tower: Tower = Tower.new()
var paused: bool = false
var speed_index: int = 0

var _accumulator: float = 0.0


func _process(delta: float) -> void:
	run_frame(delta)


## Steps the sim for delta real seconds. Returns the number of ticks run.
func run_frame(delta: float) -> int:
	if paused:
		return 0
	_accumulator += delta * BASE_TICKS_PER_SECOND * SPEEDS[speed_index]
	var ticks: int = mini(int(_accumulator), MAX_TICKS_PER_FRAME)
	_accumulator = 0.0 if ticks == MAX_TICKS_PER_FRAME else _accumulator - ticks
	for _i in ticks:
		tower.step()
	return ticks


func set_paused(value: bool) -> void:
	paused = value


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
