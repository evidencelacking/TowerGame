extends RefCounted
## The hospital (#377): the four catalogue rows and their needs, the needs check (degraded service, never a blocked
## build), the daily patient income, the care rule for assisted living, the medical demand an emergency room meets, the
## toolbar and room panel, and that a tower without the new kinds plays exactly as before. Our own kinds: every number is
## a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Names := preload("res://scripts/sim/names.gd")
const Hospital := preload("res://scripts/sim/hospital.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Demands := preload("res://scripts/sim/demands.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const StarRules := preload("res://scripts/sim/star_rules.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")

const DAY_TICKS := 2550
const KINDS: Array[String] = ["emergency_room", "operating_room", "imaging", "patient_ward"]
## state_hash of old_tower_hash() taken on main before the hospital existed (office, condo, clinic, medical, assisted).
const OLD_TOWER_HASH := -8559877193199727974


static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


## A tower with a shaft from the lobby to floor 11 and floors 3 to 11 built; rooms are [kind, floor, x] triples.
static func _tower(rooms: Array = []) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in range(3, 12):
		t.floors.fill_span(f, 100, 163)
	for r: Array in rooms:
		assert(_place(t, r[0], r[1], r[2]) == 0, "%s places" % r[0])
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, 11, 100)
	t.rooms.add_car(t.ledger, 0, 3, t.rooms._shaft_base(t.rooms.link_at(1, 100)), 1)
	t.step()
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


static func _income(t: TowerSim) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == t.ledger.INCOME:
			total += line[1]
	return total


## The scenario the old-tower regression runs: no hospital room, but the rooms its rules read (office, condo, clinic,
## medical center, assisted living, a shaft), a fixed seed, three days.
static func old_tower_hash() -> int:
	var t := _tower([["office", 3, 110], ["condo", 4, 110], ["clinic", 5, 110], ["medical", 6, 110], ["assisted", 7, 110]])
	t.clock.set_to_tick(0)
	for n in 3 * DAY_TICKS:
		t.step()
	return t.state_hash()


