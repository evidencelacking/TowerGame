class_name Complaints
extends RefCounted
## Complaint reasons (5.7): why a tenant room is unhappy. A pure read of the same inputs that
## drive the grade, so nothing is stored or saved and a reason clears the moment its cause does
## (lower the rent and the rent reason is gone at the next read; a restored rent brings it back,
## the "lower then restore" exploit being a conscious choice: it leaves no lasting penalty).
##
## Reasons (the view maps each to its own words):
##   NOISE     the room is disturbed (Noise level >= NOISE_FROM). Condos and hotel rooms only.
##   DISTANCE  its occupants' travel stress (average before modifiers) is at or above DISTANCE_FROM,
##             which means long walks, queues or rides to the lobby.
##   RENT      its rent level adds stress (Rent.stress_offset > 0).
##   NO_FOOD   an office on a weekday in a tower of FOOD_NEEDED_FROM or more offices whose lunch places cover under
##             FOOD_LOW_PERCENT of the workers (#439).
##   UNREACHED a hotel room whose latest guests could not reach it and left (Hotel.unreached).
## reasons(room) lists every reason that applies, in priority order; reason(room) is the first.
## Priority (unverified, tunable): noise, then distance, then rent. Ties are therefore fixed.
##
## Noise is also wired into the grade here: attach registers a Grades modifier that adds
## Noise.stress_for(level) to the room's average.

const GradesScript := preload("res://scripts/sim/grades.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const CommerceScript := preload("res://scripts/sim/commerce.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const NONE := 0
const NOISE := 1
const DISTANCE := 2
const RENT := 3
const UNREACHED := 4
const NO_GROCERY := 5
const NO_FOOD := 6

## Priority order of the reasons: first match is the main one.
const PRIORITY: Array[int] = [NOISE, DISTANCE, RENT, NO_FOOD, UNREACHED, NO_GROCERY]

const NOISE_FROM := 3  ## Noise level at or above this is a complaint (unverified, tunable).
## A tower with this many condos and no grocery store gives every condo a complaint (#322, our own design, tunable).
const GROCERY_NEEDED_FROM := 10
## Office lunch (#439, our own design, tunable, unverified): from this many offices, on a weekday, lunch coverage under
## FOOD_LOW_PERCENT adds FOOD_LOW_STRESS and under FOOD_VERY_LOW_PERCENT adds FOOD_VERY_LOW_STRESS to every office. NO_FOOD
## is the complaint under FOOD_LOW_PERCENT.
const FOOD_NEEDED_FROM := 10
const FOOD_LOW_PERCENT := 50
const FOOD_VERY_LOW_PERCENT := 25
const FOOD_LOW_STRESS := 10
const FOOD_VERY_LOW_STRESS := 20
const DISTANCE_FROM := PeopleScript.UNEASY_FROM  ## Travel stress at or above this is a complaint (unverified, tunable).

var _grades: GradesScript
var _rooms: RoomsScript
var _grid: GridScript
var _people: PeopleScript
var _rent: RentScript
var hotel: HotelScript  ## Set by Tower; the source of UNREACHED.
var clock: ClockScript  ## Set by Tower; food penalties apply on weekdays only.
var _food_revision: int = -1  ## Rooms.layout_revision the cached coverage is for.
var _food_coverage: int = -1
var _food_offices: int = 0


## Wires the reasons to the tower's parts and registers noise as a grade modifier. Tower calls
## it from _init, after its members exist.
func attach(grades: GradesScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, rent: RentScript) -> void:
	_grades = grades
	_rooms = rooms
	_grid = grid
	_people = people
	_rent = rent
	grades.add_modifier(noise_stress)
	grades.add_modifier(food_stress)


## Extra stress for a room from noise (the Grades modifier).
func noise_stress(room: int) -> int:
	return NoiseScript.stress_for(NoiseScript.noise_at(_grid, _rooms, room))


## Extra stress for an office from a lunch shortfall (the Grades modifier). Zero for other rooms.
func food_stress(room: int) -> int:
	if _rooms.kind_of(room) != "office" or not _food_applies():
		return 0
	if _food_coverage < FOOD_VERY_LOW_PERCENT:
		return FOOD_VERY_LOW_STRESS
	if _food_coverage < FOOD_LOW_PERCENT:
		return FOOD_LOW_STRESS
	return 0


## True on a weekday in a tower with enough offices (refreshes the cached coverage when the layout changed).
func _food_applies() -> bool:
	if clock != null and clock.day_of_week() == ClockScript.WE:
		return false
	if _food_revision != _rooms.layout_revision:
		_food_revision = _rooms.layout_revision
		_food_coverage = CommerceScript.lunch_coverage(_rooms)
		_food_offices = 0
		for id in _rooms.room_ids():
			if _rooms.kind_of(id) == "office":
				_food_offices += 1
	return _food_offices >= FOOD_NEEDED_FROM


## True if the reason applies to the room right now.
func has_reason(room: int, reason: int) -> bool:
	if not GradesScript.is_graded(_rooms.kind_of(room)):
		return false
	match reason:
		NOISE:
			return NoiseScript.noise_at(_grid, _rooms, room) >= NOISE_FROM
		DISTANCE:
			return _grades.average_stress(_rooms, _people, room) >= DISTANCE_FROM
		RENT:
			return _rent.stress_offset(_rooms, room) > 0
		UNREACHED:
			return hotel != null and hotel.unreached(room)
		NO_GROCERY:
			return CatalogueScript.is_condo(_rooms.kind_of(room)) and lacks_grocery()
		NO_FOOD:
			return _rooms.kind_of(room) == "office" and _food_applies() and _food_coverage < FOOD_LOW_PERCENT
	return false


## True when the tower has enough condos to want a grocery store and has none.
func lacks_grocery() -> bool:
	var condos := 0
	for id in _rooms.room_ids():
		var kind := _rooms.kind_of(id)
		if kind == "grocery":
			return false
		if CatalogueScript.is_condo(kind):
			condos += 1
	return condos >= GROCERY_NEEDED_FROM


## Every reason that applies, most important first. Empty for a content or ungraded room.
func reasons(room: int) -> Array[int]:
	var found: Array[int] = []
	for reason in PRIORITY:
		if has_reason(room, reason):
			found.append(reason)
	return found


## The main reason, or NONE.
func reason(room: int) -> int:
	var found := reasons(room)
	return NONE if found.is_empty() else found[0]


## Short label for a reason, in this game's own words (the room window may use richer text).
static func label(reason: int) -> String:
	match reason:
		NOISE:
			return "Noisy neighbours"
		DISTANCE:
			return "Too far from the lobby or lifts"
		RENT:
			return "Rent too high"
		UNREACHED:
			return "Guests could not reach the room"
		NO_GROCERY:
			return "No grocery store in the tower"
		NO_FOOD:
			return "Nowhere to eat lunch"
	return ""
