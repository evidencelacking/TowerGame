extends RefCounted
## Burst pipe (M9 9.10, #472): a seeded day-start roll from its own stream, the card's three choices (plumber stops it at
## once, own maintenance stops it in two periods only within reach, ignore spreads to a floor with no rooms or the lobby),
## the day a soaked room stays closed, and the rules about what a closed room does NOT do (no refund, eviction, cut-off or
## stress, no change to the fire and threat rolls).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Pipe := preload("res://scripts/sim/pipe.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Alerts := preload("res://scripts/sim/alerts.gd")
const Fixtures := preload("res://tests/fixtures.gd")

const DAY_TICKS := 2550
const FLOOR_TOP := 8
const FUNDS := 100000000


## Floors 1 (a lobby `lobby_height` floors tall) to 8 built across columns 100 to 163, stars 3, a pipe that bursts on every
## day start in the top office. Offices stack on floors `down_to` to 8 at column 112 (a column for the water to run down).
static func _tower(down_to: int = 3, lobby_height: int = 2) -> TowerSim:
	var t := TowerSim.new(5, FUNDS)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, lobby_height)
	for f in range(lobby_height + 1, FLOOR_TOP + 1):
		t.floors.fill_span(f, 100, 163)
	t.stars = 3
	for f in range(down_to, FLOOR_TOP + 1):
		_put(t, "office", f, 112)
	t.pipe.one_in = 1
	t.pipe.min_origin = FLOOR_TOP
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)
	return t.grid.cell_at(floor_number, x)


## Steps across the start of a day (day 1 is WD2), where the pipe rolls.
static func _to_day_start(t: TowerSim, day: int) -> void:
	var at := day * DAY_TICKS - 5
	t.tick = at
	t.clock.set_to_tick(at)
	for _i in 10:
		t.step()


## Answers the one open card through the CHOOSE_EVENT command.
static func _answer(t: TowerSim, choice: int) -> void:
	var id: int = t.events.open_events()[0][0]
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, choice] as Array[int]))
	t.step()
	t.step()


## Steps to the next period start.
static func _to_period_start(t: TowerSim) -> void:
	for _i in 700:
		t.step()
		if t.clock.ticks_in_period() == 0:
			return


static func _wet_floors(t: TowerSim) -> Array[int]:
	return t.pipe.wet_floors(t.grid)


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


static func _last_stop(t: TowerSim) -> Array[int]:
	var found: Array[int] = []
	for i in t.messages.count():
		if t.messages.entry(i)[1] == Messages.PIPE_STOPPED:
			found = t.messages.entry(i)
	return found


static func run(check: Callable) -> void:
	_burst_and_gates(check)
	_choices(check)
	_closed_day(check)
	_no_side_effects(check)
	_streams_and_saving(check)


## The days out of `days` on which a pipe with the default odds bursts, for one seed. Each burst is cleared afterwards, so every
## day rolls fresh (the cooldown is tested apart).
static func _burst_days(seed_value: int, days: int) -> Array[int]:
	var t := _tower()
	t.pipe.one_in = Pipe.ONE_DAY_IN
	t.pipe.reseed(seed_value)
	var clock := Clock.new()
	var hit: Array[int] = []
	for d in days:
		clock.day_started = true
		t.pipe.tick(clock, 3, t.grid, t.events, t.messages, d * DAY_TICKS)
		if t.pipe.is_flowing():
			hit.append(d)
			t.events.withdraw(t.events.open_events()[0][0])
			var rest := Pipe.rest_ints()
			rest[0] = t.pipe.state_ints()[0]  # keep the stream, drop the burst
			t.pipe.load_ints(rest)
			t.rooms.wet = {}
	return hit


