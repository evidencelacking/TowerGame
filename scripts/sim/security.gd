class_name Security
extends RefCounted
## Security offices (7.4, #169): staffed rooms that cover the tower by distance. Stateless: every
## answer is derived from the placed rooms, so nothing here is saved or hashed.
##
## Staff reach a floor only by the tower's outside emergency stairs, never by the inside stairs,
## escalators or elevators (gameplay review, #169). Emergency stairs are not bought and carry no
## ordinary people, so no route search is needed: coverage is a plain distance in floors (owner
## ruling: floors now, walking time in M9). An office covers every floor within COVER_FLOORS of its
## own, measured in floors (GridScript.floor_to_index, so there is no floor 0 gap). Response time is the
## distance to the nearest office, so it grows with distance rather than ending at a hard line.
## Every number is a tunable (reach 15 is the owner's ruling; guards per office and floors per
## minute are guesses).
##
## Fire (#217) and threat (#218) share one response: `response_ticks` is the time for the nearest covering
## office to reach a floor, `search_rank` the order a guard party sweeps floors from its office.
## The guards use the same emergency stairs, so no route search is needed (#216).
##
## An office is needed for star 3 (StarRules) and clears the "needs security" demand (Demands).
## Fires and threats only happen once an office exists (OFFICE_KIND count above 0); those events
## are not built yet, so `threats_possible` is the hook they will test.

const GridScript := preload("res://scripts/sim/grid.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")

const OFFICE_KIND := "security"
const COVER_FLOORS := 15  ## Floors an office reaches up or down (owner ruling, #169).
const GUARDS_PER_OFFICE := 4  ## Staff employed per office (tunable guess).
const FLOORS_PER_MINUTE := 3  ## Emergency stairs pace used for the response estimate (tunable guess).


## Placed offices.
static func offices(rooms: Rooms) -> Array[int]:
	var found: Array[int] = []
	for id in rooms.room_ids():
		if rooms.kind_of(id) == OFFICE_KIND:
			found.append(id)
	return found


## Guards employed across all offices.
static func staff_count(rooms: Rooms) -> int:
	return offices(rooms).size() * GUARDS_PER_OFFICE


## Floors between two floors, counting the lobby floor 1 and B1 as neighbours (no floor 0).
static func distance(a: int, b: int) -> int:
	return absi(GridScript.floor_to_index(a) - GridScript.floor_to_index(b))


## The nearest office to a floor as {"room": id, "distance": floors}, or {} with no office.
## A tie goes to the lower room id, so the answer is the same on every machine.
static func nearest(rooms: Rooms, grid: GridScript, floor_number: int) -> Dictionary:
	var best: Dictionary = {}
	for id in offices(rooms):
		var run := grid.run_of(id)
		if run.is_empty():
			continue
		var d := distance(run[0], floor_number)
		if best.is_empty() or d < int(best["distance"]):
			best = {"room": id, "distance": d}
	return best


## True when some office reaches the floor.
static func covers(rooms: Rooms, grid: GridScript, floor_number: int) -> bool:
	var near := nearest(rooms, grid, floor_number)
	return not near.is_empty() and int(near["distance"]) <= COVER_FLOORS


## Minutes for a guard to reach a floor, or -1 with no office. Grows with distance; at least 1.
static func response_minutes(rooms: Rooms, grid: GridScript, floor_number: int) -> int:
	var near := nearest(rooms, grid, floor_number)
	if near.is_empty():
		return -1
	return maxi(1, (int(near["distance"]) + FLOORS_PER_MINUTE - 1) / FLOORS_PER_MINUTE)


## Ticks for guards to reach a floor from the nearest office, or -1 when no office covers it (none
## placed, or the floor is beyond COVER_FLOORS of every office). At least 1; rounds up.
static func response_ticks(rooms: Rooms, grid: GridScript, floor_number: int) -> int:
	var near := nearest(rooms, grid, floor_number)
	if near.is_empty() or int(near["distance"]) > COVER_FLOORS:
		return -1
	var minutes := response_minutes(rooms, grid, floor_number)
	return maxi(1, (minutes * 60 + CarsScript.SECONDS_PER_TICK - 1) / CarsScript.SECONDS_PER_TICK)


## The office that answers a floor (the nearest, the lower room id on a tie), or 0 when none covers it.
static func responder(rooms: Rooms, grid: GridScript, floor_number: int) -> int:
	return int(nearest(rooms, grid, floor_number)["room"]) if covers(rooms, grid, floor_number) else 0


## Where a floor falls in a sweep from an office: 0 is the office's own floor, then one up, one down,
## two up, two down and so on (counted in floors, so no floor 0 gap). -1 beyond COVER_FLOORS.
static func search_rank(office_floor: int, floor_number: int) -> int:
	var gap := GridScript.floor_to_index(floor_number) - GridScript.floor_to_index(office_floor)
	if absi(gap) > COVER_FLOORS:
		return -1
	if gap == 0:
		return 0
	return 2 * gap - 1 if gap > 0 else -2 * gap


## Fires and threats only occur once the tower has a security office.
static func threats_possible(rooms: Rooms) -> bool:
	return not offices(rooms).is_empty()
