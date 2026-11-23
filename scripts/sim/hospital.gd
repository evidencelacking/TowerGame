class_name Hospital
extends RefCounted
## The hospital's daily income (#377, our own design, every number an unverified tunable). An optional chain of four
## rooms (emergency room, operating room, imaging, patient ward; room_catalogue.gd) for prestige and money: it never
## gates a star. Stateless and integer only: nothing is saved, and it draws no random numbers.
##
## Each new day, if a working emergency room stands (not burned out, not cut off), patients are admitted in the fixed
## order tower people first, then outsiders, up to ER_PLACES per emergency room:
##   tower patients    people whose mood is below PATIENT_MOOD_BELOW (a fire, a threat or a bad room lowers it).
##   outside patients  OUTSIDE_PER_ER arrive through the lobby for each emergency room, plus HELIPAD_EXTRA while a
##                     reachable helicopter pad stands. They are abstract: not people, so not in the population.
## Each admitted patient pays ER_FEE. SURGERY_PERCENT of them need surgery, up to OPERATING_PLACES per working
## operating room, each paying SURGERY_FEE; SCAN_PERCENT need a scan, up to IMAGING_PLACES per working imaging room,
## each paying SCAN_FEE; each surgery patient takes a bed, up to WARD_BEDS per working ward, paying STAY_FEE. A room whose
## needs fail (Rooms.service_degraded) serves nobody. The income is one ledger line against the first emergency room.
## An emergency room also counts as a medical center toward the medical demand (demands.gd).

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")

const ER := "emergency_room"
const OPERATING := "operating_room"
const IMAGING := "imaging"
const WARD := "patient_ward"

const PATIENT_MOOD_BELOW := 40  ## A person this unhappy turns up at the emergency room.
const ER_PLACES := 8  ## Patients one emergency room admits a day.
const OUTSIDE_PER_ER := 3  ## Outside patients a day through the lobby, per emergency room.
const HELIPAD_EXTRA := 3  ## More a day while a reachable helicopter pad stands.
const SURGERY_PERCENT := 25
const SCAN_PERCENT := 50
const OPERATING_PLACES := 2  ## Operations a day per operating room.
const IMAGING_PLACES := 6  ## Scans a day per imaging room.
const WARD_BEDS := 4  ## Stays a day per ward.
const ER_FEE := 1500
const SURGERY_FEE := 8000
const SCAN_FEE := 800
const STAY_FEE := 3000


## Ids of the working rooms of a hospital kind: placed, not burned out, not cut off, needs met. Ascending.
static func working(rooms: RoomsScript, grid: GridScript, kind: String) -> Array[int]:
	var found: Array[int] = []
	for id in rooms.room_ids():
		if rooms.kind_of(id) == kind and not rooms.is_charred(id) and not rooms.is_cut_off(id) and not rooms.service_degraded(grid, id):
			found.append(id)
	return found


## People who would turn up at the emergency room today: those whose mood is below PATIENT_MOOD_BELOW.
static func tower_patients(people: PeopleScript) -> int:
	var n := 0
	for i in people.count():
		if people.mood_of(i) < PATIENT_MOOD_BELOW:
			n += 1
	return n


## Patients admitted today as [from the tower, from outside], for `ers` working emergency rooms.
static func admissions(ers: int, tower: int, helipad: bool) -> Array[int]:
	var places := ers * ER_PLACES
	var inside := mini(tower, places)
	var outside := mini(ers * OUTSIDE_PER_ER + (HELIPAD_EXTRA if helipad else 0), places - inside)
	return [inside, outside]


## Dollars one day earns for `admitted` patients with the given counts of working rooms. Pure.
static func day_income(admitted: int, operating: int, imaging: int, wards: int) -> int:
	var surgeries := mini(admitted * SURGERY_PERCENT / 100, operating * OPERATING_PLACES)
	var scans := mini(admitted * SCAN_PERCENT / 100, imaging * IMAGING_PLACES)
	var stays := mini(surgeries, wards * WARD_BEDS)
	return admitted * ER_FEE + surgeries * SURGERY_FEE + scans * SCAN_FEE + stays * STAY_FEE


## Credits one day's income. Returns the dollars credited (0 with no working emergency room).
static func collect(rooms: RoomsScript, grid: GridScript, people: PeopleScript, ledger: LedgerScript, at_tick: int) -> int:
	var ers := working(rooms, grid, ER)
	if ers.is_empty():
		return 0
	var got := admissions(ers.size(), tower_patients(people), rooms.helipad_reachable())
	var amount := day_income(got[0] + got[1], working(rooms, grid, OPERATING).size(), working(rooms, grid, IMAGING).size(), working(rooms, grid, WARD).size())
	ledger.income(at_tick, amount, ers[0])
	return amount
