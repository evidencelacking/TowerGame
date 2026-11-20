extends RefCounted
## Thought icon tests (12.6): an icon appears only past its threshold, one per person, only in the person's
## own window of the period, capped, deterministic for a tower and tick, unchanged by the graphics style
## setting, and picking never changes the sim hash.

const TowerSim := preload("res://scripts/sim/tower.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const ThoughtIcons := preload("res://scripts/view/thought_icons.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const TestPersonWindow := preload("res://tests/test_person_window.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")


static func _state(t: TowerSim, i: int) -> int:
	return ThoughtIcons.state_of(t, i, MoodScript.floor_counts(t.people, t.grid, t.floors))


## The first tick at or after `from` at which person `id` is inside its window (or outside it).
static func _tick_where(id: int, from: int, inside: bool) -> int:
	var tick := from
	while ThoughtIcons.is_showing(id, tick) != inside:
		tick += 1
	return tick


static func _only(picks: Array[Dictionary], id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pick: Dictionary in picks:
		if pick["id"] == id:
			out.append(pick)
	return out


static func run(check: Callable) -> void:
	var t := TestPersonWindow._fixture()
	var id: int = t.people.id_at(0)
	t.people.set_stress(0, 0)
	t.people.set_mood(0, 60)

	# Thresholds: nothing in the middle, each icon only past its line.
	check.call(_state(t, 0) == ThoughtIcons.NONE, "thoughts: a calm, middling person shows nothing")
	t.people.set_mood(0, MoodScript.HIGH_FROM - 1)
	check.call(_state(t, 0) == ThoughtIcons.NONE, "thoughts: just under the happy line shows nothing")
	t.people.set_mood(0, MoodScript.HIGH_FROM)
	check.call(_state(t, 0) == ThoughtIcons.HEART, "thoughts: mood at the happy line shows a heart")
	t.people.set_mood(0, MoodScript.LOW_BELOW)
	check.call(_state(t, 0) == ThoughtIcons.NONE, "thoughts: mood at the unhappy line shows nothing")
	t.people.set_mood(0, MoodScript.LOW_BELOW - 1)
	check.call(_state(t, 0) == ThoughtIcons.CLOUD, "thoughts: mood under the unhappy line shows a cloud")
	t.people.set_mood(0, 60)
	t.people.set_stress(0, PeopleScript.ANGRY_OVER)
	check.call(_state(t, 0) == ThoughtIcons.NONE, "thoughts: stress at the angry line shows nothing")
	t.people.set_stress(0, PeopleScript.ANGRY_OVER + 1)
	check.call(_state(t, 0) == ThoughtIcons.CLOCK, "thoughts: stress past the angry line shows a clock")
	t.people.set_mood(0, 10)
	check.call(_state(t, 0) == ThoughtIcons.CLOCK, "thoughts: one icon only: waiting beats unhappy")

	# Hungry: office workers at lunch, in the office (no food room yet), then after lunch.
	var office := TestOfficeDay._filled()
	TestOfficeDay._at(office, PeopleScript.LUNCH + 1)
	office.people.set_stress(0, 0)
	office.people.set_mood(0, 60)
	check.call(office.people.goal_of(0) == PeopleScript.DEST_LUNCH and _state(office, 0) == ThoughtIcons.FORK, "thoughts: someone heading to lunch with no food yet shows a fork")
	TestOfficeDay._at(office, PeopleScript.LUNCH + PeopleScript.LUNCH_LENGTH + 1)
	office.people.set_stress(0, 0)
	office.people.set_mood(0, 60)
	check.call(office.people.goal_of(0) != PeopleScript.DEST_LUNCH and _state(office, 0) == ThoughtIcons.NONE, "thoughts: after lunch the fork is gone")

	# The window: SHOW_TICKS of every PERIOD_TICKS, and neighbours are spread across it.
	var shown := 0
	for tick in ThoughtIcons.PERIOD_TICKS:
		if ThoughtIcons.is_showing(id, tick):
			shown += 1
	check.call(shown == ThoughtIcons.SHOW_TICKS, "thoughts: a person shows for %d of every %d ticks" % [ThoughtIcons.SHOW_TICKS, ThoughtIcons.PERIOD_TICKS])
	var at_once := 0
	for other in 100:
		if ThoughtIcons.is_showing(other, 1000):
			at_once += 1
	check.call(at_once > 10 and at_once < 45, "thoughts: of 100 people only about a quarter show at once (%d)" % at_once)

	# pick: only people inside their window, cleaners skipped, capped, deterministic, hash untouched.
	t.people.set_stress(0, PeopleScript.ANGRY_OVER + 1)
	var figures := PeopleView.new().figures(t)
	var mine: Array[Dictionary] = []
	for figure: Dictionary in figures:
		if figure["id"] == id:
			mine.append(figure)
	check.call(mine.size() == 1, "thoughts: the fixture draws the test person")
	t.tick = _tick_where(id, t.tick, true)
	var hash_before := t.state_hash()
	var picks := ThoughtIcons.pick(t, figures)
	var found := _only(picks, id)
	check.call(found.size() == 1 and found[0]["icon"] == ThoughtIcons.CLOCK, "thoughts: an angry person inside their window shows one clock")
	check.call(found.size() == 1 and found[0]["at"] == ThoughtIcons.head_of(mine[0]), "thoughts: the bubble points at the figure's head")
	check.call(ThoughtIcons.pick(t, figures) == picks and t.state_hash() == hash_before, "thoughts: the same tower and tick give the same icons, and the sim hash is unchanged")
	t.tick = _tick_where(id, t.tick, false)
	check.call(_only(ThoughtIcons.pick(t, figures), id).is_empty(), "thoughts: outside their window the icon is gone")
	var staff: Array[Dictionary] = [{"id": id, "staff": true, "floor": 3, "x": 110, "moving": true}]
	t.tick = _tick_where(id, t.tick, true)
	check.call(ThoughtIcons.pick(t, staff).is_empty(), "thoughts: cleaners never show icons")
	var many: Array[Dictionary] = []
	for n in ThoughtIcons.MAX_ICONS * 6:
		many.append(figures[n % figures.size()])
	check.call(ThoughtIcons.pick(t, many).size() <= ThoughtIcons.MAX_ICONS, "thoughts: never more than %d icons at once" % ThoughtIcons.MAX_ICONS)

	# The choice does not depend on the graphics style setting.
	var before := ViewSettings.detailed_graphics
	ViewSettings.detailed_graphics = false
	var classic := ThoughtIcons.pick(t, figures)
	ViewSettings.detailed_graphics = true
	var detailed := ThoughtIcons.pick(t, figures)
	ViewSettings.detailed_graphics = before
	check.call(classic == detailed, "thoughts: Classic and Detailed pick the same icons")

	# Every icon has a 7 by 7 picture and colours.
	var drawn := true
	for icon in range(1, ThoughtIcons.KIND_COUNT):
		var rows: Array = ThoughtIcons.PICTURES.get(icon, [])
		drawn = drawn and rows.size() == 7 and ThoughtIcons.COLORS.has(icon)
		for row: String in rows:
			drawn = drawn and row.length() == 7
	check.call(drawn, "thoughts: each icon has a 7 by 7 picture and colours")
