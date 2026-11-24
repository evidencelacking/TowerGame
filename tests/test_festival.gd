extends RefCounted
## Street festival (M9 9.12, #474): announced on the weekday before a weekend, at most about once a year; sponsor, ignore and
## no festival compared on visitors and takings; the per-room customer caps hold; population and the stars never see the
## crowd; rain and the festival combine multiplicatively; the gates (stars, shops, Q4) and the yearly cap hold.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Festival := preload("res://scripts/sim/festival.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Weather := preload("res://scripts/sim/weather.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Alerts := preload("res://scripts/sim/alerts.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")

const DAY_TICKS := 2550
const QUARTER_TICKS := 3 * DAY_TICKS
const FUNDS := 100000000
const MIXED := 0x2545F4914F6CDD1D


## A lobby and floor 3 over columns 100 to 199 with `kinds` placed on floor 3 from column 112, stairs up from the lobby.
static func _tower(kinds: Array[String], stars: int = 3) -> TowerSim:
	var t := TowerSim.new(42, FUNDS)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 199, 2)
	t.floors.fill_span(3, 100, 199)
	t.stars = stars
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	var x := 112
	for kind in kinds:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		x += int(Catalogue.field(kind, "width"))
	t.festival.one_in = 1
	return t


static func _shops() -> Array[String]:
	return ["fast_food", "fast_food", "restaurant", "retail"] as Array[String]


## Puts the clock at tick `at` and steps `steps` ticks.
static func _run_at(t: TowerSim, at: int, steps: int = 30) -> void:
	t.tick = at
	t.clock.set_to_tick(at)
	for _i in steps:
		t.step()


## Steps over the start of day number `day` of a quarter (0 WD1, 1 WD2, 2 WE), 0-based quarter.
static func _day_start(t: TowerSim, day: int, quarter: int = 0) -> void:
	_run_at(t, quarter * QUARTER_TICKS + day * DAY_TICKS - 5)


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


static func _answer(t: TowerSim, choice: int) -> void:
	var id: int = t.events.open_events()[0][0]
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, choice] as Array[int]))
	t.step()
	t.step()


static func run(check: Callable) -> void:
	_announcement_and_gates(check)
	_choices(check)
	_crowd(check)
	_stress_and_saving(check)


static func _announcement_and_gates(check: Callable) -> void:
	# On WD2 a festival is announced: one card, the lobby floor, the notice logged.
	var t := _tower(_shops())
	_day_start(t, 1)
	var cards := t.events.open_events()
	check.call(cards.size() == 1 and cards[0][1] == Festival.KIND and cards[0][2] == 1 and t.festival.is_announced(), "festival: WD2 announces it with a card on the lobby floor")
	check.call(_count(t, Messages.FESTIVAL_NOTICE) == 1 and not t.festival.is_active(), "festival: it is announced the weekday before, not yet on")
	var def := t.events.kind_def(Festival.KIND)
	check.call(def.get("manual", false) and def["default"] == Festival.CHOICE_IGNORE and def["costs"] == [0, Festival.SPONSOR_COST] and def["choices"] == 2, "festival: the kind is manual, defaults to ignore and prices the sponsorship")
	var alerts := Alerts.list(t)
	check.call(alerts.size() == 1 and alerts[0] == [Alerts.EVENT, 1, Alerts.OPEN, Festival.KIND] and Alerts.label_of(alerts[0], t) == "Street festival", "festival: the card is an alert on the lobby floor")
	# Other days of the week do not announce.
	var wd1 := _tower(_shops())
	_day_start(wd1, 0, 1)
	var we := _tower(_shops())
	_day_start(we, 2)
	check.call(wd1.events.open_count() == 0 and we.events.open_count() == 0, "festival: only the weekday before the weekend announces one")

	# Gates: stars, shops, the fourth quarter. Each draws the same stream.
	var low := _tower(_shops(), 2)
	_day_start(low, 1)
	check.call(low.events.open_count() == 0 and low.festival.state_ints()[0] == t.festival.state_ints()[0], "festival: no festival below 3 stars, and the stream draws on")
	var few := _tower(["fast_food", "fast_food", "restaurant"] as Array[String])
	_day_start(few, 1)
	check.call(few.events.open_count() == 0, "festival: no festival with fewer than four food or shop rooms")
	var q4 := _tower(_shops())
	_day_start(q4, 1, 3)
	check.call(q4.clock.quarter() == 4 and q4.events.open_count() == 0, "festival: not in the fourth quarter (the fly-past owns it)")
	var q3 := _tower(_shops())
	_day_start(q3, 1, 2)
	check.call(q3.clock.quarter() == 3 and q3.events.open_count() == 1, "festival: any other quarter is fine")

	# The odds: about 1 WD2 in 4, the same WD2s on the same seed.
	var days := _roll_days(1, 400)
	check.call(days.size() > 70 and days.size() < 130 and days == _roll_days(1, 400) and days != _roll_days(2, 400), "festival: about 1 weekend in 4 is rolled, the same on the same seed (%d of 400)" % days.size())

	# The yearly cap: once held this year no more; a new year allows one.
	var capped := _tower(_shops())
	var ints := capped.festival.state_ints()
	ints[0] = MIXED
	ints[5] = 1
	ints[6] = Festival.YEARLY_CAP
	capped.festival.load_ints(ints)
	_day_start(capped, 1, 1)
	check.call(capped.clock.year() == 1 and capped.events.open_count() == 0, "festival: one a year: no second in the same year")
	var next_year := _tower(_shops())
	next_year.festival.load_ints(ints)
	_day_start(next_year, 1, 4)
	check.call(next_year.clock.year() == 2 and next_year.events.open_count() == 1, "festival: the next year allows one again")


