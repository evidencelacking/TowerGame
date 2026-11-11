extends RefCounted
## Camera clamp and world bounds, headless.

const Cam := preload("res://scripts/view/tower_camera.gd")
const VC := preload("res://scripts/view/view_consts.gd")


static func run(check: Callable) -> void:
	var world: Rect2 = VC.world_rect()
	check.call(world.size == Vector2(400 * VC.CELL_PX, 110 * VC.CELL_PX), "world size")
	check.call(VC.floor_to_row(100) == 0, "floor 100 is the top row")
	check.call(VC.floor_to_row(1) == 99 and VC.floor_to_row(-1) == 100, "no floor 0 between 1 and B1")
	check.call(VC.floor_to_row(-10) == 109, "B10 is the last row")
	var view := Vector2(1920, 1080)
	for z: int in Cam.ZOOM_STEPS:
		var half: Vector2 = view / (2.0 * z)
		var top: Vector2 = Cam.clamp_position(Vector2(-1e6, -1e6), view, z, world)
		var bot: Vector2 = Cam.clamp_position(Vector2(1e6, 1e6), view, z, world)
		check.call(top.y - half.y >= world.position.y - 0.01, "top edge zoom %d" % z)
		check.call(bot.y + half.y <= world.end.y + 0.01, "bottom edge zoom %d" % z)
		check.call(top.x - half.x >= world.position.x - 0.01 and bot.x + half.x <= world.end.x + 0.01, "x edges zoom %d" % z)
	# At zoom 1 the view (1080px) is narrower than the tower (1760px): the top clamp shows floor 100.
	var t1: Vector2 = Cam.clamp_position(Vector2(-1e6, -1e6), view, 1, world)
	check.call(t1.y - 540.0 == 0.0, "camera reaches the floor 100 top and no further")
	var b1: Vector2 = Cam.clamp_position(Vector2(1e6, 1e6), view, 1, world)
	check.call(b1.y + 540.0 == world.end.y, "camera reaches the B10 bottom and no further")
	# A view bigger than the world is centred.
	var c: Vector2 = Cam.clamp_position(Vector2(5, 5), Vector2(100000, 100000), 1, world)
	check.call(c == world.get_center(), "oversized view centres")
	# Starting on the lobby and zooming in keeps the lobby row visible at every zoom.
	var focus: Vector2 = Cam.start_focus()
	var lobby_top: float = VC.floor_to_row(1) * VC.CELL_PX
	for z: int in Cam.ZOOM_STEPS:
		var pos: Vector2 = Cam.view_position(focus, view, z, world)
		var vis := Rect2(pos - view / (2.0 * z), view / float(z))
		check.call(vis.position.y <= lobby_top and vis.end.y >= lobby_top + VC.CELL_PX, "lobby visible at zoom %d" % z)
	# Cursor-anchored zoom keeps the world point under the cursor at the same screen spot.
	var centre := Vector2(800, 900)
	var cursor_world := Vector2(1000, 950)
	for z: int in range(1, 4):
		var nz: int = z + 1
		var before: Vector2 = (cursor_world - centre) * z
		var nc: Vector2 = Cam.zoom_about(centre, cursor_world, z, nz)
		var after: Vector2 = (cursor_world - nc) * nz
		check.call((after - before).length() <= 1.0, "cursor stays put zooming %d to %d" % [z, nz])