static func run(check: Callable) -> void:
	# Catalogue: four rows appended after the existing ids, placeable, titled, star 4, in the hospital group.
	var ids := Catalogue.IDS
	var tail_ok := true
	for k in KINDS.size():
		tail_ok = tail_ok and ids[ids.size() - KINDS.size() - 2 + k] == KINDS[k]  # the bowling alley and arcade (#324) come after
	check.call(tail_ok and ids.find("assisted") == ids.size() - KINDS.size() - 3, "ids: the hospital kinds are appended last, after assisted living")
	var placeable_tail := Rooms.PLACEABLE.slice(Rooms.PLACEABLE.size() - KINDS.size())
	check.call(placeable_tail == KINDS, "placeable: the hospital kinds are appended last")
	for kind: String in KINDS:
		check.call(Rooms.PLACEABLE.has(kind) and Names.TITLES.has(kind) and Catalogue.star(kind) == 4 and Catalogue.is_hospital(kind) and Catalogue.display_name(kind) != kind, "%s: placeable, titled, star 4, a hospital room with a display name" % kind)
	check.call(not Catalogue.row("emergency_room").has("needs") and Catalogue.row("operating_room")["needs"][0][0] == "emergency_room" and Catalogue.row("imaging")["needs"][0][0] == "emergency_room" and Catalogue.row("patient_ward")["needs"][0][0] == "operating_room", "needs: the emergency room needs nothing, the operating room and imaging need it, the ward needs an operating room")
	check.call(not Catalogue.is_hospital("clinic") and not Catalogue.is_hospital("medical"), "is_hospital: the four kinds only")
	var reqs := str(StarRules.REQUIREMENTS)
	check.call(not reqs.contains("hospital") and not reqs.contains("emergency") and not reqs.contains("ward"), "stars: the hospital is not a star requirement")

	# Needs: within 6 floors meets, 7 does not; it only degrades, the build still succeeds.
	var t := _tower([["emergency_room", 3, 110], ["operating_room", 9, 110], ["imaging", 4, 110], ["patient_ward", 10, 110]])
	var er := _room(t, "emergency_room")
	var op := _room(t, "operating_room")
	var img := _room(t, "imaging")
	var ward := _room(t, "patient_ward")
	check.call(er >= 0 and not t.rooms.service_degraded(t.grid, er) and not t.rooms.service_degraded(t.grid, op) and not t.rooms.service_degraded(t.grid, img) and not t.rooms.service_degraded(t.grid, ward), "needs: a full chain within 6 floors has no degraded room")
	var far := _tower([["emergency_room", 3, 110], ["operating_room", 10, 110]])
	var far_op := _room(far, "operating_room")
	check.call(far.rooms.service_degraded(far.grid, far_op) and far.rooms.unmet_needs(far.grid, far_op) == ["emergency_room"], "needs: an operating room 7 floors from the emergency room is degraded and names what it lacks")
	var alone := _tower([["operating_room", 5, 110], ["imaging", 6, 110], ["patient_ward", 7, 110]])
	var alone_op := _room(alone, "operating_room")
	check.call(alone_op >= 0 and alone.rooms.service_degraded(alone.grid, alone_op) and alone.rooms.service_degraded(alone.grid, _room(alone, "imaging")), "needs: a dependent room builds without its supplier and is degraded")
	var no_op := _tower([["emergency_room", 3, 110], ["patient_ward", 6, 110]])
	check.call(no_op.rooms.unmet_needs(no_op.grid, _room(no_op, "patient_ward")) == ["operating_room"], "needs: a ward with no operating room lacks an operating room")
	check.call(t.rooms.bulldoze(t.grid, t.floors, t.ledger, 0, 3, 110) == 0 and t.rooms.service_degraded(t.grid, op) and t.rooms.service_degraded(t.grid, img) and not t.rooms.service_degraded(t.grid, ward), "needs: losing the emergency room degrades the rooms that need it, not the ward")
	var burned := _tower([["emergency_room", 3, 110], ["operating_room", 4, 110]])
	check.call(not burned.rooms.service_degraded(burned.grid, _room(burned, "operating_room")), "needs: an operating room beside a working emergency room is fine")
	burned.rooms.charred[_room(burned, "emergency_room")] = true
	check.call(burned.rooms.service_degraded(burned.grid, _room(burned, "operating_room")), "needs: a burned-out emergency room no longer serves")
	check.call(RoomLook.describe(alone, alone_op)["state"] == RoomLook.DEGRADED and RoomLook.describe(far, _room(far, "emergency_room"))["state"] != RoomLook.DEGRADED, "look: a degraded room shows as degraded, a working one does not")
	var lines := RoomInfo.lines_for(RoomInfo.describe(alone, alone_op))
	check.call(lines.any(func(l: String) -> bool: return l.contains("Service degraded") and l.contains("Emergency Room")), "panel: the room panel says what the degraded room needs")

	# Patients and income: pure numbers first.
	check.call(Hospital.admissions(1, 0, false) == [0, 3] and Hospital.admissions(1, 0, true) == [0, 6] and Hospital.admissions(1, 20, true) == [8, 0] and Hospital.admissions(2, 5, false) == [5, 6], "patients: tower patients first, then outsiders, up to 8 places an emergency room, a helipad adds outsiders")
	check.call(Hospital.day_income(8, 0, 0, 0) == 8 * Hospital.ER_FEE, "income: patients alone pay the emergency room fee")
	check.call(Hospital.day_income(8, 1, 1, 1) == 8 * 1500 + 2 * 8000 + 4 * 800 + 2 * 3000, "income: surgery, scans and ward stays add to each admitted patient (%d)" % Hospital.day_income(8, 1, 1, 1))
	check.call(Hospital.day_income(8, 5, 5, 5) == Hospital.day_income(8, 1, 1, 1) and Hospital.day_income(8, 0, 1, 1) < Hospital.day_income(8, 1, 1, 1), "income: spare rooms add nothing past the patients, a missing operating room costs the surgery and stay fees")
	check.call(Hospital.day_income(8, 5, 5, 0) < Hospital.day_income(8, 5, 5, 5), "income: no ward, no stay fees")

	# Collect on a tower: the emergency room alone, then with the chain, then with a low-mood patient.
	var solo := _tower([["emergency_room", 3, 110]])
	var before := _income(solo)
	var paid := Hospital.collect(solo.rooms, solo.grid, solo.people, solo.ledger, 0)
	check.call(paid == 3 * Hospital.ER_FEE and _income(solo) - before == paid, "collect: a lone emergency room earns three outside patients a day (%d)" % paid)
	var full := _tower([["emergency_room", 3, 110], ["operating_room", 5, 110], ["imaging", 4, 110], ["patient_ward", 6, 110]])
	var paid_full := Hospital.collect(full.rooms, full.grid, full.people, full.ledger, 0)
	check.call(paid_full == Hospital.day_income(3, 1, 1, 1) and paid_full > paid, "collect: the chain earns more than the emergency room alone (%d)" % paid_full)
	check.call(Hospital.collect(alone.rooms, alone.grid, alone.people, alone.ledger, 0) == 0, "collect: no emergency room, no income, whatever else stands")
	var broken_chain := _tower([["emergency_room", 3, 110], ["operating_room", 10, 110]])
	check.call(Hospital.collect(broken_chain.rooms, broken_chain.grid, broken_chain.people, broken_chain.ledger, 0) == 3 * Hospital.ER_FEE, "collect: a degraded operating room adds nothing")
	var sick := _tower([["emergency_room", 3, 110], ["condo", 4, 110]])
	var who := sick.people.add_person(_room(sick, "condo"), People.NONE, sick.rng)
	var i := sick.people.index_of(who)
	sick.people.set_mood(i, Hospital.PATIENT_MOOD_BELOW - 1)
	check.call(Hospital.tower_patients(sick.people) == 1, "patients: a person in a low mood is a patient")
	check.call(Hospital.collect(sick.rooms, sick.grid, sick.people, sick.ledger, 0) == 4 * Hospital.ER_FEE, "collect: a tower patient takes a place and the three outsiders still come")
	sick.people.set_mood(i, Hospital.PATIENT_MOOD_BELOW)
	check.call(Hospital.tower_patients(sick.people) == 0, "patients: a person at the threshold is not a patient")

	# Care for assisted living: a hospital room counts like a clinic.
	for kind: String in KINDS:
		check.call(Synergy.CARE_KINDS.has(kind) and Synergy.has_care([3, 110, 14], [[kind, [5, 110, 12]]]), "care: a %s within 5 floors is care for assisted living" % kind)
	var home := _tower([["assisted", 3, 110], ["emergency_room", 5, 130]])
	check.call(not home.complaint_reasons(_room(home, "assisted")).has(Complaints.NO_CARE), "care: an assisted-living room with an emergency room near has no care complaint")
	var bare := _tower([["assisted", 3, 110]])
	check.call(bare.complaint_reasons(_room(bare, "assisted")).has(Complaints.NO_CARE), "care: the same room with no care at all has the complaint")

	# The medical demand: an emergency room counts as a medical center.
	var buildable: Array[String] = ["medical"]
	var medical_bit := 1 << (Demands.MEDICAL - 1)
	check.call(Demands.compute(4, {"office": 20}, buildable) & medical_bit != 0, "demand: twenty offices and no medical center want one")
	check.call(Demands.compute(4, {"office": 20, "emergency_room": 1}, buildable) & medical_bit == 0, "demand: an emergency room meets the medical demand")
	check.call(Demands.compute(4, {"office": 21, "emergency_room": 1}, buildable) & medical_bit != 0, "demand: one emergency room covers twenty offices, not twenty-one")

	# Toolbar: the four join Services (a new category would push the tools off the bar), with a tip for each.
	var cat: Array = []
	for c: Array in Toolbar.CATEGORIES:
		if c[0] == "Services":
			cat = c[1]
	var tips := true
	for kind: String in KINDS:
		tips = tips and String(Toolbar.TOOL_TIPS.get(kind, "")) != ""
	check.call(cat.slice(cat.size() - KINDS.size()) == KINDS and tips, "toolbar: the Services category ends with the four hospital kinds, each with a tip")

	# Old towers: the same state_hash as before the hospital existed.
	var hash_now := old_tower_hash()
	check.call(OLD_TOWER_HASH != 0 and hash_now == OLD_TOWER_HASH, "regression: an old tower without hospital rooms keeps its state_hash (%d)" % hash_now)

	# A fixed-seed run: two runs agree, the hospital pays the emergency room's account, and the tower saves and loads.
	var layout: Array = [["emergency_room", 3, 110], ["operating_room", 5, 110], ["imaging", 4, 110], ["patient_ward", 6, 110]]
	var x := _tower(layout)
	var y := _tower(layout)
	for tower: TowerSim in [x, y]:
		tower.clock.set_to_tick(0)
		for n in 3 * DAY_TICKS:
			tower.step()
	var er_x := _room(x, "emergency_room")
	var from_er := 0
	for line: Array in x.ledger.lines:
		if line[2] == x.ledger.INCOME and line[3] == er_x:
			from_er += line[1]
	check.call(from_er > 0 and x.state_hash() == y.state_hash(), "seeded run: patients pay the emergency room's account and two runs agree (%d)" % from_er)
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(x.save()) and copy.state_hash() == x.state_hash(), "save: a tower with the hospital survives save and load")