## The WD2s out of `weeks` on which a festival rolls, for one seed.
static func _roll_days(seed_value: int, weeks: int) -> Array[int]:
	var t := _tower(_shops())
	t.festival.one_in = Festival.ONE_IN
	t.festival.reseed(seed_value)
	var clock := Clock.new()
	var hit: Array[int] = []
	for w in weeks:
		clock.set_to_tick(w * QUARTER_TICKS + DAY_TICKS)
		clock.day_started = true
		t.festival.tick(clock, 3, t.people, t.events, t.messages, 1, false)
		if t.festival.state_ints()[4] == 1:
			hit.append(w)
	return hit


static func _choices(check: Callable) -> void:
	# Timeout default: ignore. Nobody answers; the card times out and the weekend comes with the small crowd.
	var ignored := _tower(_shops())
	_day_start(ignored, 1)
	_run_at(ignored, 2 * DAY_TICKS - 5, 30)  # past the card's deadline (04:00), into the weekend
	check.call(ignored.events.open_count() == 0 and ignored.events.resolved()[-1][2] == Festival.CHOICE_IGNORE, "festival: unanswered, the card times out to ignore")
	check.call(ignored.festival.is_active() and ignored.festival.level() == Festival.LEVEL_IGNORE and ignored.festival.boost_percent("fast_food") == Festival.IGNORE_PERCENT and _count(ignored, Messages.FESTIVAL_BEGAN) == 1, "festival: ignored, the weekend crowd is +20% for food and shops")
	# Explicit ignore and sponsor, by command.
	var plain := _tower(_shops())
	_day_start(plain, 1)
	var funds := plain.ledger.balance
	_answer(plain, Festival.CHOICE_IGNORE)
	check.call(plain.ledger.balance == funds and plain.festival.is_announced(), "festival: ignoring costs nothing")
	_run_at(plain, 2 * DAY_TICKS - 5, 30)
	check.call(plain.festival.level() == Festival.LEVEL_IGNORE, "festival: an answered ignore is the small crowd")
	var sponsor := _tower(_shops())
	_day_start(sponsor, 1)
	funds = sponsor.ledger.balance
	_answer(sponsor, Festival.CHOICE_SPONSOR)
	check.call(funds - sponsor.ledger.balance == Festival.SPONSOR_COST, "festival: sponsoring costs $50,000")
	_run_at(sponsor, 2 * DAY_TICKS - 5, 30)
	check.call(sponsor.festival.level() == Festival.LEVEL_SPONSOR and sponsor.festival.boost_percent("retail") == Festival.SPONSOR_PERCENT and sponsor.festival.boost_percent("fast_food") == Festival.SPONSOR_PERCENT and sponsor.festival.boost_percent("pool") == Festival.SPONSOR_PERCENT * Festival.OTHER_KINDS_SHARE / 100, "festival: sponsored, food and shops get +60% and the other kinds half of it")
	check.call(sponsor.festival.held_this_year(1) == 1, "festival: it counts against the year's cap")
	# It ends when the weekend does.
	_run_at(sponsor, 3 * DAY_TICKS - 5, 30)
	check.call(not sponsor.festival.is_active() and sponsor.festival.boost_percent("fast_food") == 0, "festival: the crowd goes home with the weekend")
	# Too poor to sponsor: the card stays open.
	var poor := _tower(_shops())
	_day_start(poor, 1)
	poor.ledger.balance = 1000
	var id: int = poor.events.open_events()[0][0]
	poor.enqueue(Command.make(poor.tick + 1, Command.CHOOSE_EVENT, [id, Festival.CHOICE_SPONSOR] as Array[int]))
	poor.step()
	check.call(poor.events.open_count() == 1, "festival: a sponsorship you cannot afford leaves the card open")


