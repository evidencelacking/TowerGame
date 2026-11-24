extends RefCounted
## The movie theatre and the party hall (#500). The theatre: placed two floors tall and permanent, a film chosen by command
## (no film, no shows), the licence charged once, a deterministic audience that fades after the film's run, outside viewers kept
## out of the population, the shop boost at 5 floors but not 6, and a cut-off theatre earning nothing. The party hall: a party
## a day that needs a reachable hotel room, the fee tiers. Save and load keeps the film and its age. Our own design: every
## number is a tunable (see theatre.gd and commerce.gd).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Theatre := preload("res://scripts/sim/theatre.gd")
const Bookings := preload("res://scripts/sim/bookings.gd")
const Names := preload("res://scripts/sim/names.gd")

const DAY_TICKS := 2550
const SHOWS_DONE_TICKS := 2400  ## Past the 19:30 show but before the next morning, so the day's counters are still standing.
const THEATRE_X := 150


## Lobby on floors 1-2, floors 3 up to `top` filled and (unless stairs is false) joined by stairs, so every floor is reachable.
static func _tower(top: int = 3, stairs: bool = true) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 199, 2)
	for f in range(3, top + 1):
		t.floors.fill_span(f, 100, 199)
	if stairs and top > 4:  # stairs are limited to four flights a leg, so a tall tower gets a local shaft with a car
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, top, 100)
		t.rooms.add_car(t.ledger, 0, 3, t.rooms._shaft_base(t.rooms.link_at(1, 100)), 1)
	elif stairs:
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
		for f in range(3, top):
			t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, f, 100 if f % 2 == 1 else 104)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


## Ticket money so far for a room: the SHOP ledger lines whose ref is the room.
static func _takings(t: TowerSim, room: int) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == Ledger.SHOP and line[3] == room:
			total += line[1]
	return total


## Choose a film by command, as the room window does, and step so it applies.
static func _choose(t: TowerSim, room: int, film_id: int) -> void:
	var args: Array[int] = [room, film_id]
	t.enqueue(TowerSim.Command.make(t.tick + 1, TowerSim.Command.CHOOSE_FILM, args))
	t.step()
	t.step()


static func _steps(t: TowerSim, n: int) -> void:
	for k in n:
		t.step()


static func _guests(t: TowerSim, n: int) -> void:
	var hotel := _room(t, "hotel_single")
	for k in n:
		var id := t.people.add_person(hotel, People.NONE, t.rng)
		t.people.start_trip(t.people.index_of(id), 600)


static func _party(t: TowerSim, day: int) -> void:
	var meal: Array = []
	for row: Array in Commerce.MEALS:
		if row[3] == "party_hall":
			meal = row
	t.commerce._serve("party_hall", meal[1], meal[2], t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, meal[0], t.life)


## Floors 3-4 hold the theatre; fast food on floors 9 and 10; stairs up to floor 10. Both towers take the same steps.
static func _boost_tower(film: bool) -> TowerSim:
	var t := _tower(10)
	_put(t, "movie_theatre", 3, THEATRE_X)
	_put(t, "fast_food", 9, 110)
	_put(t, "fast_food", 10, 110)
	if film:
		_choose(t, _room(t, "movie_theatre"), 1)
	else:
		_steps(t, 2)
	return t


static func _shop_on(t: TowerSim, floor_number: int) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "fast_food" and t.grid.run_of(id)[0] == floor_number:
			return id
	return -1


## The 15:00 snack wave: half an hour after the 12:30 show ends at 14:30, inside the shops' hour.
static func _snack(t: TowerSim) -> void:
	t.commerce._serve("fast_food", Commerce.SNACK_WINDOW, Commerce.SNACK_PERCENT, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, Clock.WD1, Commerce.SNACK_AFTERNOON, t.life)


