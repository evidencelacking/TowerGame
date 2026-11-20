class_name SynergyOverlay
extends Node2D
## Draws the synergy overlay (#294) over the tower when SynergyLook.on is set. A child of the renderer, whose
## tower it reads each frame (the tower is assigned after this node exists); it never writes to it. It
## repaints when the option, the room under the cursor, or the tower (every REFRESH_TICKS) changes, and does
## nothing while the option is off.

const SynergyLook := preload("res://scripts/view/synergy_look.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")

const REFRESH_TICKS := 30
const FOLLOW_MOUSE := -2

var hover_id: int = -1  ## The room painted as hovered, or -1.
var hover_override: int = FOLLOW_MOUSE  ## Anything but FOLLOW_MOUSE is used as the hovered room (tests).
var _shown_on: bool = false
var _shown_hover: int = -1
var _shown_tick: int = -1000000


func _ready() -> void:
	z_index = 4  # above the tower's sprite layers
	z_as_relative = false


func _tower() -> Object:
	var parent := get_parent()
	return parent.get("tower") if parent != null else null


func _process(_delta: float) -> void:
	var tower := _tower()
	var on := SynergyLook.on and tower != null
	if not on and not _shown_on:
		return
	hover_id = -1
	if on:
		hover_id = hover_override if hover_override != FOLLOW_MOUSE else RoomInfo.room_at(tower, get_global_mouse_position())
	var tick: int = tower.tick if tower != null else 0
	if on != _shown_on or hover_id != _shown_hover or absi(tick - _shown_tick) >= REFRESH_TICKS:
		_shown_on = on
		_shown_hover = hover_id
		_shown_tick = tick
		queue_redraw()


func _draw() -> void:
	var tower := _tower()
	if tower != null and SynergyLook.on:
		SynergyLook.draw(self, tower, hover_id)