## The customers a shop of `kind` serves on a weekend day, summed over its meals, when `percent` extra visitors come and the
## rain cuts by `cut`: each meal's crowd is boosted, then cut, then limited to the room's seats.
static func _expected(kind: String, percent: int, cut: int) -> int:
	var total := 0
	for meal: Array in Commerce.MEALS:
		if meal[3] != kind:
			continue
		var raw := Commerce.visitors_for(kind, Commerce.period_of_minute(meal[0]), Clock.WE)
		var count := Weather.cut(Festival.boost(raw, percent) if percent > 0 else raw, cut)
		total += mini(count, Commerce.seats_per_meal(kind, meal[1]))
	return total


## One weekend day in a tower with a single shop of `kind`: the customers it served, the extra festival visitors counted
## apart, and what the tower counted as visitors, population and stars. `level` is 0 none, 1 ignore, 2 sponsor.
static func _weekend(kind: String, level: int, rain: bool) -> Dictionary:
	var t := _tower([kind] as Array[String])
	t.clock.set_to_tick(Clock.WE * DAY_TICKS)
	if level > 0:
		t.festival.load_ints([MIXED, Festival.ACTIVE, 0, level, 0, 1, 1])
	if rain:
		t.weather.load_ints([t.weather.state_ints()[0], 0, 6, 0])
	var shop := -1
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			shop = id
	var peak := 0
	var visitors := 0
	var population := 0
	var permanent := 0
	var extra := 0
	for _i in DAY_TICKS - 100:  # peaks are read while they stand: the settle at 23:00 clears the day's counts
		t.step()
		peak = maxi(peak, t.commerce.customers_today(shop))
		visitors = maxi(visitors, t.commerce.visitors_today())
		population = maxi(population, t.population())
		permanent = maxi(permanent, t.permanent_population())
		extra = maxi(extra, t.commerce.festival_today)
	return {"customers": peak, "visitors": visitors, "population": population, "permanent": permanent, "extra": extra, "stars": t.stars}


