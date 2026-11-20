extends RefCounted
## Extra looks for offices, food rooms and shops (#275). Each kind keeps its base recipe in
## room_recipes.gd / recipes_batch_2.gd as variant 0; the recipes here are variants 1 and up, in the same
## format (see room_recipes.gd) and the same thin-line style. Every variant defines its own spots, so people
## sit and stand on its furniture. RoomRecipes.variant_for() picks one per room from the room id.
## Pure data: build() returns {kind: [recipe, ...]} and loops only over fixed ranges.

const BOTTLE_ROLES: Array[String] = ["red", "gold", "green", "white"]


## A chair facing right: back at x, seat 5 wide, on the floor.
static func _chair_r(x: int, a: String = "l") -> Array:
	return [[x, 17, 1, 8, "furn", a], [x, 24, 5, 1, "furn", a], [x, 25, 1, 5, "furn", a], [x + 4, 25, 1, 5, "furn", a]]


## A chair facing left: back at x (its right edge), seat 5 wide.
static func _chair_l(x: int, a: String = "l") -> Array:
	return [[x, 17, 1, 8, "furn", a], [x - 4, 24, 5, 1, "furn", a], [x - 4, 25, 1, 5, "furn", a], [x, 25, 1, 5, "furn", a]]


## A round-topped bar or cafe stool, 8 px wide.
static func _stool(x: int, a: String = "l") -> Array:
	return [[x, 24, 8, 1, "furn", a], [x + 3, 25, 2, 5, "furn", a]]


## A window: sky, frame and cross bars (the same as RoomRecipes._win; a preload back would be circular).
static func _win(x: int, y: int, w: int, h: int, a: String = "l") -> Array:
	return [[x, y, w, h, "window", a], [x, y, w, h, "furn", a], [x + w / 2, y, 1, h, "furn", a], [x, y + h / 2, w, 1, "furn", a]]


## A window with a striped awning above it.
static func _win_awning(x: int, y: int, w: int, h: int) -> Array:
	return [[x, y, w, h, "window"], [x, y, w, h, "furn"], [x + w / 2, y, 1, h, "furn"], [x - 1, y - 4, w + 2, 3, "red"], [x + 2, y - 4, 3, 3, "white"], [x + 8, y - 4, 3, 3, "white"]]


static func build() -> Dictionary:
	var out: Dictionary = {}
	out["office"] = _offices()
	out["restaurant"] = _restaurants()
	out["fast_food"] = _fast_food()
	out["retail"] = _retail()
	return out


