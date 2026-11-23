extends RefCounted
## Room catalogue tests: every row against docs/gameplay-reference.md (Construction and
## placement table and Limits). Expected rows: id, cost, star, removable, limit, limit group.

const Catalogue := preload("res://scripts/sim/room_catalogue.gd")

const EXPECTED: Array = [
	["lobby", 5000, 1, false, 0, ""],
	["floor", 500, 1, false, 0, ""],
	["stairs", 5000, 1, true, 64, "stairs_escalators"],
	["local_shaft", 200000, 1, true, 24, "shafts"],
	["local_car", 80000, 1, true, 8, ""],
	["office", 40000, 1, true, 0, ""],
	["condo", 80000, 1, true, 0, ""],
	["fast_food", 100000, 1, true, 0, ""],
	["service_shaft", 100000, 2, true, 24, "shafts"],
	["service_car", 50000, 2, true, 8, ""],
	["hotel_single", 20000, 2, true, 0, ""],
	["housekeeping", 50000, 2, false, 0, ""],
	["security", 100000, 2, false, 10, "medical_security"],
	["escalator", 20000, 3, true, 64, "stairs_escalators"],
	["express_shaft", 400000, 3, true, 24, "shafts"],
	["express_car", 150000, 3, true, 8, ""],
	["hotel_twin", 50000, 3, true, 0, ""],
	["hotel_suite", 100000, 3, true, 0, ""],
	["restaurant", 200000, 3, true, 0, ""],
	["retail", 100000, 3, true, 512, "parking_shops"],
	["movie_theatre", 500000, 3, false, 16, "theatres_halls"],
	["party_hall", 100000, 3, true, 16, "theatres_halls"],
	["medical", 500000, 3, false, 10, "medical_security"],
	["recycling", 500000, 3, true, 0, ""],
	["parking_ramp", 50000, 3, true, 0, ""],
	["parking_space", 3000, 3, true, 512, "parking_shops"],
	["metro", 1000000, 3, false, 1, ""],
	["cathedral", 3000000, 5, false, 1, ""],
	["gym", 120000, 2, true, 0, ""],
	["daycare", 80000, 2, true, 0, ""],
	["clinic", 200000, 3, true, 0, ""],
	["nightclub", 250000, 4, true, 0, ""],
	["coworking", 150000, 3, true, 0, ""],
	["observation_deck", 800000, 4, true, 0, ""],
	["casino", 1200000, 4, true, 0, ""],
	["cafe", 90000, 2, true, 0, ""],
	["pizza", 120000, 2, true, 0, ""],
	["sushi", 180000, 3, true, 0, ""],
	["fine_dining", 300000, 4, true, 0, ""],
	["bar", 140000, 3, true, 0, ""],
	["grocery", 180000, 2, true, 0, ""],
	["deli", 60000, 1, true, 0, ""],
	["pool", 700000, 3, true, 0, ""],
	["helipad", 400000, 3, true, 0, ""],
	["school", 150000, 3, true, 0, ""],
	["ballroom", 600000, 4, true, 0, ""],
	["conference_center", 400000, 3, true, 0, ""],
	["apartment", 50000, 2, true, 0, ""],
	["studio", 50000, 1, true, 0, ""],
	["penthouse", 140000, 1, true, 0, ""],
	["assisted", 70000, 3, true, 0, ""],
	["emergency_room", 700000, 4, true, 0, ""],
	["operating_room", 900000, 4, true, 0, ""],
	["imaging", 600000, 4, true, 0, ""],
	["patient_ward", 500000, 4, true, 0, ""],
]


static func run(check: Callable) -> void:
	check.call(EXPECTED.size() == Catalogue.IDS.size(), "the catalogue has one row per expected room")
	var ids_match := EXPECTED.size() == Catalogue.IDS.size()
	for index in mini(EXPECTED.size(), Catalogue.IDS.size()):
		if Catalogue.IDS[index] != EXPECTED[index][0]:
			ids_match = false
	check.call(ids_match, "the catalogue id order matches the reference table")

	for entry: Array in EXPECTED:
		var id: String = entry[0]
		var tag := "room " + id + ": "
		check.call(Catalogue.has(id), tag + "has a row")
		check.call(Catalogue.cost(id) == entry[1], tag + "cost")
		check.call(Catalogue.star(id) == entry[2], tag + "unlock star")
		check.call(Catalogue.is_removable(id) == entry[3], tag + "removable")
		check.call(Catalogue.field(id, "limit") == entry[4], tag + "limit")
		check.call(Catalogue.field(id, "limit_group") == entry[5], tag + "limit group")
		var width: int = Catalogue.field(id, "width")
		var height: int = Catalogue.field(id, "height")
		check.call(width >= 1 and height >= 1, tag + "size is positive")
		var placement: int = Catalogue.field(id, "placement")
		check.call(placement >= 0 and placement <= Catalogue.PLACE_FLOOR_100, tag + "placement rule is known")
		check.call(Catalogue.field(id, "per_unit") is bool, tag + "per_unit is a bool")
		var scope: String = Catalogue.field(id, "limit_scope")
		check.call(scope == "tower" or scope == "shaft", tag + "limit scope is tower or shaft")

	# Sizes the reference states.
	check.call(Catalogue.field("movie_theatre", "height") == 2, "movie theatre is 2 floors")
	check.call(Catalogue.field("recycling", "height") == 2, "recycling centre is 2 floors")
	check.call(Catalogue.field("metro", "height") == 1, "metro station is one basement floor (our own, smaller than the reference)")

	# Prices set by the gameplay review.
	check.call(Catalogue.field("lobby", "per_unit") == true, "the lobby is charged per unit")
	check.call(Catalogue.FLOOR_COST_PER_UNIT == 500, "the floor under a room is $500 a unit")
	check.call(Catalogue.field("floor", "cost") == Catalogue.FLOOR_COST_PER_UNIT, "a floor costs the floor rate")
	check.call(Catalogue.cost("local_shaft") != Catalogue.cost("express_shaft"), "shafts are priced per kind")
	check.call(Catalogue.cost("local_car") != Catalogue.cost("service_car"), "cars are priced per kind")
	check.call(Catalogue.field("stairs", "limit") == Catalogue.field("escalator", "limit"), "stairs and escalators share a limit")
	check.call(Catalogue.field("security", "limit") == 10, "security limit is 10")

	# Resolved values: passengers per car and the rescue cost.
	check.call(Catalogue.field("local_car", "capacity") == 17, "a local car carries 17")
	check.call(Catalogue.field("express_car", "capacity") == 36, "an express car carries 36")
	check.call(Catalogue.field("service_car", "capacity") == 17, "a service car carries 17")
	check.call(Catalogue.field("office", "capacity") == 0, "a non-car room has no car capacity")
	check.call(Catalogue.RESCUE_COST == 500000, "fire rescue costs $500,000")

	# Unknown ids.
	check.call(not Catalogue.has("nonsense"), "an unknown id has no row")
	check.call(Catalogue.row("nonsense").is_empty(), "an unknown id gives an empty row")
	check.call(Catalogue.cost("nonsense") == 0, "an unknown id costs 0")