static func _crowd(check: Callable) -> void:
	var capped_somewhere := false
	for kind: String in ["fast_food", "restaurant", "retail"]:
		var none := _weekend(kind, 0, false)
		var ignore := _weekend(kind, 1, false)
		var sponsor := _weekend(kind, 2, false)
		check.call(none["customers"] == _expected(kind, 0, 0) and none["customers"] > 0, "festival: %s with no festival serves the ordinary crowd (%d)" % [kind, none["customers"]])
		check.call(ignore["customers"] == _expected(kind, Festival.IGNORE_PERCENT, 0), "festival: %s ignored serves +20%% up to its seats (%d, expected %d)" % [kind, ignore["customers"], _expected(kind, Festival.IGNORE_PERCENT, 0)])
		check.call(sponsor["customers"] == _expected(kind, Festival.SPONSOR_PERCENT, 0), "festival: %s sponsored serves +60%% up to its seats (%d, expected %d)" % [kind, sponsor["customers"], _expected(kind, Festival.SPONSOR_PERCENT, 0)])
		check.call(sponsor["customers"] > ignore["customers"] and ignore["customers"] > none["customers"], "festival: %s sponsor %d beats ignore %d beats none %d" % [kind, sponsor["customers"], ignore["customers"], none["customers"]])
		var uncapped := 0
		for meal: Array in Commerce.MEALS:
			if meal[3] == kind:
				uncapped += Festival.boost(Commerce.visitors_for(kind, Commerce.period_of_minute(meal[0]), Clock.WE), Festival.SPONSOR_PERCENT)
		capped_somewhere = capped_somewhere or uncapped > sponsor["customers"]
		# The crowd is never counted as visitors, population or the stars: the extras are counted apart.
		check.call(sponsor["visitors"] == none["visitors"] and sponsor["population"] == none["population"] and sponsor["permanent"] == none["permanent"] and sponsor["stars"] == none["stars"], "festival: %s crowd leaves visitors, population and stars as they were" % kind)
		check.call(none["extra"] == 0 and sponsor["extra"] == sponsor["customers"] - none["customers"], "festival: %s extras are counted apart (%d)" % [kind, sponsor["extra"]])
	check.call(not capped_somewhere, "festival: the real crowd fits the seats (the cap test below uses an outsized one)")
	_caps(check)

	# Food takings: sponsor, ignore and none, from the ledger.
	var takings := {}
	for level in [0, 1, 2]:
		takings[level] = _food_takings(level)
	check.call(takings[2] > takings[0] and takings[1] >= takings[0] and takings[2] >= takings[1], "festival: food takings rise with the crowd, in steps of the shop's tiers (none %d, ignore %d, sponsor %d)" % [takings[0], takings[1], takings[2]])

	# Rain and festival combine multiplicatively: boost first, then the cut; less than a dry festival, more than rain alone.
	var rain_only := _weekend("fast_food", 0, true)
	var rain_fest := _weekend("fast_food", 2, true)
	var dry_fest := _weekend("fast_food", 2, false)
	var cut: int = Weather.FOOD_CUT_PERCENT
	check.call(rain_only["customers"] == _expected("fast_food", 0, cut) and rain_fest["customers"] == _expected("fast_food", Festival.SPONSOR_PERCENT, cut), "festival: rain and a festival multiply (%d, expected %d)" % [rain_fest["customers"], _expected("fast_food", Festival.SPONSOR_PERCENT, cut)])
	check.call(rain_only["customers"] < rain_fest["customers"] and rain_fest["customers"] < dry_fest["customers"], "festival: a rainy festival beats rain alone and loses to a dry festival")
	check.call(Weather.cut(Festival.boost(10, 60), 50) == 8 and Festival.boost(10, 20) == 12 and Festival.boost(0, 60) == 0, "festival: the combine is integer, half up")


## An outsized crowd (+500%) from a stand-in festival: the rooms' seats still limit the customers, and the crowd still stays out of
## the visitor count.
class HugeCrowd:
	extends RefCounted

	func boost_percent(_kind: String) -> int:
		return 500

	func boost(count: int, percent: int) -> int:
		return Festival.boost(count, percent)


static func _caps(check: Callable) -> void:
	var capped_all := true
	var binds := false
	for kind: String in ["fast_food", "restaurant", "retail"]:
		var t := _tower([kind] as Array[String])
		t.clock.set_to_tick(Clock.WE * DAY_TICKS)
		t.commerce.festival = HugeCrowd.new()
		var shop := -1
		for id in t.rooms.room_ids():
			if t.rooms.kind_of(id) == kind:
				shop = id
		var peak := 0
		var visitors := 0
		for _i in DAY_TICKS - 100:
			t.step()
			peak = maxi(peak, t.commerce.customers_today(shop))
			visitors = maxi(visitors, t.commerce.visitors_today())
		var cap := _expected(kind, 500, 0)
		var uncapped := 0
		var seats := 0
		for meal: Array in Commerce.MEALS:
			if meal[3] == kind:
				uncapped += Festival.boost(Commerce.visitors_for(kind, Commerce.period_of_minute(meal[0]), Clock.WE), 500)
				seats += Commerce.seats_per_meal(kind, meal[1])
		capped_all = capped_all and peak == cap and peak <= seats and visitors == _weekend(kind, 0, false)["visitors"]
		binds = binds or uncapped > peak
	check.call(capped_all, "festival: an outsized crowd never seats more than each room's per-meal seats, and still adds no visitors")
	check.call(binds, "festival: at least one room's seats actually cap the outsized crowd")


