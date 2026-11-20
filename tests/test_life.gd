extends RefCounted
## Life event tests (12.3): each event's conditions and effects, the story log, determinism and
## the save round trip. Percentages are forced to 100 for the event under test and 0 for the rest.

const TowerSim := preload("res://scripts/sim/tower.gd")
const LifeScript := preload("res://scripts/sim/life.gd")
const NamesScript := preload("res://scripts/sim/names.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")

const YOUNG := NamesScript.BAND_YOUNG
const ADULT := NamesScript.BAND_ADULT
const SENIOR := NamesScript.BAND_SENIOR
const FIELDS: Array[String] = ["couple_percent", "move_in_percent", "child_percent", "promotion_percent", "retire_percent", "leave_percent"]


## A name seed under which person ids 0, 1, 2 ... have the given age bands, or -1 if none is found.
static func _seed_for(bands: Array[int]) -> int:
	for candidate in 5000:
		var fits := true
		for id in bands.size():
			if NamesScript.age_band(candidate, id) != bands[id]:
				fits = false
		if fits:
			return candidate
	return -1


## Every event off except the one named (a percentage field of LifeScript), which is certain.
static func _only(life: LifeScript, field: String) -> void:
	for each in FIELDS:
		life.set(each, 100 if each == field else 0)


static func _kind_count(life: LifeScript, kind: int) -> int:
	var n := 0
	for k in life.story_count():
		if life.story(k)[1] == kind:
			n += 1
	return n


static func _last_room(t: TowerSim) -> int:
	return t.rooms.room_ids()[t.rooms.room_ids().size() - 1]