static func _burst_and_gates(check: Callable) -> void:
	# A day start rolls: with the pipe forced, a card opens in the top office with the floor named.
	var t := _tower()
	_to_day_start(t, 1)
	var card := t.events.open_events()
	check.call(card.size() == 1 and card[0][1] == Pipe.KIND and card[0][2] == FLOOR_TOP, "pipe: a burst opens a card for the room's floor")
	check.call(t.pipe.is_flowing() and _wet_floors(t) == ([FLOOR_TOP] as Array[int]) and t.rooms.wet.size() == 1, "pipe: the burst room is wet and the water is flowing")
	check.call(_count(t, Messages.PIPE_BURST) == 1, "pipe: the burst is logged")
	var def := t.events.kind_def(Pipe.KIND)
	check.call(def.get("manual", false) and def["default"] == Pipe.CHOICE_IGNORE and def["costs"] == [0, Pipe.PLUMBER_COST, 0], "pipe: the kind is manual, defaults to ignore and prices the plumber")

	# Gates: 1 star or no room to burst in means no card, yet the stream draws just the same.
	var low := _tower()
	low.stars = 1
	_to_day_start(low, 1)
	check.call(low.events.open_count() == 0 and not low.pipe.is_flowing(), "pipe: no burst below 2 stars")
	check.call(low.pipe.state_ints()[0] == t.pipe.state_ints()[0], "pipe: the stream draws the same whether or not it can fire")
	var bare := TowerSim.new(5, FUNDS)
	bare.stars = 3
	bare.pipe.one_in = 1
	_to_day_start(bare, 1)
	check.call(bare.events.open_count() == 0, "pipe: no burst without a room to burst in")

	# At least a quarter between bursts: the next day start does not burst again.
	var again := _tower()
	_to_day_start(again, 1)
	_answer(again, Pipe.CHOICE_PLUMBER)
	_to_day_start(again, 2)
	check.call(_count(again, Messages.PIPE_BURST) == 1 and not again.pipe.is_flowing(), "pipe: at least a quarter between bursts")

	# About 1 day in 20, the same days on the same seed, other days on another.
	var first := _burst_days(3, 2000)
	check.call(first.size() > 60 and first.size() < 150, "pipe: about 1 day in 20 bursts (%d of 2000)" % first.size())
	check.call(first == _burst_days(3, 2000) and first != _burst_days(4, 2000), "pipe: the same seed bursts the same days, another seed differs")