## Dollars of shop sales credited on a weekend day (to a fast-food room) at a festival level.
static func _food_takings(level: int) -> int:
	var t := _tower(["fast_food"] as Array[String])
	t.clock.set_to_tick(Clock.WE * DAY_TICKS)
	if level > 0:
		t.festival.load_ints([MIXED, Festival.ACTIVE, 0, level, 0, 1, 1])
	var started := t.ledger.lines.size()
	for _i in 2480:  # past the settle at 23:00
		t.step()
	var total := 0
	for n in range(started, t.ledger.lines.size()):
		if t.ledger.lines[n][2] == Ledger.SHOP:
			total += t.ledger.lines[n][1]
	return total


static func _stress_and_saving(check: Callable) -> void:
	# The crowd loads the ground-floor queue: waiting there is more stressful on the festival day, more when sponsored.
	var stresses := {}
	for level in [0, 1, 2]:
		stresses[level] = _queued_stress(level)
	check.call(stresses[0] < stresses[1] and stresses[1] < stresses[2], "festival: queued riders at the lobby are more stressed in a bigger crowd (%s)" % str(stresses))

	# Saved while announced and while on: the same tower, the same future.
	var t := _tower(_shops())
	_day_start(t, 1)
	var loaded := TowerSim.new(0, FUNDS)
	check.call(loaded.load_state(t.save()) and loaded.state_hash() == t.state_hash() and loaded.festival.is_announced(), "festival: a save while announced loads as the same tower")
	_answer(t, Festival.CHOICE_SPONSOR)
	_answer(loaded, Festival.CHOICE_SPONSOR)
	_run_at(t, 2 * DAY_TICKS - 5, 30)
	_run_at(loaded, 2 * DAY_TICKS - 5, 30)
	check.call(t.festival.is_active() and loaded.state_hash() == t.state_hash(), "festival: the loaded tower and the original reach the weekend alike")
	var again := TowerSim.new(0, FUNDS)
	check.call(again.load_state(t.save()) and again.state_hash() == t.state_hash() and again.festival.level() == Festival.LEVEL_SPONSOR, "festival: a save on the festival day keeps the crowd")
	var bad := t.save()
	bad["festival"] = [1, 2, 3]
	check.call(not TowerSim.new(0, 1).load_state(bad), "festival: a damaged festival block is refused")

	# Old saves load: a version 48 save (no pipe, stall or festival blocks) migrates to the resting state.
	var old := TowerSim.new(0, FUNDS)
	var data := TowerSim.new(3, FUNDS).save()
	data["version"] = 48
	data.erase("pipe")
	data.erase("stall")
	data.erase("festival")
	check.call(old.load_state(data) and old.pipe.hash_ints().is_empty() and old.stall.hash_ints().is_empty() and old.festival.hash_ints().is_empty() and old.festival.state_ints() == Festival.rest_ints(), "festival: a version 48 save loads with the three events at rest")


## The stress of a person waiting in the lobby queue of a shaft with no car for 120 ticks, on a weekend morning at `level`.
static func _queued_stress(level: int) -> int:
	var t := _tower([] as Array[String])
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, 3, 190)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 176)
	var office := t.grid.cell_at(3, 176)
	t.people.add_person(-1, office, t.rng)
	var shaft: int = t.rooms.shaft_ids()[0]
	t.rooms.join_queue(t.people.id_at(0), shaft, 1, 3)
	t.clock.set_to_tick(Clock.WE * DAY_TICKS + 700)
	t.tick = Clock.WE * DAY_TICKS + 700
	if level > 0:
		t.festival.load_ints([MIXED, Festival.ACTIVE, 0, level, 0, 1, 1])
	for _i in 120:
		t.step()
	return t.people.stress_of(0)
