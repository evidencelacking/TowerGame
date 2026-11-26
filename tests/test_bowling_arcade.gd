extends RefCounted
## The bowling alley and the arcade (#324, our own design, every number a tunable): catalogue rows, the star unlock, placement,
## the hours each is open and the weekend peak of outside visitors, the entry fees credited at settlement, a room no route
## reaches earning nothing, the grade, noise, the build menu, both looks, and a save round trip (v54, with its migration step).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const Names := preload("res://scripts/sim/names.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Migration := preload("res://scripts/sim/save_migration.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")

const BOWL_X := 110
const ARCADE_X := 140


## Lobby on floors 1-2, floor 3 above it joined by stairs (so it is reachable), unless stairs is false.
static func _tower(stairs: bool = true) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 199, 2)
	t.floors.fill_span(3, 100, 199)
	if stairs:
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _put(t: TowerSim, kind: String, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


## The start minutes of a kind's waves, in MEALS order.
static func _waves(kind: String) -> Array[int]:
	var out: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == kind:
			out.append(meal[0])
	return out


## One wave of a kind (its index among the kind's MEALS rows) on a day, at the wave's own window and percent.
static func _wave(t: TowerSim, kind: String, index: int, day: int) -> void:
	var rows: Array = []
	for row: Array in Commerce.MEALS:
		if row[3] == kind:
			rows.append(row)
	var meal: Array = rows[index]
	t.commerce._serve(kind, meal[1], meal[2], t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, meal[0], t.life)


static func _settle(t: TowerSim) -> int:
	var before := t.ledger.balance
	t.commerce._settle(t.floors, t.rooms, t.grid, t.tenancy, t.ledger, t.messages, t.tick, t.rng)
	return t.ledger.balance - before


static func run(check: Callable) -> void:
	# Catalogue rows: our numbers, the star each unlocks at, wider than a shop but narrower than the theatre.
	var bowl: Dictionary = Catalogue.row("bowling")
	var arc: Dictionary = Catalogue.row("arcade")
	check.call(int(bowl["width"]) == 24 and int(bowl["height"]) == 1 and int(bowl["cost"]) == 160000 and Catalogue.star("bowling") == 3 and bool(bowl["removable"]), "bowling: 24 wide, one floor, $160,000, star 3, removable")
	check.call(int(arc["width"]) == 12 and int(arc["height"]) == 1 and int(arc["cost"]) == 70000 and Catalogue.star("arcade") == 2 and bool(arc["removable"]), "arcade: 12 wide, one floor, $70,000, star 2, removable")
	check.call(int(bowl["width"]) > int(Catalogue.field("fast_food", "width")) and int(bowl["width"]) < int(Catalogue.field("movie_theatre", "width")), "bowling: wider than a shop, narrower than the theatre")
	check.call(int(arc["width"]) <= int(Catalogue.field("fast_food", "width")) and int(arc["cost"]) < int(bowl["cost"]), "arcade: shop-sized and cheaper than the alley")
	check.call(Rooms.PLACEABLE.has("bowling") and Rooms.PLACEABLE.has("arcade") and Catalogue.IDS.has("bowling") and Catalogue.IDS.has("arcade"), "bowling and arcade: placeable catalogue kinds")

	# Unlock: locked below their star in the build menu and by the ghost, open at it.
	var g := _tower()
	check.call(ToolbarScript.item_state("bowling", 2)["locked"] and not ToolbarScript.item_state("bowling", 3)["locked"], "bowling: locked below 3 stars, open at 3")
	check.call(ToolbarScript.item_state("arcade", 1)["locked"] and not ToolbarScript.item_state("arcade", 2)["locked"], "arcade: locked at 1 star, open at 2")
	check.call(Ghost.evaluate(g, "bowling", 3, BOWL_X, 2)["text"] == "Needs 3 stars" and Ghost.evaluate(g, "arcade", 3, ARCADE_X, 1)["text"] == "Needs 2 stars", "the ghost words the star lock")
	check.call(Ghost.evaluate(g, "bowling", 3, BOWL_X, 3)["valid"] and Ghost.evaluate(g, "arcade", 3, ARCADE_X, 2)["valid"], "the ghost accepts both at their star")
	var in_menu := 0
	for category: Array in ToolbarScript.CATEGORIES:
		if category[0] == "Entertainment" and category[1].has("bowling") and category[1].has("arcade"):
			in_menu += 1
	check.call(in_menu == 1 and ToolbarScript.TOOL_TIPS.has("bowling") and ToolbarScript.TOOL_TIPS.has("arcade"), "both are in the Entertainment menu with a tip")

	# Placement: above ground, charged, standing at the width, not on the lobby floor, not underground, no overlap.
	var t := _tower()
	var before := t.ledger.balance
	check.call(_put(t, "bowling", BOWL_X) == Rooms.OK and _put(t, "arcade", ARCADE_X) == Rooms.OK, "placement: both are placed on floor 3")
	var bid := _room(t, "bowling")
	var aid := _room(t, "arcade")
	check.call(before - t.ledger.balance == 160000 + 70000, "placement: they cost their price (%d)" % (before - t.ledger.balance))
	check.call(t.grid.cell_at(3, BOWL_X + 23) == bid and t.grid.cell_at(3, BOWL_X + 24) != bid and t.grid.cell_at(3, ARCADE_X + 11) == aid, "placement: each fills its width")
	check.call(_put(t, "bowling", BOWL_X + 10) == Rooms.OVERLAPS_ROOM, "placement: a second room over the alley is refused")
	check.call(t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("bowling"), 1, 150) == Rooms.LOBBY_FLOOR and t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("arcade"), -3, 150) == Rooms.BELOW_GROUND, "placement: not on the lobby floor, not underground")
	check.call(t.rooms.check_bulldoze(t.grid, t.floors, 3, BOWL_X)["reason"] == Rooms.OK, "placement: the alley can be bulldozed")

	# Hours: the alley opens after the offices close, the arcade in the afternoon and evening; none at night.
	check.call(_waves("bowling") == [1110], "bowling: one evening wave from 18:30, after the offices close (%s)" % str(_waves("bowling")))
	check.call(_waves("arcade") == [900, 1080], "arcade: an afternoon wave at 15:00 and an evening one at 18:00 (%s)" % str(_waves("arcade")))
	check.call(1110 + Commerce.BOWLING_WINDOW <= 1320, "bowling: the wave ends by 22:00")
	for kind: String in ["bowling", "arcade"]:
		check.call(Commerce.is_shop(kind) and Commerce.has_sales(kind) and Commerce.visitors_for(kind, 6, Clock.WD1) == 0 and Commerce.visitors_for(kind, 6, Clock.WE) == 0 and Commerce.visitors_for(kind, 1, Clock.WE) == 0, "%s: the street brings nobody at night or in the morning" % kind)
	# The weekend peak: more visitors from outside at the weekend than on a weekday, in the hours it is open.
	check.call(Commerce.visitors_for("bowling", 5, Clock.WE) == 18 and Commerce.visitors_for("bowling", 5, Clock.WD1) == 6 and Commerce.visitors_for("bowling", 5, Clock.WD2) == 6, "bowling: 6 visitors on a weekday evening, 18 at the weekend")
	check.call(Commerce.visitors_for("arcade", 4, Clock.WE) > Commerce.visitors_for("arcade", 4, Clock.WD1) and Commerce.visitors_for("arcade", 5, Clock.WE) > Commerce.visitors_for("arcade", 5, Clock.WD1) and Commerce.visitors_for("arcade", 4, Clock.WD1) > 0, "arcade: the street comes in the afternoon and evening, more at the weekend")
	# Served at the wave: a tower with nobody inside still gets the street's visitors, and no more.
	var wd := _tower()
	_put(wd, "bowling", BOWL_X)
	_wave(wd, "bowling", 0, Clock.WD1)
	var we := _tower()
	_put(we, "bowling", BOWL_X)
	_wave(we, "bowling", 0, Clock.WE)
	var wd_came := wd.commerce.customers_today(_room(wd, "bowling"))
	var we_came := we.commerce.customers_today(_room(we, "bowling"))
	check.call(wd_came == 6 and we_came == 18 and we_came > wd_came, "bowling: the weekend evening brings 3 times the weekday's visitors (%d against %d)" % [we_came, wd_came])
	check.call(wd.commerce.visitors_today() == 6 and we.commerce.visitors_today() == 18, "bowling: the street's visitors are counted as visitors")
	var afternoon := _tower()
	_put(afternoon, "arcade", ARCADE_X)
	_wave(afternoon, "arcade", 0, Clock.WD1)
	var weekend_pm := _tower()
	_put(weekend_pm, "arcade", ARCADE_X)
	_wave(weekend_pm, "arcade", 0, Clock.WE)
	_wave(weekend_pm, "arcade", 1, Clock.WE)
	var pm_came := afternoon.commerce.customers_today(_room(afternoon, "arcade"))
	var we_pm := weekend_pm.commerce.customers_today(_room(weekend_pm, "arcade"))
	check.call(pm_came == 4 and we_pm == 20, "arcade: 4 in a weekday afternoon, 10 in each weekend wave (%d, %d)" % [pm_came, we_pm])
	# People of the tower come too, at the wave's own percent.
	var crowd := _tower()
	_put(crowd, "bowling", BOWL_X)
	for k in 40:
		var pid := crowd.people.add_person(-1, -1, crowd.rng)
		crowd.people.start_trip(crowd.people.index_of(pid), 600)
	_wave(crowd, "bowling", 0, Clock.WD1)
	check.call(crowd.commerce.customers_today(_room(crowd, "bowling")) > 6, "bowling: people inside the tower join the street's visitors (%d)" % crowd.commerce.customers_today(_room(crowd, "bowling")))

	# Income: each visitor pays at the door, less the staff's wages; credited to the ledger at settlement.
	check.call(Commerce.entry_takings("bowling", 0) == -3000 and Commerce.entry_takings("bowling", 20) == 20 * 180 - 3000, "bowling: $180 a bowler, $3,000 wages")
	check.call(Commerce.entry_takings("arcade", 0) == -1000 and Commerce.entry_takings("arcade", 20) == 20 * 60 - 1000, "arcade: $60 a player, $1,000 wages")
	check.call(Commerce.ENTRY_FEES["arcade"][0] < Commerce.ENTRY_FEES["bowling"][0] and Commerce.ENTRY_FEES["arcade"][1] < Commerce.ENTRY_FEES["bowling"][1], "arcade: cheaper and lower income than the alley")
	var paid := _settle(we)
	check.call(paid == Commerce.entry_takings("bowling", we_came), "bowling: a weekend evening credits its entry fees less wages (%d)" % paid)
	var wd_paid := _settle(wd)
	check.call(wd_paid == Commerce.entry_takings("bowling", wd_came) and paid > wd_paid, "bowling: the weekend pays more than a weekday (%d against %d)" % [paid, wd_paid])
	var line := 0
	for ledger_line: Array in we.ledger.lines:
		if ledger_line[3] == _room(we, "bowling") and ledger_line[1] == paid:
			line += 1
	check.call(line == 1, "bowling: the takings land on the room's own shop line")
	check.call(we.commerce.customers_last_day(_room(we, "bowling")) == we_came, "bowling: the day's visitors are kept for the grade")
	var arc_paid := _settle(weekend_pm)
	check.call(arc_paid == Commerce.entry_takings("arcade", we_pm) and arc_paid > 0, "arcade: a weekend day credits its entry fees less wages (%d)" % arc_paid)

	# The grade, like other commercial rooms.
	check.call(Commerce.grade_of_customers("bowling", 24) == Grades.GRADE_A and Commerce.grade_of_customers("bowling", 12) == Grades.GRADE_B and Commerce.grade_of_customers("bowling", 3) == Grades.GRADE_C, "bowling: graded A, B or C by the day's visitors")
	check.call(Commerce.grade_of_customers("arcade", 20) == Grades.GRADE_A and Commerce.grade_of_customers("arcade", 10) == Grades.GRADE_B and Commerce.grade_of_customers("arcade", 2) == Grades.GRADE_C, "arcade: graded A, B or C by the day's visitors")
	check.call(we.commerce.grade(we.rooms, _room(we, "bowling")) == Commerce.grade_of_customers("bowling", we_came) and weekend_pm.commerce.grade_input(weekend_pm.rooms, _room(weekend_pm, "arcade")) == we_pm, "grades: the room's grade comes from its last day")

	# Reachability: a room no route reaches draws nobody and earns, and costs, nothing.
	var cut := _tower(false)
	_put(cut, "bowling", BOWL_X)
	_put(cut, "arcade", ARCADE_X)
	cut.refresh_reach()
	var cut_bowl := _room(cut, "bowling")
	check.call(cut.rooms.is_cut_off(cut_bowl), "reach: with no stairs the alley is cut off")
	_wave(cut, "bowling", 0, Clock.WE)
	_wave(cut, "arcade", 0, Clock.WE)
	check.call(cut.commerce.customers_today(cut_bowl) == 0 and cut.commerce.customers_today(_room(cut, "arcade")) == 0 and cut.commerce.visitors_today() == 0, "reach: a cut-off alley and arcade get no visitors")
	check.call(_settle(cut) == 0, "reach: a cut-off alley and arcade earn nothing")

	# NoiseScript and names.
	check.call(NoiseScript.is_source("bowling") and NoiseScript.is_source("arcade") and int(NoiseScript.SOURCES["bowling"]) > int(NoiseScript.SOURCES["arcade"]) and int(NoiseScript.SOURCES["arcade"]) > 0, "noise: both are sources, the alley the louder")
	check.call(Names.TITLES.has("bowling") and Names.TITLES.has("arcade"), "names: staff titles for both")

	# Both looks: Classic (flat colour and recipe) and Detailed (drawn in code).
	for kind: String in ["bowling", "arcade"]:
		check.call(RoomLook.handles(kind) and RoomLook.base_color(kind) != Color(0.85, 0.2, 0.85) and RoomRecipes.has(kind) and DetailRooms.handles(kind), "%s: a Classic colour, a recipe and a Detailed drawing" % kind)
		var width_px: int = int(Catalogue.field(kind, "width")) * 8
		check.call(not RoomRecipes.spots(kind, width_px).is_empty(), "%s: its recipe holds places for people" % kind)
	check.call(RoomLook.base_color("bowling") != RoomLook.base_color("arcade") and RoomLook.describe(t, bid)["kind"] == "bowling" and RoomLook.describe(t, aid)["kind"] == "arcade", "bowling and arcade: colours of their own")

	# Save: version 54, the rooms and the day's counters survive a round trip, and the copy carries on alike.
	var s := _tower()
	_put(s, "bowling", BOWL_X)
	_put(s, "arcade", ARCADE_X)
	_wave(s, "bowling", 0, Clock.WE)
	for k in 600:
		s.step()
	var saved := s.save()
	check.call(int(saved["version"]) == 54 and TowerSim.SAVE_VERSION == 54, "save: version 54")
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(saved) and copy.state_hash() == s.state_hash(), "save: the loaded tower matches the original")
	check.call(_room(copy, "bowling") == _room(s, "bowling") and copy.rooms.kind_of(_room(copy, "arcade")) == "arcade" and copy.commerce.customers_today(_room(copy, "bowling")) == s.commerce.customers_today(_room(s, "bowling")), "save: both rooms and the day's visitors survive")
	for k in 2600:
		s.step()
		copy.step()
	check.call(copy.state_hash() == s.state_hash() and copy.ledger.balance == s.ledger.balance, "save: the loaded tower goes on exactly like the original")
	# Migration: a v53 save is carried to 54 unchanged and loads.
	var old := s.save()
	old["version"] = 53
	var up := Migration.migrate(old, TowerSim.SAVE_VERSION)
	var loaded := TowerSim.new(1, 1)
	check.call(not up.is_empty() and int(up["version"]) == 54 and loaded.load_state(old) and loaded.state_hash() == s.state_hash(), "save: a v53 save is migrated to v54 and loads")
