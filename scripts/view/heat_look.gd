extends RefCounted
## The heat-map overlays (#376, #488): a view filter that colours each room on a scale, by its daily income
## (loss red through neutral to profit green), by the mood of the people who live or work there (low red to high
## green), and since #488 by the lift queues (Traffic), the rent level (Rent), the grade (Grade) or the state of
## a hotel room (Hotel). Modelled on the synergy overlay (#294): pure reading of the sim, nothing here writes to
## the tower, and it paints in world pixels so one path serves Classic and Detailed.
##
## Traffic paints each lift stop (a floor of a shaft) where people are waiting, green to red with the length of
## the queue. Stairs and escalators keep no queue in the sim, so they show nothing.
##
## Income comes from the ledger: the lines that name the room (rent, sales, hotel nights, shop takings and
## running costs) over the last quarter, averaged per day. Quarterly lines make this a smoothed figure, not
## the exact figure of one day.

const LedgerScript := preload("res://scripts/sim/ledger.gd")
const FinanceScript := preload("res://scripts/sim/finance.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const GradeReader := preload("res://scripts/view/grade_reader.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")

const OFF := 0
const INCOME := 1
const MOOD := 2
const TRAFFIC := 3
const RENT := 4
const GRADE := 5
const HOTEL := 6
const MODES := 7
const NAMES: Array[String] = ["Off", "Income", "Mood", "Traffic", "Rent", "Grade", "Hotel"]

## Hotel room states, in the order of HOTEL_COLOURS and the legend.
const H_OCCUPIED := 0
const H_VACANT := 1
const H_DIRTY := 2
const H_PESTS := 3
const HOTEL_NAMES: Array[String] = ["Occupied", "Vacant, clean", "Dirty", "Pests"]
const HOTEL_COLOURS: Array[Color] = [Color(0.3, 0.55, 1.0), Color(0.3, 0.85, 0.4), Color(0.95, 0.6, 0.15), Color(0.85, 0.25, 0.8)]
## Rent levels lowest to highest: the colours of the rent buttons (blue, green, yellow, red).
const RENT_COLOURS: Array[Color] = [Color(0.3, 0.55, 1.0), Color(0.3, 0.85, 0.4), Color(0.95, 0.85, 0.2), Color(0.9, 0.25, 0.2)]
## Grade A, B, C.
const GRADE_COLOURS: Array[Color] = [Color(0.3, 0.85, 0.4), Color(0.95, 0.85, 0.2), Color(0.9, 0.25, 0.2)]
const TRAFFIC_FULL := 10  ## This many people waiting at one stop (or more) shows the strongest red. UNVERIFIED tunable.
const AMBER := Color(0.95, 0.75, 0.2)

const INCOME_FULL := 4000  ## Dollars a day (a loss or a profit) that shows the strongest colour. UNVERIFIED tunable.
const MOOD_MID := 50  ## The neutral mood; 0 is full red and PeopleScript.MOOD_MAX full green.
const ALPHA := 0.55
const NEUTRAL := Color(0.85, 0.85, 0.85)
const GOOD := Color(0.25, 0.85, 0.35)
const BAD := Color(0.9, 0.25, 0.2)

const INCOME_KINDS: Array[int] = [LedgerScript.INCOME, LedgerScript.SALE, LedgerScript.HOTEL, LedgerScript.SHOP, LedgerScript.COST]

## The view option: which overlay is shown. Session state only: never saved, in the tower or elsewhere.
static var mode: int = OFF


## The next mode in the cycle Off, Income, Mood, Traffic, Rent, Grade, Hotel, Off.
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


## Traffic: green when few wait, through amber to red at TRAFFIC_FULL waiting.
static func traffic_colour(waiting: int) -> Color:
	var t := clampf(float(waiting) / float(TRAFFIC_FULL), 0.0, 1.0)
	var c := GOOD.lerp(AMBER, t * 2.0) if t < 0.5 else AMBER.lerp(BAD, t * 2.0 - 1.0)
	return Color(c.r, c.g, c.b, ALPHA)


static func rent_colour(level: int) -> Color:
	var c := RENT_COLOURS[clampi(level, 0, RENT_COLOURS.size() - 1)]
	return Color(c.r, c.g, c.b, ALPHA)


## Transparent for a room that is not graded.
static func grade_colour(grade: int) -> Color:
	if grade < 0 or grade >= GRADE_COLOURS.size():
		return Color(0.0, 0.0, 0.0, 0.0)
	var c := GRADE_COLOURS[grade]
	return Color(c.r, c.g, c.b, ALPHA)


static func hotel_colour(state: int) -> Color:
	var c := HOTEL_COLOURS[clampi(state, 0, HOTEL_COLOURS.size() - 1)]
	return Color(c.r, c.g, c.b, ALPHA)


## The state of a hotel room for the Hotel overlay: pests first (an infested room is not dirty), then dirty, then
## occupied (guests arriving or staying), else vacant and clean.
static func hotel_state(tower: Object, room: int) -> int:
	if tower.hotel.is_infested(room):
		return H_PESTS
	if tower.hotel.is_dirty(room):
		return H_DIRTY
	if tower.hotel.state_of(room) != HotelScript.VACANT:
		return H_OCCUPIED
	return H_VACANT


## People waiting at each lift stop: {"shaft", "floor", "rect", "count"} (both directions summed), in queue order.
## Reads the hall queues and the shaft's width from the catalogue, not the grid, so it costs one pass over the
## people waiting.
static func traffic_stops(tower: Object) -> Array[Dictionary]:
	var stops: Dictionary = {}
	var found: Array[Dictionary] = []
	for entry: Array in tower.rooms._queue:
		var key: int = int(entry[1]) * 1000 + int(entry[2]) + 100
		if not stops.has(key):
			var x: int = tower.rooms.shaft_x(entry[1])
			if x < 0:
				continue
			var width: int = CatalogueScript.field(tower.rooms.kind_of(entry[1]), "width")
			stops[key] = {"shaft": entry[1], "floor": entry[2], "count": 0,
				"rect": Rect2i(x * VC.CELL_W, VC.floor_to_row(int(entry[2])) * VC.CELL_H, width * VC.CELL_W, VC.CELL_H)}
			found.append(stops[key])
		stops[key]["count"] = int(stops[key]["count"]) + 1
	return found


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
## (a room with no lines is neutral); mood paints only rooms with people; rent, grade and hotel paint the rooms
## that have one. Traffic paints lift stops, not rooms: its "id" is the shaft.
static func painted_rooms(tower: Object, which: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if which == OFF:
		return found
	if which == TRAFFIC:
		for stop: Dictionary in traffic_stops(tower):
			found.append({"id": stop["shaft"], "rect": stop["rect"], "colour": traffic_colour(stop["count"])})
		return found
	var values: Dictionary = {}
	if which == INCOME:
		values = income_by_room(tower)
	elif which == MOOD:
		values = mood_by_room(tower)
	var batch: Variant = GradeReader.begin(tower) if which == GRADE else null
	for id: int in tower.rooms.room_ids():
		if not tower.grid.has_occupant(id):
			continue
		var colour := Color(0.0, 0.0, 0.0, 0.0)
		match which:
			INCOME:
				colour = income_colour(int(values.get(id, 0)))
			MOOD:
				if not values.has(id):
					continue
				colour = mood_colour(int(values[id]))
			RENT:
				if not RentScript.is_rentable(tower.rooms.kind_of(id)):
					continue
				colour = rent_colour(tower.rent_level(id))
			GRADE:
				colour = grade_colour(tower.grade(id))
				if colour.a == 0.0:
					continue
			HOTEL:
				if not tower.hotel.is_hotel(id):
					continue
				colour = hotel_colour(hotel_state(tower, id))
		found.append({"id": id, "rect": SynergyLook.rect_of(tower.grid.run_of(id)), "colour": colour})
	if which == GRADE:
		GradeReader.end(tower, batch)
	return found


static func draw(canvas: Object, tower: Object, which: int) -> void:
	for room: Dictionary in painted_rooms(tower, which):
		canvas.draw_rect(Rect2(room["rect"]), room["colour"])


## The legend's text ends for a continuous mode: [low label, high label].
static func legend_text(which: int) -> Array[String]:
	if which == INCOME:
		return ["Loss -$%d/day" % INCOME_FULL, "Profit +$%d/day" % INCOME_FULL]
	if which == MOOD:
		return ["Unhappy 0", "Happy %d" % PeopleScript.MOOD_MAX]
	if which == TRAFFIC:
		return ["Quiet", "%d+ waiting" % TRAFFIC_FULL]
	return ["", ""]


## The swatches of a categorical mode: [{"colour", "label"}]. Empty for the continuous modes.
static func legend_swatches(which: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if which == RENT:
		for level: int in RENT_COLOURS.size():
			out.append({"colour": rent_colour(level), "label": RoomInfo.LEVEL_NAMES[level]})
	elif which == GRADE:
		for grade: int in GRADE_COLOURS.size():
			out.append({"colour": grade_colour(grade), "label": GradesScript.letter(grade)})
	elif which == HOTEL:
		for state: int in HOTEL_NAMES.size():
			out.append({"colour": hotel_colour(state), "label": HOTEL_NAMES[state]})
	return out


## The colours of the legend's bar for a continuous mode, low end first.
static func legend_colours(which: int) -> PackedColorArray:
	if which == TRAFFIC:
		return PackedColorArray([Color(GOOD.r, GOOD.g, GOOD.b), Color(AMBER.r, AMBER.g, AMBER.b), Color(BAD.r, BAD.g, BAD.b)])
	return PackedColorArray([Color(BAD.r, BAD.g, BAD.b), Color(NEUTRAL.r, NEUTRAL.g, NEUTRAL.b), Color(GOOD.r, GOOD.g, GOOD.b)])


## A legend control: low label, colour bar, high label, and a row of swatches for the categorical modes. Hidden
## while the overlay is off; call refresh_legend when the mode changes.
static func make_legend() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "HeatLegend"
	var low := Label.new()
	low.name = "Low"
	var bar := TextureRect.new()
	bar.name = "Bar"
	var tex := GradientTexture1D.new()
	tex.gradient = Gradient.new()
	tex.width = 96
	bar.texture = tex
	bar.custom_minimum_size = Vector2(96, 12)
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var high := Label.new()
	high.name = "High"
	var swatches := HBoxContainer.new()
	swatches.name = "Swatches"
	box.add_child(low)
	box.add_child(bar)
	box.add_child(high)
	box.add_child(swatches)
	refresh_legend(box, mode)
	return box


static func refresh_legend(legend: Control, which: int) -> void:
	var text := legend_text(which)
	(legend.get_node("Low") as Label).text = text[0]
	(legend.get_node("High") as Label).text = text[1]
	var swatches := legend_swatches(which)
	var continuous := swatches.is_empty()
	for part: String in ["Low", "Bar", "High"]:
		(legend.get_node(part) as Control).visible = continuous
	var bar := legend.get_node("Bar") as TextureRect
	var gradient := (bar.texture as GradientTexture1D).gradient
	gradient.colors = legend_colours(which)
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var holder := legend.get_node("Swatches") as Control
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.free()
	for swatch: Dictionary in swatches:
		var chip := ColorRect.new()
		var c: Color = swatch["colour"]
		chip.color = Color(c.r, c.g, c.b)
		chip.custom_minimum_size = Vector2(12, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = swatch["label"]
		holder.add_child(chip)
		holder.add_child(label)
	holder.visible = not continuous
	legend.visible = which != OFF
