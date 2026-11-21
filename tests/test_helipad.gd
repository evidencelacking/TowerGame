extends RefCounted
## The helicopter pad (#409): a roof-only room, one per tower, from 3 stars. Placement and its refusals, the
## fire rescue it discounts and speeds, the VIP's air arrival, the daily income while it is reachable, and the
## noise it makes for the rooms below. Our own design: every number is an unverified tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const FireScript := preload("res://scripts/sim/fire.gd")
const VipScript := preload("res://scripts/sim/vip.gd")
const HelipadScript := preload("res://scripts/sim/helipad.gd")
const NoiseSim := preload("res://scripts/sim/noise.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestFire := preload("res://tests/test_fire.gd")
const TestVip := preload("res://tests/test_vip.gd")
const TestHotel := preload("res://tests/test_hotel.gd")

const DAY_TICKS := 2550  ## Clock.PERIOD_n_TICKS added up.
const FIRE_SEEDS := 20  ## Seeds tried for a fire that does not start in the pad itself.
const VIP_SEEDS := 40


## Lobby on floors 1-2, floors 3 to 6 built, stairs up from the lobby to floor `reach` (3 to 6), an office on
## floor 5 so floor 6 is the roof. The pad goes on floor 6 at column 130 when `pad` is set.
static func _tower(reach: int, pad: bool = true, seed_value: int = 42) -> TowerSim:
	var t := TowerSim.new(seed_value, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for floor_number in [3, 4, 5, 6]:
		t.floors.fill_span(floor_number, 100, 163)
	_put(t, "office", 5, 100)
	t.stars = 3
	for floor_number in range(1, reach):
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, floor_number, 100 + 4 * (floor_number - 1))
	if pad:
		var refusal := _put(t, "helipad", 6, 130)
		assert(refusal == Rooms.OK, "the pad places, refusal %d" % refusal)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _income_lines(t: TowerSim, room: int) -> int:
	var n := 0
	for line: Array in t.ledger.lines:
		if line[2] == Ledger.INCOME and line[3] == room and line[1] == HelipadScript.DAILY_INCOME:
			n += 1
	return n


## A fire tower: a security office on floor 3, an office on floor 5, a pad on floor 6 (reachable, or cut off).
## Tries seeds until a fire breaks out in a room other than the pad; returns that tower with the fire burning.
static func _burning_tower(reachable: bool) -> TowerSim:
	for seed_value in range(1, FIRE_SEEDS + 1):
		var t := _tower(6 if reachable else 4, true, seed_value)
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("security"), 3, 120)
		TestFire._force(t)
		if TestFire._until_burning(t) and t.rooms.kind_of(t.fire.burning_rooms()[0]) != "helipad":
			return t
	return null


## Pays for the rescue; returns [dollars charged, ticks until the craft arrives, a full period's ticks].
static func _pay(t: TowerSim) -> Array[int]:
	var balance := t.ledger.balance
	var event_id: int = t.events.open_events()[0][0]
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [event_id, FireScript.PAY] as Array[int]))
	t.step()
	return [balance - t.ledger.balance, t.fire.rescue_at() - t.tick, Clock.period_ticks(t.clock.period() - 1)] as Array[int]


## The VIP test tower with no parking, plus a floor 4 and (optionally) a pad on it that stairs from floor 3 reach.
static func _vip_tower(seed_value: int, pad: bool) -> TowerSim:
	var t := TestVip._tower({"stress": 0}, false)
	t.vip.reseed(seed_value)
	t.floors.fill_span(4, 100, 131)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 3, 100)
	if pad:
		_put(t, "helipad", 4, 112)
	t.step()
	return t


