extends RefCounted
## The room catalogue: one data row per buildable type. Integers only; see CLAUDE.md.
##
## Look a row up by room id, then read fields by name:
##   RoomCatalogue.cost("office")            -> 40000
##   RoomCatalogue.row("office")["width"]    -> 9
## Values come from docs/gameplay-reference.md (Construction and placement, Limits).
##
## Fields:
##   width, height  size in grid units (a cell is one unit wide, one floor tall).
##                  Widths are UNVERIFIED tunables (the reference gives none; see #12).
##                  height is the minimum for rooms that can grow (lobby, shafts).
##   cost           dollars; per unit of width when per_unit is true (lobby, floor).
##                  Every room also pays FLOOR_COST_PER_UNIT for a missing floor under it.
##   per_unit       cost is charged per unit of width.
##   star           star rating that unlocks it (1 to 5).
##   removable      false for rooms the player cannot bulldoze.
##   placement      a PLACE_* rule, a hint for the building issues to enforce.
##   limit          most allowed per tower, or 0 for no limit.
##   limit_group    rooms sharing one limit share this group name; "" counts alone.
##   people         workers (office), residents (condo, apartment) or guests (hotel: single 1, twin 2, suite 2) the room holds; absent elsewhere for now.
##                  Population is People.in_tower_count().
##   rent           quarterly rent in dollars at each of 4 levels, lowest to highest (office only;
##                  UNVERIFIED tunables; the third is the $10,000 default, see rent.gd).
##                  Hotel rows: the rent is dollars per NIGHT at each level (default the third: $2,000 single,
##                  $4,000 twin, $8,000 suite; UNVERIFIED tunables, owner ruling #146), paid at check-out (hotel.gd).
##   suite          true for the suite only: the VIP task finds suites through Hotel.suites().
##   needs_parking  true when a guest needs a free parking space to rent the room (suite only).
##   upkeep         quarterly running cost in dollars (see running_costs.gd); absent means free (stairs).
##                  Charged per shaft for elevators, per room otherwise, once for the ground lobby.
##                  All tunable (owner ruling); the kinds in UPKEEP_UNVERIFIED are guesses.
##   staff          workers a room employs (our own kinds: gym, daycare, clinic, ...). Their wages are folded into
##                  the shop's empty-day loss in commerce.gd; names.gd gives them job titles. All tunable.
##   capacity       passengers per car (car rows only; 0 elsewhere).
##   limit_scope    "tower", or "shaft" for elevator cars (limit is cars per shaft).

const FLOOR_COST_PER_UNIT := 500  ## Dollars per unit for the floor under any room.
const RESCUE_COST := 500000  ## Fire rescue, dollars (decided 2026-11-10).

## Kinds whose upkeep is a guess: only the $10,000 per elevator (local shaft) is in the reference.
const UPKEEP_UNVERIFIED: Array[String] = [
	"lobby", "service_shaft", "express_shaft", "housekeeping", "security", "escalator", "recycling", "parking_ramp", "metro", "observation_deck", "casino", "pool", "helipad",
]

const PLACE_ANYWHERE := 0  ## Above or below ground.
const PLACE_ABOVE_GROUND := 1
const PLACE_LOBBY_FLOORS := 2  ## Floor 1, then every 15 floors (15 to 90).
const PLACE_STACKED := 3  ## Needs a floor on the level below no narrower than itself.
const PLACE_BETWEEN_FLOORS := 4  ## Stairs; not over elevators.
const PLACE_SHAFT := 5  ## Elevator shaft: a vertical run of floors (local up to 30).
const PLACE_CAR := 6  ## Elevator car: inside a shaft of its own kind.
const PLACE_ESCALATOR := 7  ## Commercial, lobby or empty floor only.
const PLACE_UNDERGROUND := 8
const PLACE_RAMP := 9  ## One vertical column under the ground lobby.
const PLACE_CHAIN := 10  ## Must chain to a ramp; broken chains stop working.
const PLACE_BOTTOM_B10 := 11  ## Metro: bottom at B10, nothing below.
const PLACE_FLOOR_100 := 12  ## Cathedral: floor 100 only.

## Room id order, for stable iteration.
const IDS: Array[String] = [
	"lobby", "floor", "stairs", "local_shaft", "local_car", "office", "condo", "fast_food",
	"service_shaft", "service_car", "hotel_single", "housekeeping", "security", "escalator",
	"express_shaft", "express_car", "hotel_twin", "hotel_suite", "restaurant", "retail",
	"movie_theatre", "party_hall", "medical", "recycling", "parking_ramp", "parking_space",
	"metro", "cathedral", "gym", "daycare", "clinic", "nightclub", "coworking", "observation_deck", "casino",
	"cafe", "pizza", "sushi", "fine_dining", "bar",
	"grocery", "deli", "pool", "helipad", "school",
	"ballroom", "conference_center", "apartment",
]

