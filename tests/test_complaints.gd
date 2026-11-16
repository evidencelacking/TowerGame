extends RefCounted
## Complaint reason tests (5.7): noise (condos and hotels, never office beside office), distance,
## rent, clearing when the cause goes, priority and tie-breaking, determinism, and noise wired
## into the grade.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const NoiseSim := preload("res://scripts/sim/noise.gd")
const Rent := preload("res://scripts/sim/rent.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(7, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	for f in range(2, 9):
		t.floors.fill_span(f, 100, 131)
	return t


## Places a room and returns its id, or -1 when it was not placed.
static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	var before := t.rooms.room_ids().size()
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x)
	var ids := t.rooms.room_ids()
	return ids[ids.size() - 1] if ids.size() > before else -1


## Puts a kind that cannot be placed yet (hotel, communal) straight into the grid and kind table.
static func _inject(t: TowerSim, id: int, kind: String, floor_number: int, x: int) -> void:
	t.grid.place(id, floor_number, x, CatalogueScript.field(kind, "width"))
	t.rooms._kind_of[id] = CatalogueScript.IDS.find(kind)


## Sets the room's occupants (two) to the stress, adding them first if the room has none, and
## marks them as having made a trip.
static func _occupy(t: TowerSim, room: int, stress: int) -> void:
	var work := t.rooms.kind_of(room) == "office"
	var tripped: Array[int] = [0]
	for i in t.people.count():
		var mine := t.people.work_of(i) == room if work else t.people.home_of(i) == room
		if mine:
			t.people.set_stress(i, stress)
			tripped.append(t.people.id_at(i))
	if tripped.size() == 1:
		for k in 2:
			var i := t.people.add_person(-1 if work else room, room if work else -1, t.rng)
			t.people.set_stress(i, stress)
			tripped.append(t.people.id_at(i))
	tripped[0] = tripped.size() - 1
	t.grades.load_ints(tripped)