static func _offices() -> Array:
	var cubicles := {
		"fixed": [[-9, 4, 7, 7, "white", "c"], [-9, 4, 7, 7, "furn", "c"], [-6, 5, 1, 3, "furn", "c"], [-6, 7, 2, 1, "furn", "c"],
			[-12, 24, 8, 6, "furn", "r"], [-9, 17, 1, 7, "green", "r"], [-11, 15, 6, 1, "green", "r"], [-10, 12, 4, 1, "green", "r"]],
		"repeats": [{"pad": 4, "every": 30, "lo": 0, "hi": 26, "shapes": [
			[0, 11, 1, 19, "furn"], [0, 11, 26, 1, "furn"],  # partition
			[3, 22, 16, 1, "furn"], [4, 23, 1, 7, "furn"], [17, 23, 1, 7, "furn"],  # desk
			[6, 16, 8, 6, "furn"], [7, 17, 6, 4, "lamp"], [9, 21, 2, 1, "furn"],  # monitor
			[21, 18, 1, 6, "furn"], [19, 24, 4, 1, "furn"], [20, 25, 1, 5, "furn"], [22, 25, 1, 5, "furn"],  # chair
			[4, 2, 14, 1, "lamp"]], "spots": [[20, 30]]}],
	}
	var meeting := {
		"fixed": [[-14, 5, 28, 12, "white", "c"], [-14, 5, 28, 12, "furn", "c"], [-10, 8, 12, 1, "red", "c"], [-10, 11, 18, 1, "accent", "c"],
			[-20, 21, 40, 2, "furn", "c"], [-17, 23, 2, 7, "furn", "c"], [15, 23, 2, 7, "furn", "c"], [-8, 2, 16, 1, "lamp", "c"],
			[-5, 18, 3, 3, "white", "c"], [2, 18, 3, 3, "gold", "c"]]
			+ _chair_r(-30, "c") + _chair_l(29, "c"),
		"spots": [[-29, 30, "c"], [24, 30, "c"], [-3, 30, "c"]],
	}
	var executive := {
		"fixed": [[4, 21, 26, 2, "furn"], [5, 23, 8, 7, "furn"], [5, 26, 8, 1, "furn"], [28, 23, 1, 7, "furn"], [10, 15, 8, 6, "furn"], [11, 16, 6, 4, "lamp"],
			[32, 12, 2, 13, "furn"], [30, 24, 6, 1, "furn"], [32, 25, 1, 5, "furn"], [2, 29, 28, 1, "gold"], [6, 2, 18, 1, "lamp"],
			[-22, 8, 14, 22, "furn", "r"], [-22, 15, 14, 1, "furn", "r"], [-22, 22, 14, 1, "furn", "r"],
			[-20, 9, 2, 6, "red", "r"], [-17, 10, 3, 5, "gold", "r"], [-13, 9, 2, 6, "accent", "r"],
			[-20, 16, 3, 6, "gold", "r"], [-16, 17, 2, 5, "red", "r"], [-12, 16, 3, 6, "white", "r"]] + _win(38, 5, 9, 10),
		"spots": [[31, 30], [44, 30]],
	}
	var bench := {
		"fixed": [[2, 22, 0, 1, "furn"], [-10, 12, 8, 18, "furn", "r"], [-9, 13, 6, 6, "window", "r"], [-9, 21, 6, 1, "furn", "r"], [-8, 23, 4, 1, "accent", "r"]],
		"repeats": [{"pad": 4, "every": 14, "lo": 0, "hi": 12, "reserve": 12, "shapes": [
			[1, 15, 8, 6, "furn"], [2, 16, 6, 4, "lamp"], [4, 21, 2, 1, "furn"], [1, 23, 1, 7, "furn"],
			[2, 24, 8, 1, "furn"], [5, 25, 2, 5, "furn"], [2, 2, 8, 1, "lamp"]], "spots": [[3, 30]]}],
	}
	return [cubicles, meeting, executive, bench]


static func _restaurants() -> Array:
	var diner := {
		"fixed": [[8, 19, 0, 2, "furn"], [8, 21, 0, 9, "furn"], [10, 26, 0, 1, "red"], [8, 10, 0, 1, "furn"], [8, 2, 0, 1, "lamp"],
			[-26, 12, 12, 7, "furn", "r"], [-25, 13, 10, 5, "lamp", "r"]],  # a pie case on the counter
		"repeats": [
			{"pad": 12, "every": 10, "lo": 0, "hi": 5, "reserve": 40, "shapes": [[0, 5, 2, 5, "gold"], [3, 6, 2, 4, "green"]]},
			{"pad": 14, "every": 16, "lo": 0, "hi": 8, "reserve": 36, "shapes": [[0, 24, 8, 1, "furn"], [3, 25, 2, 5, "furn"]], "spots": [[1, 30]]},
		],
	}
	var cafe := {
		"fixed": [[-14, 5, 28, 13, "ink", "c"], [-14, 5, 28, 13, "furn", "c"], [-10, 8, 12, 1, "white", "c"], [-10, 11, 18, 1, "gold", "c"], [-10, 14, 8, 1, "white", "c"],
			[-12, 24, 8, 6, "furn", "r"], [-9, 17, 1, 7, "green", "r"], [-11, 15, 6, 1, "green", "r"], [-10, 12, 4, 1, "green", "r"]],
		"repeats": [
			{"pad": 10, "every": 50, "lo": 0, "hi": 14, "avoid": 16, "shapes": _win_awning(0, 5, 14, 11)},
			{"pad": 16, "every": 34, "lo": -6, "hi": 20, "reserve": 30, "shapes": [
				[0, 22, 12, 1, "furn"], [5, 23, 2, 6, "furn"], [3, 29, 6, 1, "furn"], [5, 19, 2, 3, "green"], [4, 17, 4, 2, "red"],
				[5, 2, 1, 8, "furn"], [2, 10, 8, 2, "lamp"], [2, 10, 8, 2, "furn"]] + _chair_r(-6) + _chair_l(17),
				"spots": [[-5, 30], [14, 30]]},
		],
	}
	var bar_fixed: Array = [[-40, 19, 80, 2, "furn", "c"], [-40, 21, 80, 9, "furn", "c"], [-38, 26, 76, 1, "gold", "c"],
		[-36, 10, 72, 1, "furn", "c"], [-36, 3, 72, 7, "furn", "c"], [-12, 1, 24, 2, "lamp", "c"]]
	var bar_spots: Array = []
	for i: int in 12:
		bar_fixed.append([-34 + i * 6, 5, 2, 5, BOTTLE_ROLES[i % 4], "c"])
	for i: int in 6:
		bar_fixed.append_array(_stool(-35 + i * 13, "c"))
		bar_spots.append([-34 + i * 13, 30, "c"])
	var bar := {"fixed": bar_fixed, "spots": bar_spots}
	return [diner, cafe, bar]


