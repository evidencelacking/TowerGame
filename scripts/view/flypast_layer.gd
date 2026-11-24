extends Node2D
## The seasonal fly-past (9.7, #222): a lantern-like craft drifts across the night sky behind the tower on a Q4
## weekend, 21:00 to 23:00. Our own design, drawn by code in whole-pixel rects: a paper lantern with ribs, a warm glow,
## a cap and tassel, and a little trail of sparks. It is a pure function of the sim's clock (Weather.flypast_progress),
## draws nothing outside the window, saves nothing and changes nothing in the sim. The renderer adds it before the
## room layers, so every room hides it where they overlap.

const BODY_ROWS: Array[int] = [10, 16, 20, 22, 22, 20, 16, 10]  ## Widths of the lantern's rows, top to bottom.
const ROW_H := 5  ## Drawn pixels per row.
const UNIT := 1  ## World pixels per drawn pixel of the craft.
const BOB: Array[int] = [0, 1, 2, 3, 2, 1, 0, -1, -2, -3, -2, -1]
const MARGIN := 80  ## World pixels the craft starts and ends beyond the view's edges.
const HEIGHT_FROM_TOP := 0.28  ## Where in the view it floats: this share down from the top.

var progress: int = -1  ## 0 to 999 across the sky, or -1 when it is not flying.


## The craft's centre as an offset in world pixels from the view's left edge: just left of the view at progress 0,
## just right of it at 1000, so it always crosses what the player can see.
static func x_in_view(at_progress: int, view_width: float) -> float:
	var travel: float = view_width + 2.0 * MARGIN
	return -MARGIN + travel * float(clampi(at_progress, 0, 1000)) / 1000.0


## The slow bob, in world pixels, for a progress.
static func bob_at(at_progress: int) -> int:
	return BOB[(maxi(at_progress, 0) / 6) % BOB.size()] * UNIT


## Places the craft for a camera: the node's position is its centre in world space. Hidden outside the window.
func follow(at_progress: int, camera_pos: Vector2, view_size: Vector2) -> void:
	if at_progress < 0:
		progress = -1
		visible = false
		return
	var left: float = camera_pos.x - view_size.x * 0.5
	var top: float = camera_pos.y - view_size.y * 0.5
	var spot := Vector2(roundf(left + x_in_view(at_progress, view_size.x)), roundf(top + view_size.y * HEIGHT_FROM_TOP + bob_at(at_progress)))
	if not visible or spot != position or at_progress != progress:
		visible = true
		position = spot
		progress = at_progress
		queue_redraw()


func _draw() -> void:
	if progress < 0:
		return
	var rows: int = BODY_ROWS.size()
	var height: int = rows * ROW_H * UNIT
	var top: int = -height / 2
	# The warm glow: three soft ellipses behind the paper, widest and faintest first.
	_halo(Vector2i(26, height / 2 + 12), Color(1.0, 0.7, 0.3, 0.06))
	_halo(Vector2i(20, height / 2 + 7), Color(1.0, 0.74, 0.32, 0.09))
	_halo(Vector2i(15, height / 2 + 3), Color(1.0, 0.78, 0.36, 0.13))
	# The paper: rows that swell and narrow, a bright core and darker ribs.
	for row in rows:
		var w: int = BODY_ROWS[row] * UNIT
		var y: int = top + row * ROW_H * UNIT
		draw_rect(Rect2i(-w / 2, y, w, ROW_H * UNIT), Color("e8742a"))
		draw_rect(Rect2i(-w / 4, y, w / 2, ROW_H * UNIT), Color("ffb347"))
		draw_rect(Rect2i(-UNIT, y, 2 * UNIT, ROW_H * UNIT), Color("ffe08a"))
		draw_rect(Rect2i(-w / 2, y, UNIT, ROW_H * UNIT), Color("b4491c"))
		draw_rect(Rect2i(w / 2 - UNIT, y, UNIT, ROW_H * UNIT), Color("b4491c"))
	# Cap, loop and tassel.
	draw_rect(Rect2i(-6 * UNIT, top - 3 * UNIT, 12 * UNIT, 3 * UNIT), Color("5a2a1a"))
	draw_rect(Rect2i(-UNIT, top - 7 * UNIT, 2 * UNIT, 4 * UNIT), Color("5a2a1a"))
	draw_rect(Rect2i(-6 * UNIT, top + height, 12 * UNIT, 2 * UNIT), Color("5a2a1a"))
	draw_rect(Rect2i(-UNIT, top + height + 2 * UNIT, 2 * UNIT, 6 * UNIT), Color("ffd27a"))
	draw_rect(Rect2i(-2 * UNIT, top + height + 8 * UNIT, 4 * UNIT, 3 * UNIT), Color("ffd27a"))
	# A trail of sparks drifting back along the way it came, each fainter than the last.
	for n in 6:
		var back: int = -(16 + n * 9) * UNIT
		var rise: int = (n * 5 + progress / 10) % 7 - 3
		draw_rect(Rect2i(back, rise * UNIT, 2 * UNIT, 2 * UNIT), Color(1.0, 0.82, 0.4, 0.75 - 0.11 * n))


## A filled ellipse of the given half sizes about the origin, in whole-pixel rows two pixels tall.
func _halo(radius: Vector2i, color: Color) -> void:
	for y in range(-radius.y, radius.y, 2):
		var across: float = sqrt(1.0 - pow(float(y + 1) / float(radius.y), 2.0))
		var half: int = int(float(radius.x) * across) * UNIT
		draw_rect(Rect2i(-half, y * UNIT, half * 2, 2 * UNIT), color)
