extends RefCounted
## The people view keeps rooms' lights and the spot order incrementally (#451). Over a few hundred ticks of the
## mixed fixture, a view that is kept between ticks must give exactly what a view made fresh for that tick gives:
## the same figures in the same order and spots, and the same rooms in use and asleep, whole or culled.

const Mixed := preload("res://tools/bench_mixed.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const WINDOWS: Array[int] = [600, 900, 2300]  ## Clock ticks to start from: the 6:00 wake, the morning rush, the 22:00 bedtime.
const TICKS := 110


static func run(check: Callable) -> void:
	var t := Mixed.build(42)
	for _i in 60:
		t.step()
	var whole := PeopleView.new()
	var culled := PeopleView.new()
	var area := Rect2(0.0, float(VC.floor_to_row(30) * VC.CELL_H), float(60 * VC.CELL_W), float(18 * VC.CELL_H))
	var bad_whole := -1
	var bad_culled := -1
	var bad_lights := -1
	var most_culled := 0
	var steps := 0
	var removed := false
	for start: int in WINDOWS:
		t.clock.set_to_tick(start)
		for n in TICKS:
			t.step()
			steps += 1
			if not removed and steps == 150:  # a removal shifts every later index: the kept state must start over
				t.people.remove_person(t.people.count() / 2)
				removed = true
			var kept := whole.figures(t)
			var kept_culled := culled.figures(t, area)
			var fresh := PeopleView.new()
			var expect := fresh.figures(t)
			if kept != expect and bad_whole < 0:
				bad_whole = steps
			if bad_lights < 0 and (whole.in_use != fresh.in_use or whole.asleep != fresh.asleep or culled.in_use != fresh.in_use or culled.asleep != fresh.asleep):
				bad_lights = steps
			var fresh_culled := PeopleView.new()
			if kept_culled != fresh_culled.figures(t, area) and bad_culled < 0:
				bad_culled = steps
			most_culled = maxi(most_culled, kept_culled.size())
	check.call(bad_whole < 0, "people view incremental: figures match a fresh view every tick (first difference at step %d)" % bad_whole)
	check.call(bad_culled < 0, "people view incremental: culled figures match a fresh culled view every tick (first difference at step %d)" % bad_culled)
	check.call(bad_lights < 0, "people view incremental: in_use and asleep match a fresh view every tick (first difference at step %d)" % bad_lights)
	check.call(removed and most_culled > 0 and whole.in_use.size() > 0, "people view incremental: the fixture has people on the area and rooms in use, so the comparison covers something")
