extends GraphicsStyle
## Detailed graphics (#301, #302): the G Lit look at double density (16 px per column, 64 px per floor).
## Batch 1 is real: the lobby, offices (every variant and joined suites), condos, hotel rooms and
## housekeeping are drawn by detail_rooms.gd on a 2x sub-pixel grid. Everything else is still Classic's.
## Density is realised without touching the layout: a Detailed room paints into the same world rect as a
## Classic one, in half-pixel steps, and the renderer shows Detailed on a canvas twice the size, so each
## step is a whole screen pixel. Camera, picking and the grid stay in native pixels, and the recipes' spots
## are shared data that this style reports doubled (density 2), which is where its furniture stands.

const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const Palette := preload("res://scripts/view/palette.gd")


func density() -> int:
	return 2


func room(canvas: Object, tower: Tower, id: int, rect: Rect2i, broken: Variant, lit: bool, dark: bool) -> void:
	var look := RoomLook.describe(tower, id, broken)
	var kind: String = look["kind"]
	if not DetailRooms.handles(kind):
		super.room(canvas, tower, id, rect, broken, lit, dark)
		return
	var shown := RoomLook.appearance(look, lit, dark)
	DetailRooms.draw(canvas, kind, rect, shown[0], shown[1], tower.rooms.is_tall_upper(id), id)
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
