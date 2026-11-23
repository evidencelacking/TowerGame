extends RefCounted
## What a person resting in a room is doing, and how it is drawn (10.6). Pure functions of sim facts
## (kind, goal, hotel state, minute of day) plus the sim tick and the person id for idle motion, so the
## same sim moment always draws the same. Reads nothing from the tower itself; people_view.gd gathers the
## facts. Figures are placed on the recipe spots of the room (room_recipes.gd) and drawn here as
## seated, lying or standing poses with a small prop (cup, fork, broom, bag) that moves a little.

const PeopleScript := preload("res://scripts/sim/people.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
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
## Pose boxes, all derived from VC.FIGURE_W and VC.FIGURE_H. A prop or a forward leg reaches two
## columns past the body; a seated figure is two rows shorter than a standing one; a sleeper lies
## as long as a standing figure is tall, a third as thick, and sits on the bed a little above the floor.
const BOX_W := VC.FIGURE_W + 2
const SEAT_H := VC.FIGURE_H - 2
const HEAD_H := VC.FIGURE_H / 3  ## Hair row and face.
const LEG_H := VC.FIGURE_H / 3
const LYING_W := VC.FIGURE_H
const LYING_H := VC.FIGURE_H / 3
const LYING_UP := VC.FIGURE_H * 9 / 16  ## Top of a sleeper above the feet row (on the mattress).


static func is_night(minute: int) -> bool:
	return minute >= SLEEP_FROM or minute < SLEEP_TO


## The activity of a person resting in a room of `kind`. works_here: their work room is this one.
## goal: PeopleScript.DEST_*. staying: a hotel guest in residence. waiting: a trip is requested.
static func classify(kind: String, works_here: bool, goal: int, staying: bool, minute: int, waiting: bool) -> int:
	var sleeps_here := kind.begins_with("hotel_") or CatalogueScript.is_condo(kind) or kind == "apartment"
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
		return Rect2i(x, feet - LYING_UP, LYING_W, LYING_H)
	if SEATED.has(act):
		return Rect2i(x, feet - SEAT_H, BOX_W, SEAT_H)
	return Rect2i(x, feet - VC.FIGURE_H, BOX_W, VC.FIGURE_H)


## Where a figure for a spot ([x, feet] in room pixels, x the body's left edge as for standing figures)
## is drawn, moved so the whole pose lies inside a room width_px wide. Returns the pose's origin
## (left edge, feet row) in room pixels.
static func place(act: int, spot: Vector2i, width_px: int) -> Vector2i:
	var x := spot.x - (LYING_W / 2 if act == SLEEPING else 0)
	var rect := body_rect(act, x, spot.y)
	x = clampi(x, 0, maxi(width_px - rect.size.x, 0))
	return Vector2i(x, clampi(spot.y, -body_rect(act, 0, 0).position.y, RoomRecipes.INTERIOR_H))


## The spot a person uses: rooms hand out their spots in turn (`turn` counts people already placed
## there), sleepers take the first (the bed), standing activities the next one over. With no recipe
## spot the figure stands on the floor by column, as before.
static func spot_for(kind: String, width_px: int, id: int, turn: int, act: int, variant: int = 0) -> Vector2i:
	var spots := RoomRecipes.spots(kind, width_px, variant)
	if spots.is_empty():
		var columns := maxi(width_px / VC.CELL_W, 1)
		return Vector2i((id % columns) * VC.CELL_W + (VC.CELL_W - VC.FIGURE_W) / 2, VC.CELL_H - 3)
	if act == SLEEPING:
		return spots[0]
	var shift := 0 if SEATED.has(act) or act == IDLE else 1
	return spots[(turn + shift + kind.length()) % spots.size()]


## A standing figure, FIGURE_W x FIGURE_H with its feet at `feet`: a hair line and face (one dark dot
## for the eye), a shirt with a darker belt line, and two legs. apart spreads the legs to the body's
## edges (mid-stride) instead of tucking them under it; lift_l and lift_r raise a foot by that many rows.
## Shared by walkers, queues and car riders so every figure looks alike.
static func draw_person(canvas: Object, x: int, feet: int, shirt: Color, skin: Color, apart: bool = false, lift_l: int = 0, lift_r: int = 0) -> void:
	var hair := skin.darkened(0.65)
	var top := feet - VC.FIGURE_H
	var legs := shirt.darkened(0.4)
	var head_x := x + 1
	var head_w := VC.FIGURE_W - 2
	canvas.draw_rect(Rect2i(head_x, top, head_w, 1), hair)
	canvas.draw_rect(Rect2i(head_x, top + 1, head_w, HEAD_H - 1), skin)
	canvas.draw_rect(Rect2i(x + VC.FIGURE_W - 2, top + 2, 1, 1), hair)  # an eye, facing right
	var body_h := VC.FIGURE_H - HEAD_H - LEG_H
	canvas.draw_rect(Rect2i(x, top + HEAD_H, VC.FIGURE_W, body_h), shirt)
	canvas.draw_rect(Rect2i(x, top + HEAD_H + body_h - 1, VC.FIGURE_W, 1), legs)  # belt
	var lx := x if apart else x + 1
	var rx := x + VC.FIGURE_W - 2 if apart else x + VC.FIGURE_W - 3
	canvas.draw_rect(Rect2i(lx, feet - LEG_H - lift_l, 2, LEG_H), legs)
	canvas.draw_rect(Rect2i(rx, feet - LEG_H - lift_r, 2, LEG_H), legs)


## Paints one figure; canvas needs only draw_rect, so tests can pass a recorder. x is the left edge of
## the pose box and feet the floor row, in the canvas's pixels.
static func draw(canvas: Object, x: int, feet: int, act: int, ph: int, shirt: Color, skin: Color, prop: Color, white: Color) -> void:
	var legs := shirt.darkened(0.4)
	var hair := skin.darkened(0.65)
	var fw := VC.FIGURE_W
	if act == SLEEPING:
		var top := feet - LYING_UP + (1 if ph % 4 >= 2 else 0)  # breathing: the blanket rises and falls
		var head_w := LYING_H - 1
		canvas.draw_rect(Rect2i(x, top + 1, head_w, LYING_H - 2), skin)
		canvas.draw_rect(Rect2i(x, top + 1, 1, LYING_H - 2), hair)
		canvas.draw_rect(Rect2i(x + head_w, top + 1, LYING_W - head_w, LYING_H - 2), shirt)
		canvas.draw_rect(Rect2i(x + head_w, top + 1, LYING_W - head_w, 1), white)
		return
	if SEATED.has(act):
		var top := feet - SEAT_H
		canvas.draw_rect(Rect2i(x + 1, top, fw - 2, 1), hair)
		canvas.draw_rect(Rect2i(x + 1, top + 1, fw - 2, HEAD_H - 1), skin)
		canvas.draw_rect(Rect2i(x + fw - 2, top + 2, 1, 1), hair)
		canvas.draw_rect(Rect2i(x, top + HEAD_H, fw, 5), shirt)
		canvas.draw_rect(Rect2i(x, top + HEAD_H + 5, BOX_W, 2), legs)  # thighs, forward
		canvas.draw_rect(Rect2i(x + BOX_W - 2, top + HEAD_H + 7, 2, 2), legs)  # shins, down
		var hand_y := top + HEAD_H + 1 + (ph % 2)  # typing, or fork to mouth
		if act == WORKING:
			canvas.draw_rect(Rect2i(x + fw, hand_y, 2, 1), skin)
		else:
			var lift := 2 if ph % 2 == 1 else 0
			canvas.draw_rect(Rect2i(x + fw, hand_y - lift, 1, 1), skin)
			canvas.draw_rect(Rect2i(x + fw + 1, hand_y - lift, 1, 2), prop)
		return
	var top := feet - VC.FIGURE_H
	var tap := act == QUEUEING and ph % 2 == 1
	draw_person(canvas, x, feet, shirt, skin, true, 0, 1 if tap else 0)
	match act:
		BREAK:  # a cup with steam
			canvas.draw_rect(Rect2i(x + fw, top + 8, 2, 3), white)
			canvas.draw_rect(Rect2i(x + fw + (ph % 2), top + 5, 1, 2), white)
		SHOPPING:  # a bag
			canvas.draw_rect(Rect2i(x + fw, top + 8, 2, 5), prop)
		CLEANING:  # a broom swinging
			var sweep := ph % 2
			canvas.draw_rect(Rect2i(x + fw + sweep, top + 4, 1, VC.FIGURE_H - 5), prop)
			canvas.draw_rect(Rect2i(x + fw + sweep - 1, feet - 1, 2, 1), prop)