static func _choices(check: Callable) -> void:
	# Ignore: it drops a floor each period down to floor 3 and stops at floor 2, which has no room (END_DRY).
	var ignore := _tower()
	_to_day_start(ignore, 1)
	_answer(ignore, Pipe.CHOICE_IGNORE)
	_to_period_start(ignore)
	check.call(_wet_floors(ignore) == ([7, 8] as Array[int]) and ignore.pipe.next_floor(ignore.grid) == 6, "pipe: it drops one floor a period and the view knows the next one")
	for _p in 4:
		_to_period_start(ignore)
	check.call(ignore.pipe.is_flowing() and _wet_floors(ignore) == ([3, 4, 5, 6, 7, 8] as Array[int]), "pipe: ignored, the water reaches every floor of the stack")
	_to_period_start(ignore)
	check.call(_count(ignore, Messages.PIPE_STOPPED) == 1 and _last_stop(ignore)[3] == Pipe.END_DRY and _last_stop(ignore)[2] == 3, "pipe: it stops once, at a floor with no rooms below")

	# Down to the lobby: with rooms on floor 2 (a one-floor lobby), the water stops at the lobby.
	var deep := _tower(2, 1)
	_to_day_start(deep, 1)
	_answer(deep, Pipe.CHOICE_IGNORE)
	for _p in 6:
		_to_period_start(deep)
	check.call(deep.pipe.is_flowing() and _wet_floors(deep).has(2) and not _wet_floors(deep).has(1), "pipe: the water reaches the second floor and not the lobby floor")
	_to_period_start(deep)
	check.call(not deep.pipe.is_flowing() and _last_stop(deep)[3] == Pipe.END_LOBBY, "pipe: it ends at the lobby")

	# The timeout default is ignore: nobody answers, the card times out and the water goes on.
	var idle := _tower()
	_to_day_start(idle, 1)
	for _i in Pipe.NOTICE_TICKS + 20:
		idle.step()
	check.call(idle.events.open_count() == 0 and idle.events.resolved()[-1][2] == Pipe.CHOICE_IGNORE and (idle.pipe.is_flowing() or _wet_floors(idle).size() > 1), "pipe: unanswered, the card times out to ignore and the water goes on")

	# Plumber: charged $25,000 by the command, the water stops at once and only the first room is wet.
	var plumber := _tower()
	_to_day_start(plumber, 1)
	var funds := plumber.ledger.balance
	_answer(plumber, Pipe.CHOICE_PLUMBER)
	check.call(funds - plumber.ledger.balance == Pipe.PLUMBER_COST, "pipe: the plumber costs $25,000")
	check.call(not plumber.pipe.is_flowing() and _count(plumber, Messages.PIPE_STOPPED) == 1, "pipe: the plumber stops the water at once")
	_to_period_start(plumber)
	_to_period_start(plumber)
	check.call(_wet_floors(plumber) == ([FLOOR_TOP] as Array[int]), "pipe: after the plumber nothing more gets wet")
	var poor := _tower()
	poor.ledger.balance = 1000
	_to_day_start(poor, 1)
	var poor_id: int = poor.events.open_events()[0][0]
	poor.enqueue(Command.make(poor.tick + 1, Command.CHOOSE_EVENT, [poor_id, Pipe.CHOICE_PLUMBER] as Array[int]))
	poor.step()
	check.call(poor.events.open_count() == 1 and poor.pipe.is_flowing(), "pipe: a plumber you cannot afford leaves the card open")

	# Own maintenance within reach (a housekeeping room within 5 floors): stops at the second period start, one more floor wet.
	var near := _tower()
	_put(near, "housekeeping", 5, 140)
	_to_day_start(near, 1)
	check.call(near.events.kind_def(Pipe.KIND)["labels"][2] == "Own maintenance (free)", "pipe: the card says maintenance is possible with housekeeping in reach")
	var before := near.ledger.balance
	_answer(near, Pipe.CHOICE_MAINTENANCE)
	_to_period_start(near)
	check.call(near.pipe.is_flowing() and _wet_floors(near) == ([7, 8] as Array[int]), "pipe: maintenance lets it spread once more")
	_to_period_start(near)
	check.call(not near.pipe.is_flowing() and _wet_floors(near) == ([7, 8] as Array[int]) and _last_stop(near)[3] == Pipe.END_STOPPED, "pipe: maintenance stops it at the second period")
	check.call(near.ledger.balance >= before - 2000 and before - near.ledger.balance < Pipe.PLUMBER_COST, "pipe: maintenance costs nothing")

	# Out of reach (the station is 6 floors below the burst): the choice acts as ignore.
	var far := _tower(3, 1)
	_put(far, "housekeeping", 2, 140)
	_to_day_start(far, 1)
	check.call(far.events.kind_def(Pipe.KIND)["labels"][2].contains("no housekeeping"), "pipe: the card says maintenance needs housekeeping in reach")
	_answer(far, Pipe.CHOICE_MAINTENANCE)
	for _p in 3:
		_to_period_start(far)
	check.call(_wet_floors(far).size() >= 4, "pipe: maintenance without housekeeping in reach does not stop the water (%d wet floors)" % _wet_floors(far).size())

	# A card still open when the water stops by itself goes away.
	var short := _tower(7)
	_to_day_start(short, 1)
	_to_period_start(short)
	_to_period_start(short)
	check.call(not short.pipe.is_flowing() and short.events.open_count() == 0, "pipe: when the water stops on its own the card goes")


