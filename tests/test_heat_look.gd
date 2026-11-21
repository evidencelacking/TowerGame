extends RefCounted
## Heat-map overlays (#376): the colour at the ends and midpoint of both scales, the mode cycle, the legend,
## and income and mood read from a tower without changing it.

const Look := preload("res://scripts/view/heat_look.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")


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
	check.call(seen == [Look.INCOME, Look.MOOD, Look.OFF], "heat: the toggle cycles Off, Income, Mood, Off")
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
	legend.free()

	_in_a_tower(check)


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
