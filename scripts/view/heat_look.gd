extends RefCounted
## The heat-map overlays (#376): a view filter that colours each room on a scale, either by its daily income
## (loss red through neutral to profit green) or by the mood of the people who live or work there (low red to
## high green). Modelled on the synergy overlay (#294): pure reading of the sim, nothing here writes to the
## tower, and it paints in world pixels so one path serves Classic and Detailed.
##
## Income comes from the ledger: the lines that name the room (rent, sales, hotel nights, shop takings and
## running costs) over the last quarter, averaged per day. Quarterly lines make this a smoothed figure, not
## the exact figure of one day.

const LedgerScript := preload("res://scripts/sim/ledger.gd")
const FinanceScript := preload("res://scripts/sim/finance.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")

const OFF := 0
const INCOME := 1
const MOOD := 2
const MODES := 3
const NAMES: Array[String] = ["Off", "Income", "Mood"]

const INCOME_FULL := 4000  ## Dollars a day (a loss or a profit) that shows the strongest colour. UNVERIFIED tunable.
const MOOD_MID := 50  ## The neutral mood; 0 is full red and PeopleScript.MOOD_MAX full green.
const ALPHA := 0.55
const NEUTRAL := Color(0.85, 0.85, 0.85)
const GOOD := Color(0.25, 0.85, 0.35)
const BAD := Color(0.9, 0.25, 0.2)

const INCOME_KINDS: Array[int] = [LedgerScript.INCOME, LedgerScript.SALE, LedgerScript.HOTEL, LedgerScript.SHOP, LedgerScript.COST]

## The view option: which overlay is shown. Session state only: never saved, in the tower or elsewhere.
static var mode: int = OFF


## The next mode in the cycle Off, Income, Mood, Off.
static func next_mode(from: int) -> int:
	return (from + 1) % MODES


static func cycle() -> void:
	mode = next_mode(mode)


## The colour for a position t on the scale, -1 (bad) to +1 (good), neutral grey at 0.
static func scale_colour(t: float) -> Color:
	var s := clampf(t, -1.0, 1.0)
	var end := GOOD if s >= 0.0 else BAD
	var c := NEUTRAL.lerp(end, absf(s))
	return Color(c.r, c.g, c.b, ALPHA)


static func income_colour(per_day: int) -> Color:
	return scale_colour(float(per_day) / float(INCOME_FULL))


static func mood_colour(mood: int) -> Color:
	return scale_colour(float(mood - MOOD_MID) / float(MOOD_MID))


## Daily income of every room that has any ledger line in the last quarter: {room id: dollars a day}.
static func income_by_room(tower: Object) -> Dictionary:
	var sums: Dictionary = {}
	var from: int = tower.tick - FinanceScript.ticks_per_quarter()
	var lines: Array = tower.ledger.lines
	var n := lines.size() - 1
	while n >= 0 and lines[n][0] > from:
		if INCOME_KINDS.has(lines[n][2]) and lines[n][3] > 0:
			sums[lines[n][3]] = int(sums.get(lines[n][3], 0)) + int(lines[n][1])
		n -= 1
	var per_day: Dictionary = {}
	for id: int in sums:
		per_day[id] = int(sums[id]) / ClockScript.DAYS_PER_QUARTER
	return per_day


## Average mood of the people who live or work in each room: {room id: mood 0 to 100}.
static func mood_by_room(tower: Object) -> Dictionary:
	var totals: Dictionary = {}
	var counts: Dictionary = {}
	for i: int in tower.people.count():
		var mood: int = tower.people.mood_of(i)
		for room: int in [tower.people.home_of(i), tower.people.work_of(i)]:
			if room > 0:
				totals[room] = int(totals.get(room, 0)) + mood
				counts[room] = int(counts.get(room, 0)) + 1
	var avg: Dictionary = {}
	for room: int in totals:
		avg[room] = int(totals[room]) / int(counts[room])
	return avg


## Every placed room to paint for `which`: {"id", "rect", "colour"}, in room id order. Income paints every room
## (a room with no lines is neutral); mood paints only rooms with people.
static func painted_rooms(tower: Object, which: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if which == OFF:
		return found
	var values: Dictionary = income_by_room(tower) if which == INCOME else mood_by_room(tower)
	for id: int in tower.rooms.room_ids():
		if not tower.grid.has_occupant(id):
			continue
		if which == MOOD and not values.has(id):
			continue
		var value := int(values.get(id, 0))
		var colour := income_colour(value) if which == INCOME else mood_colour(value)
		found.append({"id": id, "rect": SynergyLook.rect_of(tower.grid.run_of(id)), "colour": colour})
	return found


static func draw(canvas: Object, tower: Object, which: int) -> void:
	for room: Dictionary in painted_rooms(tower, which):
		canvas.draw_rect(Rect2(room["rect"]), room["colour"])


## The legend's text ends for a mode: [low label, high label].
static func legend_text(which: int) -> Array[String]:
	if which == INCOME:
		return ["Loss -$%d/day" % INCOME_FULL, "Profit +$%d/day" % INCOME_FULL]
	if which == MOOD:
		return ["Unhappy 0", "Happy %d" % PeopleScript.MOOD_MAX]
	return ["", ""]


## A legend control: low label, colour bar, high label. Hidden while the overlay is off; call refresh_legend
## when the mode changes.
static func make_legend() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "HeatLegend"
	var low := Label.new()
	low.name = "Low"
	var bar := TextureRect.new()
	bar.name = "Bar"
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(BAD.r, BAD.g, BAD.b), Color(NEUTRAL.r, NEUTRAL.g, NEUTRAL.b), Color(GOOD.r, GOOD.g, GOOD.b)])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	tex.width = 96
	bar.texture = tex
	bar.custom_minimum_size = Vector2(96, 12)
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var high := Label.new()
	high.name = "High"
	box.add_child(low)
	box.add_child(bar)
	box.add_child(high)
	refresh_legend(box, mode)
	return box


static func refresh_legend(legend: Control, which: int) -> void:
	var text := legend_text(which)
	(legend.get_node("Low") as Label).text = text[0]
	(legend.get_node("High") as Label).text = text[1]
	legend.visible = which != OFF
