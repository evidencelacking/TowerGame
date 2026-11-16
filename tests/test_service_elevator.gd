extends RefCounted
## Service elevator tests (6.1): staff only, 17 per car, 2 stars, shares the shaft limits.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RunningCosts := preload("res://scripts/sim/running_costs.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")


static func _shaft(t: TowerSim, kind: String, bottom: int, top: int, x: int) -> int:
	var code: int = t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), bottom, top, x)
	if code != RoomsScript.OK:
		return -code
	return t.rooms._shaft_base(t.rooms.link_at(bottom, x))


static func _find(t: TowerSim, to_floor: int, staff: bool) -> Dictionary:
	return RoutesScript.find(t.floors, t.rooms, t.grid, 1, 100, to_floor, 100, staff)


static func _rides(route: Dictionary, shaft: int) -> bool:
	for leg: Dictionary in route["legs"]:
		if leg["kind"] == RoutesScript.ELEVATOR and leg["shaft"] == shaft:
			return true
	return false


static func run(check: Callable) -> void:
	# Catalogue: $100,000 shaft, $50,000 car, 2 stars, 17 per car, quarterly upkeep like a local shaft.
	check.call(CatalogueScript.cost("service_shaft") == 100000 and CatalogueScript.cost("service_car") == 50000, "service shaft costs $100,000 and a car $50,000")
	check.call(CatalogueScript.field("service_shaft", "star") == 2 and CatalogueScript.field("service_car", "star") == 2, "service elevators need 2 stars")
	check.call(CatalogueScript.field("service_car", "capacity") == 17, "a service car carries 17")
	check.call(RunningCosts.upkeep_of("service_shaft") == RunningCosts.upkeep_of("local_shaft") and RunningCosts.upkeep_of("service_shaft") > 0, "a service shaft has the local shaft's quarterly upkeep")

	# Placement is gated by stars (the catalogue star), and a service shaft is charged once.
	var t := TestElevatorRoutes._plain(6)
	check.call(Toolbar.item_state("service_shaft", 1)["locked"] and not Toolbar.item_state("service_shaft", 2)["locked"], "the service shaft and car unlock at 2 stars")
	check.call(Toolbar.item_state("service_car", 1)["locked"] and not Toolbar.item_state("service_car", 2)["locked"], "the service car unlocks at 2 stars")

	# A service shaft holds only service cars, a local shaft only local ones: the car kind follows the shaft.
	var funds := t.ledger.balance
	var svc := _shaft(t, "service_shaft", 1, 6, 100)
	check.call(svc > 0 and funds - t.ledger.balance == 100000, "a service shaft is charged $100,000")
	funds = t.ledger.balance
	check.call(t.rooms.add_car(t.ledger, 0, 3, svc, 1) == RoomsScript.OK and funds - t.ledger.balance == 50000, "a service car is charged $50,000")
	var cars: Array = t.rooms.cars_of(svc)
	check.call(cars.size() == 1, "the car sits in the service shaft")

	# Shafts never share a column: a standard shaft cannot overlap a service shaft.
	check.call(_shaft(t, "local_shaft", 1, 6, 102) == -RoomsScript.OVER_SHAFT, "a standard shaft cannot share a column with a service shaft")
	check.call(_shaft(t, "service_shaft", 1, 6, 101) == -RoomsScript.OVER_SHAFT, "a service shaft cannot share a column with another shaft")

	# Cars count toward the 8 per shaft limit.
	var rich := TestElevatorRoutes._plain(6)
	var big := _shaft(rich, "service_shaft", 1, 6, 100)
	var added := 0
	for n in 9:
		if rich.rooms.add_car(rich.ledger, 0, 5, big, 1) == RoomsScript.OK:
			added += 1
	check.call(added == 8 and rich.rooms.add_car(rich.ledger, 0, 5, big, 1) == RoomsScript.MAX_CARS, "a service shaft takes 8 cars at most")

	# Counts toward the 24 shaft limit (shared group with local shafts).
	check.call(CatalogueScript.field("service_shaft", "limit_group") == CatalogueScript.field("local_shaft", "limit_group") and CatalogueScript.field("service_shaft", "limit") == 24, "service shafts share the 24 shaft limit")

	# Routing: staff ride the service car; guests, tenants and workers never do, even when it is the only link.
	var only := TestElevatorRoutes._plain(6)
	var s_only := _shaft(only, "service_shaft", 1, 6, 100)
	var staff_route := _find(only, 6, true)
	check.call(staff_route["reason"] == RoutesScript.OK and _rides(staff_route, s_only), "a housekeeper rides the service elevator")
	var guest_route := _find(only, 6, false)
	check.call(guest_route["reason"] != RoutesScript.OK and not _rides(guest_route, s_only), "a guest never rides it, even as the only link")

	# With both a service and a standard shaft, each group takes its own.
	var both := TestElevatorRoutes._plain(6)
	var s_both := _shaft(both, "service_shaft", 1, 6, 100)
	var l_both := _shaft(both, "local_shaft", 1, 6, 110)
	both.rooms.add_car(both.ledger, 0, 3, s_both, 1)
	both.rooms.add_car(both.ledger, 0, 3, l_both, 1)
	var staff_both := RoutesScript.find(both.floors, both.rooms, both.grid, 1, 100, 6, 100, true)
	var guest_both := RoutesScript.find(both.floors, both.rooms, both.grid, 1, 110, 6, 110, false)
	check.call(staff_both["reason"] == RoutesScript.OK and _rides(staff_both, s_both) and not _rides(staff_both, l_both), "staff take the service car, not the standard one")
	check.call(guest_both["reason"] == RoutesScript.OK and _rides(guest_both, l_both) and not _rides(guest_both, s_both), "guests take the standard car, not the service one")
	var staff_std := RoutesScript.find(both.floors, both.rooms, both.grid, 1, 110, 6, 110, true)
	check.call(staff_std["reason"] != RoutesScript.OK or not _rides(staff_std, l_both), "staff never ride a standard elevator")

	# Staff use stairs, not escalators.
	var esc := TestElevatorRoutes._plain(3)
	esc.rooms.place_escalator(esc.grid, esc.floors, esc.ledger, 0, 1, 100)
	check.call(_find(esc, 2, false)["reason"] == RoutesScript.OK and _find(esc, 2, true)["reason"] != RoutesScript.OK, "staff do not ride escalators")