static func run(check: Callable) -> void:
	var adult_pair := _seed_for([ADULT, ADULT, YOUNG])
	var senior_seed := _seed_for([SENIOR, ADULT, ADULT, ADULT, ADULT, ADULT])
	check.call(adult_pair >= 0 and senior_seed >= 0, "life: test seeds with the wanted age bands exist")

	# Couples: two uncoupled adults in one condo pair up; nothing when the chance is 0.
	var t := TestEvaluation._pair("condo")
	t.names.name_seed = adult_pair
	_only(t.life, "couple_percent")
	t.life.couple_percent = 0
	t.life.daily(t)
	check.call(t.life.couple_count() == 0 and t.life.story_count() == 0, "life: no couple when the chance is 0")
	t.life.couple_percent = 100
	t.life.daily(t)
	check.call(t.life.partner_of(0) == 1 and t.life.partner_of(1) == 0 and t.life.partner_of(2) == -1, "life: two adults in a condo become a couple, a young third does not")
	var first := t.life.story(0)
	check.call(t.life.story_count() == 1 and first[1] == LifeScript.COUPLE and first[2] == 0 and first[3] == 1, "life: the couple is in the story log")
	check.call(t.life.describe(0, t.names).contains(" and ") and t.life.describe(0, t.names).ends_with("became a couple"), "life: the story reads as a sentence")
	t.life.daily(t)
	check.call(t.life.couple_count() == 1, "life: a coupled person is not paired again")

	# Moving in together: a couple in two condos shares one with room; the emptied condo is freed.
	var m := TestEvaluation._pair("condo")
	var second := _last_room(m)
	var first_condo: int = m.rooms.room_ids()[0]
	m.rooms.set_sold(second, true)
	var other: int = m.people.add_person(second, PeopleScript.NONE, m.rng)
	m.people.remove_person(m.people.index_of(2))
	m.people.remove_person(m.people.index_of(1))
	m.life.pair_up(0, other)
	_only(m.life, "move_in_percent")
	var balance := m.ledger.balance
	m.life.daily(m)
	check.call(m.people.home_of(m.people.index_of(other)) == first_condo, "life: the partner moves into the condo with room")
	check.call(not m.rooms.is_sold(second) and m.ledger.balance == balance - CatalogueScript.cost("condo"), "life: the emptied condo is vacant and the price paid back (a payout)")
	check.call(m.life.story(0)[1] == LifeScript.MOVE_IN and m.life.story(0)[4] == first_condo, "life: the move is logged with the new home")
	# A full condo cannot take them: the one with room does, and the other keeps its sale.
	var f := TestEvaluation._pair("condo")
	var f_second := _last_room(f)
	f.rooms.set_sold(f_second, true)
	var f_other: int = f.people.add_person(f_second, PeopleScript.NONE, f.rng)
	f.people.add_person(f_second, PeopleScript.NONE, f.rng)
	f.life.pair_up(0, f_other)
	_only(f.life, "move_in_percent")
	f.life.daily(f)
	check.call(f.people.home_of(f.people.index_of(0)) == f_second and f.rooms.is_sold(f.rooms.room_ids()[0]), "life: a full condo is not moved into; the other is, and the first stays sold")

	# Children: a couple in a condo with a free place has a child; a full condo has none.
	var c := TestEvaluation._pair("condo")
	c.names.name_seed = adult_pair
	c.people.remove_person(c.people.index_of(2))
	c.life.pair_up(0, 1)
	_only(c.life, "child_percent")
	c.life.daily(c)
	var kid: int = c.life.story(0)[3]
	check.call(c.life.story_count() == 1 and c.life.story(0)[1] == LifeScript.CHILD and c.life.is_child(kid) and c.people.count() == 3, "life: a couple with room gains a child")
	check.call(c.life.age_band(adult_pair, kid) == YOUNG and c.life.title_for(adult_pair, kid, "condo") == "Child", "life: the child is young and titled Child")
	c.life.daily(c)
	check.call(c.people.count() == 3 and c.life.story_count() == 1, "life: a full condo gains no further child")

	# Promotion: adult office workers only, with a senior title and a mood lift.
	var p := TestEvaluation._pair("office")
	p.names.name_seed = senior_seed
	_only(p.life, "promotion_percent")
	var mood_before := p.people.mood_of(p.people.index_of(1))
	p.life.daily(p)
	var promoted_ok := true
	for id in 6:
		if p.life.is_promoted(id) != (NamesScript.age_band(senior_seed, id) == ADULT):
			promoted_ok = false
	check.call(promoted_ok and p.life.is_promoted(1) and not p.life.is_promoted(0), "life: exactly the adult office workers are promoted")
	check.call(p.people.mood_of(p.people.index_of(1)) == mood_before + LifeScript.PROMOTION_MOOD, "life: a promotion lifts mood")
	check.call((NamesScript.TITLES["office"][SENIOR] as Array).has(p.life.title_for(senior_seed, 1, "office")), "life: a promoted worker has a senior title")
	var promotions := _kind_count(p.life, LifeScript.PROMOTION)
	p.life.daily(p)
	check.call(_kind_count(p.life, LifeScript.PROMOTION) == promotions, "life: nobody is promoted twice")

	# Retirement: a senior leaves the office and, with a condo place, stays as a resident.
	var r := TestEvaluation._pair("office")
	r.names.name_seed = senior_seed
	r.rooms.place_room(r.grid, r.floors, r.ledger, 0, CatalogueScript.IDS.find("condo"), 3, 135)
	var condo := _last_room(r)
	check.call(r.rooms.kind_of(condo) == "condo", "life: the condo for the retiree is placed")
	r.rooms.set_sold(condo, true)
	_only(r.life, "retire_percent")
	r.life.retire_stay_percent = 100
	var office: int = r.rooms.room_ids()[0]
	var workers := r.people.workers_in(office)
	r.life.daily(r)
	check.call(r.people.index_of(0) == -1 and r.people.workers_in(office) == workers - 1, "life: the senior retires out of the office, others stay")
	var story := r.life.story(0)
	check.call(story[1] == LifeScript.RETIREMENT and story[2] == 0 and story[3] != -1 and r.people.home_of(r.people.index_of(story[3])) == condo, "life: the retiree stays on as a resident of the condo")
	var n := TestEvaluation._pair("office")
	n.names.name_seed = senior_seed
	_only(n.life, "retire_percent")
	n.life.daily(n)
	check.call(n.life.story(0)[3] == -1 and n.people.index_of(0) == -1, "life: with no condo place the retiree simply leaves")

	# Leaving town: low mood for days, and only then.
	var l := TestEvaluation._pair("condo")
	l.life.pair_up(0, 1)
	l.people.set_mood(l.people.index_of(0), 5)
	l.people.set_low_days(l.people.index_of(0), LifeScript.LEAVE_LOW_DAYS)
	l.people.set_mood(l.people.index_of(1), 5)
	l.people.set_low_days(l.people.index_of(1), LifeScript.LEAVE_LOW_DAYS - 1)
	_only(l.life, "leave_percent")
	l.life.daily(l)
	check.call(l.people.index_of(0) == -1 and l.people.index_of(1) != -1 and l.people.index_of(2) != -1, "life: only the person with enough low days leaves town")
	check.call(l.life.story(0)[1] == LifeScript.LEFT_TOWN and l.life.story(0)[2] == 0 and l.life.partner_of(1) == -1, "life: it is logged and the couple ends")

	# The log keeps only the last LOG_MAX stories.
	var ring := LifeScript.new()
	for k in LifeScript.LOG_MAX + 10:
		ring._record(k, LifeScript.COUPLE, k, k + 1, 0)
	check.call(ring.story_count() == LifeScript.LOG_MAX and ring.story(0)[0] == 10 and ring.story(LifeScript.LOG_MAX - 1)[0] == LifeScript.LOG_MAX + 9, "life: the log keeps the last 50 stories, oldest dropped")

	# Save round trip and validation.
	var saved := TestEvaluation._pair("condo")
	saved.names.name_seed = adult_pair
	_only(saved.life, "couple_percent")
	saved.life.daily(saved)
	saved.life._kids.append(2)
	saved.life._promoted.append(0)
	var copy := TowerSim.new(7)
	check.call(copy.load_state(saved.save()) and copy.life.state_ints() == saved.life.state_ints() and copy.life.partner_of(0) == 1 and copy.life.is_child(2) and copy.life.is_promoted(0) and copy.life.story_count() == 1, "life: couples, children, promotions and the log survive save and load")
	check.call(LifeScript.valid_ints(saved.life.state_ints()) and not LifeScript.valid_ints([1, 5]) and not LifeScript.valid_ints([0, 0, 0, 1, 0, 9, 0, 0, 0]), "life: saved ints are validated")

	# Determinism: the same tower and days give the same result, with the chances in the middle.
	var one := TestEvaluation._pair("condo")
	var two := TestEvaluation._pair("condo")
	for tower: TowerSim in [one, two]:
		tower.names.name_seed = adult_pair
		for field in FIELDS:
			tower.life.set(field, 50)
		for day in 5:
			tower.life.daily(tower)
	check.call(one.state_hash() == two.state_hash(), "life: the same tower lives the same days")

	# The person window shows a partner.
	var w := TestEvaluation._pair("condo")
	w.life.pair_up(0, 1)
	check.call("\n".join(PersonInfo.lines_for(PersonInfo.describe(w, 0))).contains("Partner: %s" % w.names.name_of(1)), "life: the person window names the partner")