static func _fast_food() -> Array:
	var booths := {
		"fixed": [[-32, 19, 28, 11, "furn", "r"], [-33, 18, 30, 1, "furn", "r"], [-31, 26, 26, 1, "red", "r"], [-30, 5, 24, 9, "accent", "r"], [-30, 5, 24, 9, "furn", "r"],
			[-27, 8, 12, 1, "furn", "r"], [-27, 10, 16, 1, "furn", "r"], [-14, 22, 3, 3, "gold", "r"]],
		"repeats": [{"pad": 6, "every": 36, "lo": 0, "hi": 32, "reserve": 40, "shapes": [
			[0, 17, 3, 13, "furn"], [0, 26, 10, 4, "furn"], [10, 22, 12, 1, "furn"], [15, 23, 2, 7, "furn"],
			[29, 17, 3, 13, "furn"], [22, 26, 10, 4, "furn"], [3, 2, 26, 1, "lamp"]], "spots": [[2, 30], [24, 30]]}],
		"spots": [[-14, 30, "r"]],
	}
	var kiosk := {
		"fixed": [[8, 5, 0, 10, "window"], [8, 5, 0, 10, "furn"], [8, 1, 0, 1, "lamp"], [8, 19, 0, 2, "furn"], [10, 21, 0, 1, "gold"],
			[-14, 22, 10, 8, "furn", "r"], [-13, 17, 8, 5, "red", "r"]],
		"repeats": [{"pad": 12, "every": 18, "lo": 0, "hi": 8, "reserve": 20, "shapes": [[0, 24, 8, 1, "furn"], [3, 25, 2, 5, "furn"]], "spots": [[1, 30]]}],
	}
	var hatch := {
		"fixed": [[6, 10, 26, 14, "furn"], [8, 12, 22, 8, "lamp"], [6, 5, 26, 4, "red"], [10, 5, 4, 4, "white"], [18, 5, 4, 4, "white"], [26, 5, 4, 4, "white"],
			[4, 24, 30, 6, "furn"], [3, 23, 32, 1, "furn"], [-24, 6, 20, 12, "ink", "r"], [-24, 6, 20, 12, "furn", "r"], [-20, 9, 12, 1, "gold", "r"], [-20, 12, 8, 1, "white", "r"]],
		"repeats": [{"pad": 44, "every": 14, "lo": 0, "hi": 6, "reserve": 40, "shapes": [[0, 22, 1, 8, "furn"], [0, 22, 14, 1, "red"]], "spots": [[0, 30]]}],
	}
	return [booths, kiosk, hatch]


