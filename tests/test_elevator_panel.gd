extends RefCounted
## The elevator panel, #187: stop on/off, per-car home floors, add and remove cars, all as commands.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const ElevatorWindow := preload("res://scripts/view/elevator_window.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")


static func run(check: Callable) -> void:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 1, 10, 100)
	t.stars = 3
	var id := TestCars._shaft_id(t, 1, 100)
	TestCars._add(t, id, 1)
	TestCars._add(t, id, 5)

	# Home floors: the nth car, oldest first, must be given a stop.
	check.call(TestRooms._send(t, Command.SET_CAR_HOME, [id, 1, 8] as Array[int]) == RoomsScript.OK and t.rooms.cars_of(id)[1][CarsScript.HOME] == 8, "SET_CAR_HOME moves the second car's home")
	check.call(t.rooms.cars_of(id)[0][CarsScript.HOME] == 1, "the first car keeps its home")
	check.call(TestRooms._send(t, Command.SET_SHAFT_STOP, [id, 3, 0] as Array[int]) == RoomsScript.OK and not t.rooms.is_stop(id, 3), "a floor can be switched off")
	check.call(TestRooms._send(t, Command.SET_CAR_HOME, [id, 0, 3] as Array[int]) == RoomsScript.BAD_HOME_FLOOR and t.rooms.cars_of(id)[0][CarsScript.HOME] == 1, "a home on a switched-off floor is refused")
	check.call(TestRooms._send(t, Command.SET_CAR_HOME, [id, 5, 2] as Array[int]) == RoomsScript.NO_SUCH_CAR, "a car that does not exist is refused")
	check.call(TestRooms._send(t, Command.SET_SHAFT_STOP, [id, 8, 0] as Array[int]) == RoomsScript.HOME_STOP and t.rooms.is_stop(id, 8), "a home floor stays a stop")

	# Fewer than 2 stops is refused.
	var tight := TestShafts._tall()
	TestShafts._shaft(tight, 1, 4, 100)
	var tid := TestCars._shaft_id(tight, 1, 100)
	check.call(TestRooms._send(tight, Command.SET_SHAFT_STOP, [tid, 2, 0] as Array[int]) == RoomsScript.OK, "a floor goes off")
	check.call(TestRooms._send(tight, Command.SET_SHAFT_STOP, [tid, 3, 0] as Array[int]) == RoomsScript.OK, "a second floor goes off")
	check.call(TestRooms._send(tight, Command.SET_SHAFT_STOP, [tid, 1, 0] as Array[int]) == RoomsScript.TOO_FEW_STOPS and tight.rooms.is_stop(tid, 1), "the last two stops cannot be switched off")

	# What the panel shows.
	var info := ElevatorWindow.describe(t, id)
	check.call(not info.is_empty() and info["cars"] == 2 and info["homes"] == ([1, 8] as Array[int]) and info["rows"].size() == 10, "the panel lists every floor and each car's home")
	var top: Dictionary = info["rows"][0]
	check.call(top["floor"] == 10 and top["label"] == "10" and top["stop"] and top["homes"] == ([false, false] as Array[bool]), "rows run top floor first")
	var row8: Dictionary = info["rows"][2]
	check.call(row8["floor"] == 8 and row8["homes"] == ([false, true] as Array[bool]), "a home floor is marked on the car's column")
	var row3: Dictionary = info["rows"][7]
	check.call(row3["floor"] == 3 and not row3["stop"], "a switched-off floor shows unticked")
	check.call(ElevatorWindow.describe(t, 9999).is_empty(), "an unknown shaft describes as nothing")

	# The panel's buttons queue commands for the next tick.
	var w := ElevatorWindow.new()
	w.bind(t, null)
	check.call(not w.set_stop(4, false), "a closed panel queues nothing")
	w.show_shaft(id)
	check.call(w.is_open() and w.set_stop(4, false), "an open panel queues a stop change")
	t.step()
	check.call(not t.rooms.is_stop(id, 4), "the stop change reaches the sim")
	check.call(w.set_home(0, 6), "the panel queues a home change")
	t.step()
	check.call(t.rooms.cars_of(id)[0][CarsScript.HOME] == 6, "the home change reaches the sim")
	check.call(w.add_car(), "the panel queues an added car")
	t.step()
	check.call(t.rooms.car_count(id) == 3, "the added car exists")
	check.call(w.remove_car(), "the panel queues a removed car")
	t.step()
	check.call(t.rooms.car_count(id) == 2, "the removed car is gone")
	check.call(w.set_schedule(1, 1, 8, 45), "the panel queues a schedule slot")
	t.step()
	check.call(t.rooms.schedule_field(id, 1, 0) == 1 and t.rooms.schedule_field(id, 1, 1) == 8 and t.rooms.schedule_field(id, 1, 2) == 45, "the schedule change reaches the sim")
	check.call(ElevatorWindow.describe(t, id)["schedule"].size() == 18, "the panel describes all six schedule slots")
	w.close()
	check.call(not w.is_open() and not w.set_stop(4, true), "a closed panel is shut")
	w.free()

	# Saves keep the homes.
	var u := TowerSim.new(0)
	check.call(u.load_state(t.save()) and u.state_hash() == t.state_hash() and u.rooms.cars_of(id)[0][CarsScript.HOME] == 6, "homes survive a save")