static func _closed_day(check: Callable) -> void:
	# A wet room dries a day after it got wet.
	var t := _tower()
	_to_day_start(t, 1)
	_answer(t, Pipe.CHOICE_PLUMBER)
	check.call(t.rooms.wet.size() == 1, "pipe: the room is closed while wet")
	for _i in DAY_TICKS - 100:
		t.step()
	check.call(t.rooms.wet.size() == 1, "pipe: still wet before the day is out")
	for _i in 200:
		t.step()
	check.call(t.rooms.wet.is_empty() and t.pipe.wet_rooms().is_empty(), "pipe: a soaked room dries a day later")
	check.call(Alerts.list(t).filter(func(alert: Array) -> bool: return alert[0] == Alerts.PIPE).is_empty(), "pipe: dry rooms raise no alert")

	# Food takings: a wet fast-food room is closed for the day; the same room on a dry day takes money.
	var wet := _food_day(true)
	var dry := _food_day(false)
	check.call(dry != 0, "pipe: the dry control has a food line (%d)" % dry)
	check.call(wet == 0, "pipe: a wet food room posts no takings for the day (%d)" % wet)


## Dollars of shop sales credited for a fast-food room on floor 3 in a day, with or without a burst in it.
static func _food_day(burst: bool) -> int:
	var t := TowerSim.new(5, FUNDS)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.stars = 3
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	_put(t, "fast_food", 3, 112)
	t.pipe.min_origin = 3
	t.pipe.one_in = 1 if burst else 1000000
	_to_day_start(t, 1)
	var started := t.ledger.lines.size()
	for _i in 2480:  # past the settle at 23:00 (tick 2437 of the day)
		t.step()
	var total := 0
	for n in range(started, t.ledger.lines.size()):
		if t.ledger.lines[n][2] == Ledger.SHOP:
			total += t.ledger.lines[n][1]
	return total


static func _no_side_effects(check: Callable) -> void:
	# The stack: a fast-food room (the burst), a condo with a resident, an office. Nothing but takings changes.
	var runs: Array = []
	for burst in [true, false]:
		var t := TowerSim.new(5, FUNDS)
		t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
		for f in range(3, 7):
			t.floors.fill_span(f, 100, 163)
		t.stars = 3
		Fixtures.connect_floors(t, 6)  # a lift reaches every floor, so no room is cut off by the route
		_put(t, "fast_food", 5, 112)
		var condo := _put(t, "condo", 4, 112)
		_put(t, "office", 3, 112)
		t.people.add_person(condo, -1, t.rng)
		t.pipe.min_origin = 5
		t.pipe.one_in = 1 if burst else 1000000
		_to_day_start(t, 1)
		if t.events.open_count() > 0:
			_answer(t, Pipe.CHOICE_IGNORE)
		for _i in 2500:
			t.step()
		runs.append({"tower": t, "condo": condo})
	var hit: TowerSim = runs[0]["tower"]
	var control: TowerSim = runs[1]["tower"]
	var condo_id: int = runs[0]["condo"]
	check.call(_count(hit, Messages.PIPE_BURST) == 1 and _count(control, Messages.PIPE_BURST) == 0, "pipe: the side-effect tower burst and its control did not")
	check.call(_count(hit, Messages.PIPE_STOPPED) == 1, "pipe: the water ran through the condo and office floors")
	var bad_lines := 0
	for line: Array in hit.ledger.lines:
		if line[2] == Ledger.REFUND or line[2] == Ledger.PAYOUT:
			bad_lines += 1
	check.call(bad_lines == 0 and _count(hit, Messages.CONDO_REFUND) == 0, "pipe: a soaked condo is never refunded or paid out")
	check.call(hit.rooms.has_room(condo_id) and not hit.rooms.is_cut_off(condo_id) and not hit.rooms.is_charred(condo_id), "pipe: a soaked condo stays a room, is not cut off and not charred")
	check.call(hit.people.count() > 0 and hit.people.count() == control.people.count() and _homes(hit) == _homes(control), "pipe: nobody is evicted or lost: everyone has the same home as on the dry control (%d people)" % hit.people.count())
	check.call(hit.people.stress_of(0) == control.people.stress_of(0), "pipe: a closed room is not a 'no trip' stress source")
	check.call(_count(hit, Messages.TENANT_LEFT) == _count(control, Messages.TENANT_LEFT), "pipe: no tenant leaves because of the water")