static func _retail() -> Array:
	var clothes := {
		"fixed": [[-14, 8, 10, 22, "window", "r"], [-14, 8, 10, 22, "furn", "r"], [-9, 12, 1, 14, "furn", "r"], [-14, 2, 10, 1, "lamp", "r"]],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 20, "reserve": 18, "shapes": [
			[0, 12, 20, 1, "furn"], [0, 12, 1, 18, "furn"], [19, 12, 1, 18, "furn"],
			[2, 13, 3, 8, "red"], [6, 13, 3, 9, "white"], [10, 13, 3, 7, "gold"], [14, 13, 3, 9, "accent"], [2, 2, 14, 1, "lamp"]], "spots": [[7, 30]]}],
	}
	var electronics := {
		"fixed": [[-24, 22, 20, 8, "furn", "r"], [-25, 21, 22, 1, "furn", "r"], [-20, 17, 6, 4, "lamp", "r"], [-20, 17, 6, 4, "furn", "r"]],
		"repeats": [
			{"pad": 4, "every": 16, "lo": 0, "hi": 14, "reserve": 30, "shapes": [
				[0, 3, 14, 9, "lamp"], [0, 3, 14, 9, "furn"], [0, 13, 14, 9, "lamp"], [0, 13, 14, 9, "furn"]]},
			{"pad": 4, "every": 16, "lo": 0, "hi": 14, "reserve": 30, "shapes": [[0, 25, 14, 5, "furn"], [2, 23, 3, 2, "accent"], [8, 22, 4, 3, "gold"]], "spots": [[4, 30]]},
		],
	}
	var florist := {
		"fixed": [[-16, 20, 12, 10, "furn", "r"], [-17, 19, 14, 1, "furn", "r"], [-14, 12, 8, 7, "green", "r"], [-12, 6, 2, 6, "red", "r"], [-9, 7, 2, 5, "gold", "r"]],
		"repeats": [
			{"pad": 4, "every": 22, "lo": 0, "hi": 18, "reserve": 22, "shapes": [
				[0, 24, 18, 1, "furn"], [1, 25, 1, 5, "furn"], [16, 25, 1, 5, "furn"],
				[1, 20, 5, 4, "furn"], [2, 15, 1, 5, "green"], [3, 13, 3, 3, "red"], [7, 20, 5, 4, "furn"], [9, 14, 1, 6, "green"], [8, 12, 3, 3, "gold"],
				[13, 20, 4, 4, "furn"], [14, 16, 1, 4, "green"], [13, 14, 3, 3, "accent"], [2, 2, 12, 1, "lamp"]], "spots": [[6, 30]]},
		],
	}
	return [clothes, electronics, florist]