static func run(check: Callable) -> void:
	# Noise: a condo beside an office is disturbed; the office beside it is not.
	var t := _tower()
	var condo := _place(t, "condo", 4, 100)
	var office := _place(t, "office", 4, 116)  # touching
	check.call(condo >= 0 and office >= 0, "complaints: condo and office placed")
	check.call(t.complaint_reason(condo) == Complaints.NOISE, "complaints: a condo beside an office is noisy")
	check.call(t.complaint_reasons(condo) == [Complaints.NOISE], "complaints: noise is the only reason listed")
	check.call(t.complaint_reason(office) == Complaints.NONE, "complaints: the office beside a condo has no reason")
	check.call(Complaints.label(Complaints.NOISE) != "" and Complaints.label(Complaints.NONE) == "", "complaints: labels exist for reasons only")

	# Office next to office: no noise reason (K).
	var t2 := _tower()
	var a := _place(t2, "office", 4, 100)
	var b := _place(t2, "office", 4, 109)
	check.call(t2.complaint_reason(a) == Complaints.NONE and t2.complaint_reason(b) == Complaints.NONE, "complaints: office beside office shows no noise reason")

	# Hotels count, and communal spaces are sources (party hall above a hotel room).
	var t3 := _tower()
	var hotel := 5000
	_inject(t3, hotel, "hotel_single", 4, 100)
	_inject(t3, 5001, "party_hall", 5, 100)
	check.call(t3.rooms.kind_of(hotel) == "hotel_single", "complaints: hotel and party hall injected")
	check.call(t3.complaint_reason(hotel) == Complaints.NOISE, "complaints: a party hall above disturbs a hotel room")
	var t3b := _tower()
	var hotel_b := 5000
	_inject(t3b, hotel_b, "hotel_single", 4, 100)
	_inject(t3b, 5001, "movie_theatre", 5, 100)
	check.call(t3b.complaint_reason(hotel_b) == Complaints.NOISE, "complaints: a movie theatre is a communal source too")

	# Noise is wired into the grade: stress 100 and noise level n gives quality 200 - 5n.
	var t4 := _tower()
	var c4 := _place(t4, "condo", 4, 100)
	_occupy(t4, c4, 100)
	check.call(t4.quality(c4) == 200, "complaints: a quiet condo at stress 100 is quality 200")
	var o4 := _place(t4, "office", 4, 116)
	var level := NoiseSim.noise_at(t4.grid, t4.rooms, c4)
	check.call(o4 >= 0 and level == 3, "complaints: the office touching the condo makes noise level 3")
	check.call(t4.quality(c4) == 200 - NoiseSim.STRESS_PER_NOISE_LEVEL * level, "complaints: noise lowers the grade by its stress")
	check.call(NoiseSim.STRESS_PER_NOISE_LEVEL > 0, "complaints: noise stress is on")
	check.call(t4.grid.remove(o4), "complaints: office removed")
	t4.rooms._kind_of.erase(o4)
	check.call(t4.quality(c4) == 200 and t4.complaint_reason(c4) != Complaints.NOISE, "complaints: removing the source clears the noise and its stress")

	# Distance: high travel stress and no other cause.
	var t5 := _tower()
	var c5 := _place(t5, "condo", 4, 100)
	_occupy(t5, c5, Complaints.DISTANCE_FROM - 1)
	check.call(t5.complaint_reason(c5) == Complaints.NONE, "complaints: stress just under the line is content")
	_occupy(t5, c5, Complaints.DISTANCE_FROM)
	check.call(t5.complaint_reason(c5) == Complaints.DISTANCE, "complaints: a far unit with travel stress shows distance")

	# Rent: a high-rent office with low stress shows rent; lowering it clears the reason.
	var t6 := _tower()
	var o6 := _place(t6, "office", 4, 100)
	_occupy(t6, o6, 10)
	check.call(t6.complaint_reason(o6) == Complaints.NONE, "complaints: an average-rent office with low stress is content")
	check.call(t6.rent.set_rent(t6.rooms, o6, Rent.LEVEL_HIGH) == Rent.OK, "complaints: rent raised")
	check.call(t6.complaint_reason(o6) == Complaints.RENT, "complaints: a max-rent office with good stress shows rent")
	check.call(t6.rent.set_rent(t6.rooms, o6, Rent.LEVEL_GREEN) == Rent.OK, "complaints: rent lowered")
	check.call(t6.complaint_reason(o6) == Complaints.NONE, "complaints: lowering rent clears the rent reason")
	t6.rent.set_rent(t6.rooms, o6, Rent.LEVEL_HIGH)
	check.call(t6.complaint_reason(o6) == Complaints.RENT, "complaints: restoring the rent brings the reason back")

	# Tie-breaking: several causes at once list in priority order, the first is the main one.
	_occupy(t6, o6, 150)
	check.call(t6.complaint_reasons(o6) == [Complaints.DISTANCE, Complaints.RENT], "complaints: distance outranks rent")
	check.call(t6.complaint_reason(o6) == Complaints.DISTANCE, "complaints: the main reason is the highest priority")
	var t7 := _tower()
	var c7 := _place(t7, "condo", 4, 100)
	_place(t7, "office", 4, 116)
	_occupy(t7, c7, 150)
	check.call(t7.complaint_reasons(c7) == [Complaints.NOISE, Complaints.DISTANCE], "complaints: noise outranks distance")
	check.call(t7.complaint_reason(c7) == Complaints.NOISE, "complaints: noise is the main reason when both apply")

	# Unknown ids have no reason; the same tower gives the same answer.
	check.call(t7.complaint_reason(-5) == Complaints.NONE and t7.complaint_reasons(9999).is_empty(), "complaints: unknown rooms have no reason")
	check.call(t7.complaint_reasons(c7) == t7.complaint_reasons(c7), "complaints: repeatable")
