extends Node2D
## One piece of the outdoors behind the tower (#306): a far skyline, a near skyline or the street. The
## renderer adds three of these before its own sprites, so they sit in front of the sky and behind every
## room. The skylines slide against the camera by `factor` (1 stays fixed to the world, lower trails
## behind it) and grow with the star rating; the street stays put. What a layer draws is the style's call, so
## Classic, whose methods draw nothing, shows nothing.

const SkyLook := preload("res://scripts/view/sky_look.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")

const STREET := -1  ## `depth` of the street layer; 0 and 1 are the far and near skylines.

var depth: int = 0
var factor: float = 1.0
var stars: int = 1
var daylight: int = SkyLook.FULL
var raining: bool = false
var built: Dictionary = {}  ## Columns of floor 1 with floor units: the street leaves these clear.


## Moves the layer against the camera: the world's middle stays where it is, the rest trails by 1 - factor.
func follow(camera_x: float) -> void:
	var world_w := VC.world_rect().size.x
	position.x = roundf((camera_x - world_w * 0.5) * (1.0 - factor))


func _draw() -> void:
	var world_w := int(VC.world_rect().size.x)
	var ground_y := VC.GridScript.FLOOR_MAX * VC.CELL_H
	var style := GraphicsStyle.current()
	if depth == STREET:
		style.street(self, daylight, world_w, ground_y, built)
	else:
		style.skyline(self, Palette.get_palette(), daylight, raining, stars, depth, world_w, ground_y)
