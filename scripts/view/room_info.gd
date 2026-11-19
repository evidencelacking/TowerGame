extends RefCounted
## What the room window says (5.8), and which room a screen point is over. Reads the sim only.

const VC := preload("res://scripts/view/view_consts.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const CommerceScript := preload("res://scripts/sim/commerce.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const ComplaintsScript := preload("res://scripts/sim/complaints.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const RunningCosts := preload("res://scripts/sim/running_costs.gd")

const LEVEL_NAMES: Array[String] = ["Lowest", "Low", "Average", "Highest"]
const QUALITY_MAX := 300  ## The grade bar's full scale (Grades quality runs 0 to 300).
## Bar colours by grade: A blue, B yellow, C red (the three colours of the reference).
const GRADE_COLORS: Array[Color] = [Color(0.25, 0.65, 0.95), Color(0.95, 0.80, 0.20), Color(0.85, 0.15, 0.15)]
## Kinds graded by customers (food and shops) rather than stress.
const CUSTOMER_KINDS: Array[String] = ["restaurant", "fast_food", "retail"]


## The floor number of a world-space y, or 0 if outside the tower.
static func floor_at_y(y: float) -> int:
	var row := floori(y / VC.CELL_PX)
	if row < 0 or row >= GridScript.FLOOR_COUNT:
		return 0
	return GridScript.FLOOR_MAX - row if row < GridScript.FLOOR_MAX else GridScript.FLOOR_MAX - 1 - row


## The room id under a world point, or -1 (nothing there, or not a room such as a lift shaft).
static func room_at(tower: Object, world: Vector2) -> int:
	var floor_number := floor_at_y(world.y)
	if floor_number == 0 or world.x < 0.0:
		return -1
	var id: int = tower.grid.cell_at(floor_number, floori(world.x / VC.CELL_PX))
	if id <= GridScript.EMPTY or tower.rooms.kind_of(id) == "":
		return -1
	return id


## The room's data: {"id", "kind", "label", "floor_label", "width", "occupants" (names),
## "capacity", "vacant", "quality" (-1 if none), "grade", "customers_grade" (true if the bar
## would come from customers), "rentable", "rent_level", "rent", "upkeep" (dollars a quarter), "reasons"}.
static func describe(tower: Object, room: int) -> Dictionary:
	var kind: String = tower.rooms.kind_of(room)
	var run: Array[int] = tower.grid.run_of(room)
	var names: Array[String] = []
	var by_work: bool = GradesScript.WORK_KINDS.has(kind)
	if by_work or GradesScript.HOME_KINDS.has(kind):
		for i in tower.people.count():
			var held: int = tower.people.work_of(i) if by_work else tower.people.home_of(i)
			if held == room:
				names.append(tower.names.name_of(tower.people.id_at(i)))
	var graded: bool = GradesScript.is_graded(kind)
	var rentable: bool = RentScript.is_rentable(kind)
	return {
		"id": room, "kind": kind, "label": kind.capitalize().replace("_", " "),
		"floor_label": PersonInfo.room_label(tower, room).get_slice(", ", 1),
		"width": run[2] if run.size() == 3 else 0,
		"occupants": names, "capacity": tower.rooms.people_in(room),
		"vacant": (graded and names.is_empty()) or tower.commerce.is_vacant(room),
		"quality": tower.quality(room) if graded else -1,
		"grade": tower.grade(room) if graded else tower.commerce.grade(tower.rooms, room),
		"customers_grade": CUSTOMER_KINDS.has(kind),
		"customers": tower.commerce.customers_last_day(room),
		"customer_cap": CommerceScript.PROFILES[kind]["grade_cap"] if CommerceScript.is_shop(kind) else 0,
		"rentable": rentable,
		"rent_level": tower.rent_level(room) if rentable else -1,
		"rent": tower.rent_amount(room),
		"upkeep": RunningCosts.upkeep_of(kind),
		"reasons": tower.complaint_reasons(room),
		"dirty": tower.hotel.is_dirty(room),
	}


## Text lines for the window body.
static func lines_for(info: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("Floor %s, width %d" % [info["floor_label"], info["width"]])
	var names: Array[String] = info["occupants"]
	if info["vacant"]:
		lines.append("For Rent: no occupants")
	elif info["capacity"] > 0 or not names.is_empty():
		lines.append("Occupants: %d of %d" % [names.size(), info["capacity"]])
		for n in names:
			lines.append("  " + n)
	if info.get("dirty", false):
		lines.append("Dirty: needs cleaning before it can be rented")
	if info["customers_grade"] and info["grade"] != GradesScript.GRADE_NONE:
		lines.append("Grade %s (%d customers yesterday)" % [GradesScript.letter(info["grade"]), info["customers"]])
	elif info["grade"] != GradesScript.GRADE_NONE:
		lines.append("Grade %s (quality %d of %d)" % [GradesScript.letter(info["grade"]), info["quality"], QUALITY_MAX])
	elif info["customers_grade"]:
		lines.append("Grade: waiting for customer numbers")
	if info["rentable"]:
		lines.append("Rent: $%d a quarter (%s)" % [info["rent"], LEVEL_NAMES[info["rent_level"]]])
	if info["upkeep"] > 0:
		lines.append("Upkeep: $%d a quarter" % info["upkeep"])
	var reasons: Array[int] = info["reasons"]
	if reasons.is_empty():
		if info["grade"] != GradesScript.GRADE_NONE:
			lines.append("Complaints: none")
	else:
		lines.append("Complaints, worst first:")
		for r in reasons:
			lines.append("  " + ComplaintsScript.label(r))
	return lines


## Fill of the grade bar 0 to QUALITY_MAX, or -1 for no bar. Food and shops fill from last day's
## customers, scaled so the grade cap fills the bar.
static func bar_value(info: Dictionary) -> int:
	if info["customer_cap"] > 0:
		return mini(info["customers"], info["customer_cap"]) * QUALITY_MAX / info["customer_cap"]
	return info["quality"]


static func bar_color(info: Dictionary) -> Color:
	return GRADE_COLORS[clampi(info["grade"], 0, GRADE_COLORS.size() - 1)]
