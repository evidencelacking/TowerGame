extends RefCounted
## A copy of Tower.step() and Tower._run_systems() with a hook after each system, so tools/perf_save.gd can
## time them one by one. It must stay line for line in step with tower.gd: tests/test_perf_split.gd steps this
## and Tower.step() on the mixed fixture and compares state_hash, so a drift fails the suite. Whenever
## _run_systems, refresh_reach's call site or evaluate_tenants changes, change this too.
## mark is called with "" before the first system (start the clock) and with a label after each.

const CarsScript := preload("res://scripts/sim/cars.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const EvaluationScript := preload("res://scripts/sim/evaluation.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const HelipadScript := preload("res://scripts/sim/helipad.gd")
const RunningCostsScript := preload("res://scripts/sim/running_costs.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")


static func step(t: Tower, mark: Callable) -> void:
	t.tick += 1
	mark.call("")  # starts the clock
	t._apply_due_commands()
	mark.call("commands")
	t.clock.advance()
	mark.call("clock")
	t.refresh_reach()
	mark.call("refresh_reach")
	if t._slow_due(Tower.TENANCY_AT):
		t.tenancy.tick(t.clock, t.floors, t.rooms, t.grid, t.people, t.rng, t.ledger, t.tick)
	mark.call("tenancy")
	t.commerce.tick(t.clock, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, t.ledger, t.messages, t.tick, t.life)
	mark.call("commerce")
	if t._slow_due(Tower.VIP_AT):
		t.vip.tick(t.clock, t.stars, t.people, t.grades, t.messages, t.events, t.ledger, t.grid, t.tick)
	mark.call("vip")
	if t._slow_due(Tower.HOTEL_AT):
		t.hotel.tick(t.clock, t.floors, t.people, t.rng, t.ledger, t.messages, t.tick)
	mark.call("hotel")
	if t._slow_due(Tower.PESTS_AT):
		t.pests.tick(t.hotel, t.grid, t.rng, t.messages, t.tick)
	mark.call("pests")
	if t._slow_due(Tower.HOUSEKEEPING_AT):
		t.housekeeping.tick(t.clock, t.floors, t.grid, Tower.SLOW_EVERY)
	mark.call("housekeeping")
	if t._slow_due(Tower.RECYCLING_AT):
		t.recycling.tick(t.clock, t.population())
	mark.call("recycling")
	if t.clock.day_started:
		t.rent.collect(t.rooms, t.people, t.ledger, t.tick, t.clock.quarter_started, t.rent_bonus_percent())
		t.commerce.collect_rent(t.rooms, t.rent, t.ledger, t.tick, t.clock.quarter_started)
		HelipadScript.collect(t.rooms, t.ledger, t.tick)
		mark.call("daily rent")
	if t.clock.quarter_started:
		var rent_income := t._quarter_rent()
		var running := RunningCostsScript.charge(t.rooms, t.floors, t.ledger, t.tick)
		if rent_income > 0 or running > 0:
			t.messages.add(t.tick, MessagesScript.QUARTER_SETTLED, rent_income, running)
		mark.call("quarter")
	t.trips.tick(t.clock, t.floors, t.rooms, t.grid, t.people)
	mark.call("trips")
	if t.trips.blocked_transfers > 0:
		if not t.messages.recent(MessagesScript.TRIP_UNREACHABLE, t.tick - TripsScript.WARN_EVERY_TICKS + 1):
			t.messages.add(t.tick, MessagesScript.TRIP_UNREACHABLE, t.trips.blocked_transfers)
		t.trips.blocked_transfers = 0
	mark.call("grades")
	t.rooms.schedule_slot = RoomsScript.slot_for(t.clock.day_of_week() == ClockScript.WE, t.clock.period())
	CarsScript.tick(t.rooms)
	mark.call("cars")
	t.trips.collect_arrivals(t.floors, t.rooms, t.grid, t.people)
	mark.call("arrivals")
	t.people.tick(t.clock)
	t.grades.tick(t.people)
	mark.call("people")
	if t.clock.ticks_in_period() == 0:
		t.threat.population = t.population()
	mark.call("population")
	t.events.tick(t.clock, t.stars, t.tick)
	t.fire.tick(t.clock, t.events, t.grid, t.people, t.messages, t.tick)
	t.threat.tick(t.events, t.grid, t.messages, t.tick)
	mark.call("events/fire/threat")
	if t._slow_due(Tower.MOOD_AT) or t.fire.started or t.threat.started:
		if not t.fire.burning_rooms().is_empty():
			t.mood.note_event(MoodScript.FIRE_SHOCK, t.people)
		if t.threat.is_active():
			t.mood.note_event(MoodScript.THREAT_SHOCK, t.people)
	for id in t.fire.take_burned():
		t.char_room(id)
	for id in t.threat.take_destroyed():
		t.destroy_room(id)
	mark.call("fire aftermath")
	if EvaluationScript.is_due(t.clock):  # Tower.evaluate_tenants, split to time each step
		t.mood.update(t.rooms, t.grid, t.floors, t.grades, t.people)
		mark.call("eval: mood.update")
		t.evaluation.evaluate(t.rooms, t.people, t.grades, t.grid, t.floors, t.tenancy, t.ledger, t.messages, t.rng, t.tick)
		mark.call("eval: evaluate")
		t.evaluation.evaluate_moods(t.rooms, t.people, t.grades, t.grid, t.ledger, t.messages, t.tick)
		mark.call("eval: evaluate_moods")
		t.life.daily(t)
		mark.call("eval: life.daily")
		t.apartments.daily(t)
		mark.call("eval: apartments.daily")
		t.commerce.evaluate(t.floors, t.rooms, t.grid, t.tenancy, t.rent, t.messages, t.tick)
		mark.call("eval: commerce.evaluate")
	if StarRulesScript.is_check_tick(t.tick):
		t.promote_stars()
		mark.call("promote_stars")
