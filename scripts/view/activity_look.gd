extends RefCounted
## What a person resting in a room is doing, and how it is drawn (10.6). Pure functions of sim facts
## (kind, goal, hotel state, minute of day) plus the sim tick and the person id for idle motion, so the
## same sim moment always draws the same. Reads nothing from the tower itself; people_view.gd gathers the
## facts. Figures are placed on the recipe spots of the room (room_recipes.gd) and drawn here as
## seated, lying or standing poses with a small prop (cup, fork, broom, bag) that moves a little.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const VC := preload("res://scripts/view/view_consts.gd")

## Activities.
const IDLE := 0  ## Standing or sitting about, nothing particular.
const WORKING := 1  ## Seated at a desk, counter or station.
const BREAK := 2  ## Standing with a cup.
const LUNCH := 3  ## Seated with a meal.
const EATING := 4  ## A visitor at a food room, seated with a meal.
const SLEEPING := 5  ## Lying down; the room's lights are off.
const CLEANING := 6  ## Standing with a broom.
const QUEUEING := 7  ## Waiting to set off: standing, tapping a foot.
const SHOPPING := 8  ## A visitor in a shop, carrying a bag.
const COUNT := 9

const NAMES: Array[String] = ["idle", "working", "break", "lunch", "eating", "sleeping", "cleaning", "queueing", "shopping"]
const SLEEP_FROM := 1320  ## 22:00
const SLEEP_TO := 360  ## 6:00
const FRAME_TICKS := 8  ## Ticks per animation frame.
const FOOD_KINDS: Array[String] = ["fast_food", "restaurant"]
const SEATED: Array[int] = [WORKING, LUNCH, EATING]
## Width of any pose box and its height by pose; a prop reaches one column past the body.
const BOX_W := VC.FIGURE_W + 2
const LYING_W := VC.FIGURE_H
const LYING_H := 5


static func is_night(minute: int) -> bool:
	return minute >= SLEEP_FROM or minute < SLEEP_TO


## The activity of a person resting in a room of `kind`. works_here: their work room is this one.
## goal: PeopleScript.DEST_*. staying: a hotel guest in residence. waiting: a trip is requested.
static func classify(kind: String, works_here: bool, goal: int, staying: bool, minute: int, waiting: bool) -> int:
	var sleeps_here := kind.begins_with("hotel_") or kind == "condo"
	if sleeps_here and is_night(minute) and (staying or goal == PeopleScript.DEST_HOME):
		return SLEEPING
	if waiting:
		return QUEUEING
	if kind == "housekeeping" and works_here:
		return CLEANING
	if FOOD_KINDS.has(kind):
		return WORKING if works_here else EATING
	if kind == "retail":
		return WORKING if works_here else SHOPPING
	if goal == PeopleScript.DEST_BREAK:
		return BREAK
	if goal == PeopleScript.DEST_LUNCH:
		return LUNCH
	if goal == PeopleScript.DEST_WORK:
		return WORKING
	return IDLE


## The animation frame 0 to 3 for a person at a sim tick: each id runs on its own offset.
static func frame(id: int, tick: int) -> int:
	return (tick / FRAME_TICKS + id) % 4


## The box a pose takes, with its left edge at x and its feet at `feet`.
static func body_rect(act: int, x: int, feet: int) -> Rect2i:
	if act == SLEEPING:
		return Rect2i(x, feet - 10, LYING_W, LYING_H)
	if SEATED.has(act):
		return Rect2i(x, feet - 8, BOX_W, 8)
	return Rect2i(x, feet - VC.FIGURE_H, BOX_W, VC.FIGURE_H)


## Where a figure for a spot ([x, feet] in room pixels, x the body's left edge as for standing figures)
## is drawn, moved so the whole pose lies inside a room width_px wide. Returns the pose's origin
## (left edge, feet row) in room pixels.
static func place(act: int, spot: Vector2i, width_px: int) -> Vector2i:
	var x := spot.x - (3 if act == SLEEPING else 0)
	var rect := body_rect(act, x, spot.y)
	x = clampi(x, 0, maxi(width_px - rect.size.x, 0))
	return Vector2i(x, clampi(spot.y, rect.size.y, RoomRecipes.INTERIOR_H))


