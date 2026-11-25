class_name Theatre
extends RefCounted
## The movie theatre (#500, our own design; every number here is an UNVERIFIED tunable unless marked ref). Integers only and
## no random draw: an audience is a pure function of the film, its age and the day, so two runs agree.
##
## ref (owner, #324/#500): two floors tall, permanent, three shows a day, a film chosen on the room window with a one-time
## licence, six original genre films, films fade after their run, about 60% outside viewers counted apart, $10 a ticket,
## shops within 5 floors get +20% customers in the hour after a show.
##
## A theatre with no film holds no shows. Each show seats SEATS; the fill is the film's draw (percent), plus WEEKEND_BONUS
## points on the weekend day (WE), capped at 100, then cut by the film's fade. A film is FADE_STEP percent weaker for each
## game week (a quarter: WD1, WD2, WE, Clock.DAYS_PER_QUARTER days) it has run past its run days, up to nothing. Choosing a
## film starts its age at 0; choosing the film already showing is refused and costs nothing.
##
## The audience: OUTSIDE_PERCENT of it comes from the street (visitors: never counted in the population, the stars or
## Commerce's visitors), the rest from the people inside the tower, never more than are inside. Tickets are paid at the
## start of each show on the SHOP ledger line ("Shop sales"). The film licence is a COST line ("Running costs"). A theatre
## that is cut off from the lobby, burned out or closed by a pipe earns nothing and boosts nothing. Not modelled: the
## audience walking in at the top and out at the bottom (ref).
##
## Saved: the last minute swept, then per theatre with a film: room id, film id, age in days.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const KIND := "movie_theatre"
const NO_FILM := 0
## The six films (original, made up): "id" is 1-based and saved; "licence" is the one-time cost in dollars; "draw" is the
## percent of the seats it fills on an ordinary day; "run" is the days before it starts to fade.
const FILMS: Array[Dictionary] = [
	{"id": 1, "name": "Skyline Heist", "genre": "Caper (new release)", "licence": 60000, "draw": 90, "run": 12},
	{"id": 2, "name": "Clockwork Hearts", "genre": "Romance", "licence": 40000, "draw": 80, "run": 18},
	{"id": 3, "name": "The Lantern Crew", "genre": "Family adventure", "licence": 30000, "draw": 75, "run": 24},
	{"id": 4, "name": "Nine Rooms Down", "genre": "Horror", "licence": 22000, "draw": 70, "run": 15},
	{"id": 5, "name": "Dust Over Kestrel Ridge", "genre": "Western", "licence": 12000, "draw": 60, "run": 36},
	{"id": 6, "name": "Moonlit Waltz", "genre": "Classic drama (cheap, steady)", "licence": 5000, "draw": 50, "run": 120},
]

const SHOW_STARTS: Array[int] = [750, 930, 1170]  ## ref: 12:30, 15:30, 19:30.
const SHOW_MINUTES := 120  ## How long a show runs; the shops' hour starts when it ends. Tunable.
const BOOST_MINUTES := 60  ## ref: the hour after a show.
const BOOST_PERCENT := 20  ## ref: shops within BOOST_FLOORS get this many percent more customers.
const BOOST_FLOORS := 5  ## ref: above and below, counted from the theatre's nearest floor.
const SEATS := 128  ## ref.
const TICKET := 10  ## ref: dollars a seat.
const OUTSIDE_PERCENT := 60  ## ref: about 60% of the audience comes from the street.
const WEEKEND_BONUS := 15  ## ref: percentage points added to the fill at the weekend.
const FADE_STEP := 10  ## ref: percent lost per game week past the run.

const OK := 0
const NOT_A_THEATRE := 1
const UNKNOWN_FILM := 2
const ALREADY_SHOWING := 3
const SHORT_OF_FUNDS := 4