static func _homes(t: TowerSim) -> Array[int]:
	var homes: Array[int] = []
	for i in t.people.count():
		homes.append(t.people.home_of(i))
	return homes


static func _streams_and_saving(check: Callable) -> void:
	# The own kinds are manual: registering them leaves fire and threat rolls exactly as before.
	var with_all := _tower()
	var without := _tower()
	without.events.kinds = [without.fire.kind(), without.threat.kind(), without.vip.kind()] as Array[Dictionary]
	for t in [with_all, without]:
		t.pipe.one_in = 1000000
	for _i in 3 * DAY_TICKS:
		with_all.step()
		without.step()
	check.call(with_all.events.rolls > 10 and with_all.events.rolls == without.events.rolls and with_all.events.state_ints() == without.events.state_ints(), "pipe: fire and threat rolls and outcomes are the same with the three own kinds registered")
	check.call(with_all.fire.state_ints() == without.fire.state_ints() and with_all.threat.state_ints() == without.threat.state_ints(), "pipe: the fire and threat systems end in the same state")
	var cards := _tower()
	var plain := _tower()
	plain.pipe.one_in = 1000000
	_to_day_start(cards, 1)
	_to_day_start(plain, 1)
	check.call(cards.events.open_count() == 1 and plain.events.open_count() == 0 and cards.events.state_ints()[0] == plain.events.state_ints()[0] and cards.events.rolls == plain.events.rolls, "pipe: opening a card leaves the shared Events stream where it was")

	# Save mid-burst and load: the same state and the same future; a quiet tower hashes as before the events existed.
	var t := _tower()
	_to_day_start(t, 1)
	_answer(t, Pipe.CHOICE_IGNORE)
	_to_period_start(t)
	var loaded := TowerSim.new(0, FUNDS)
	check.call(loaded.load_state(t.save()) and loaded.state_hash() == t.state_hash() and loaded.pipe.wet_rooms() == t.pipe.wet_rooms() and loaded.rooms.wet == t.rooms.wet, "pipe: a save in mid-burst loads as the same tower, wet rooms and all")
	for _i in 800:
		t.step()
		loaded.step()
	check.call(loaded.state_hash() == t.state_hash(), "pipe: the loaded tower and the original stay in step")
	var quiet := TowerSim.new(5, FUNDS)
	check.call(quiet.pipe.hash_ints().is_empty() and quiet.stall.hash_ints().is_empty() and quiet.festival.hash_ints().is_empty(), "pipe: a tower where none of the own events ever ran adds nothing to its hash")
	var bad := t.save()
	bad["pipe"] = [1, 2, 3]
	check.call(not TowerSim.new(0, 1).load_state(bad), "pipe: a damaged pipe block is refused")

	# The alert list names the wet floors and the open card.
	var floors: Array[int] = []
	for alert: Array in Alerts.list(t):
		if alert[0] == Alerts.PIPE:
			floors.append(alert[1])
	check.call(floors == t.pipe.wet_floors(t.grid) and not floors.is_empty() and Alerts.label_of([Alerts.PIPE, 8, 1, 0], t) == "Water damage", "pipe: each wet floor is an alert")
	var card := _tower()
	_to_day_start(card, 1)
	var alerts := Alerts.list(card)
	check.call(alerts.size() == 2 and alerts[0] == [Alerts.EVENT, FLOOR_TOP, Alerts.OPEN, Pipe.KIND] and Alerts.label_of(alerts[0], card) == "Burst pipe", "pipe: the open card is an alert at the burst floor")