## The spot a person uses: rooms hand out their spots in turn (`turn` counts people already placed
## there), sleepers take the first (the bed), standing activities the next one over. With no recipe
## spot the figure stands on the floor by column, as before.
static func spot_for(kind: String, width_px: int, id: int, turn: int, act: int) -> Vector2i:
	var spots := RoomRecipes.spots(kind, width_px)
	if spots.is_empty():
		var columns := maxi(width_px / VC.CELL_W, 1)
		return Vector2i((id % columns) * VC.CELL_W + (VC.CELL_W - VC.FIGURE_W) / 2, VC.CELL_H - 3)
	if act == SLEEPING:
		return spots[0]
	var shift := 0 if SEATED.has(act) or act == IDLE else 1
	return spots[(turn + shift + kind.length()) % spots.size()]


## Paints one figure; canvas needs only draw_rect, so tests can pass a recorder. x is the left edge of
## the pose box and feet the floor row, in the canvas's pixels.
static func draw(canvas: Object, x: int, feet: int, act: int, ph: int, shirt: Color, skin: Color, prop: Color, white: Color) -> void:
	var legs := shirt.darkened(0.4)
	if act == SLEEPING:
		var top := feet - 10 + (1 if ph % 4 >= 2 else 0)  # breathing: the blanket rises and falls
		canvas.draw_rect(Rect2i(x, top + 1, 3, 3), skin)
		canvas.draw_rect(Rect2i(x + 3, top + 1, LYING_W - 3, 3), shirt)
		canvas.draw_rect(Rect2i(x + 3, top + 1, LYING_W - 3, 1), white)
		return
	if SEATED.has(act):
		var top := feet - 8
		canvas.draw_rect(Rect2i(x, top, VC.FIGURE_W, 3), skin)
		canvas.draw_rect(Rect2i(x, top + 3, VC.FIGURE_W, 3), shirt)
		canvas.draw_rect(Rect2i(x, top + 6, VC.FIGURE_W + 2, 1), legs)
		canvas.draw_rect(Rect2i(x + VC.FIGURE_W + 1, top + 7, 1, 1), legs)
		var hand_y := top + 4 + (ph % 2)  # typing, or fork to mouth
		if act == WORKING:
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W, hand_y, 1, 1), skin)
		else:
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W, hand_y - (2 if ph % 2 == 1 else 0), 1, 1), skin)
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W + 1, hand_y - (2 if ph % 2 == 1 else 0), 1, 1), prop)
		return
	var head_h := maxi(VC.FIGURE_H / 3, 2)
	var leg_h := maxi(VC.FIGURE_H / 4, 1)
	var top := feet - VC.FIGURE_H
	canvas.draw_rect(Rect2i(x, top, VC.FIGURE_W, head_h), skin)
	canvas.draw_rect(Rect2i(x, top + head_h, VC.FIGURE_W, VC.FIGURE_H - head_h - leg_h), shirt)
	var tap := act == QUEUEING and ph % 2 == 1
	canvas.draw_rect(Rect2i(x, feet - leg_h, 1, leg_h), legs)
	canvas.draw_rect(Rect2i(x + VC.FIGURE_W - 1, feet - leg_h - (1 if tap else 0), 1, leg_h), legs)
	match act:
		BREAK:  # a cup with steam
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W, top + 5, 2, 2), white)
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W + (ph % 2), top + 3, 1, 1), white)
		SHOPPING:  # a bag
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W, top + 5, 2, 3), prop)
		CLEANING:  # a broom swinging
			var sweep := ph % 2
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W + sweep, top + 2, 1, VC.FIGURE_H - 3), prop)
			canvas.draw_rect(Rect2i(x + VC.FIGURE_W + sweep - 1, feet - 1, 2, 1), prop)
