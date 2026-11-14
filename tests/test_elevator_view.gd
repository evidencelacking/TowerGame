extends RefCounted
## Drawing elevators (4.9): shafts over their span with disabled stops marked, cars with their
## load, queues by direction (up left, down right), cars sliding between ticks, and a rush hour
## queue. Reads the sim only: drawing never changes its hash.

const Tower := preload("res://scripts/sim/tower.gd")
const Command := Tower.Command
const CarsScript := preload("res://scripts/sim/cars.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const TestDispatch := preload("res://tests/test_dispatch.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestBoarding := preload("res://tests/test_boarding.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")


static func _find(rows: Array[Dictionary], key: String, value: Variant) -> Dictionary:
	for row: Dictionary in rows:
		if row[key] == value:
			return row
	return {}


static func run(check: Callable) -> void:
	# Shafts: span, width, stops and disabled stops.
	var t := TestBoarding._setup([1] as Array[int], 40)
	var id := TestDispatch._id(t)
	TestRooms._send(t, Command.SET_SHAFT_STOP, [id, 7, 0] as Array[int])
	var shafts := ElevatorView.shafts(t)
	check.call(shafts.size() == 1 and shafts[0]["id"] == id and shafts[0]["x"] == 100 and shafts[0]["width"] == 4 and shafts[0]["bottom"] == 1 and shafts[0]["top"] == 30, "elevator view: a shaft is drawn from its bottom floor to its top")
	check.call(shafts[0]["disabled"] == [7] and (shafts[0]["stops"] as Array).size() == 29 and not (shafts[0]["stops"] as Array).has(7), "elevator view: a disabled stop is marked apart from the stops")
	var basement := TestShafts._tall()
	TestShafts._shaft(basement, -3, 4, 110)
	var low := ElevatorView.shafts(basement)
	check.call(low.size() == 1 and low[0]["bottom"] == -3 and low[0]["top"] == 4, "elevator view: a shaft through the basements spans its floors")

	# Labels and geometry.
	check.call(ElevatorView.load_label(12, 17) == "12/17" and ElevatorView.load_label(0, 17) == "0/17", "elevator view: a car shows its load as n/capacity")
	check.call(ElevatorView.overflow_label(5, 5) == "" and ElevatorView.overflow_label(12, 5) == "+7", "elevator view: a long queue gets a count label")
	check.call(ElevatorView.level_of(1) == 1 and ElevatorView.level_of(-1) == 0 and ElevatorView.level_to_y(100.0, 16) == 0.0 and ElevatorView.level_to_y(1.0, 16) == 99 * 16.0 and ElevatorView.level_to_y(0.0, 16) == 100 * 16.0, "elevator view: floor 100 is the top row, B1 sits just under floor 1")

	# Cars: position and load label.
	var v := ElevatorView.new()
	v.observe(t)
	var cars := v.cars(t, 1.0)
	check.call(cars.size() == 1 and cars[0]["level"] == 1.0 and cars[0]["label"] == "0/17" and cars[0]["x"] == 100, "elevator view: an idle car is drawn at its floor with its load")

	# Interpolation: a car that moved 5 floors in a tick slides between the two positions.
	var u := TestDispatch._setup([1] as Array[int])
	var w := ElevatorView.new()
	w.observe(u)
	u.rooms.send_car(0, 6)
	u.step()
	w.observe(u)
	var floor_now: int = u.rooms._cars[0][CarsScript.FLOOR]
	var start := w.cars(u, 0.0)[0]
	var mid := w.cars(u, 0.5)[0]
	var done := w.cars(u, 1.0)[0]
	check.call(floor_now == 6 and start["level"] == 1.0 and done["level"] == 6.0 and mid["level"] == 3.5 and mid["moving"], "elevator view: a car slides from its last sim floor to its new one over the tick")
	check.call(w.cars(u, 5.0)[0]["level"] == 6.0 and w.cars(u, -1.0)[0]["level"] == 1.0, "elevator view: interpolation stays between the two sim positions")
	check.call(not w.observe(u), "elevator view: observing the same tick twice changes nothing")
	u.step()
	u.step()
	w.observe(u)
	check.call(not w.cars(u, 0.5)[0]["moving"] and w.cars(u, 0.5)[0]["level"] == float(ElevatorView.level_of(u.rooms._cars[0][CarsScript.FLOOR])), "elevator view: a parked car stands still")

	# Queues: up on the left, down on the right.
	var q := TestBoarding._setup([30] as Array[int], 20)
	var qid := TestDispatch._id(q)
	TestBoarding._queue(q, 0, 8, 1, 20)  # 8 going up from floor 1
	TestBoarding._queue(q, 8, 11, 15, 2)  # 3 going down from floor 15
	var queues := ElevatorView.queues(q)
	var up := _find(queues, "dir", CarsScript.UP)
	var down := _find(queues, "dir", CarsScript.DOWN)
	check.call(queues.size() == 2 and up["floor"] == 1 and up["count"] == 8 and up["side"] == -1, "elevator view: people going up queue on the left")
	check.call(down["floor"] == 15 and down["count"] == 3 and down["shown"] == 3 and down["side"] == 1 and down["label"] == "", "elevator view: people going down queue on the right")
	check.call(up["shown"] == ElevatorView.MAX_QUEUE_FIGURES and up["label"] == "+3" and up["shaft"] == qid, "elevator view: a long queue is cut to its first figures and a count")
	var before := q.state_hash()
	ElevatorView.queues(q)
	ElevatorView.shafts(q)
	var observer := ElevatorView.new()
	observer.observe(q)
	observer.cars(q, 0.5)
	check.call(q.state_hash() == before, "elevator view: drawing leaves the sim hash unchanged")

	# Rush hour: a scripted morning, people queued both ways at once, both sides show.
	var r := TestBoarding._setup([1, 1] as Array[int], 60)
	r.clock.set_to_tick(TestOfficeDay._tick_at(PeopleScript.ARRIVE - 5, 0))
	TestBoarding._queue(r, 0, 25, 1, 25)  # the 9 am wave going up from the lobby
	TestBoarding._queue(r, 25, 31, 25, 1)  # early leavers going down from floor 25
	var rv := ElevatorView.new()
	var both := false
	var longest := 0
	var loaded := false
	for n in 12:
		r.step()
		rv.observe(r)
		for car: Dictionary in rv.cars(r, 1.0):
			loaded = loaded or ((car["load"] as int) > 0 and car["label"] == "%d/17" % car["load"])
		var up_count := 0
		var down_count := 0
		for entry: Dictionary in ElevatorView.queues(r):
			if entry["dir"] == CarsScript.UP:
				up_count += entry["count"] as int
				check.call(entry["side"] == -1 and entry["shown"] <= ElevatorView.MAX_QUEUE_FIGURES, "elevator view: rush hour up queues are left of the shaft and capped")
			else:
				down_count += entry["count"] as int
				check.call(entry["side"] == 1, "elevator view: rush hour down queues are right of the shaft")
		check.call(up_count + down_count == r.rooms.queued_ids().size(), "elevator view: queue counts match the sim queue at tick %d" % n)
		both = both or (up_count > 0 and down_count > 0)
		longest = maxi(longest, up_count)
	check.call(both and longest > ElevatorView.MAX_QUEUE_FIGURES, "elevator view: at rush hour people queue up and down at once, and the long queue shows a count")
	check.call(loaded, "elevator view: a car carrying the morning wave shows a load")
