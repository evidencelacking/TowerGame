class_name ThoughtLayer
extends Node2D
## Draws the thought icons (12.6) over the tower, in a layer of its own on top of the renderer, so both
## graphics styles share it and neither draws icons itself. It reads the figures the renderer drew and
## repaints once per sim tick. View only.

const ThoughtIcons := preload("res://scripts/view/thought_icons.gd")

var tower: Tower = null
var renderer: TowerRenderer = null
var enabled: bool = true
var respect_window: bool = true  ## Off only for captures that want every icon at once.
var _picks: Array[Dictionary] = []
var _seen_tick: int = -1


func bind(tower_value: Tower, renderer_value: TowerRenderer) -> void:
	tower = tower_value
	renderer = renderer_value


## The icons shown now: [{"id", "icon", "at"}].
func picks() -> Array[Dictionary]:
	return _picks


func _process(_delta: float) -> void:
	if tower == null or renderer == null or tower.tick == _seen_tick:
		return
	_seen_tick = tower.tick
	_picks = ThoughtIcons.pick(tower, renderer.figures(), respect_window) if enabled else ([] as Array[Dictionary])
	queue_redraw()


func _draw() -> void:
	for pick: Dictionary in _picks:
		ThoughtIcons.draw_icon(self, pick["icon"], pick["at"])