static func run(check: Callable) -> void:
	# The catalogue row and the build menu.
	var row: Dictionary = Catalogue.row("helipad")
	check.call(int(row["cost"]) == 400000 and Catalogue.star("helipad") == 3 and int(row["height"]) == 1, "helipad: $400,000, star 3, one floor")
	check.call(Clock.DAYS_PER_QUARTER == 3 and int(row["upkeep"]) == 2000 * Clock.DAYS_PER_QUARTER, "helipad: $2,000 a day upkeep is $6,000 a quarter")
	check.call(Rooms.PLACEABLE.has("helipad"), "helipad: it is placeable")
	check.call(ToolbarScript.item_state("helipad", 2)["locked"] and not ToolbarScript.item_state("helipad", 3)["locked"], "helipad: locked before star 3, open at star 3")
	check.call(String(ToolbarScript.TOOL_TIPS.get("helipad", "")).contains("$300,000") and Ghost.ROOM_TEXT.has(Rooms.ONE_HELIPAD), "helipad: the tooltip explains the hooks and the ghost explains the one-pad rule")

	# Placement: the top floor only, one per tower, never below ground.
	var t := _tower(6, false)
	var low := t.rooms.check_place(t.grid, t.floors, "helipad", 4, 130)
	check.call(low["reason"] == Rooms.NOT_TOP, "helipad: refused below a room (%d)" % low["reason"])
	check.call(_put(t, "helipad", 5, 130) == Rooms.OK, "helipad: places on the top floor")
	var again := t.rooms.check_place(t.grid, t.floors, "helipad", 5, 146)
	check.call(again["reason"] == Rooms.ONE_HELIPAD, "helipad: a second pad is refused (%d)" % again["reason"])
	var below := t.rooms.check_place(t.grid, t.floors, "helipad", -1, 130)
	check.call(below["reason"] != Rooms.OK, "helipad: never below ground")

	# Income: $5,000 a day through the ledger while reachable, none while cut off.
	var reach := _tower(6)
	var pad := reach.rooms.helipad_id()
	reach.step()
	check.call(pad != 0 and reach.rooms.helipad_reachable() and not reach.rooms.is_cut_off(pad), "helipad: stairs all the way up reach it")
	check.call(HelipadScript.collect(reach.rooms, reach.ledger, reach.tick) == 5000 and _income_lines(reach, pad) == 1, "helipad: a reachable pad credits $5,000 through the ledger")
	var cut := _tower(4)
	cut.step()
	var cut_pad := cut.rooms.helipad_id()
	check.call(cut.rooms.is_cut_off(cut_pad) and not cut.rooms.helipad_reachable(), "helipad: with no route to floor 6 it is cut off")
	check.call(HelipadScript.collect(cut.rooms, cut.ledger, cut.tick) == 0 and _income_lines(cut, cut_pad) == 0, "helipad: a cut-off pad earns nothing")
	var days := _tower(6)
	var days_cut := _tower(4)
	for _n in 3 * DAY_TICKS + 100:  # three days, bounded
		days.step()
		days_cut.step()
	check.call(_income_lines(days, days.rooms.helipad_id()) >= 2, "helipad: over the days the tower runs, the daily income arrives (%d lines)" % _income_lines(days, days.rooms.helipad_id()))
	check.call(_income_lines(days_cut, days_cut.rooms.helipad_id()) == 0, "helipad: a cut-off pad earns nothing as the days pass")

	# Noise: condos up to 3 floors below the pad, not the 4th, not offices, not above; falling off with distance.
	var noisy := TowerSim.new(7, 1000000000)
	noisy.floors.build_lobby(noisy.ledger, 0, 1, 100, 163, 2)
	for floor_number in range(3, 10):
		noisy.floors.fill_span(floor_number, 100, 163)
	var placed := _put(noisy, "helipad", 9, 100)
	for floor_number in [8, 7, 6, 5]:
		placed += _put(noisy, "condo", floor_number, 100)
	placed += _put(noisy, "office", 8, 120)
	check.call(placed == Rooms.OK, "helipad: the noise test rooms place")
	var level_8 := NoiseSim.noise_at(noisy.grid, noisy.rooms, noisy.grid.cell_at(8, 100))
	var level_6 := NoiseSim.noise_at(noisy.grid, noisy.rooms, noisy.grid.cell_at(6, 100))
	var level_5 := NoiseSim.noise_at(noisy.grid, noisy.rooms, noisy.grid.cell_at(5, 100))
	check.call(level_8 > level_6 and level_6 > 0, "helipad: a condo one floor below is disturbed, more than one three floors below (%d, %d)" % [level_8, level_6])
	check.call(level_5 == 0, "helipad: the fourth floor below is out of reach (%d)" % level_5)
	check.call(NoiseSim.noise_at(noisy.grid, noisy.rooms, noisy.grid.cell_at(8, 120)) == 0, "helipad: an office is not disturbed")
	check.call(NoiseSim.level_among("condo", [10, 100, 16], [["helipad", [9, 100, 16]]]) == 0, "helipad: a room above the pad hears nothing")
	check.call(NoiseSim.level_among("hotel_single", [7, 100, 10], [["helipad", [9, 100, 16]]]) > 0, "helipad: hotel rooms are disturbed too")

	# Fire: the paid rescue costs $300,000 and arrives in half the time while the pad is reachable.
	var plain := TestFire._uncovered(3)
	check.call(plain.fire.rescue_cost() == 500000 and plain.events.kind_def(FireScript.KIND)["costs"] == [0, 500000], "helipad: with no pad the rescue costs $500,000")
	var guarded := _burning_tower(true)
	var unguarded := _burning_tower(false)
	check.call(guarded != null and unguarded != null, "helipad: a fire starts outside the pad in both fire towers")
	if guarded == null or unguarded == null:
		return
	check.call(guarded.fire.rescue_cost() == 300000 and guarded.events.kind_def(FireScript.KIND)["costs"] == [0, 300000], "helipad: a reachable pad makes the rescue $300,000")
	var def: Dictionary = guarded.events.kind_def(FireScript.KIND)
	check.call(String(def["text"]).contains("$300,000") and String((def["labels"] as Array)[1]).contains("$300,000") and not String(def["text"]).contains("$500,000"), "helipad: the fire's text and labels show the pad's price")
	check.call(unguarded.fire.rescue_cost() == 500000, "helipad: a cut-off pad does not discount the rescue")
	var plain_def: Dictionary = unguarded.events.kind_def(FireScript.KIND)
	check.call(String(plain_def["text"]).contains("$500,000") and String((plain_def["labels"] as Array)[1]).contains("$500,000"), "helipad: the plain price shows without a reachable pad")
	var with_pad := _pay(guarded)
	var without_pad := _pay(unguarded)
	check.call(with_pad[0] == 300000 and without_pad[0] == 500000, "helipad: paying charges $300,000 with the pad, $500,000 without (%d, %d)" % [with_pad[0], without_pad[0]])
	check.call(with_pad[1] > 0 and with_pad[1] * 2 <= with_pad[2] + 1 and with_pad[1] * 2 >= with_pad[2] - 1, "helipad: the rescue arrives in half a period (%d of %d ticks)" % [with_pad[1], with_pad[2]])
	check.call(without_pad[1] == without_pad[2], "helipad: without the pad it takes the full period (%d of %d)" % [without_pad[1], without_pad[2]])
	for _i in with_pad[1] + 2:
		guarded.step()
	check.call(guarded.fire.burning_rooms().is_empty(), "helipad: the craft has arrived and the fire is out")

	# VIP: over seeds, a day drawn "by air" with a reachable pad starts the visit with no parking space.
	var drawn_air := 0
	var air_visits := 0
	var ground_visits := 0
	for seed_value in VIP_SEEDS:
		var v := _vip_tower(seed_value, true)
		TestHotel._jump(v, 17 * 60 + 30, 0)
		TestHotel._step_to(v, 19 * 60, 0)
		var air := v.vip.state_ints()[8] == 1  # the draw made for that day
		if air:
			drawn_air += 1
			if v.vip.is_visiting():
				air_visits += 1
		elif v.vip.is_visiting():
			ground_visits += 1
	check.call(drawn_air > 8 and drawn_air < 32, "helipad: about half the seeds draw an air arrival (%d of %d)" % [drawn_air, VIP_SEEDS])
	check.call(air_visits == drawn_air, "helipad: every air arrival starts a visit with no parking space (%d of %d)" % [air_visits, drawn_air])
	check.call(ground_visits == 0, "helipad: a day not drawn by air still needs a parking space, and there is none")
	var no_pad := _vip_tower(1, false)
	TestHotel._jump(no_pad, 17 * 60 + 30, 0)
	TestHotel._step_to(no_pad, 19 * 60, 0)
	check.call(not no_pad.vip.is_visiting(), "helipad: with no pad a VIP with no parking space stays away")
	var a := _vip_tower(1, true)
	var b := _vip_tower(1, false)
	for tower: TowerSim in [a, b]:
		TestHotel._jump(tower, 17 * 60 + 30, 0)
		TestHotel._step_to(tower, 19 * 60, 0)
	check.call(a.vip.state_ints()[6] == b.vip.state_ints()[6], "helipad: the stream is drawn the same with and without a pad")
	check.call(VipScript.valid_ints(a.vip.state_ints()) and not VipScript.valid_ints([0, -1, -1, 0, 0, 0]), "helipad: the VIP's saved state carries its stream, and the old shape is refused")
