extends RefCounted
## Heat-map overlays (#376): the colour at the ends and midpoint of both scales, the mode cycle, the legend,
## and income and mood read from a tower without changing it.

const Look := preload("res://scripts/view/heat_look.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")
const TestPests := preload("res://tests/test_pests.gd")
const TestBoarding := preload("res://tests/test_boarding.gd")
const TestDispatch := preload("res://tests/test_dispatch.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const VC := preload("res://scripts/view/view_consts.gd")


static func run(check: Callable) -> void:
	var neutral := Look.income_colour(0)
	var good := Look.income_colour(Look.INCOME_FULL)
	var bad := Look.income_colour(-Look.INCOME_FULL)
	check.call(good.is_equal_approx(Color(Look.GOOD.r, Look.GOOD.g, Look.GOOD.b, Look.ALPHA)), "heat: full profit is green")
	check.call(bad.is_equal_approx(Color(Look.BAD.r, Look.BAD.g, Look.BAD.b, Look.ALPHA)), "heat: full loss is red")
	check.call(neutral.r == neutral.g and neutral.g == neutral.b, "heat: zero income is neutral grey")
	check.call(Look.income_colour(Look.INCOME_FULL * 9).is_equal_approx(good), "heat: income beyond the scale is capped")
	var half := Look.income_colour(Look.INCOME_FULL / 2)
	check.call(half.r < neutral.r and half.g > half.r, "heat: half profit sits between neutral and green")
	check.call(Look.mood_colour(0).is_equal_approx(bad), "heat: mood 0 is red")
	check.call(Look.mood_colour(100).is_equal_approx(good), "heat: mood 100 is green")
	check.call(Look.mood_colour(Look.MOOD_MID).is_equal_approx(neutral), "heat: the middle mood is neutral")

	var m := Look.OFF
	var seen: Array[int] = []
	for i in Look.MODES:
		m = Look.next_mode(m)
		seen.append(m)
	check.call(seen == [Look.INCOME, Look.MOOD, Look.TRAFFIC, Look.RENT, Look.GRADE, Look.HOTEL, Look.OFF], "heat: the toggle cycles Off, Income, Mood, Traffic, Rent, Grade, Hotel, Off")
	check.call(Look.NAMES.size() == Look.MODES, "heat: every mode has a name")
	Look.mode = Look.OFF
	Look.cycle()
	check.call(Look.mode == Look.INCOME, "heat: cycle() steps the shared mode")
	Look.mode = Look.OFF

	var legend := Look.make_legend()
	check.call(legend.get_node_or_null("Low") != null and legend.get_node_or_null("Bar") != null and legend.get_node_or_null("High") != null, "heat: the legend has both labels and a colour bar")
	check.call(not legend.visible, "heat: the legend is hidden while the overlay is off")
	Look.refresh_legend(legend, Look.INCOME)
	check.call(legend.visible and (legend.get_node("Low") as Label).text.contains("Loss"), "heat: the income legend shows and names the loss end")
	Look.refresh_legend(legend, Look.MOOD)
	check.call((legend.get_node("High") as Label).text.contains("Happy"), "heat: the mood legend names the happy end")
	Look.refresh_legend(legend, Look.TRAFFIC)
	check.call(legend.get_node("Bar").visible and not legend.get_node("Swatches").visible and (legend.get_node("High") as Label).text.contains("waiting"), "heat: the traffic legend is a bar ending at the crowded stop")
	Look.refresh_legend(legend, Look.GRADE)
	var chips := legend.get_node("Swatches").get_children()
	check.call(legend.visible and legend.get_node("Swatches").visible and not legend.get_node("Bar").visible and chips.size() == 6, "heat: the grade legend is three swatches with their letters")
	check.call((chips[1] as Label).text == "A" and (chips[3] as Label).text == "B" and (chips[5] as Label).text == "C", "heat: the grade swatches read A, B, C")
	Look.refresh_legend(legend, Look.HOTEL)
	check.call(legend.get_node("Swatches").get_child_count() == 8 and (legend.get_node("Swatches").get_child(7) as Label).text == "Pests", "heat: the hotel legend names occupied, vacant, dirty and pests")
	Look.refresh_legend(legend, Look.RENT)
	check.call(legend.get_node("Swatches").get_child_count() == 8, "heat: the rent legend has four swatches")
	Look.refresh_legend(legend, Look.INCOME)
	check.call(legend.get_node("Swatches").get_child_count() == 0 and legend.get_node("Bar").visible, "heat: going back to a bar mode clears the swatches")
	legend.free()

	_colours(check)
	_in_a_tower(check)
	_rent_grade(check)
	_hotel(check)
	_traffic(check)


## The colour of each category, and that the categories can be told apart.
static func _colours(check: Callable) -> void:
	check.call(Look.traffic_colour(0).g > Look.traffic_colour(0).r, "heat: an empty stop is green")
	var mid := Look.traffic_colour(Look.TRAFFIC_FULL / 2)
	check.call(mid.r > 0.8 and mid.g > 0.6 and mid.b < 0.3, "heat: a half-full queue is amber")
	check.call(Look.traffic_colour(Look.TRAFFIC_FULL).is_equal_approx(Color(Look.BAD.r, Look.BAD.g, Look.BAD.b, Look.ALPHA)), "heat: a full queue is red")
	check.call(Look.traffic_colour(Look.TRAFFIC_FULL * 9).is_equal_approx(Look.traffic_colour(Look.TRAFFIC_FULL)), "heat: traffic beyond the scale is capped")
	check.call(Look.traffic_colour(3).r < Look.traffic_colour(7).r and Look.traffic_colour(3).g > Look.traffic_colour(9).g, "heat: a longer queue is redder")
	check.call(Look.grade_colour(GradesScript.GRADE_A).g > Look.grade_colour(GradesScript.GRADE_A).r and Look.grade_colour(GradesScript.GRADE_C).r > Look.grade_colour(GradesScript.GRADE_C).g, "heat: grade A is green and C is red")
	check.call(Look.grade_colour(GradesScript.GRADE_NONE).a == 0.0, "heat: an ungraded room has no colour")
	check.call(Look.rent_colour(0).b > Look.rent_colour(0).r and Look.rent_colour(3).r > Look.rent_colour(3).b, "heat: the lowest rent is blue and the highest red")
	check.call(Look.rent_colour(-5).is_equal_approx(Look.rent_colour(0)) and Look.rent_colour(9).is_equal_approx(Look.rent_colour(3)), "heat: rent levels out of range are clamped")
	for set_colours: Array in [Look.RENT_COLOURS, Look.GRADE_COLOURS, Look.HOTEL_COLOURS]:
		var distinct := true
		for i: int in set_colours.size():
			for j: int in range(i + 1, set_colours.size()):
				var a: Color = set_colours[i]
				var b: Color = set_colours[j]
				distinct = distinct and (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) > 0.5
		check.call(distinct, "heat: the categories of a mode are told apart (%d colours)" % set_colours.size())


static func _by_id(rooms: Array[Dictionary], id: int) -> Dictionary:
	for room: Dictionary in rooms:
		if room["id"] == id:
			return room
	return {}


## Rent and Grade on a pair of offices: the rent button's level and the grade from stress.
static func _rent_grade(check: Callable) -> void:
	var t := TestEvaluation._pair("office")
	var office := -1
	for id: int in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			office = id
			break
	var found := _by_id(Look.painted_rooms(t, Look.RENT), office)
	check.call(not found.is_empty() and found["colour"].is_equal_approx(Look.rent_colour(t.rent_level(office))), "heat: an office paints its rent level (the default)")
	t.rent.set_rent(t.rooms, office, 3)
	check.call(_by_id(Look.painted_rooms(t, Look.RENT), office)["colour"].is_equal_approx(Look.rent_colour(3)), "heat: the highest rent paints red")
	t.rent.set_rent(t.rooms, office, 0)
	check.call(_by_id(Look.painted_rooms(t, Look.RENT), office)["colour"].is_equal_approx(Look.rent_colour(0)), "heat: the lowest rent paints blue")
	TestEvaluation._stress(t, TestEvaluation.A_STRESS)
	check.call(t.grade(office) == GradesScript.GRADE_A and _by_id(Look.painted_rooms(t, Look.GRADE), office)["colour"].is_equal_approx(Look.grade_colour(GradesScript.GRADE_A)), "heat: an A office paints grade A")
	TestEvaluation._stress(t, TestEvaluation.C_STRESS)
	check.call(t.grade(office) == GradesScript.GRADE_C and _by_id(Look.painted_rooms(t, Look.GRADE), office)["colour"].is_equal_approx(Look.grade_colour(GradesScript.GRADE_C)), "heat: a C office paints grade C")
	var before := t.state_hash()
	Look.painted_rooms(t, Look.RENT)
	Look.painted_rooms(t, Look.GRADE)
	check.call(t.state_hash() == before, "heat: reading rent and grade leaves the tower unchanged")
	var plain := TestPests._tower()
	var shop := TestPests._room(plain, "fast_food", 3, 100)
	check.call(shop > 0 and not GradesScript.is_graded("fast_food") and Look.painted_rooms(plain, Look.GRADE).is_empty(), "heat: a room that is not graded is not painted by Grade")


## Hotel: occupied, vacant clean, dirty and pests, side by side on one floor.
static func _hotel(check: Callable) -> void:
	var t := TestPests._tower()
	var rooms: Array[int] = []
	for n: int in 4:
		rooms.append(TestPests._room(t, "hotel_single", 3, 100 + 4 * n))
	check.call(rooms.min() > 0, "heat: the four hotel rooms place")
	TestPests._clean(t, rooms[1])
	TestPests._dirty(t, rooms[2], 0)
	TestPests._dirty(t, rooms[3], 0)
	t.pests._infested.append(rooms[3])
	t.hotel._records[rooms[0]] = [HotelScript.STAYING, -1, -1, 420, -1, 0, -1, 0] as Array[int]
	var expected: Array[int] = [Look.H_OCCUPIED, Look.H_VACANT, Look.H_DIRTY, Look.H_PESTS]
	var painted := Look.painted_rooms(t, Look.HOTEL)
	check.call(painted.size() == 4, "heat: Hotel paints exactly the hotel rooms")
	for n: int in 4:
		check.call(Look.hotel_state(t, rooms[n]) == expected[n], "heat: hotel room %d reads %s" % [n, Look.HOTEL_NAMES[expected[n]]])
		var room := _by_id(painted, rooms[n])
		check.call(not room.is_empty() and room["colour"].is_equal_approx(Look.hotel_colour(expected[n])), "heat: hotel room %d is painted %s" % [n, Look.HOTEL_NAMES[expected[n]]])
	t.hotel._records[rooms[0]] = [HotelScript.ARRIVING, -1, -1, 420, -1, 0, -1, 0] as Array[int]
	check.call(Look.hotel_state(t, rooms[0]) == Look.H_OCCUPIED, "heat: guests on their way count as occupied")
	var office_tower := TestEvaluation._pair("office")
	check.call(Look.painted_rooms(office_tower, Look.HOTEL).is_empty(), "heat: a tower without hotel rooms paints nothing for Hotel")


## Traffic: a queue at a lift stop paints that stop, redder with more people.
static func _traffic(check: Callable) -> void:
	var t := TestBoarding._setup([1] as Array[int], 40)
	check.call(Look.painted_rooms(t, Look.TRAFFIC).is_empty(), "heat: with nobody waiting Traffic paints nothing")
	TestBoarding._queue(t, 0, 2, 1, 10)
	var shaft := TestDispatch._id(t)
	var stops := Look.traffic_stops(t)
	check.call(stops.size() == 1 and stops[0]["floor"] == 1 and stops[0]["count"] == 2 and stops[0]["shaft"] == shaft, "heat: two people waiting on floor 1 make one stop of 2")
	var rect := Rect2i(100 * VC.CELL_W, VC.floor_to_row(1) * VC.CELL_H, 4 * VC.CELL_W, VC.CELL_H)
	check.call(stops.size() == 1 and stops[0]["rect"] == rect, "heat: the stop is the shaft's cells on its floor")
	TestBoarding._queue(t, 2, 4, 1, 20)  # the other direction on the same floor
	check.call(Look.traffic_stops(t).size() == 1 and Look.traffic_stops(t)[0]["count"] == 4, "heat: both directions at a stop are added")
	var few: Color = Look.painted_rooms(t, Look.TRAFFIC)[0]["colour"]
	TestBoarding._queue(t, 4, 20, 1, 10)
	var many: Color = Look.painted_rooms(t, Look.TRAFFIC)[0]["colour"]
	check.call(many.r > few.r and many.g < few.g, "heat: a longer queue paints redder")
	TestBoarding._queue(t, 20, 22, 7, 12)
	check.call(Look.traffic_stops(t).size() == 2, "heat: a queue on another floor is its own stop")
	var before := t.state_hash()
	Look.painted_rooms(t, Look.TRAFFIC)
	check.call(t.state_hash() == before, "heat: reading the queues leaves the tower unchanged")


static func _in_a_tower(check: Callable) -> void:
	var t := TestEvaluation._pair("office")
	var office := -1
	for id: int in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			office = id
			break
	check.call(office > 0, "heat: the test office places")
	check.call(Look.painted_rooms(t, Look.OFF).is_empty(), "heat: off paints nothing")
	var moods := Look.mood_by_room(t)
	check.call(moods.has(office) and int(moods[office]) >= 0 and int(moods[office]) <= 100, "heat: an occupied office has a mood")
	check.call(Look.painted_rooms(t, Look.MOOD).size() == moods.size(), "heat: mood paints exactly the rooms with people")
	var base: int = Look.income_by_room(t).get(office, 0)
	t.ledger.income(t.tick, 9000, office)
	var per_day: int = int(Look.income_by_room(t).get(office, 0)) - base
	check.call(per_day == 3000, "heat: 9000 of rent in the quarter adds 3000 a day (%d)" % per_day)
	var found := false
	for room: Dictionary in Look.painted_rooms(t, Look.INCOME):
		if room["id"] == office:
			found = room["colour"].g > room["colour"].r
	check.call(found, "heat: a profitable office paints green")
	t.ledger.running_cost(t.tick, 90000, office)
	check.call(int(Look.income_by_room(t).get(office, 0)) < 0, "heat: a running cost larger than the takings is a loss")
	var before := t.state_hash()
	Look.painted_rooms(t, Look.INCOME)
	Look.painted_rooms(t, Look.MOOD)
	check.call(t.state_hash() == before, "heat: reading leaves the tower unchanged")
