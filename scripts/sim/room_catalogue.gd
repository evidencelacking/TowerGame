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
##   people         workers (office) or residents (condo) the room holds; absent elsewhere for now.
##                  Rent comes later; population is People.in_tower_count().
##   capacity       passengers per car (car rows only; 0 elsewhere).
##   limit_scope    "tower", or "shaft" for elevator cars (limit is cars per shaft).

const FLOOR_COST_PER_UNIT := 500  ## Dollars per unit for the floor under any room.
const RESCUE_COST := 500000  ## Fire rescue, dollars (decided 2026-11-10).

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
	"metro", "cathedral",
]

const _ROWS: Dictionary = {
	"lobby": {"width": 1, "height": 1, "cost": 5000, "per_unit": true, "star": 1,
		"removable": false, "placement": PLACE_LOBBY_FLOORS, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"floor": {"width": 1, "height": 1, "cost": 500, "per_unit": true, "star": 1,
		"removable": false, "placement": PLACE_STACKED, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"stairs": {"width": 4, "height": 2, "cost": 5000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_BETWEEN_FLOORS, "limit": 64,
		"limit_group": "stairs_escalators", "limit_scope": "tower"},
	"local_shaft": {"width": 4, "height": 1, "cost": 200000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"local_car": {"capacity": 17, "width": 4, "height": 1, "cost": 80000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"office": {"people": 6, "width": 9, "height": 1, "cost": 40000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"condo": {"people": 3, "width": 16, "height": 1, "cost": 80000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"fast_food": {"width": 16, "height": 1, "cost": 100000, "per_unit": false, "star": 1,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"service_shaft": {"width": 4, "height": 1, "cost": 100000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"service_car": {"capacity": 17, "width": 4, "height": 1, "cost": 50000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"hotel_single": {"width": 4, "height": 1, "cost": 20000, "per_unit": false, "star": 2,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"housekeeping": {"width": 16, "height": 1, "cost": 50000, "per_unit": false, "star": 2,
		"removable": false, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	# tune later (#9: 10 vs 8). The reference gives 10 (I) for medical and security together; S says 8.
	"security": {"width": 16, "height": 1, "cost": 100000, "per_unit": false, "star": 2,
		"removable": false, "placement": PLACE_ANYWHERE, "limit": 10,
		"limit_group": "medical_security", "limit_scope": "tower"},
	"escalator": {"width": 8, "height": 2, "cost": 20000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ESCALATOR, "limit": 64,
		"limit_group": "stairs_escalators", "limit_scope": "tower"},
	"express_shaft": {"width": 6, "height": 1, "cost": 400000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_SHAFT, "limit": 24,  # unverified: reference doesn't scope 24 shafts
		"limit_group": "shafts", "limit_scope": "tower"},
	"express_car": {"capacity": 36, "width": 6, "height": 1, "cost": 150000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_CAR, "limit": 8,
		"limit_group": "", "limit_scope": "shaft"},
	"hotel_twin": {"width": 6, "height": 1, "cost": 50000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"hotel_suite": {"width": 10, "height": 1, "cost": 100000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ABOVE_GROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"restaurant": {"width": 24, "height": 1, "cost": 200000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_ANYWHERE, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"retail": {"width": 12, "height": 1, "cost": 100000, "per_unit": false, "star": 3,
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
	"recycling": {"width": 16, "height": 2, "cost": 500000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_UNDERGROUND, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"parking_ramp": {"width": 4, "height": 1, "cost": 50000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_RAMP, "limit": 0,
		"limit_group": "", "limit_scope": "tower"},
	"parking_space": {"width": 4, "height": 1, "cost": 3000, "per_unit": false, "star": 3,
		"removable": true, "placement": PLACE_CHAIN, "limit": 512,
		"limit_group": "parking_shops", "limit_scope": "tower"},
	"metro": {"width": 32, "height": 3, "cost": 1000000, "per_unit": false, "star": 4,
		"removable": false, "placement": PLACE_BOTTOM_B10, "limit": 1,
		"limit_group": "", "limit_scope": "tower"},
	"cathedral": {"width": 32, "height": 1, "cost": 3000000, "per_unit": false, "star": 5,
		"removable": false, "placement": PLACE_FLOOR_100, "limit": 1,
		"limit_group": "", "limit_scope": "tower"},
}


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
