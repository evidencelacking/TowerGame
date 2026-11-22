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
const FONT_SIZE: int = 8
const LABEL_BASE: int = 24  ## Baseline inside the floor cell: in the door frame, clear of the indicator above it.
const ALPHA: float = 0.7  ## Faint: the car stays the clearest thing in the shaft.


## The label of a floor: B1, B2 ... below the lobby, 1 for the lobby (there is no floor 0), then 2, 3 ...
static func label(floor_number: int) -> String:
	return ElevatorTools.floor_label(floor_number)


## How many floors apart the labels are at a camera zoom (1 means every floor).
static func step_for_zoom(zoom: float) -> int:
	return 1 if zoom >= ZOOM_ALL else FAR_STEP


## Whether a floor is labelled at this step: the ground floors (1 and B1) always, then multiples of step.
static func shown(floor_number: int, step: int) -> bool:
	return step <= 1 or absi(floor_number) == 1 or floor_number % step == 0


## Draws the labels for floors bottom..top of a shaft whose rect is given (machine-room floors are skipped).
static func draw(canvas: Object, rect: Rect2i, bottom: int, top: int, step: int, shaft_color: Color) -> void:
	var ink := shaft_color.lightened(0.7)
	ink.a = ALPHA
	var shadow := shaft_color.darkened(0.6)
	shadow.a = 0.85
	var font := ThemeDB.fallback_font
	for floor_number: int in range(bottom, top + 1):
		if floor_number == 0 or not shown(floor_number, step):
			continue
		var row := VC.floor_to_row(floor_number)
		var text := label(floor_number)
		var at := Vector2(rect.position.x, row * VC.CELL_H + LABEL_BASE)
		canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, FONT_SIZE, 1, shadow)
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, FONT_SIZE, ink)
