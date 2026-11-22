class_name ShaftNumbers
extends RefCounted
## Floor numbers in the background of each elevator shaft cell (#431): a small faint label per floor, so a
## shaft doubles as a floor reference while building. View only. Drawn by the renderer's shaft layer after the
## style has drawn the shaft, so Classic and Detailed (glass or opaque) share it, and it is repainted with the
## shaft piece (a resize, a style change) like the rest of the shaft.

const ElevatorTools := preload("res://scripts/view/elevator_tools.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const ZOOM_ALL: float = 2.0  ## From this camera zoom up every floor is labelled.
const FAR_STEP: int = 5  ## Below it, the lobby and every 5th floor (5, 10, ... B5, ...).
const PLAQUE_TOP: int = 17  ## Rows from the top of the floor cell: inside the door frame, clear of the indicator above it.
const PLAQUE_ALPHA: float = 0.7
const GLYPH_W: int = 3
const GLYPH_H: int = 5
const ADVANCE: int = 4
## 3x5 pixel digits and B, one int per row (top to bottom), bit 2 the left column: crisp at any zoom, whole pixels.
const GLYPHS: Dictionary = {
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7], "4": [5, 5, 7, 1, 1],
	"5": [7, 4, 7, 1, 7], "6": [7, 4, 7, 5, 7], "7": [7, 1, 1, 1, 1], "8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 7],
	"B": [6, 5, 6, 5, 6],
}


## The label of a floor: B1, B2 ... below the lobby, 1 for the lobby (there is no floor 0), then 2, 3 ...
static func label(floor_number: int) -> String:
	return ElevatorTools.floor_label(floor_number)


## How many floors apart the labels are at a camera zoom (1 means every floor).
static func step_for_zoom(zoom: float) -> int:
	return 1 if zoom >= ZOOM_ALL else FAR_STEP


## Whether a floor is labelled at this step: the ground floors (1 and B1) always, then multiples of step.
static func shown(floor_number: int, step: int) -> bool:
	return step <= 1 or absi(floor_number) == 1 or floor_number % step == 0


## Draws the labels for floors bottom..top of a shaft whose rect is given: each a light pixel number on a small
## dark plaque (so it reads over any room behind a glass shaft). Machine-room floors are not in the range.
static func draw(canvas: Object, rect: Rect2i, bottom: int, top: int, step: int, _shaft_color: Color) -> void:
	var plaque := Color(0.03, 0.04, 0.07, PLAQUE_ALPHA)
	var ink := Color(0.93, 0.92, 0.85)
	for floor_number: int in range(bottom, top + 1):
		if floor_number == 0 or not shown(floor_number, step):
			continue
		var text := label(floor_number)
		var w := text.length() * ADVANCE - 1
		var x := rect.position.x + (rect.size.x - w) / 2
		var y := VC.floor_to_row(floor_number) * VC.CELL_H + PLAQUE_TOP
		canvas.draw_rect(Rect2i(x - 1, y - 1, w + 2, GLYPH_H + 2), plaque)
		for n: int in text.length():
			var rows: Array = GLYPHS[text[n]]
			for r: int in GLYPH_H:
				for c: int in GLYPH_W:
					if (rows[r] as int) & (4 >> c) != 0:
						canvas.draw_rect(Rect2i(x + n * ADVANCE + c, y + r, 1, 1), ink)
