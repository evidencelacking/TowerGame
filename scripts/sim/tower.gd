class_name Tower
extends RefCounted
## The tower simulation state. Integers only; see CLAUDE.md.
##
## 1 tick = 1 frame. step() is the only thing that advances time. Input reaches the state
## only as Commands: queue them with enqueue(), and step() applies those due at the new
## tick, in queue order, at one fixed point (see step). Everything random comes from rng.

const Rng := preload("res://scripts/sim/sim_rng.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Grid := preload("res://scripts/sim/grid.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const SynergyScript := preload("res://scripts/sim/synergy.gd")
const FinanceScript := preload("res://scripts/sim/finance.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const ApartmentsScript := preload("res://scripts/sim/apartments.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const WordOfMouthScript := preload("res://scripts/sim/word_of_mouth.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const NamesScript := preload("res://scripts/sim/names.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const EvaluationScript := preload("res://scripts/sim/evaluation.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const RunningCostsScript := preload("res://scripts/sim/running_costs.gd")
const ComplaintsScript := preload("res://scripts/sim/complaints.gd")
const CommerceScript := preload("res://scripts/sim/commerce.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const PestsScript := preload("res://scripts/sim/pests.gd")
const HousekeepingScript := preload("res://scripts/sim/housekeeping.gd")
const RecyclingScript := preload("res://scripts/sim/recycling.gd")
const VipScript := preload("res://scripts/sim/vip.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const EventsScript := preload("res://scripts/sim/events.gd")
const FireScript := preload("res://scripts/sim/fire.gd")
const HelipadScript := preload("res://scripts/sim/helipad.gd")
const HospitalScript := preload("res://scripts/sim/hospital.gd")
const ThreatScript := preload("res://scripts/sim/threat.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const LifeScript := preload("res://scripts/sim/life.gd")
const WeatherScript := preload("res://scripts/sim/weather.gd")
const PipeScript := preload("res://scripts/sim/pipe.gd")
const StallScript := preload("res://scripts/sim/stall.gd")
const FestivalScript := preload("res://scripts/sim/festival.gd")
const SaveMigrationScript := preload("res://scripts/sim/save_migration.gd")

## The only way input changes the simulation. Queued for a tick and applied at one fixed
## point in that tick (see step). Integers only, so it saves and hashes exactly.
class Command:
	extends RefCounted
	## Command kinds. Add new kinds on their own line; Tower._apply_command handles each.
	const NOTE := 1  ## Foundation placeholder: adds args[0] to Tower.notes.
	const ROLL := 2  ## Foundation placeholder: adds a random draw below args[0] to Tower.notes.
	const PLACE := 3  ## Places an occupant on the grid: args are id, floor, column, length.
	const REMOVE := 4  ## Removes an occupant from the grid: args[0] is its id.
	const PURCHASE := 5  ## Spends money: args are cost, ref (room id). Refused if short.
	const REFUND := 6  ## Returns money: args are amount, ref. Always applies.
	const BUILD_FLOOR := 7  ## Builds a floor span: args are floor, x_start, x_end (inclusive).
	const BUILD_LOBBY := 8  ## Builds the ground lobby: args are floor (must be 1), x_start, x_end, height (1 to 3).
	const PLACE_ROOM := 9  ## Places a room: args are room_kind (index in RoomCatalogue.IDS), floor, x_left.
	const REPLACE_ROOM := 12  ## Bulldozes the room covering (floor, x_left) and places a room there, atomically: args are room_kind, floor, x_left. See Rooms.replace_room.
	const BULLDOZE := 10  ## Removes the room covering a cell, free: args are floor, x. See Rooms.bulldoze.
	const PLACE_STAIRS := 11  ## Places stairs between two floors: args are lower floor, x_left. See Rooms.place_stairs.
	const PLACE_SHAFT := 13  ## Places an elevator shaft: args are room_kind (index in RoomCatalogue.IDS), bottom floor, top floor, x_left. See Rooms.place_shaft.
	const RESIZE_SHAFT := 14  ## Grows or shrinks a shaft in place: args are shaft id, new bottom, new top. See Rooms.resize_shaft.
	const ADD_CAR := 16  ## Adds an elevator car: args are shaft id, home floor. See Rooms.add_car.
	const REMOVE_CAR := 17  ## Removes a shaft's newest car: args are shaft id. See Rooms.remove_car.
	const SET_RENT := 19  ## Sets a room's rent level: args are room id, level (0 lowest to 3 highest). See Rent.set_rent.
	const SET_RENT_MANY := 22  ## Bulk rent (#28): args are level, then room ids. Applies Rent.set_rent to each id in ascending order, as that many SET_RENT commands would; condos and non-rentable rooms are skipped and counted in last_bulk_rent.
	const RENAME_PERSON := 40  ## Renames a person: args are person id, then the new name as code points (none restores the generated name). See PersonNames.
	const PLACE_ESCALATOR := 18  ## Places an escalator between two floors: args are lower floor, x_left. See Rooms.place_escalator.
	const DEBUG_UNLOCK_ALL := 90  ## Debug only: args[0] 1 unlocks every room kind, 0 restores star gating. See Tower.unlock_all.
	const DEBUG_SET_STARS := 91  ## Debug only (demo mode, #262): args[0] raises the star rating to 1..5. Never lowers it.
	const SET_CAR_HOME := 20  ## Moves a car's home floor: args are shaft id, the car's place among the shaft's cars (0 oldest), floor. See Rooms.set_car_home.
	const SET_SCHEDULE := 21  ## Sets one shaft schedule slot: args are shaft id, slot (0 to 5: weekday then weekend, 3 periods each), mode (0 normal, 1 express to top, 2 to bottom), response distance, departure wait in seconds. See Rooms.set_schedule.
	const CHOOSE_EVENT := 50  ## Answers an open event: args are event id, choice (0 declines). See Events.choose.
	const REPAIR_ROOM := 51  ## Repairs the burned-out room covering a cell: args are floor, x. Costs Fire.repair_cost. See Tower.repair_room.
	const SET_SHAFT_STOP := 15  ## Turns a shaft's stop on a floor on or off: args are shaft id, floor, on (1 or 0). See Rooms.set_shaft_stop.

	var tick: int = 0  ## The tick this command applies at.
	var kind: int = 0
	var args: Array[int] = []

	static func make(for_tick: int, command_kind: int, command_args: Array[int] = []) -> Command:
		var command := Command.new()
		command.tick = for_tick
		command.kind = command_kind
		command.args = command_args.duplicate()
		return command


const SAVE_VERSION := 49  ## Every bump needs a step in save_migration.gd (a test enforces it).
const START_STARS := 1  ## A new tower starts at 1 star (docs/gameplay-reference.md). The one source of truth; views read Tower.stars.
const HASH_OFFSET := -3750763034362895579  # FNV-1a 64-bit offset basis, as signed
const HASH_PRIME := 1099511628211

## Slow cadence (#459): state that changes slowly is checked every SLOW_EVERY ticks, not every tick. Each system has its
## own offset so the costs land on different ticks. Anything that moves people or cars still runs every tick.
const SLOW_EVERY := 10
const TENANCY_AT := 1  ## tenancy.tick: leasing and condo sales (once per sim minute inside).
const HOTEL_AT := 2  ## hotel.tick: bookings, check-in, check-out (windows tolerate the gap, see Hotel).
const MOOD_AT := 3  ## mood.note_event while a fire or threat burns (also once when one starts).
const VIP_AT := 4  ## vip.tick.
const PESTS_AT := 5  ## pests.tick: once a day.
const HOUSEKEEPING_AT := 6  ## housekeeping.tick: counts the minutes since its last run.
const RECYCLING_AT := 7  ## recycling.tick and the population it reads: once an hour.
const EVENTS_AT := 8  ## festival.tick's search for a place to open its card (#474).

var tick: int = 0
var rng := Rng.new()
var clock := Clock.new()
var grid := Grid.new()
var ledger := LedgerScript.new()
var floors := FloorsScript.new()
var rooms := RoomsScript.new()
## Refusals and notable events, for the message log (see Messages).
var messages := MessagesScript.new()
## The people: home, work, day plan, trip and stress (see People).
var people := PeopleScript.new()
## Person names: generated from the seed and id (not saved) plus the player's renames (saved). See PersonNames.
var names := NamesScript.new()
## Office tenancy: moves workers in (see Tenancy). Derived from people, so not saved.
var tenancy := TenancyScript.new()
## Rental apartments: residents arrive and leave over the days (#379). Derived from people and rooms, so not saved.
var apartments := ApartmentsScript.new()
## Trip executor: moves people along routes and charges travel stress (see Trips). Not saved.
var trips := TripsScript.new()
## Quality score and A/B/C grade of tenant rooms (see Grades). Saved: who has made a first trip.
var grades := GradesScript.new()
## Rest-period evaluation: A brings a friend, C leaves (see Evaluation). Saved: red-day counts.
var evaluation := EvaluationScript.new()
## Complaints from C rooms lower nearby tenants (see WordOfMouth). Derived from grades, so not saved.
var word_of_mouth := WordOfMouthScript.new()
## Rent level per room and quarterly rent collection (see Rent). Saved: the non-default levels.
var rent := RentScript.new(rooms)
## Hotel guests: check-in, check-out, nightly income, dirty rooms (see Hotel). Saved.
var hotel := HotelScript.new(rooms, rent)
## Pests in long-dirty hotel rooms (see Pests). Saved.
var pests := PestsScript.new(rooms)
## Housekeepers: six per station, they clean dirty hotel rooms (see Housekeeping). Saved.
var housekeeping := HousekeepingScript.new(rooms, hotel)
## Recycling centres: rubbish fills them by day and a truck empties them each morning (see Recycling). Saved.
var recycling := RecyclingScript.new(rooms)
## The VIP visit that gates star 4: one reserved suite, a verdict, a retry after a bad one (see Vip). Saved.
var vip := VipScript.new(rooms, hotel)
var demands := DemandsScript.new()
var events := EventsScript.new()  ## The event scheduler (#214): its own seeded stream, saved with the tower.
## Mood (12.2): the day's event shock, saved; each person's mood lives in People.
var mood := MoodScript.new()
## Life events (12.3): couples, children, promotions and the story log. Saved.
var life := LifeScript.new()
## Treasure, rain and the fly-past (M9 9.5 to 9.7): see Weather. Saved: the rain stream, today's rain, the treasure taken.
var weather := WeatherScript.new()
## Our own events (M9 9.10 to 9.12): a burst pipe, a stalled car and a street festival. Each decides when it happens from its
## own salted stream (never the shared Events one) and opens its card as a manual kind. Saved.
var pipe := PipeScript.new(rooms)
var stall := StallScript.new(rooms)
var festival := FestivalScript.new(rooms)
var threat := ThreatScript.new(rooms)  ## Threats (#218): the notice, the search, the blast. Saved.
var fire := FireScript.new(rooms)  ## Fires (#217): burning rooms, the rescue craft. Saved.
## Why a tenant room is unhappy: noise, distance or rent (see Complaints). Derived, so not saved.
var complaints := ComplaintsScript.new()
## Result of the most recent PURCHASE, BUILD_FLOOR, BUILD_LOBBY, PLACE_ROOM, PLACE_STAIRS, BULLDOZE or REPLACE_ROOM command (OK or a refusal reason; see
## Ledger and Floors for the codes).
var last_refusal: int = 0
## The last SET_RENT_MANY (#28): rooms set, rooms skipped, and the tick it applied at. Not saved or hashed; the view reads it.
var last_bulk_rent: Array[int] = [0, 0, -1]
## Placeholder state that commands change, so tests can see them. Replaced as real state lands.
var notes: int = 0
## The tower's star rating, 1 to 5. Only promote_stars raises it and nothing lowers it. The HUD, toolbar and ghost read it.
var stars: int = START_STARS
## Debug switch (#156): treat every star-gated kind as unlocked. Off in a normal game, set only by
## the DEBUG_UNLOCK_ALL command, hashed while on, and never saved (a loaded tower starts it off).
var unlock_all: bool = false

## Shop customers and daily sales (see Commerce). Saved: today's and yesterday's counts.
var commerce := CommerceScript.new()

var _queue: Array[Command] = []
var _parking_working: int = 0  ## Working parking spaces, found at most once a tick (derived, not saved).
var _reach_sig: int = -1  ## What refresh_reach last saw (derived, not saved).
var _parking_at: int = -1  ## The tick _parking_working was found at.


func _init(seed_value: int = 0, starting_funds: int = LedgerScript.DEFAULT_STARTING_FUNDS) -> void:
	rng.reseed(seed_value)
	names.name_seed = seed_value
	events.reseed(seed_value)
	fire.reseed(seed_value)
	vip.reseed(seed_value)
	threat.reseed(seed_value)
	weather.reseed(seed_value)
	pipe.reseed(seed_value)
	stall.reseed(seed_value)
	festival.reseed(seed_value)
	commerce.weather = weather
	commerce.festival = festival
	events.kinds = [fire.kind(), threat.kind(), vip.kind(), pipe.kind(), stall.kind(), festival.kind()] as Array[Dictionary]  # the VIP, pipe, stall and festival cards are manual: never rolled, so they shift no draw
	ledger = LedgerScript.new(starting_funds)
	rooms.floors = floors
	word_of_mouth.attach(grades, rooms, grid, people)
	grades.add_modifier(rent.grade_modifier)
	complaints.attach(grades, rooms, grid, people, rent)
	complaints.hotel = hotel
	complaints.clock = clock
	hotel.pests = pests
	hotel.reserved_room = vip.reserved_suite
	hotel.working_spaces = _parking_spaces
	people.guest_home = hotel.is_hotel


## Queues a command for a future tick. Returns false (and queues nothing) if that tick has
## already happened or is the current one: a command must apply at its own tick.
func enqueue(command: Command) -> bool:
	if command.tick <= tick:
		return false
	_queue.append(command)
	return true


## Advances one tick. The order is fixed:
##   1. the tick counter increments
##   2. commands due at this tick apply, in queue order
##   3. systems run (clock #2, grid #3 and later systems hook in here, in a fixed order)
## People in the tower right now (derived from people, not saved).
func population() -> int:
	return people.in_tower_count() + commerce.visitors_inside(clock.minute_of_day())


## The permanent population (#456): everyone registered with the tower (residents, workers and hotel guests, each once),
## with no outside visitors. It changes only when people move in or out, not as they come and go through the day.
## The star rules, the goals panel and the save slots read it; population() (inside this minute) feeds recycling,
## threat and sound.
func permanent_population() -> int:
	return people.count()


## Population by group, for the top bar (#383). "now" is people in the tower this minute (its total is
## population(), what the star rules use); "overall" is everyone who uses the building in a day: each
## registered person once (a hotel guest, else a worker, else a resident) plus outside visitors served today.
## Derived from people, rooms and commerce; only the visitors-today counter is saved.
func population_breakdown() -> Dictionary:
	var now := {"residents": 0, "workers": 0, "guests": 0, "visitors": commerce.visitors_inside(clock.minute_of_day())}
	var overall := {"residents": 0, "workers": 0, "guests": 0, "visitors": commerce.visitors_today()}
	for i in people.count():
		var home := people.home_of(i)
		var group := "residents"
		if home != PeopleScript.NONE and rooms.has_room(home) and HotelScript.is_hotel_kind(rooms.kind_of(home)):
			group = "guests"
		elif people.work_of(i) != PeopleScript.NONE:
			group = "workers"
		overall[group] = int(overall[group]) + 1
		if people.location_of(i) != PeopleScript.NONE or people.trip_state(i) != PeopleScript.TRIP_IDLE:
			now[group] = int(now[group]) + 1
	var total_now := 0
	var total_overall := 0
	for group: String in now:
		total_now += int(now[group])
		total_overall += int(overall[group])
	return {"now": now, "overall": overall, "now_total": total_now, "overall_total": total_overall}


## Removes a room by disaster (fire, #217) and lets go of everything that pointed at it, as a bulldoze does.
func destroy_room(id: int) -> void:
	if rooms.destroy(grid, floors, id):
		people.remove_room(id)
		rent.remove_room(id)
		commerce.remove_room(id)
		hotel.remove_room(id)
		pests.remove_room(id)


## Burns a room out (fire, #373): it stays standing but charred, and everything that pointed at it lets go.
## A sold condo is unsold, so repairing it lets it sell again. Rooms.charred (set by Fire) keeps it empty.
func char_room(id: int) -> void:
	people.remove_room(id)
	rent.remove_room(id)
	commerce.remove_room(id)
	hotel.remove_room(id)
	pests.remove_room(id)
	rooms.set_sold(id, false)
	rooms.cut_off.erase(id)  # a charred room is never marked cut off (refresh_reach skips it), whichever way it got there


## Repairs the charred room covering a cell, paying Fire.repair_cost. Returns OK or a reason code
## (NOTHING_THERE, NOT_CHARRED, SHORT_OF_FUNDS), changing nothing on a refusal.
func repair_room(floor_number: int, x: int) -> int:
	if not Grid.is_valid_floor(floor_number):
		return RoomsScript.BAD_FLOOR
	var id := rooms.room_of(grid.cell_at(floor_number, x))
	if id == 0:
		return RoomsScript.NOTHING_THERE
	if not rooms.is_charred(id):
		return RoomsScript.NOT_CHARRED
	var kind := rooms.kind_of(id)
	var paid := ledger.charge(tick, FireScript.repair_cost(kind), CatalogueScript.IDS.find(kind))
	if paid != LedgerScript.OK:
		return paid
	rooms.charred.erase(id)
	_reach_sig = -1  # a repaired room is checked again
	messages.add(tick, MessagesScript.ROOM_REPAIRED, CatalogueScript.IDS.find(kind), floor_number)
	return RoomsScript.OK


## Marks every room no route from the ground lobby reaches in Rooms.cut_off (#368), reusing Tenancy.reachable. Derived, so
## not saved: it reruns whenever the floors or the room list change (a placement, a bulldoze or a replacement gives a new
## id set), so a new link or a cut link takes effect on the next tick. Charred rooms are left to Rooms.is_charred.
func refresh_reach() -> void:
	var sig := (floors.revision * 1000003 + rooms.route_revision) * 1000003 + rooms.room_ids().size()
	for id in rooms.room_ids():
		sig = (sig * 31 + id) & 0x3fffffffffff
	if sig == _reach_sig:
		return
	_reach_sig = sig
	rooms.cut_off = {}
	if not floors.has_lobby():
		return
	var entry_x := floors.lobby_span()[0]
	var map := RoutesScript.reach_map(floors, rooms, grid, TenancyScript.GROUND_FLOOR, entry_x)  # one search for every room (#415)
	for id in rooms.room_ids():
		if RoomsScript.needs_route(rooms.kind_of(id)) and not rooms.is_charred(id):
			var run := grid.run_of(id)
			if run.is_empty() or not RoutesScript.map_reaches(floors, map, run[0], run[1]):
				rooms.cut_off[id] = true


## Working parking spaces now, searched once per tick however many suites ask.
func _parking_spaces() -> int:
	if _parking_at != tick:
		_parking_working = Parking.working_spaces(rooms, grid)
		_parking_at = tick
	return _parking_working


func step() -> void:
	tick += 1
	_apply_due_commands()
	_run_systems()


func _apply_due_commands() -> void:
	var remaining: Array[Command] = []
	for command in _queue:
		if command.tick == tick:
			_apply_command(command)
		else:
			remaining.append(command)
	_queue = remaining


func _apply_command(command: Command) -> void:
	match command.kind:
		Command.NOTE:
			notes += command.args[0]
		Command.ROLL:
			notes += rng.next_below(command.args[0])
		Command.PLACE:
			if command.args.size() == 4:
				grid.place(command.args[0], command.args[1], command.args[2], command.args[3])
		Command.REMOVE:
			if command.args.size() == 1:
				grid.remove(command.args[0])
		Command.PURCHASE:
			if command.args.size() == 2:
				last_refusal = ledger.charge(tick, command.args[0], command.args[1])
				_note_refusal(MessagesScript.PURCHASE_REFUSED, command.args[1])
		Command.REFUND:
			if command.args.size() == 2:
				ledger.refund(tick, command.args[0], command.args[1])
		Command.BUILD_FLOOR:
			if command.args.size() == 3:
				last_refusal = floors.build_span(ledger, tick, command.args[0], command.args[1], command.args[2])
				if not _note_refusal(MessagesScript.FLOOR_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.FLOOR_BUILT, command.args[0])
		Command.BUILD_LOBBY:
			if command.args.size() == 4:
				last_refusal = floors.build_lobby(ledger, tick, command.args[0], command.args[1], command.args[2], command.args[3], grid)
				if not _note_refusal(MessagesScript.LOBBY_REFUSED, 0):
					messages.add(tick, MessagesScript.LOBBY_BUILT, command.args[3])
		Command.PLACE_ROOM:
			if command.args.size() == 3:
				last_refusal = rooms.place_room(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2])
				if not _note_refusal(MessagesScript.ROOM_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_BUILT, command.args[0], command.args[1])
		Command.BULLDOZE:
			if command.args.size() == 2:
				var doomed := rooms.check_bulldoze(grid, floors, command.args[0], command.args[1])
				var doomed_kind := CatalogueScript.IDS.find(rooms.kind_of(doomed["room_id"]))
				last_refusal = rooms.bulldoze(grid, floors, ledger, tick, command.args[0], command.args[1])
				if last_refusal == RoomsScript.OK:
					people.remove_room(doomed["room_id"])
					rent.remove_room(doomed["room_id"])
					commerce.remove_room(doomed["room_id"])
					hotel.remove_room(doomed["room_id"])
					pests.remove_room(doomed["room_id"])
				if not _note_refusal(MessagesScript.BULLDOZE_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_REMOVED, doomed_kind, command.args[0])
					if doomed["refund"] > 0:
						messages.add(tick, MessagesScript.CONDO_REFUND, doomed["refund"])
		Command.REPLACE_ROOM:
			if command.args.size() == 3:
				var replaced := rooms.check_bulldoze(grid, floors, command.args[1], command.args[2])
				last_refusal = rooms.replace_room(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2])
				if last_refusal == RoomsScript.OK:
					people.remove_room(replaced["room_id"])
					rent.remove_room(replaced["room_id"])
					commerce.remove_room(replaced["room_id"])
					hotel.remove_room(replaced["room_id"])
					pests.remove_room(replaced["room_id"])
				if not _note_refusal(MessagesScript.REPLACE_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_REPLACED, command.args[0], command.args[1])
					if replaced["refund"] > 0:
						messages.add(tick, MessagesScript.CONDO_REFUND, replaced["refund"])
		Command.SET_RENT:
			if command.args.size() == 2:
				last_refusal = rent.set_rent(rooms, command.args[0], command.args[1])
				if not _note_refusal(MessagesScript.RENT_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.RENT_SET, command.args[0], command.args[1])
		Command.SET_RENT_MANY:
			if command.args.size() >= 2:
				_set_rent_many(command.args)
		Command.PLACE_STAIRS:
			if command.args.size() == 2:
				last_refusal = rooms.place_stairs(grid, floors, ledger, tick, command.args[0], command.args[1])
				if not _note_refusal(MessagesScript.STAIRS_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.STAIRS_BUILT, command.args[0])
		Command.PLACE_ESCALATOR:
			if command.args.size() == 2:
				last_refusal = rooms.place_escalator(grid, floors, ledger, tick, command.args[0], command.args[1])
				if not _note_refusal(MessagesScript.STAIRS_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ESCALATOR_BUILT, command.args[0])
		Command.PLACE_SHAFT:
			if command.args.size() == 4:
				last_refusal = rooms.place_shaft(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2], command.args[3])
				if not _note_refusal(MessagesScript.ROOM_REFUSED, command.args[0]):
					messages.add(tick, MessagesScript.ROOM_BUILT, command.args[0], command.args[1])
		Command.RESIZE_SHAFT:
			if command.args.size() == 3:
				last_refusal = rooms.resize_shaft(grid, floors, ledger, tick, command.args[0], command.args[1], command.args[2])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.SET_SHAFT_STOP:
			if command.args.size() == 3:
				last_refusal = rooms.set_shaft_stop(command.args[0], command.args[1], command.args[2] != 0)
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.DEBUG_UNLOCK_ALL:
			if command.args.size() == 1:
				unlock_all = command.args[0] != 0
		Command.DEBUG_SET_STARS:
			if command.args.size() == 1:
				stars = maxi(stars, clampi(command.args[0], 1, 5))
		Command.ADD_CAR:
			if command.args.size() == 2:
				last_refusal = rooms.add_car(ledger, tick, unlocked_stars(), command.args[0], command.args[1])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.SET_CAR_HOME:
			if command.args.size() == 3:
				last_refusal = rooms.set_car_home(command.args[0], command.args[1], command.args[2])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.SET_SCHEDULE:
			if command.args.size() == 5:
				last_refusal = rooms.set_schedule(command.args[0], command.args[1], command.args[2], command.args[3], command.args[4])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.REMOVE_CAR:
			if command.args.size() == 1:
				last_refusal = rooms.remove_car(command.args[0])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.CHOOSE_EVENT:
			if command.args.size() == 2:
				var cost := events.cost_of(command.args[0], command.args[1])
				if cost > ledger.balance:  # cannot afford it: the event stays open
					last_refusal = LedgerScript.SHORT_OF_FUNDS
					_note_refusal(MessagesScript.PURCHASE_REFUSED, command.args[0])
				elif events.choose(command.args[0], command.args[1], tick) and cost > 0:
					ledger.charge(tick, cost, command.args[0])
		Command.REPAIR_ROOM:
			if command.args.size() == 2:
				last_refusal = repair_room(command.args[0], command.args[1])
				_note_refusal(MessagesScript.ROOM_REFUSED, command.args[0])
		Command.RENAME_PERSON:
			if command.args.size() >= 1 and people.index_of(command.args[0]) != -1:
				names.apply_args(command.args)
		_:
			push_error("Unknown sim command kind %d" % command.kind)
	_dig_treasure()


## The tower's buried treasure spot: x is the column, y the floor (B3 to B8). A pure function of the tower seed.
func treasure_spot() -> Vector2i:
	return WeatherScript.spot_for(names.name_seed)


## Pays the treasure once, when a floor unit stands over its spot (checked after every command, so a floor, a room
## or a shaft that digs there all find it). Never again in this tower (#220).
func _dig_treasure() -> void:
	var spot := treasure_spot()
	if weather.treasure_due(spot, floors):
		weather.treasure_found = true
		ledger.windfall(tick, WeatherScript.TREASURE_PAYS, spot.y)
		messages.add(tick, MessagesScript.TREASURE_FOUND, spot.y, WeatherScript.TREASURE_PAYS)


## SET_RENT_MANY (#28): the same as one SET_RENT per id, ascending, each id once. A room that cannot take
## a rent level (condo, not rentable, gone) is skipped and counted; it logs nothing. The #36 reset stays per room.
func _set_rent_many(args: Array[int]) -> void:
	var ids: Array[int] = args.slice(1)
	ids.sort()
	var done := 0
	var skipped := 0
	var previous := -1
	for id in ids:
		if id == previous:
			continue
		previous = id
		if rent.set_rent(rooms, id, args[0]) == RentScript.OK:
			messages.add(tick, MessagesScript.RENT_SET, id, args[0])
			done += 1
		else:
			skipped += 1
	last_bulk_rent = [done, skipped, tick]


## Logs the refusal in last_refusal, if it is one. Returns true if it was.
func _note_refusal(code: int, detail: int) -> bool:
	if last_refusal == 0:
		return false
	messages.add(tick, code, last_refusal, detail)
	return true


## Per-tick systems, in a fixed order: the clock first, then (later) the grid and the rest.
func _run_systems() -> void:
	clock.advance()
	weather.tick(clock)
	if WeatherScript.flypast_opens(clock):
		messages.add(tick, MessagesScript.FLYPAST)
	pipe.tick(clock, stars, grid, events, messages, tick)
	stall.tick(clock, stars, people, events, messages, tick)
	festival.tick(clock, stars, people, events, messages, tick, _slow_due(EVENTS_AT))
	refresh_reach()
	if _slow_due(TENANCY_AT):
		tenancy.tick(clock, floors, rooms, grid, people, rng, ledger, tick)
	commerce.tick(clock, floors, rooms, grid, people, tenancy, rng, ledger, messages, tick, life)
	if _slow_due(VIP_AT):
		vip.tick(clock, stars, people, grades, messages, events, ledger, grid, tick)
	if _slow_due(HOTEL_AT):
		hotel.tick(clock, floors, people, rng, ledger, messages, tick)
	if _slow_due(PESTS_AT):
		pests.tick(hotel, grid, rng, messages, tick)
	if _slow_due(HOUSEKEEPING_AT):
		housekeeping.tick(clock, floors, grid, SLOW_EVERY)
	if _slow_due(RECYCLING_AT):
		recycling.tick(clock, population())
	if clock.day_started:  # rent comes in daily (#261); the quarter's last day pays the remainder
		rent.collect(rooms, people, ledger, tick, clock.quarter_started, rent_bonus_percent())
		commerce.collect_rent(rooms, rent, ledger, tick, clock.quarter_started)
		HelipadScript.collect(rooms, ledger, tick)  # landing fees while the pad is reachable (#409)
		HospitalScript.collect(rooms, grid, people, ledger, tick)  # patients pay while a working emergency room stands (#377)
	if clock.quarter_started:
		var rent_income := _quarter_rent()
		var running := RunningCostsScript.charge(rooms, floors, ledger, tick)
		if rent_income > 0 or running > 0:
			messages.add(tick, MessagesScript.QUARTER_SETTLED, rent_income, running)
	trips.tick(clock, floors, rooms, grid, people)
	if trips.blocked_transfers > 0:  # a trip that needs a second transfer has no route: warn once a day
		if not messages.recent(MessagesScript.TRIP_UNREACHABLE, tick - TripsScript.WARN_EVERY_TICKS + 1):
			messages.add(tick, MessagesScript.TRIP_UNREACHABLE, trips.blocked_transfers)
		trips.blocked_transfers = 0
	rooms.schedule_slot = RoomsScript.slot_for(clock.day_of_week() == Clock.WE, clock.period())
	CarsScript.tick(rooms)
	trips.collect_arrivals(floors, rooms, grid, people)
	people.tick(clock)
	grades.tick(people)  # every tick, right after the requests are made: it only reads People.trip_requests, so a quiet tick costs nothing
	if clock.ticks_in_period() == 0:  # the only ticks Events rolls (and the threat gate reads it): always fresh, so a load cannot change it
		threat.population = population()
	events.tick(clock, stars, tick)
	fire.tick(clock, events, grid, people, messages, tick)
	threat.tick(events, grid, messages, tick)
	if _slow_due(MOOD_AT) or fire.started or threat.started:  # when an event starts, then refreshed on the cadence (#459)
		if not fire.burning_rooms().is_empty():
			mood.note_event(MoodScript.FIRE_SHOCK, people)
		if threat.is_active():
			mood.note_event(MoodScript.THREAT_SHOCK, people)
	for id in fire.take_burned():
		char_room(id)
	for id in threat.take_destroyed():
		destroy_room(id)
	var eval_step := EvaluationScript.step_due(clock)
	if eval_step >= 0:
		evaluate_step(eval_step)
	if StarRulesScript.is_check_tick(tick):
		promote_stars()


## True on this tick for a slow system with the given offset (see SLOW_EVERY).
func _slow_due(at: int) -> bool:
	return tick % SLOW_EVERY == at


## Rent credited in the quarter that just closed: the ledger's rent lines of the last quarter's ticks.
func _quarter_rent() -> int:
	var from := tick - FinanceScript.ticks_per_quarter()
	var total := 0
	var n := ledger.lines.size() - 1
	while n >= 0 and ledger.lines[n][0] > from:
		if ledger.lines[n][2] == LedgerScript.INCOME:
			total += ledger.lines[n][1]
		n -= 1
	return total


## Percent added to office rent by a connected tower (a linked metro station, #325). Read-only.
func rent_bonus_percent() -> int:
	return SynergyScript.rent_percent(SynergyScript.others_of(grid, rooms, tenancy.transit_linked(floors, rooms, grid)))


## The star rating the build gates use: the real rating, or the top rating while unlock_all is on.
## Views must gate on this, never on stars directly.
func unlocked_stars() -> int:
	return 5 if unlock_all else stars


## What the star rules ask about the tower now (keys as in StarRules.REQUIREMENTS). Read-only.
## Demands and the VIP verdict are real systems now (Demands, Vip).


func star_facts() -> Dictionary:
	var security := 0
	var metro := 0
	var suites := 0
	for id in rooms.room_ids():
		if rooms.is_cut_off(id):
			continue  # a room no route reaches counts for no star (#368)
		if hotel.is_suite(id):
			suites += 1
		match rooms.kind_of(id):
			"security": security += 1
			"metro": metro += 1
	var facts := {
		"population": permanent_population(), "security": security, "suites": suites, "metro": metro,
		"demands_met": demands.all_met(),  # no open demand (transport demands will join them)
		"vip_good": vip.is_good(),
	}
	return facts


## Raises stars to what the tower now earns and logs one message per star gained. Never lowers.
## Runs every StarRules.CHECK_EVERY ticks; public so tests can call it at any tick. The cheap
## population test goes first so the room scan only runs when the next star is within reach.
func promote_stars() -> void:
	demands.update(rooms, stars, messages, tick, Rooms.PLACEABLE, {"parking_working": Parking.working_spaces(rooms, grid), "recycling_short": 1 if recycling.short() else 0, "lunch_coverage": CommerceScript.lunch_coverage(rooms)})
	var people_now := permanent_population()
	while stars < 5 and people_now >= StarRulesScript.population_for(stars + 1):
		if not StarRulesScript.meets(stars + 1, star_facts()):
			break
		stars += 1
		messages.add(tick, MessagesScript.STAR_PROMOTED, stars)
		demands.update(rooms, stars, messages, tick, Rooms.PLACEABLE, {"parking_working": Parking.working_spaces(rooms, grid), "recycling_short": 1 if recycling.short() else 0, "lunch_coverage": CommerceScript.lunch_coverage(rooms)})


## Grades every tenanted office and condo: A brings a friend, C leaves (see Evaluation). Runs once
## a day (Evaluation.EVALUATE_MINUTE); public so tests can call it.
func evaluate_tenants() -> void:
	for k in EvaluationScript.STEPS:
		evaluate_step(k)


## One step of the daily evaluation. _run_systems runs step k on the k-th tick of the evening period (#452), so a
## big tower does not spend one tick on all of them; evaluate_tenants runs them back to back.
func evaluate_step(k: int) -> void:
	match k:
		0:  # fills caches only: the layout-keyed ones the steps after it read
			complaints.warm()
			word_of_mouth.warm()
		1: mood.update(rooms, grid, floors, grades, people)
		2: evaluation.evaluate(rooms, people, grades, grid, floors, tenancy, ledger, messages, rng, tick)
		3: evaluation.evaluate_moods(rooms, people, grades, grid, ledger, messages, tick)
		4: life.daily(self)
		5:
			apartments.daily(self)
			commerce.evaluate(floors, rooms, grid, tenancy, rent, messages, tick)


## A person's mood factors as [reason, change] pairs, worst first, for the view. Read-only.
func mood_factors(i: int) -> Array[Array]:
	return mood.factors(rooms, grid, grades, people, MoodScript.floor_counts(people, grid, floors), i)


## Quality score 0 to 300 of a graded room (office, condo, hotel), or -1. Read-only, for the view.
func quality(room: int) -> int:
	return grades.quality(rooms, people, room)


## GradesScript.GRADE_A, GRADE_B or GRADE_C for a graded room, or GRADE_NONE. Read-only.
func grade(room: int) -> int:
	return grades.grade(rooms, people, room)


## Main complaint reason of a room (ComplaintsScript.NONE, NOISE, DISTANCE or RENT). Read-only.
func complaint_reason(room: int) -> int:
	return complaints.reason(room)


## Every complaint reason that applies to the room, most important first. Read-only.
func complaint_reasons(room: int) -> Array[int]:
	return complaints.reasons(room)


## Rent level 0 to 3 of a room (see Rent). Read-only, for the view.
func rent_level(room: int) -> int:
	return rent.level_of(room)


## Quarterly rent in dollars at the room's level, or 0 if not rentable. Read-only.
func rent_amount(room: int) -> int:
	return rent.rent_of(rooms, room)


## Deterministic 64-bit hash of the whole simulation state, RNG and queue included.
func state_hash() -> int:
	var h := HASH_OFFSET
	for value in _state_ints():
		h = _mix(h, value)
	return h


func _state_ints() -> Array[int]:
	var ints: Array[int] = [tick, rng.state, notes, stars]
	ints.append_array(clock.state_ints())
	ints.append(grid.occupant_count())
	ints.append_array(grid.state_ints())
	ints.append_array(ledger.state_ints())
	ints.append_array(floors.state_ints())
	ints.append_array(rooms.state_ints())
	ints.append_array(messages.state_ints())
	ints.append_array(people.state_ints())
	ints.append_array(grades.state_ints())
	ints.append_array(evaluation.state_ints())
	ints.append_array(names.state_ints())
	ints.append_array(rent.state_ints())
	ints.append_array(commerce.state_ints())
	ints.append_array(hotel.state_ints())
	ints.append_array(pests.state_ints())
	ints.append_array(housekeeping.state_ints())
	ints.append_array(recycling.state_ints())
	ints.append_array(vip.hash_ints())  # the #219 fields only once a notice has been opened
	ints.append_array(demands.state_ints())
	ints.append_array(events.state_ints())
	ints.append_array(fire.state_ints())
	ints.append_array(threat.state_ints())
	ints.append_array(mood.state_ints())
	ints.append_array(life.state_ints())
	ints.append_array(weather.hash_ints())  # empty on a dry day with the treasure unfound, so a quiet tower hashes as before
	ints.append_array(pipe.hash_ints())  # the three own events add nothing while they have never run, so a quiet tower hashes as before
	ints.append_array(stall.hash_ints())
	ints.append_array(festival.hash_ints())
	ints.append(last_refusal)
	if unlock_all:
		ints.append(1)  # Only while on, so a normal game hashes exactly as before.
	ints.append(_queue.size())
	for command in _queue:
		ints.append(command.tick)
		ints.append(command.kind)
		ints.append(command.args.size())
		ints.append_array(command.args)
	return ints


func _mix(h: int, value: int) -> int:
	for byte_index in 8:
		h = (h ^ ((value >> (byte_index * 8)) & 0xFF)) * HASH_PRIME
	return h


## Everything needed to resume the run exactly, including the RNG state.
func save() -> Dictionary:
	var queued: Array = []
	for command in _queue:
		queued.append([command.tick, command.kind, command.args.duplicate()])
	return {"version": SAVE_VERSION, "tick": tick, "rng_state": rng.state, "notes": notes, "stars": stars, "clock": clock.state_ints(), "grid": grid.state_ints(), "ledger": ledger.state_ints(), "floors": floors.state_ints(), "rooms": rooms.state_ints(), "messages": messages.state_ints(), "people": people.state_ints(), "grades": grades.state_ints(), "names": names.state_ints(), "rent": rent.state_ints(), "hotel": hotel.state_ints(), "pests": pests.state_ints(), "commerce": commerce.state_ints(), "housekeeping": housekeeping.state_ints(), "recycling": recycling.state_ints(), "vip": vip.state_ints(), "demands": demands.state_ints(), "events": events.state_ints(), "fire": fire.state_ints(), "threat": threat.state_ints(), "mood": mood.state_ints(), "life": life.state_ints(), "weather": weather.state_ints(), "pipe": pipe.state_ints(), "stall": stall.state_ints(), "festival": festival.state_ints(), "evaluation": evaluation.state_ints(), "last_refusal": last_refusal, "queue": queued}


## Replaces this tower's state with a save() result. Returns false, changing nothing, if
## the data is not a supported save: every part is validated before any field is assigned.
func load_state(data: Dictionary) -> bool:
	if data.get("version", 0) != SAVE_VERSION:
		data = SaveMigrationScript.migrate(data, SAVE_VERSION)  # older saves are upgraded step by step (#395)
		if data.is_empty():
			return false
	_reach_sig = -1  # the loaded rooms are checked afresh
	for key in ["tick", "rng_state", "notes", "last_refusal"]:
		if typeof(data.get(key)) != TYPE_INT:
			return false
	# "stars" is absent in saves from before the sim held it: those load at the start rating.
	var loaded_stars: Variant = data.get("stars", START_STARS)
	if typeof(loaded_stars) != TYPE_INT or loaded_stars < 1 or loaded_stars > 5:
		return false
	var clock_ints: Variant = data.get("clock")
	var grid_ints: Variant = data.get("grid")
	var ledger_ints: Variant = data.get("ledger")
	var floors_ints: Variant = data.get("floors")
	var rooms_ints: Variant = data.get("rooms")
	var messages_ints: Variant = data.get("messages")
	var people_ints: Variant = data.get("people")
	var names_ints: Variant = data.get("names")
	var grades_ints: Variant = data.get("grades")
	var rent_ints: Variant = data.get("rent")
	var hotel_ints: Variant = data.get("hotel")
	var pests_ints: Variant = data.get("pests")
	var housekeeping_ints: Variant = data.get("housekeeping")
	var recycling_ints: Variant = data.get("recycling")
	var vip_ints: Variant = data.get("vip")
	var evaluation_ints: Variant = data.get("evaluation")
	var demands_ints: Variant = data.get("demands")
	var commerce_ints: Variant = data.get("commerce")
	var events_ints: Variant = data.get("events")
	var fire_ints: Variant = data.get("fire")
	var threat_ints: Variant = data.get("threat")
	var mood_ints: Variant = data.get("mood")
	var life_ints: Variant = data.get("life")
	var weather_ints: Variant = data.get("weather")
	var pipe_ints: Variant = data.get("pipe")
	var stall_ints: Variant = data.get("stall")
	var festival_ints: Variant = data.get("festival")
	var queue_data: Variant = data.get("queue")
	if not (clock_ints is Array and grid_ints is Array and ledger_ints is Array and floors_ints is Array and rooms_ints is Array and messages_ints is Array and people_ints is Array and grades_ints is Array and names_ints is Array and rent_ints is Array and hotel_ints is Array and commerce_ints is Array and housekeeping_ints is Array and recycling_ints is Array and vip_ints is Array and pests_ints is Array and evaluation_ints is Array and demands_ints is Array and events_ints is Array and fire_ints is Array and threat_ints is Array and mood_ints is Array and life_ints is Array and weather_ints is Array and pipe_ints is Array and stall_ints is Array and festival_ints is Array and queue_data is Array):
		return false
	var loaded_grid := Grid.new()
	if not Clock.valid_ints(clock_ints) or not loaded_grid.load_ints(grid_ints) or not LedgerScript.valid_ints(ledger_ints) or not FloorsScript.valid_ints(floors_ints):
		return false
	if not RoomsScript.valid_ints(rooms_ints, loaded_grid):
		return false
	if not MessagesScript.valid_ints(messages_ints):
		return false
	if not PeopleScript.valid_ints(people_ints):
		return false
	if not GradesScript.valid_ints(grades_ints) or not NamesScript.valid_ints(names_ints) or not EvaluationScript.valid_ints(evaluation_ints):
		return false
	if not RentScript.valid_ints(rent_ints) or not HotelScript.valid_ints(hotel_ints) or not CommerceScript.valid_ints(commerce_ints) or not HousekeepingScript.valid_ints(housekeeping_ints) or not RecyclingScript.valid_ints(recycling_ints) or not VipScript.valid_ints(vip_ints) or not PestsScript.valid_ints(pests_ints) or not DemandsScript.valid_ints(demands_ints) or not EventsScript.valid_ints(events_ints) or not FireScript.valid_ints(fire_ints) or not ThreatScript.valid_ints(threat_ints) or not MoodScript.valid_ints(mood_ints) or not LifeScript.valid_ints(life_ints) or not WeatherScript.valid_ints(weather_ints):
		return false
	if not PipeScript.valid_ints(pipe_ints) or not StallScript.valid_ints(stall_ints) or not FestivalScript.valid_ints(festival_ints):
		return false
	var loaded_queue: Array[Command] = []
	for entry in queue_data:
		if not (entry is Array and entry.size() == 3 and entry[2] is Array):
			return false
		if typeof(entry[0]) != TYPE_INT or typeof(entry[1]) != TYPE_INT:
			return false
		var command_args: Array[int] = []
		for arg in entry[2]:
			if typeof(arg) != TYPE_INT:
				return false
			command_args.append(arg)
		loaded_queue.append(Command.make(entry[0], entry[1], command_args))
	clock.load_ints(clock_ints)
	grid = loaded_grid
	var loaded_ledger := LedgerScript.new()
	loaded_ledger.load_ints(ledger_ints)
	ledger = loaded_ledger
	floors.load_ints(floors_ints)
	rooms.load_ints(rooms_ints)
	messages.load_ints(messages_ints)
	people.load_ints(people_ints)
	grades.load_ints(grades_ints)
	evaluation.load_ints(evaluation_ints)
	names.load_ints(names_ints)
	rent.load_ints(rent_ints)
	commerce.load_ints(commerce_ints)
	hotel.load_ints(hotel_ints)
	pests.load_ints(pests_ints)
	housekeeping.load_ints(housekeeping_ints)
	recycling.load_ints(recycling_ints)
	vip.load_ints(vip_ints)
	demands.load_ints(demands_ints)
	events.load_ints(events_ints)
	fire.load_ints(fire_ints)
	people.remove_rooms(rooms.charred)  # a charred room is empty (#486): saves from before the retiree fix may hold a resident in one
	threat.load_ints(threat_ints)
	mood.load_ints(mood_ints)
	life.load_ints(life_ints)
	weather.load_ints(weather_ints)
	pipe.load_ints(pipe_ints)
	stall.load_ints(stall_ints)
	festival.load_ints(festival_ints)
	last_refusal = data["last_refusal"]
	tick = data["tick"]
	rng.state = data["rng_state"]
	notes = data["notes"]
	stars = loaded_stars
	_queue = loaded_queue
	trips.resume(clock)
	refresh_reach()  # derived, so it is found again for the loaded rooms (#368)
	return true
