class_name HeatOverlay
extends Node2D
## Draws the income / mood heat map (#376) over the tower when HeatLook.mode is not OFF. A child of the
## renderer, whose tower it reads (never writes). Repaints when the mode changes or every REFRESH_TICKS;
## does nothing while off.

const HeatLook := preload("res://scripts/view/heat_look.gd")

const REFRESH_TICKS := 30

var _shown_mode: int = HeatLook.OFF
var _shown_tick: int = -1000000


func _ready() -> void:
	z_index = 4
	z_as_relative = false


func _tower() -> Object:
	var parent := get_parent()
	return parent.get("tower") if parent != null else null


func _process(_delta: float) -> void:
	var tower := _tower()
	var which := HeatLook.mode if tower != null else HeatLook.OFF
	if which == HeatLook.OFF and _shown_mode == HeatLook.OFF:
		return
	var tick: int = tower.tick if tower != null else 0
	if which != _shown_mode or absi(tick - _shown_tick) >= REFRESH_TICKS:
		_shown_mode = which
		_shown_tick = tick
		queue_redraw()


func _draw() -> void:
	var tower := _tower()
	if tower != null and HeatLook.mode != HeatLook.OFF:
		HeatLook.draw(self, tower, HeatLook.mode)