var _film: Dictionary = {}  ## Room id -> film id (absent: no film).
var _age: Dictionary = {}  ## Room id -> days since the film was chosen.
var _last_minute: int = -1
## Today's audience by origin, for the view and tests: derived, not saved or hashed, and reset each morning. Outside viewers
## are counted here and nowhere else (never in population, the stars or Commerce.visitors_today).
var outside_today: int = 0
var tower_today: int = 0


## The save's ints at rest (the migration step, v50 to v51).
static func rest_ints() -> Array[int]:
	return [-1, 0] as Array[int]


## The film row for an id, or an empty dictionary for none or an unknown id.
static func film(film_id: int) -> Dictionary:
	if film_id < 1 or film_id > FILMS.size():
		return {}
	return FILMS[film_id - 1]


func film_of(room: int) -> int:
	return int(_film.get(room, NO_FILM))


func age_of(room: int) -> int:
	return int(_age.get(room, 0))


## Percent of its crowd a film has lost at an age in days: FADE_STEP for each started game week past its run, to 100.
static func fade_percent(film_id: int, age: int) -> int:
	var row := film(film_id)
	if row.is_empty():
		return 100
	var past := age - int(row["run"])
	if past <= 0:
		return 0
	return mini(100, FADE_STEP * ((past + ClockScript.DAYS_PER_QUARTER - 1) / ClockScript.DAYS_PER_QUARTER))


## Percent of the seats a show fills (0 to 100) for a film of an age on a day of the quarter.
static func fill_percent(film_id: int, age: int, day: int) -> int:
	var row := film(film_id)
	if row.is_empty():
		return 0
	var base := mini(100, int(row["draw"]) + (WEEKEND_BONUS if day == ClockScript.WE else 0))
	return base * (100 - fade_percent(film_id, age)) / 100


## Seats filled at a show.
static func audience(film_id: int, age: int, day: int) -> int:
	return SEATS * fill_percent(film_id, age, day) / 100


## How many of an audience come from outside the tower.
static func outside_part(total: int) -> int:
	return total * OUTSIDE_PERCENT / 100


## Chooses (or changes) a theatre's film, charging its licence once. Refused with nothing changed for a room that is not a
## theatre, an unknown film, the film already showing, or a licence the balance cannot meet.
func choose(rooms: RoomsScript, ledger: LedgerScript, at_tick: int, room: int, film_id: int) -> int:
	if rooms.kind_of(room) != KIND:
		return NOT_A_THEATRE
	var row := film(film_id)
	if row.is_empty():
		return UNKNOWN_FILM
	if film_of(room) == film_id:
		return ALREADY_SHOWING
	var licence: int = row["licence"]
	if licence > ledger.balance:
		return SHORT_OF_FUNDS
	ledger.running_cost(at_tick, licence, room)
	_film[room] = film_id
	_age[room] = 0
	return OK


## Forgets a room that was bulldozed or replaced.
func remove_room(room: int) -> void:
	_film.erase(room)
	_age.erase(room)


## True when the theatre can take an audience now: reached from the lobby, not burned out and not closed by a burst pipe.
func is_open(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, room: int) -> bool:
	if rooms.is_charred(room) or rooms.is_cut_off(room) or rooms.wet.has(room) or not grid.has_occupant(room):
		return false
	return tenancy.routed(floors, rooms, grid, room, floors.lobby_span()[0])


## The ids of the placed theatres, in room id order.
func _theatres(rooms: RoomsScript, grid: GridScript) -> Array[int]:
	var out: Array[int] = []
	for id in rooms.room_ids():
		if rooms.kind_of(id) == KIND and grid.has_occupant(id):
			out.append(id)
	return out


## Per-tick step: ages films at each new day and holds each show as the clock passes its start.
func tick(clock: ClockScript, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, ledger: LedgerScript, at_tick: int) -> void:
	if clock.day_started:
		outside_today = 0
		tower_today = 0
		for room: int in _film.keys():
			_age[room] = age_of(room) + 1
	if _film.is_empty():
		_last_minute = -1  # nothing to sweep: a tower with no film keeps the saved state at rest
		return
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	var prev := minute if _last_minute < 0 else (_last_minute if minute > _last_minute else -1)
	_last_minute = minute
	if not floors.has_lobby():
		return
	for start in SHOW_STARTS:
		if prev < start and start <= minute:
			_show(clock.day_of_week(), floors, rooms, grid, people, tenancy, ledger, at_tick)


