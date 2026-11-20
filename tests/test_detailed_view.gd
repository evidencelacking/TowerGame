extends RefCounted
## The Detailed view's skin, canvas size and zoom steps (#307), headless: the G Lit theme goes on and comes off
## leaving the default theme as it was, the canvases cover exactly the built tower (grain-snapped, inside the
## world), and Detailed offers no odd zoom 3.

const Cam := preload("res://scripts/view/tower_camera.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")


static func run(check: Callable) -> void:
	_skin(check)
	_canvas(check)
	_zoom(check)


static func _skin(check: Callable) -> void:
	var theme := ThemeDB.get_default_theme()
	check.call(theme != null, "a default theme exists")
	if theme == null:
		return
	var before_box := theme.get_stylebox("normal", "Button")
	var before_panel := theme.get_stylebox("panel", "PanelContainer")
	var before_font := theme.get_color("font_color", "Label")
	UiSkin.apply(true)
	check.call(UiSkin.is_on(), "skin is on after apply(true)")
	check.call((theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color == UiSkin.WOOD, "Detailed buttons are wood")
	check.call((theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color == UiSkin.SLATE, "Detailed panels are slate")
	check.call(theme.get_color("font_color", "Label") == UiSkin.CREAM, "Detailed labels are cream")
	UiSkin.apply(true)  # twice must not lose the originals
	UiSkin.apply(false)
	check.call(not UiSkin.is_on(), "skin is off after apply(false)")
	check.call(theme.get_stylebox("normal", "Button") == before_box, "Classic button style is the original object again")
	check.call(theme.get_stylebox("panel", "PanelContainer") == before_panel, "Classic panel style is the original object again")
	check.call(theme.get_color("font_color", "Label") == before_font, "Classic label colour restored")
	# Every item the skin sets must be well formed, so a typo in a type or name shows here.
	var bad := 0
	var items := UiSkin.items()
	for item: Array in items:
		var ok: bool = (item[0] == "style" and item[3] is StyleBoxFlat) or (item[0] == "color" and item[3] is Color)
		if not ok or str(item[1]) == "" or str(item[2]) == "":
			bad += 1
	check.call(bad == 0 and items.size() > 30, "skin items are all styleboxes or colours with a type and a name")


static func _canvas(check: Callable) -> void:
	var renderer := TowerRenderer.new()
	var world := Rect2i(VC.world_rect())
	var empty := renderer._canvas_bounds()
	check.call(empty.size == TowerRenderer.CANVAS_GRAIN, "an empty tower gets one grain of canvas")
	# A 13-row tower: a floor run across the world, rooms on it, a stair link.
	renderer._floor_rects.append(Rect2i(0, 2816, 3200, 32))
	renderer._floor_rects.append(Rect2i(200, 2432, 800, 32))
	renderer._room_runs.append([1, 1, Rect2i(240, 2432, 96, 32)])
	renderer._link_runs.append([0, Rect2i(400, 2432, 32, 64)])
	var used := Rect2i(0, 2432, 3200, 416)
	var bounds := renderer._canvas_bounds()
	check.call(bounds.encloses(used), "the canvas encloses every built rect")
	check.call(world.encloses(bounds), "the canvas stays inside the world")
	check.call(bounds.position.x % TowerRenderer.CANVAS_GRAIN.x == 0 and bounds.position.y % TowerRenderer.CANVAS_GRAIN.y == 0, "the canvas origin sits on the grain")
	check.call(bounds.size.y < world.size.y / 4, "a short tower costs a fraction of the full-height canvas")
	# A floor built inside the padded area, within the same grain, keeps the canvas as it was.
	renderer._floor_rects.append(Rect2i(0, bounds.position.y + TowerRenderer.CANVAS_PAD.y, 800, 32))
	check.call(renderer._canvas_bounds() == bounds, "building inside the padded area does not resize the canvas")
	renderer.free()


static func _zoom(check: Callable) -> void:
	var was := ViewSettings.detailed_graphics
	ViewSettings.detailed_graphics = false
	check.call(Cam.allowed(3), "Classic offers zoom 3")
	ViewSettings.detailed_graphics = true
	check.call(not Cam.allowed(3), "Detailed skips zoom 3 (its 2x canvas would show at 1.5)")
	for z: int in [1, 2, 4, 6]:
		check.call(Cam.allowed(z), "Detailed offers zoom %d" % z)
	var camera := Cam.new()
	camera.set_zoom_index(1)  # zoom 2
	camera.set_zoom_index(2)  # zoom 3 is not allowed: lands on 4
	check.call(camera._zoom_index == 3, "stepping in from 2 in Detailed lands on 4")
	camera.set_zoom_index(2)  # zoom 3 again, from above: lands on 2
	check.call(camera._zoom_index == 1, "stepping out from 4 in Detailed lands on 2")
	camera.free()
	ViewSettings.detailed_graphics = was
