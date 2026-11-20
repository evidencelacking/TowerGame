extends GraphicsStyle
## Detailed graphics (#301, #302): the G Lit look at double density (16 px per column, 64 px per floor).
## Batch 1 is real: the lobby, offices (every variant and joined suites), condos, hotel rooms and
## housekeeping are drawn by detail_rooms.gd on a 2x sub-pixel grid. Everything else is still Classic's.
## Density is realised without touching the layout: a Detailed room paints into the same world rect as a
## Classic one, in half-pixel steps, and the renderer shows Detailed on a canvas twice the size, so each
## step is a whole screen pixel. Camera, picking and the grid stay in native pixels, and the recipes' spots
## are shared data that this style reports doubled (density 2), which is where its furniture stands.

const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const DetailExterior := preload("res://scripts/view/detail_exterior.gd")
const Palette := preload("res://scripts/view/palette.gd")
const DetailTransport := preload("res://scripts/view/detail_transport.gd")
const DetailPeople := preload("res://scripts/view/detail_people.gd")


func density() -> int:
	return 2


func room(canvas: Object, tower: Tower, id: int, rect: Rect2i, broken: Variant, lit: bool, dark: bool) -> void:
	var look := RoomLook.describe(tower, id, broken)
	var kind: String = look["kind"]
	if not DetailRooms.handles(kind):
		super.room(canvas, tower, id, rect, broken, lit, dark)
		return
	var shown := RoomLook.appearance(look, lit, dark)
	DetailRooms.draw(canvas, kind, rect, shown[0], shown[1], tower.rooms.is_tall_upper(id), id, false, dark)
	RoomLook.draw_marks(canvas, look, rect, tower.rooms.is_tall_upper(id))


func suite(canvas: Object, kind: String, rect: Rect2i, id: int) -> void:
	if not DetailRooms.handles(kind):
		super.suite(canvas, kind, rect, id)
		return
	DetailRooms.draw(canvas, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), true, false, id, true)


func recipe(canvas: Object, kind: String, rect: Rect2i, hue: Color, lit: bool) -> void:
	if not DetailRooms.handles(kind):
		super.recipe(canvas, kind, rect, hue, lit)
		return
	DetailRooms.draw(canvas, kind, rect, hue, lit)


func exterior(canvas: Object, rects: Array[Rect2i], daylight: int) -> void:
	DetailExterior.shell(canvas, rects, daylight)


func street(canvas: Object, daylight: int, world_w: int, ground_y: int, built: Dictionary) -> void:
	DetailExterior.street(canvas, daylight, world_w, ground_y, built)


func skyline(canvas: Object, p: Dictionary, daylight: int, raining: bool, stars: int, depth: int, world_w: int, ground_y: int) -> void:
	DetailExterior.skyline(canvas, p, daylight, raining, stars, depth, world_w, ground_y)


## People (#304): every figure has a look of its own, from its id, age and job (detail_people.gd). Without
## a `who` (a caller that knows nothing of the person) this falls back to Classic's anonymous figure.
func person(canvas: Object, x: int, feet: int, shirt: Color, skin: Color, apart: bool, lift_l: int, lift_r: int, who: Dictionary = {}, pose: int = 0, walk: int = 0) -> void:
	if who.is_empty():
		super.person(canvas, x, feet, shirt, skin, apart, lift_l, lift_r)
		return
	DetailPeople.walker(canvas, x, feet, who, pose, walk)


func activity(canvas: Object, x: int, feet: int, act: int, frame: int, shirt: Color, skin: Color, prop: Color, white: Color, who: Dictionary = {}) -> void:
	if who.is_empty():
		super.activity(canvas, x, feet, act, frame, shirt, skin, prop, white)
		return
	DetailPeople.resting(canvas, x, feet, who, act, frame)


func link(canvas: Object, kind: String, span: Rect2i) -> void:
	if kind == "stairs":
		DetailTransport.stairs(canvas, span)
	else:
		DetailTransport.escalator(canvas, span)


func belt(canvas: Object, span: Rect2i, tick: int, _hue: Color) -> void:
	DetailTransport.belt(canvas, span, tick)


func shaft(canvas: Object, rect: Rect2i, color: Color, caps: Array[Rect2i], door_rows: Array[int], see_through: bool) -> void:
	DetailTransport.shaft(canvas, rect, color, caps, door_rows, see_through)


func car(canvas: Object, shaft_rect: Rect2i, car_rect: Rect2i, level: float, step: int, load: int, _color: Color, people: Array, lamp: Color, floor_bottom_of: Callable) -> void:
	DetailTransport.arrival(canvas, shaft_rect, level, floor_bottom_of)
	DetailTransport.car(canvas, car_rect, load, people)
	var y := car_rect.position.y
	TransportLook.draw_door_gap(canvas, Rect2i(car_rect.position.x - 3, y - 3, car_rect.size.x + 6, VC.CELL_H), y - 3 + VC.CELL_H - VC.SLAB_H, TransportLook.door_open(level, step), lamp)