const _ROWS: Dictionary = {
	"lobby": {"upkeep": 2000, "width": 1, "height": 1, "cost": 5000, "per_unit": true, "star": 1,
		"removable": false, "placement": PLACE_LOBBY_FLOORS, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"floor": {"width": 1, "height": 1, "cost": 500, "per_unit": true, "star": 1,
		"removable": false, "placement": PLACE_STACKED, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"stairs": {"width": 4, "height": 2, "cost": 5000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_BETWEEN_FLOORS, "limit": 64,
		"limit_group": "stairs_escalators", "limit_scope": "tower"},
	"local_shaft": {"upkeep": 10000, "width": 4, "height": 1, "cost": 200000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"local_car": {"capacity": 17, "width": 4, "height": 1, "cost": 80000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"office": {"rent": [3000, 6000, 10000, 15000], "people": 6, "width": 9, "height": 1, "cost": 40000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"condo": {"people": 3, "width": 16, "height": 1, "cost": 80000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"fast_food": {"width": 16, "height": 1, "cost": 100000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"service_shaft": {"upkeep": 10000, "width": 4, "height": 1, "cost": 100000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"service_car": {"capacity": 17, "width": 4, "height": 1, "cost": 50000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"hotel_single": {"people": 1, "rent": [600, 1200, 2000, 3000], "width": 4, "height": 1, "cost": 20000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"housekeeping": {"upkeep": 5000, "width": 16, "height": 1, "cost": 50000, "per_unit": false, "star": 2,
		"removable": false, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# tune later (#9: 10 vs 8). The reference gives 10 (I) for medical and security together; S says 8.
	"security": {"upkeep": 5000, "width": 16, "height": 1, "cost": 100000, "per_unit": false, "star": 2,
		"removable": false, "placement": PLACE_ANYWHERE, "limit": 10,
		"limit_group": "medical_security", "limit_scope": "tower"},
	"escalator": {"upkeep": 2000, "width": 8, "height": 2, "cost": 20000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ESCALATOR, "limit": 64,
		"limit_group": "stairs_escalators", "limit_scope": "tower"},
	"express_shaft": {"upkeep": 10000, "width": 6, "height": 1, "cost": 400000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"express_car": {"capacity": 36, "width": 6, "height": 1, "cost": 150000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"hotel_twin": {"people": 2, "rent": [1200, 2400, 4000, 6000], "width": 6, "height": 1, "cost": 50000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"hotel_suite": {"people": 2, "rent": [2400, 4800, 8000, 12000], "suite": true, "needs_parking": true, "width": 10, "height": 1, "cost": 100000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"restaurant": {"width": 24, "height": 1, "cost": 200000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"retail": {"rent": [1500, 3000, 5000, 7500], "width": 12, "height": 1, "cost": 100000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 512,
		"limit_group": "parking_shops", "limit_scope": "tower"},
	"movie_theatre": {"width": 32, "height": 2, "cost": 500000, "per_unit": false, "star": 3,
		"removable": false, "placement": PLACE_ABOVE_GROUND, "limit": 16,
		"limit_group": "theatres_halls", "limit_scope": "tower"},
	"party_hall": {"width": 24, "height": 1, "cost": 100000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 16,
		"limit_group": "theatres_halls", "limit_scope": "tower"},
	"medical": {"width": 16, "height": 1, "cost": 500000, "per_unit": false, "star": 3,
		"removable": false, "placement": PLACE_ABOVE_GROUND, "limit": 10,
		"limit_group": "medical_security", "limit_scope": "tower"},
	"recycling": {"upkeep": 10000, "width": 16, "height": 2, "cost": 500000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_UNDERGROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"parking_ramp": {"upkeep": 1000, "width": 4, "height": 1, "cost": 50000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_RAMP, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"parking_space": {"width": 4, "height": 1, "cost": 3000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_CHAIN, "limit": 512,
		"limit_group": "parking_shops", "limit_scope": "tower"},
	# The metro station (#325). The reference has a 3 floor station at B8-B10 from star 4; ours is a single
	# basement floor, 32 wide, on any basement floor, from star 3 (the owner wants transit earlier). One per tower
	# and permanent. Cost as in the reference; the upkeep is our own tunable.
	"metro": {"upkeep": 8000, "width": 32, "height": 1, "cost": 1000000, "per_unit": false, "star": 3,
		"removable": false, "placement": PLACE_UNDERGROUND, "limit": 1,
		"limit_group": "", "limit_scope": "tower"},
	"cathedral": {"width": 32, "height": 1, "cost": 3000000, "per_unit": false, "star": 5,
		"removable": false, "placement": PLACE_FLOOR_100, "limit": 1,
		"limit_group": "", "limit_scope": "tower"},
	# Our own kinds (M13, #291; not in the reference, every number a tunable). Sized and priced between
	# fast food (100k, 16 wide, star 1) and the restaurant (200k, 24 wide, star 3).
	"gym": {"staff": 4, "width": 16, "height": 1, "cost": 120000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"daycare": {"staff": 3, "width": 12, "height": 1, "cost": 80000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# School (#370): the daycare's older sibling, children of school age, weekdays. 24 places, star 3, $150,000.
	"school": {"staff": 4, "width": 16, "height": 1, "cost": 150000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Rental apartment (#379, our own kind): a home that is rented, not sold. Two residents move in over days (apartments.gd),
	# pay rent on the quarterly cycle at four levels (default the third, $4,000), and some move out over time. Every number a tunable.
	"apartment": {"people": 2, "rent": [2000, 3000, 4000, 6000], "width": 12, "height": 1, "cost": 50000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Ballroom and conference center (#359, own design): bookable event rooms (bookings.gd). Star 4 $600,000 and star 3 $400,000.
	"ballroom": {"staff": 6, "width": 32, "height": 1, "cost": 600000, "per_unit": false, "star": 4,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"conference_center": {"staff": 4, "width": 24, "height": 1, "cost": 400000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"clinic": {"staff": 3, "width": 12, "height": 1, "cost": 200000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Batch 2 (#292). The nightclub is the party hall's bigger, louder cousin (100k, 24 wide, star 3): dearer, with
	# a bar crew, and a star higher. Co-working is an office (40k, 9 wide) rented by the desk: dearer and wider.
	"nightclub": {"staff": 5, "width": 24, "height": 1, "cost": 250000, "per_unit": false, "star": 4,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"coworking": {"staff": 2, "width": 16, "height": 1, "cost": 150000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Observation deck (#318, our own kind): a landmark like the cathedral, one per tower, on the top floor only
	# (rooms.gd), 32 wide, star 4. Dearer than the nightclub, cheaper than the cathedral; every number a tunable.
	# Casino (#319, our own kind): one per tower, 40 wide, star 4, open evening to early morning. The issue asked for
	# two floors; tall rooms now work above ground (#328, rooms.gd TALL_KINDS), so making it two is a later step; it is one wide floor for now.
	"casino": {"upkeep": 10000, "staff": 6, "width": 40, "height": 1, "cost": 1200000, "per_unit": false, "star": 4,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"observation_deck": {"upkeep": 6000, "staff": 2, "width": 32, "height": 1, "cost": 800000, "per_unit": false, "star": 4,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Helicopter pad (#409, our own kind): one per tower, on the roof (the observation deck's top-floor rule), star 3.
	# Upkeep is $2,000 a day; RunningCosts charges per quarter (Clock.DAYS_PER_QUARTER = 3 days), so $6,000 a quarter.
	# Its hooks (fire rescue, VIP air arrival, daily income, noise) are in fire.gd, vip.gd, helipad.gd and noise.gd.
	"helipad": {"upkeep": 6000, "width": 16, "height": 1, "cost": 400000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# Everyday shops (#322, our own design). A grocery serves the tower's households; a deli is the small early-and-late shop.
	"grocery": {"staff": 3, "width": 20, "height": 1, "cost": 180000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"deli": {"staff": 1, "width": 8, "height": 1, "cost": 60000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# The restaurant family (#323, our own design): five kinds beside fast food and the restaurant, each with its own hours, audience and price.
	"cafe": {"staff": 2, "width": 12, "height": 1, "cost": 90000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"pizza": {"staff": 3, "width": 16, "height": 1, "cost": 120000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"sushi": {"staff": 3, "width": 16, "height": 1, "cost": 180000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"fine_dining": {"staff": 5, "width": 20, "height": 1, "cost": 300000, "per_unit": false, "star": 4,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"bar": {"staff": 3, "width": 14, "height": 1, "cost": 140000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# The swimming pool (#328, our own design): two floors tall above ground (rooms.gd TALL_KINDS), a diving board below
	# and a viewing gallery above. Between the daycare (80k) and the observation deck (800k): the height is the cost.
	# Four staff, one of them the lifeguard (names.gd). Every number a tunable.
	"pool": {"upkeep": 6000, "staff": 4, "width": 24, "height": 2, "cost": 700000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
}


## Words for ids that read badly when capitalised; the shafts and cars are elevators to the player.
const DISPLAY_NAMES: Dictionary = {
	"local_shaft": "Local elevator", "service_shaft": "Service elevator", "express_shaft": "Express elevator",
	"local_car": "Local car", "service_car": "Service car", "express_car": "Express car",
	"medical": "Medical Center", "clinic": "Wellness Clinic",  # #384
}


## The player-facing name of a room or tool id, e.g. "Local elevator" for "local_shaft".
static func display_name(room_id: String) -> String:
	return DISPLAY_NAMES.get(room_id, room_id.replace("_", " ").capitalize())


static func has(room_id: String) -> bool:
	return _ROWS.has(room_id)


## The whole row for a room id, or an empty dictionary if the id is unknown.
static func row(room_id: String) -> Dictionary:
	if not _ROWS.has(room_id):
		return {}
	var found: Dictionary = _ROWS[room_id]
	return found


## One field of a row, e.g. field("office", "cost"). Returns 0 for an unknown id or field.
static func field(room_id: String, field_name: String) -> Variant:
	return row(room_id).get(field_name, 0)


static func cost(room_id: String) -> int:
	return int(field(room_id, "cost"))


static func star(room_id: String) -> int:
	return int(field(room_id, "star"))


static func is_removable(room_id: String) -> bool:
	return bool(field(room_id, "removable"))