func _show(day: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, ledger: LedgerScript, at_tick: int) -> void:
	var inside := -1  # people inside the tower, counted once and only if a show is held
	for room in _theatres(rooms, grid):
		var film_id := film_of(room)
		if film_id == NO_FILM or not is_open(floors, rooms, grid, tenancy, room):
			continue
		var total := audience(film_id, age_of(room), day)
		if total <= 0:
			continue
		if inside < 0:
			inside = _people_inside(people)
		var outside := outside_part(total)
		var from_tower := mini(total - outside, inside)
		outside_today += outside
		tower_today += from_tower
		ledger.shop_sales(at_tick, (outside + from_tower) * TICKET, room)


static func _people_inside(people: PeopleScript) -> int:
	var count := 0
	for i in people.count():
		if people.location_of(i) != PeopleScript.NONE or people.trip_state(i) != PeopleScript.TRIP_IDLE:
			count += 1
	return count


## The floors, as pairs (lower, upper), of every open theatre whose show ended within the last BOOST_MINUTES at this minute
## of the day, so its neighbours' shops are busier. Empty when none (the usual case) or when the minute is in no show's hour.
func boost_floors(minute: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, day: int) -> Array[int]:
	var out: Array[int] = []
	if _film.is_empty():
		return out
	var in_hour := false
	for start in SHOW_STARTS:
		var ended := start + SHOW_MINUTES
		if minute >= ended and minute < ended + BOOST_MINUTES:
			in_hour = true
	if not in_hour:
		return out
	for room in _theatres(rooms, grid):
		var film_id := film_of(room)
		if film_id == NO_FILM or audience(film_id, age_of(room), day) <= 0 or not is_open(floors, rooms, grid, tenancy, room):
			continue
		var run := grid.run_of(room)
		out.append(run[0])
		out.append(RoomsScript.floor_above(run[0]))
	return out


## True when a shop floor is within BOOST_FLOORS of one of the theatre floor pairs from boost_floors.
static func near(shop_floor: int, theatre_floors: Array[int]) -> bool:
	for k in range(0, theatre_floors.size(), 2):
		if absi(_level(shop_floor) - _level(theatre_floors[k])) <= BOOST_FLOORS or absi(_level(shop_floor) - _level(theatre_floors[k + 1])) <= BOOST_FLOORS:
			return true
	return false


## A floor's place on a line with no floor 0: the ground floor is 1 and the first basement 0.
static func _level(floor_number: int) -> int:
	return floor_number if floor_number > 0 else floor_number + 1


func state_ints() -> Array[int]:
	var rooms_with: Array = _film.keys()
	rooms_with.sort()
	var ints: Array[int] = [_last_minute, rooms_with.size()]
	for room: int in rooms_with:
		ints.append_array([room, film_of(room), age_of(room)] as Array[int])
	return ints


## What the state hash takes: nothing while no theatre has a film, so a tower without one hashes as before.
func hash_ints() -> Array[int]:
	if _film.is_empty():
		return [] as Array[int]
	return state_ints()


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 2:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints[0] < -1 or ints[0] >= ClockScript.MINUTES_PER_DAY or ints[1] < 0 or ints.size() != 2 + 3 * ints[1]:
		return false
	for k in range(2, ints.size(), 3):
		if ints[k] < 0 or ints[k + 1] < 1 or ints[k + 1] > FILMS.size() or ints[k + 2] < 0:
			return false
	return true


func load_ints(ints: Array) -> void:
	_last_minute = ints[0]
	_film.clear()
	_age.clear()
	for k in range(2, ints.size(), 3):
		_film[ints[k]] = ints[k + 1]
		_age[ints[k]] = ints[k + 2]
