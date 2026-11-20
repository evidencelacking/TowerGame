extends SceneTree
## Documentation capture for the Detailed people (#304): a sheet of figures drawn by the real
## detail_people.gd through the Detailed style, rasterised in software (no window needed) at the 2x
## density and saved enlarged. Rows: variety by id, age and job; the walk cycle, stairs; every activity;
## sleepers. Exits with an error when the picture could not be saved.
## Run: <godot exe> --headless --path . --script res://tools/capture_detailed_people.gd -- out=docs/mockups/detailed_people.png

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")

const ZOOM := 4  ## The saved picture is enlarged by this much, nearest-neighbour.
const WORLD_W := 232
const WORLD_H := 160
const ROW_H := 40
const STEP := 17  ## World pixels between figures.
const WALL := Color("5a4a5e")
const FLOOR_LINE := Color("2a2030")


## Paints draw_rect calls into an image at 2 pixels per world pixel (the Detailed density).
class Raster:
	extends RefCounted
	const PER_PIXEL := 2
	var img: Image

	func _init(w: int, h: int, bg: Color) -> void:
		img = Image.create(w * PER_PIXEL, h * PER_PIXEL, false, Image.FORMAT_RGBA8)
		img.fill(bg)

	func draw_rect(r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		var rect := Rect2(r)
		var x0 := roundi(rect.position.x * PER_PIXEL)
		var y0 := roundi(rect.position.y * PER_PIXEL)
		var x1 := roundi(rect.end.x * PER_PIXEL)
		var y1 := roundi(rect.end.y * PER_PIXEL)
		for y in range(maxi(y0, 0), mini(y1, img.get_height())):
			for x in range(maxi(x0, 0), mini(x1, img.get_width())):
				img.set_pixel(x, y, c)

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		pass


func _init() -> void:
	var out := "docs/mockups/detailed_people.png"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
	var ras := Raster.new(WORLD_W, WORLD_H, WALL)
	var style := GraphicsStyle.for_detailed(true)
	for row in 4:  # a floor line under each row
		ras.draw_rect(Rect2(0, row * ROW_H + ROW_H - 3, WORLD_W, 3), FLOOR_LINE)
	var feet := ROW_H - 4
	# Row 0: variety: children, adults, seniors and jobs (id, age, child, job).
	var cast: Array = [[1, 1, false, ""], [2, 1, false, ""], [3, 1, false, ""], [4, 2, false, ""], [5, 2, false, ""], [6, 0, true, ""], [7, 0, true, ""],
		[8, 1, false, "office"], [9, 1, false, "office"], [10, 1, false, "fast_food"], [11, 1, false, "restaurant"], [12, 1, false, "housekeeping"], [13, 1, false, "security"]]
	for n in cast.size():
		var c: Array = cast[n]
		var who := {"id": c[0], "age": c[1], "child": c[2], "job": c[3], "dir": 1}
		style.person(ras, 4 + n * STEP, feet, Color.WHITE, Color.WHITE, false, 0, 0, who, 0, 0)
	# Row 1: one person's walk cycle (4 frames each way) and stairs frames.
	var row := ROW_H
	for f in 4:
		style.person(ras, 4 + f * STEP, row + feet, Color.WHITE, Color.WHITE, false, 0, 0, {"id": 21, "age": 1, "dir": 1}, 0, f)
		style.person(ras, 80 + f * STEP, row + feet, Color.WHITE, Color.WHITE, false, 0, 0, {"id": 22, "age": 1, "dir": -1}, 0, f)
		style.person(ras, 150 + f * STEP, row + feet, Color.WHITE, Color.WHITE, false, 0, 0, {"id": 23, "age": 1, "dir": 1}, 1, f)
	# Row 2: every activity at rest.
	row = ROW_H * 2
	var acts: Array = [ActivityLook.IDLE, ActivityLook.WORKING, ActivityLook.BREAK, ActivityLook.LUNCH, ActivityLook.EATING, ActivityLook.QUEUEING, ActivityLook.SHOPPING, ActivityLook.CLEANING]
	for n in acts.size():
		var who := {"id": 30 + n, "age": 1, "job": "office" if acts[n] == ActivityLook.WORKING else "", "dir": 1}
		style.activity(ras, 4 + n * 22, row + feet, acts[n], 1, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, who)
	# Row 3: sleepers through a breath, different people.
	row = ROW_H * 3
	for n in 6:
		var who := {"id": 40 + n, "age": 1 if n < 4 else 2, "child": n == 3, "dir": 1}
		style.activity(ras, 4 + n * 36, row + feet, ActivityLook.SLEEPING, n, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, who)
	var big := ras.img
	big.resize(big.get_width() * ZOOM, big.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	var err := big.save_png(out)
	print("captured ", out, " (", err, ")")
	quit(0 if err == OK else 1)
