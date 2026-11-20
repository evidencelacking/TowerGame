class_name GraphicsStyle
extends RefCounted
## The style backend (#301): how rooms, links, shafts, cars, people and the sky are drawn. This base class
## is Classic, today's drawing code unchanged: each method hands straight to the existing *Look script.
## GraphicsDetailed overrides what it draws differently. The renderer only talks to this interface.
##
## Layout stays semantic. A recipe's furniture and activity spots are data in native pixels at density 1
## (8 px column, 32 px floor); a style drawing at density 2 (16 px column, 64 px floor) multiplies them by
## `density` through scale_spot / spots, so both styles share spots and people stand in the same place.

const RoomLook := preload("res://scripts/view/room_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")

static var _classic: GraphicsStyle = null
static var _detailed: GraphicsStyle = null


## The style the setting picks (ViewSettings.detailed_graphics).
static func current() -> GraphicsStyle:
	return for_detailed(ViewSettings.detailed_graphics)


## Both styles are made on first use (the detailed one is loaded by path: it extends this class).
static func for_detailed(detailed: bool) -> GraphicsStyle:
	if _classic == null:
		_classic = GraphicsStyle.new()
		_detailed = (load("res://scripts/view/graphics_detailed.gd") as GDScript).new()
	return _detailed if detailed else _classic


## Native pixels per Classic pixel: 1 here, 2 for a style drawn at double density.
func density() -> int:
	return 1


## A spot (or any point) given at density `from`, expressed at density `to`.
static func scale_spot(spot: Vector2i, from: int, to: int) -> Vector2i:
	return Vector2i(spot.x * to / from, spot.y * to / from)


## The spots of a room kind in this style's pixels: the shared recipe spots scaled by density.
func spots(kind: String, width_px: int, variant: int = 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for spot: Vector2i in RoomRecipes.spots(kind, width_px, variant):
		out.append(scale_spot(spot, 1, density()))
	return out


## A placed room with its state (broken, in use, everyone asleep).
func room(canvas: Object, tower: Tower, id: int, rect: Rect2i, broken: Variant, lit: bool, dark: bool) -> void:
	RoomLook.draw(canvas, tower, id, rect, broken, lit, dark)


## A joined suite over the union rect of its rooms; id is the first room's.
func suite(canvas: Object, kind: String, rect: Rect2i, id: int) -> void:
	RoomLook.draw_suite(canvas, kind, rect, id)


## A recipe by kind with no room behind it (the lobby).
func recipe(canvas: Object, kind: String, rect: Rect2i, hue: Color, lit: bool) -> void:
	RoomLook.draw_recipe(canvas, kind, rect, hue, lit)


## Stairs or escalator in its two-floor rect.
func link(canvas: Object, kind: String, span: Rect2i) -> void:
	TransportLook.draw_link(canvas, kind, span)


## One shaft: body, machine-room caps (rects), and doors at each stop's floor surface row.
func shaft(canvas: Object, rect: Rect2i, color: Color, caps: Array[Rect2i], door_rows: Array[int], see_through: bool) -> void:
	TransportLook.draw_shaft_body(canvas, rect, color)
	for cap: Rect2i in caps:
		if see_through:
			canvas.draw_rect(cap, color.lightened(0.4), false, 1.0)
		else:
			canvas.draw_rect(cap, color.lightened(0.15))
	for row: int in door_rows:
		TransportLook.draw_doors(canvas, rect, row, color)


## One car: the arrival indicator over its shaft_rect (one floor tall), the car and its riders in
## car_rect, and the door gap lit with `lamp`.
func car(canvas: Object, shaft_rect: Rect2i, car_rect: Rect2i, level: float, step: int, load: int, color: Color, people: Array, lamp: Color, floor_bottom_of: Callable) -> void:
	TransportLook.draw_arrival(canvas, shaft_rect, level, floor_bottom_of)
	TransportLook.draw_car(canvas, car_rect, color, load, people)
	var x := car_rect.position.x
	var y := car_rect.position.y
	TransportLook.draw_door_gap(canvas, Rect2i(x - 3, y - 3, car_rect.size.x + 6, VC.CELL_H), y - 3 + VC.CELL_H - VC.SLAB_H, TransportLook.door_open(level, step), lamp)


## A person walking or riding.
func person(canvas: Object, x: int, feet: int, shirt: Color, skin: Color, apart: bool, lift_l: int, lift_r: int) -> void:
	ActivityLook.draw_person(canvas, x, feet, shirt, skin, apart, lift_l, lift_r)


## A person resting on a recipe spot, doing an activity.
func activity(canvas: Object, x: int, feet: int, act: int, frame: int, shirt: Color, skin: Color, prop: Color, white: Color) -> void:
	ActivityLook.draw(canvas, x, feet, act, frame, shirt, skin, prop, white)


## The sky band above the ground.
func sky(canvas: Object, p: Dictionary, minute: int, left: int, top: int, width: int, ground_y: int, world_w: int) -> void:
	SkyLook.draw(canvas, p, minute, SkyLook.daylight, SkyLook.rain, left, top, width, ground_y, world_w, VC.CELL_H)


## The outside of the tower (#306): facade edges and roofs over the built floor runs, the street along the
## ground, and a layer of city skyline behind. Classic draws none of it.
func exterior(_canvas: Object, _rects: Array[Rect2i], _daylight: int) -> void:
	pass


func street(_canvas: Object, _daylight: int, _world_w: int, _ground_y: int, _built: Dictionary) -> void:
	pass


func skyline(_canvas: Object, _p: Dictionary, _daylight: int, _raining: bool, _stars: int, _depth: int, _world_w: int, _ground_y: int) -> void:
	pass