static func run(check: Callable) -> void:
	# Placement: two floors tall, above ground, permanent.
	var row: Dictionary = Catalogue.row("movie_theatre")
	check.call(int(row["height"]) == 2 and not bool(row["removable"]) and Rooms.PLACEABLE.has("movie_theatre") and Rooms.TALL_KINDS.has("movie_theatre"), "theatre: placeable, two floors tall, permanent")
	check.call(Rooms.PLACEABLE.has("party_hall") and bool(Catalogue.field("party_hall", "removable")) and int(Catalogue.field("party_hall", "height")) == 1 and not Rooms.TALL_KINDS.has("party_hall"), "party hall: placeable, one floor, removable")
	var p := _tower()
	check.call(_put(p, "movie_theatre", 3, THEATRE_X) == Rooms.OK, "theatre: placed at floor 3")
	var tid := _room(p, "movie_theatre")
	check.call(p.grid.run_of(tid)[0] == 3 and p.grid.cell_at(4, THEATRE_X) == tid + 1 and p.floors.has_floor(4, THEATRE_X + 31), "theatre: stands on floors 3 and 4")
	check.call(p.rooms.check_bulldoze(p.grid, p.floors, 3, THEATRE_X)["reason"] == Rooms.PERMANENT and p.rooms.check_bulldoze(p.grid, p.floors, 4, THEATRE_X + 5)["reason"] == Rooms.PERMANENT, "theatre: bulldozing either floor is refused as permanent")
	check.call(_put(_tower(), "movie_theatre", 1, THEATRE_X) == Rooms.LOBBY_FLOOR and _put(_tower(), "movie_theatre", -3, THEATRE_X) == Rooms.BELOW_GROUND, "theatre: not on the lobby floor or underground")
	check.call(_put(p, "party_hall", 3, 110) == Rooms.OK and p.rooms.check_bulldoze(p.grid, p.floors, 3, 110)["reason"] == Rooms.OK, "party hall: placed on one floor and removable")

	# The six films are a table of original names.
	check.call(Theatre.FILMS.size() == 6, "theatre: six films")
	var names: Dictionary = {}
	for film: Dictionary in Theatre.FILMS:
		names[film["name"]] = true
	check.call(names.size() == 6, "theatre: six different titles")
	check.call(int(Theatre.FILMS[0]["licence"]) > int(Theatre.FILMS[5]["licence"]) and int(Theatre.FILMS[0]["draw"]) > int(Theatre.FILMS[5]["draw"]) and int(Theatre.FILMS[5]["run"]) > int(Theatre.FILMS[0]["run"]), "theatre: from a costly big-draw release to a cheap classic with a long run")

	# No film, no show: a whole day earns nothing and adds nothing to the state hash.
	var quiet := _tower()
	_put(quiet, "movie_theatre", 3, THEATRE_X)
	var qid := _room(quiet, "movie_theatre")
	_steps(quiet, DAY_TICKS)
	check.call(_takings(quiet, qid) == 0 and quiet.theatre.film_of(qid) == Theatre.NO_FILM and quiet.theatre.outside_today == 0, "theatre: with no film there are no shows and no tickets")
	check.call(quiet.theatre.hash_ints().is_empty(), "theatre: with no film it adds nothing to the state hash")

	# The licence is charged once, on choosing; the same film again is refused and free.
	var a := _tower()
	_put(a, "movie_theatre", 3, THEATRE_X)
	var aid := _room(a, "movie_theatre")
	var before := a.ledger.balance
	_choose(a, aid, 1)
	check.call(a.theatre.film_of(aid) == 1 and before - a.ledger.balance == int(Theatre.FILMS[0]["licence"]), "theatre: choosing a film charges its licence (%d)" % (before - a.ledger.balance))
	before = a.ledger.balance
	_choose(a, aid, 1)
	check.call(a.ledger.balance == before and a.theatre.age_of(aid) == 0, "theatre: the same film again charges nothing")
	check.call(a.theatre.choose(a.rooms, a.ledger, 0, aid, 99) == Theatre.UNKNOWN_FILM and a.theatre.choose(a.rooms, a.ledger, 0, 1, 1) == Theatre.NOT_A_THEATRE, "theatre: an unknown film and a room that is no theatre are refused")
	var poor := _tower()
	_put(poor, "movie_theatre", 3, THEATRE_X)
	var poor_id := _room(poor, "movie_theatre")
	poor.ledger.balance = 100
	check.call(poor.theatre.choose(poor.rooms, poor.ledger, 0, poor_id, 1) == Theatre.SHORT_OF_FUNDS and poor.theatre.film_of(poor_id) == Theatre.NO_FILM, "theatre: a licence the balance cannot meet is refused")
	# Showing for days does not charge again; changing the film charges the new licence and restarts the age.
	_steps(a, 2 * DAY_TICKS)
	var shows_balance := a.ledger.balance
	check.call(a.theatre.age_of(aid) == 2 and _takings(a, aid) > 0, "theatre: a film earns tickets and ages a day at a time (age %d, $%d)" % [a.theatre.age_of(aid), _takings(a, aid)])
	_choose(a, aid, 6)
	check.call(shows_balance - a.ledger.balance == int(Theatre.FILMS[5]["licence"]) and a.theatre.age_of(aid) == 0 and a.theatre.film_of(aid) == 6, "theatre: a new film costs its own licence and restarts the age")

	# The audience: a pure function, weekend lift, fade after the run.
	check.call(Theatre.audience(1, 0, Clock.WD1) == 115 and Theatre.fill_percent(1, 0, Clock.WE) == 100 and Theatre.audience(1, 0, Clock.WE) == 128, "theatre: 90% of 128 seats on a weekday, full at the weekend (draw +15 points, capped)")
	check.call(Theatre.fade_percent(1, 12) == 0 and Theatre.fade_percent(1, 13) == 10 and Theatre.fade_percent(1, 15) == 10 and Theatre.fade_percent(1, 16) == 20, "theatre: 10% weaker for each game week past the run")
	check.call(Theatre.fade_percent(1, 12 + 3 * 11) == 100 and Theatre.audience(1, 12 + 3 * 11, Clock.WD1) == 0, "theatre: a long-past film draws nobody")
	check.call(Theatre.fill_percent(1, 13, Clock.WD1) == 81, "theatre: a faded film fills less (%d)" % Theatre.fill_percent(1, 13, Clock.WD1))
	check.call(Theatre.outside_part(115) == 69, "theatre: 60% of an audience is from outside")

	# Deterministic: two seeded towers agree, tickets and all.
	var b := _tower()
	var c := _tower()
	for t: TowerSim in [b, c]:
		_put(t, "movie_theatre", 3, THEATRE_X)
		_choose(t, _room(t, "movie_theatre"), 2)
		_steps(t, SHOWS_DONE_TICKS)
	var bid := _room(b, "movie_theatre")
	check.call(b.state_hash() == c.state_hash() and _takings(b, bid) == _takings(c, _room(c, "movie_theatre")), "theatre: two seeded runs agree")
	# Day one is WD1: 80% of 128 is 102 seats, 61 from outside, three shows, nobody in the tower to fill the rest.
	var seats := Theatre.audience(2, 0, Clock.WD1)
	check.call(_takings(b, bid) == 3 * Theatre.outside_part(seats) * Theatre.TICKET, "theatre: three shows a day at $10 a seat, outside viewers only while the tower is empty (%d)" % _takings(b, bid))
	check.call(b.theatre.outside_today == 3 * Theatre.outside_part(seats) and b.theatre.tower_today == 0, "theatre: outside viewers are counted apart")

	# Outside viewers never reach the population or the visitors; tower people fill the rest of the seats.
	var d := _tower()
	var e := _tower()
	for t: TowerSim in [d, e]:
		_put(t, "movie_theatre", 3, THEATRE_X)
		_put(t, "hotel_single", 3, 110)
		_guests(t, 100)
	_choose(d, _room(d, "movie_theatre"), 2)
	_steps(e, 2)
	_steps(d, SHOWS_DONE_TICKS)
	_steps(e, SHOWS_DONE_TICKS)
	check.call(d.theatre.outside_today == 3 * Theatre.outside_part(seats), "theatre: with people about, the outside viewers are still 60%% (%d)" % d.theatre.outside_today)
	check.call(d.permanent_population() == e.permanent_population() and d.people.count() == e.people.count() and d.commerce.visitors_today() == e.commerce.visitors_today(), "theatre: outside viewers are not in the population or the visitors")
	check.call(d.theatre.tower_today > 0 and d.theatre.tower_today <= 3 * (seats - Theatre.outside_part(seats)), "theatre: tower people fill part of the other 40%% (%d)" % d.theatre.tower_today)
	check.call(_takings(d, _room(d, "movie_theatre")) == (d.theatre.outside_today + d.theatre.tower_today) * Theatre.TICKET, "theatre: every seat sold pays $10")

	# The shop boost: floor 4 is the theatre's upper floor, so floor 9 is 5 floors off and floor 10 is 6.
	var with_film := _boost_tower(true)
	var control := _boost_tower(false)
	for k in 6:
		_snack(with_film)
		_snack(control)
	var base_near := control.commerce.customers_today(_shop_on(control, 9))
	check.call(base_near > 0, "boost: the control tower's shop serves customers at the snack (%d)" % base_near)
	check.call(with_film.commerce.customers_today(_shop_on(with_film, 9)) > base_near, "boost: a shop 5 floors from the theatre gets more customers after a show (%d against %d)" % [with_film.commerce.customers_today(_shop_on(with_film, 9)), base_near])
	check.call(with_film.commerce.customers_today(_shop_on(with_film, 10)) == control.commerce.customers_today(_shop_on(control, 10)), "boost: a shop 6 floors away gets none")
	check.call(Theatre.near(9, [3, 4] as Array[int]) and not Theatre.near(10, [3, 4] as Array[int]) and Theatre.near(-1, [1, 2] as Array[int]) and not Theatre.near(-6, [1, 2] as Array[int]) and Theatre.near(1, [5, 6] as Array[int]), "boost: five floors above or below counts, six does not, with no floor 0")

	# A theatre cut off from the lobby earns nothing.
	var cut := _tower(4, false)
	_put(cut, "movie_theatre", 3, THEATRE_X)
	var cid := _room(cut, "movie_theatre")
	_choose(cut, cid, 1)
	_steps(cut, SHOWS_DONE_TICKS)
	check.call(cut.rooms.is_cut_off(cid) and _takings(cut, cid) == 0 and cut.theatre.outside_today == 0, "theatre: cut off from the lobby it earns nothing")
	var linked := _tower(4)
	_put(linked, "movie_theatre", 3, THEATRE_X)
	_choose(linked, _room(linked, "movie_theatre"), 1)
	_steps(linked, SHOWS_DONE_TICKS)
	check.call(_takings(linked, _room(linked, "movie_theatre")) > 0, "theatre: the same theatre with stairs earns")

	# The party hall: a daily party that needs a reachable hotel room.
	check.call(Commerce.is_shop("party_hall") and Bookings.is_bookable("party_hall") and Names.TITLES.has("party_hall") and Names.TITLES.has("movie_theatre"), "party hall: trades like a booking, has titles")
	var party_meal: Array = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == "party_hall":
			party_meal = meal
	check.call(party_meal[0] == 840 and party_meal[0] + party_meal[1] == 1080, "party hall: the party runs from 14:00 to 18:00")
	check.call(Commerce.seats_per_meal("party_hall", Commerce.PARTY_WINDOW) == 30, "party hall: 30 seats")
	var bare := _tower()
	_put(bare, "party_hall", 3, 110)
	_party(bare, Clock.WD1)
	check.call(bare.commerce.customers_today(_room(bare, "party_hall")) == 0 and not Bookings.needs_met("party_hall", bare.rooms), "party hall: with no hotel room there is no party")
	var lonely := _tower()
	_put(lonely, "party_hall", 3, 110)
	_put(lonely, "hotel_single", 3, 150)
	var lonely_id := _room(lonely, "party_hall")
	for day: int in [Clock.WD1, Clock.WD2, Clock.WE]:
		lonely.commerce._today.clear()
		_party(lonely, day)
		check.call(lonely.commerce.customers_today(lonely_id) == 10, "party hall: a party on day %d with no hotel guests holds the 10 outside guests (%d)" % [day, lonely.commerce.customers_today(lonely_id)])
	check.call(lonely.commerce.visitors_today() == 0, "party hall: outside guests are not counted as population")
	var full := _tower()
	_put(full, "party_hall", 3, 110)
	_put(full, "hotel_single", 3, 150)
	_guests(full, 80)
	_party(full, Clock.WE)
	var crowd := full.commerce.customers_today(_room(full, "party_hall"))
	check.call(crowd > 10 and crowd <= 30, "party hall: hotel guests join, never past the 30 seats (%d)" % crowd)
	check.call(Commerce.income_for("party_hall", 0) == 0 and Commerce.income_for("party_hall", 9) == 0 and Commerce.income_for("party_hall", 10) == 2500 and Commerce.income_for("party_hall", 20) == 4500 and Commerce.income_for("party_hall", 30) == 6500, "party hall: fee tiers $0, $2,500, $4,500 and $6,500")
	var money := full.ledger.balance
	full.commerce._settle(full.floors, full.rooms, full.grid, full.tenancy, full.ledger, full.messages, 0, full.rng)
	check.call(full.ledger.balance - money == Commerce.income_for("party_hall", crowd) and _takings(full, _room(full, "party_hall")) == Commerce.income_for("party_hall", crowd), "party hall: the fee lands on the shop sales line (%d)" % (full.ledger.balance - money))
	# A hotel room no route reaches is no hotel.
	var unreached := _tower(3, false)
	_put(unreached, "party_hall", 3, 110)
	_put(unreached, "hotel_single", 3, 150)
	unreached.refresh_reach()
	check.call(not Bookings.needs_met("party_hall", unreached.rooms), "party hall: a hotel room no route reaches does not count")

	# Save and load keep the film and its age, and the loaded tower carries on like the original.
	var s := _tower()
	_put(s, "movie_theatre", 3, THEATRE_X)
	var sid := _room(s, "movie_theatre")
	_choose(s, sid, 3)
	_steps(s, 2 * DAY_TICKS)
	var saved := s.save()
	check.call(saved["version"] == 51 and saved.has("theatre"), "save: version 51 holds the theatre")
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(saved) and copy.theatre.film_of(sid) == 3 and copy.theatre.age_of(sid) == 2 and copy.state_hash() == s.state_hash(), "save: the film and its age survive save and load")
	_steps(s, DAY_TICKS)
	_steps(copy, DAY_TICKS)
	check.call(copy.state_hash() == s.state_hash() and copy.ledger.balance == s.ledger.balance and copy.theatre.age_of(sid) == 3, "save: the loaded tower goes on exactly like the original")
	var bad := s.save()
	bad["theatre"] = [-1, 1, 5, 9, 0]
	check.call(not TowerSim.new(1, 1).load_state(bad), "save: a theatre with an unknown film is refused")