## Suite recipes (#276): what neighbouring rooms of one kind become when they join. They span any width of
## two rooms or more, so every part repeats along the room or hangs from the centre or an edge.
static func build_suites() -> Dictionary:
	var out: Dictionary = {}
	out["office"] = {  # a boardroom: one long table the whole way across, chairs along it, a wall of whiteboard
		"fixed": [[24, 5, 0, 12, "white"], [24, 5, 0, 12, "furn"], [30, 8, 24, 1, "red"], [30, 11, 40, 1, "accent"],
			[30, 21, 0, 2, "furn"], [8, 2, 0, 1, "lamp"],
			[-14, 24, 8, 6, "furn", "r"], [-11, 17, 1, 7, "green", "r"], [-13, 15, 6, 1, "green", "r"], [-12, 12, 4, 1, "green", "r"]],
		"repeats": [
			{"pad": 34, "every": 18, "lo": 0, "hi": 5, "reserve": 34, "shapes": [[0, 17, 1, 8, "furn"], [0, 24, 5, 1, "furn"], [0, 25, 1, 5, "furn"], [4, 25, 1, 5, "furn"]], "spots": [[0, 30]]},
			{"pad": 36, "every": 44, "lo": 0, "hi": 2, "reserve": 34, "shapes": [[0, 23, 2, 7, "furn"]]},
		],
		"spots": [[10, 30]],
	}
	out["restaurant"] = {  # a grand dining room: a band of lamps and tables laid across the whole floor
		"fixed": [[4, 3, 0, 2, "accent"], [4, 1, 0, 1, "lamp"], [8, 19, 28, 11, "furn", "r"], [7, 18, 30, 1, "furn", "r"], [10, 7, 24, 9, "furn", "r"],
			[12, 9, 2, 5, "red", "r"], [16, 9, 2, 5, "gold", "r"], [20, 9, 2, 5, "green", "r"], [24, 9, 2, 5, "red", "r"], [28, 9, 2, 5, "gold", "r"]],
		"repeats": [{"pad": 16, "every": 34, "lo": -6, "hi": 20, "reserve": 46, "shapes": [
			[0, 20, 14, 1, "furn"], [1, 21, 12, 3, "white"], [6, 24, 2, 5, "furn"], [3, 29, 8, 1, "furn"],
			[7, 18, 1, 2, "white"], [7, 17, 1, 1, "lamp"], [7, 6, 1, 4, "furn"], [3, 10, 9, 3, "lamp"], [3, 10, 9, 3, "furn"],
			[-6, 16, 1, 8, "furn"], [-6, 24, 4, 1, "furn"], [-6, 25, 1, 5, "furn"], [-3, 25, 1, 5, "furn"],
			[19, 16, 1, 8, "furn"], [16, 24, 4, 1, "furn"], [16, 25, 1, 5, "furn"], [19, 25, 1, 5, "furn"]],
			"spots": [[-5, 30], [16, 30]]}],
		"spots": [[-18, 30, "r"]],
	}
	out["fast_food"] = {  # a food court: ordering counters at both ends, booths between
		"fixed": [[4, 19, 24, 11, "furn"], [3, 18, 26, 1, "furn"], [5, 26, 22, 1, "red"], [6, 5, 20, 10, "accent"], [6, 5, 20, 10, "furn"], [9, 8, 10, 1, "furn"], [9, 10, 14, 1, "furn"],
			[-28, 19, 24, 11, "furn", "r"], [-29, 18, 26, 1, "furn", "r"], [-27, 26, 22, 1, "gold", "r"], [-26, 5, 20, 10, "accent", "r"], [-26, 5, 20, 10, "furn", "r"],
			[-23, 8, 10, 1, "furn", "r"], [-23, 10, 14, 1, "furn", "r"], [32, 1, 0, 1, "lamp"]],
		"repeats": [{"pad": 38, "every": 36, "lo": 0, "hi": 32, "reserve": 38, "shapes": [
			[0, 17, 3, 13, "furn"], [0, 26, 10, 4, "furn"], [10, 22, 12, 1, "furn"], [15, 23, 2, 7, "furn"],
			[29, 17, 3, 13, "furn"], [22, 26, 10, 4, "furn"], [3, 2, 26, 1, "lamp"]], "spots": [[2, 30], [24, 30]]}],
		"spots": [[-34, 30, "c"], [28, 30, "c"]],
	}
	out["retail"] = {  # a department store: aisles of shelving and rails under a banner
		"fixed": [[6, 2, 0, 3, "gold"], [8, 2, 0, 1, "lamp"], [-14, 8, 10, 22, "window", "r"], [-14, 8, 10, 22, "furn", "r"], [-9, 12, 1, 14, "furn", "r"]],
		"repeats": [
			{"pad": 4, "every": 30, "lo": 0, "hi": 22, "reserve": 20, "shapes": [
				[0, 10, 22, 20, "furn"], [0, 17, 22, 1, "furn"], [0, 24, 22, 1, "furn"],
				[2, 11, 4, 5, "red"], [8, 12, 4, 4, "gold"], [14, 11, 5, 5, "accent"], [2, 18, 4, 5, "white"], [9, 19, 5, 4, "red"], [15, 18, 4, 5, "gold"],
				[2, 25, 5, 4, "accent"], [9, 26, 4, 3, "white"]], "spots": [[23, 30]]},
		],
		"spots": [[-26, 30, "r"]],
	}
	return out
