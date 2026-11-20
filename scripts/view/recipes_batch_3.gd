extends RefCounted
## Room recipes, batch 3 (M13): our own kinds. The format and the coordinate rules are in room_recipes.gd.
## Gym (#291): treadmills along a mirror wall and a dumbbell rack. Daycare: play tables, an alphabet
## shelf and a slide. Clinic: a red cross, an exam bed behind a curtain and a reception desk.
## Pure data: build() only appends to a dictionary.


static func build() -> Dictionary:
	var out: Dictionary = {}
	out["gym"] = {
		"hue": "service", "look": "full",
		"fixed": [
			[2, 5, 0, 10, "window"], [2, 5, 0, 10, "furn"],
			[-26, 22, 22, 8, "furn", "r"], [-24, 19, 4, 3, "red", "r"], [-18, 19, 4, 3, "gold", "r"], [-12, 19, 4, 3, "white", "r"],
			[-54, 29, 20, 1, "green", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 34, "shapes": [
			[0, 27, 16, 3, "furn"], [14, 12, 2, 15, "furn"], [11, 10, 7, 4, "lamp"], [11, 10, 7, 4, "furn"], [3, 18, 12, 1, "furn"]],
			"spots": [[6, 27]]}],
		"spots": [[-30, 30, "r"]],
	}
	out["daycare"] = {
		"hue": "party", "look": "full",
		"fixed": [
			[4, 8, 24, 1, "furn"], [6, 3, 5, 5, "red"], [12, 3, 5, 5, "gold"], [18, 3, 5, 5, "green"], [34, 2, 20, 1, "lamp"],
			[-30, 14, 3, 16, "furn", "r"], [-27, 14, 12, 2, "gold", "r"], [-16, 16, 2, 14, "furn", "r"],
		],
		"repeats": [{"pad": 8, "every": 26, "lo": 0, "hi": 20, "reserve": 36, "shapes": [
			[0, 23, 20, 2, "furn"], [3, 25, 2, 5, "furn"], [15, 25, 2, 5, "furn"],
			[2, 18, 4, 5, "red"], [9, 19, 4, 4, "gold"], [14, 20, 3, 3, "green"]],
			"spots": [[10, 30]]}],
		"spots": [[-8, 30, "r"]],
	}
	out["clinic"] = {
		"hue": "medical", "look": "full",
		"fixed": [
			[8, 6, 4, 12, "red"], [4, 10, 12, 4, "red"],
			[-30, 20, 24, 10, "furn", "r"], [-28, 17, 6, 3, "lamp", "r"],
		],
		"repeats": [{"pad": 24, "every": 30, "lo": 0, "hi": 24, "reserve": 36, "shapes": [
			[0, 24, 22, 3, "furn"], [1, 23, 20, 1, "white"], [2, 27, 2, 3, "furn"], [18, 27, 2, 3, "furn"],
			[24, 6, 1, 24, "furn"], [22, 6, 5, 1, "furn"]],
			"spots": [[11, 30]]}],
		"spots": [[-8, 30, "r"]],
	}
	# Batch 2 (#292). Nightclub: a stage with a disco ball and lights, a bar on the right and small tables.
	out["nightclub"] = {
		"hue": "cinema", "look": "full",
		"fixed": [
			[4, 22, 44, 8, "furn"], [8, 16, 6, 6, "lamp"], [30, 14, 6, 8, "furn"], [20, 3, 7, 7, "gold"], [21, 0, 1, 3, "furn"],
			[6, 4, 3, 3, "red"], [36, 4, 3, 3, "green"],
			[-48, 20, 44, 4, "furn", "r"], [-44, 14, 5, 6, "lamp", "r"], [-34, 14, 5, 6, "lamp", "r"], [-24, 14, 5, 6, "lamp", "r"],
		],
		"repeats": [{"pad": 56, "every": 26, "lo": 0, "hi": 10, "reserve": 54, "shapes": [
			[0, 24, 14, 2, "furn"], [6, 26, 2, 4, "furn"], [3, 20, 8, 4, "gold"]],
			"spots": [[7, 30]]}],
		"spots": [[-30, 30, "r"]],
	}
	# Co-working: rows of shared desks with monitors, and a coffee corner on the right.
	out["coworking"] = {
		"hue": "office", "look": "full",
		"fixed": [
			[4, 4, 12, 1, "lamp"], [-44, 18, 40, 12, "furn", "r"], [-40, 12, 8, 6, "lamp", "r"], [-26, 14, 4, 4, "white", "r"],
		],
		"repeats": [{"pad": 6, "every": 30, "lo": 0, "hi": 27, "reserve": 52, "shapes": [
			[0, 20, 20, 1, "furn"], [1, 21, 1, 9, "furn"], [18, 21, 1, 9, "furn"], [2, 22, 9, 1, "furn"],
			[11, 14, 8, 6, "furn"], [12, 15, 6, 4, "lamp"], [14, 19, 2, 1, "furn"]],
			"spots": [[23, 30]]}],
		"spots": [[-10, 30, "r"]],
	}
	# Casino: rows of green-felt tables, a line of slot machines with lit tops, strings of lights.
	out["casino"] = {
		"hue": "party", "look": "full",
		"fixed": [
			[4, 4, 12, 1, "lamp"], [30, 4, 12, 1, "lamp"], [-70, 8, 60, 3, "lamp", "r"], [-70, 14, 8, 16, "furn", "r"], [-58, 14, 8, 16, "furn", "r"], [-46, 14, 8, 16, "furn", "r"],
		],
		"repeats": [{"pad": 8, "every": 36, "lo": 0, "hi": 27, "reserve": 80, "shapes": [
			[0, 18, 22, 3, "furn"], [4, 21, 3, 8, "furn"], [15, 21, 3, 8, "furn"], [6, 14, 10, 4, "gold"], [8, 11, 6, 2, "lamp"]],
			"spots": [[11, 28]]}],
		"spots": [[-10, 28, "r"]],
	}
	# Observation deck: a glass wall with a railing along the front, telescopes on stands, the city skyline below.
	out["observation_deck"] = {
		"hue": "office", "look": "full",
		"fixed": [
			[4, 4, 12, 1, "lamp"], [-70, 14, 24, 10, "furn", "r"], [-40, 10, 14, 14, "furn", "r"], [-20, 16, 20, 8, "furn", "r"],
		],
		"repeats": [{"pad": 8, "every": 34, "lo": 0, "hi": 27, "reserve": 40, "shapes": [
			[0, 6, 2, 20, "white"], [4, 16, 3, 10, "furn"], [4, 12, 8, 4, "lamp"], [9, 14, 4, 2, "furn"]],
			"spots": [[14, 28]]}],
		"spots": [[-10, 28, "r"]],
	}
	# Grocery: rows of shelving with produce crates in front, a checkout counter at the back.
	out["grocery"] = {
		"hue": "shop", "look": "full",
		"fixed": [
			[-64, 20, 20, 10, "furn", "r"], [-62, 16, 16, 4, "gold", "r"], [-26, 22, 18, 8, "furn", "r"], [-24, 18, 14, 4, "lamp", "r"],
		],
		"repeats": [{"pad": 8, "every": 30, "lo": 0, "hi": 24, "reserve": 40, "shapes": [
			[0, 8, 18, 2, "furn"], [0, 14, 18, 2, "furn"], [0, 20, 18, 2, "furn"], [2, 24, 4, 4, "green"], [8, 24, 4, 4, "red"], [14, 24, 4, 4, "gold"]],
			"spots": [[10, 28]]}],
		"spots": [[-40, 28, "r"]],
	}
	# Deli: a long counter with a glass case, hanging lamps and a menu board.
	out["deli"] = {
		"hue": "food", "look": "full",
		"fixed": [
			[-30, 21, 26, 9, "furn", "r"], [-29, 15, 24, 6, "white", "r"], [-28, 16, 22, 4, "lamp", "r"],
			[-30, 5, 12, 6, "furn", "r"], [-14, 6, 8, 1, "gold", "r"], [-14, 8, 8, 1, "gold", "r"],
		],
		"repeats": [{"pad": 4, "every": 16, "lo": 0, "hi": 12, "reserve": 20, "shapes": [
			[0, 8, 3, 18, "furn"], [4, 8, 3, 18, "furn"], [0, 14, 7, 2, "gold"], [0, 20, 7, 2, "gold"]],
			"spots": [[3, 28]]}],
		"spots": [[-18, 28, "r"]],
	}
	# Swimming pool (#328), two floors tall. Lower: a basin of water with lane ropes, a springboard over it, a lifeguard's chair
	# under an umbrella and a lifebuoy. Upper: a glass roof under bunting, the high-dive tower and a viewing gallery. The
	# swimmers, the guard and the cannonball are marks (room_look.gd), which stay inside the basin and on the board drawn here.
	out["pool"] = {
		"hue": "service", "look": "full",
		"fixed": [
			[22, 14, 122, 16, "window"], [22, 14, 122, 1, "white"], [16, 14, 4, 16, "furn"], [17, 13, 38, 2, "wood"],
			[24, 14, 1, 10, "gold"], [28, 14, 1, 10, "gold"],
			[-30, 16, 14, 2, "red", "r"], [-29, 18, 2, 12, "furn", "r"], [-19, 18, 2, 12, "furn", "r"], [-30, 10, 2, 6, "red", "r"],
			[-34, 3, 20, 2, "red", "r"], [-28, 3, 6, 2, "white", "r"], [-23, 5, 1, 11, "furn", "r"],
			[-12, 8, 8, 8, "red", "r"], [-10, 10, 4, 4, "white", "r"],
		],
		"repeats": [
			{"pad": 22, "every": 8, "lo": 0, "hi": 4, "reserve": 48, "shapes": [[0, 20, 4, 1, "red"], [0, 25, 4, 1, "red"]]},
			{"pad": 12, "every": 40, "lo": 0, "hi": 12, "reserve": 20, "shapes": [[0, 2, 12, 1, "lamp"]]},
		],
		"spots": [[4, 30], [-10, 30, "r"]],
		"upper": {
			"fixed": [
				[0, 3, 0, 1, "ink"], [18, 8, 0, 8, "window"], [23, 8, 5, 22, "furn"], [15, 7, 27, 2, "wood"], [15, 2, 1, 5, "furn"], [15, 2, 10, 1, "furn"],
				[-95, 19, 94, 2, "furn", "r"], [-60, 14, 3, 2, "lamp", "r"], [-30, 14, 3, 2, "lamp", "r"],
				[-30, 26, 14, 4, "wood", "r"], [-58, 26, 14, 4, "wood", "r"], [-86, 26, 14, 4, "wood", "r"],
			],
			"repeats": [
				{"pad": 2, "every": 16, "lo": 0, "hi": 8, "shapes": [[0, 4, 8, 3, "red"]]},
				{"pad": 10, "every": 16, "lo": 0, "hi": 8, "shapes": [[0, 4, 8, 3, "gold"]]},
				{"pad": 18, "every": 36, "lo": 0, "hi": 2, "shapes": [[0, 8, 2, 8, "furn"]]},
				{"pad": 98, "every": 8, "lo": 0, "hi": 1, "reserve": 4, "shapes": [[0, 21, 1, 9, "furn"]]},
			],
			"spots": [[-24, 30, "r"], [-52, 30, "r"], [-80, 30, "r"]],
		},
	}
	# Cafe: a coffee counter with a machine and cups, small round tables, a lamp over each.
	out["cafe"] = {
		"hue": "food", "look": "full",
		"fixed": [
			[-30, 21, 22, 9, "furn", "r"],
			[-29, 16, 20, 5, "white", "r"],
			[-28, 12, 6, 4, "lamp", "r"],
			[-14, 8, 8, 1, "gold", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 30, "shapes": [
			[0, 22, 10, 2, "furn"], [4, 24, 2, 6, "furn"], [2, 29, 6, 1, "furn"], [0, 6, 2, 10, "furn"],
			[3, 8, 5, 3, "lamp"], [3, 8, 5, 3, "furn"], [8, 16, 2, 2, "accent"], [5, 18, 3, 3, "gold"]],
			"spots": [[4, 28]]}],
		"spots": [[-14, 28, "r"]],
	}
	# Pizzeria: a brick oven with a glow, a long counter and checked tables.
	out["pizza"] = {
		"hue": "food", "look": "full",
		"fixed": [
			[-34, 12, 14, 18, "furn", "r"],
			[-31, 18, 8, 8, "lamp", "r"],
			[-33, 11, 16, 2, "red", "r"],
			[-16, 22, 18, 8, "furn", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 30, "shapes": [
			[0, 22, 12, 2, "red"], [1, 24, 2, 6, "furn"], [9, 24, 2, 6, "furn"], [0, 6, 2, 10, "furn"],
			[3, 8, 6, 3, "lamp"], [3, 8, 6, 3, "furn"], [2, 17, 8, 1, "white"], [4, 29, 4, 1, "furn"]],
			"spots": [[4, 28]]}],
		"spots": [[-14, 28, "r"]],
	}
	# Sushi bar: a long wooden counter with stools and a fish case behind it.
	out["sushi"] = {
		"hue": "dining", "look": "full",
		"fixed": [
			[-34, 21, 30, 3, "furn", "r"],
			[-33, 14, 28, 6, "white", "r"],
			[-32, 15, 26, 3, "lamp", "r"],
			[-34, 8, 4, 2, "red", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 30, "shapes": [
			[0, 24, 14, 2, "furn"], [2, 26, 1, 4, "furn"], [6, 26, 1, 4, "furn"], [11, 26, 1, 4, "furn"],
			[0, 6, 2, 12, "furn"], [3, 7, 8, 3, "lamp"], [3, 7, 8, 3, "furn"], [4, 12, 6, 2, "gold"]],
			"spots": [[4, 28]]}],
		"spots": [[-14, 28, "r"]],
	}
	# Fine dining: white tablecloths, tall candle lamps and a wine wall.
	out["fine_dining"] = {
		"hue": "dining", "look": "full",
		"fixed": [
			[-34, 6, 30, 14, "furn", "r"],
			[-33, 7, 28, 12, "gold", "r"],
			[-30, 8, 3, 8, "red", "r"],
			[-22, 8, 3, 8, "red", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 30, "shapes": [
			[0, 24, 12, 2, "white"], [5, 26, 2, 4, "furn"], [3, 29, 6, 1, "furn"], [0, 6, 2, 14, "furn"],
			[5, 14, 1, 10, "lamp"], [4, 12, 3, 3, "lamp"], [8, 16, 3, 3, "gold"], [3, 20, 7, 1, "white"]],
			"spots": [[4, 28]]}],
		"spots": [[-14, 28, "r"]],
	}
	# Bar: a long counter, a back shelf of bottles and neon over the stools.
	out["bar"] = {
		"hue": "party", "look": "full",
		"fixed": [
			[-34, 22, 32, 8, "furn", "r"],
			[-33, 8, 30, 3, "furn", "r"],
			[-32, 12, 28, 6, "gold", "r"],
			[-30, 6, 12, 1, "red", "r"],
		],
		"repeats": [{"pad": 6, "every": 24, "lo": 0, "hi": 18, "reserve": 30, "shapes": [
			[0, 22, 14, 2, "furn"], [2, 24, 2, 6, "furn"], [10, 24, 2, 6, "furn"], [0, 6, 2, 12, "furn"],
			[3, 8, 8, 2, "lamp"], [3, 8, 8, 2, "furn"], [4, 14, 6, 3, "accent"], [4, 29, 6, 1, "furn"]],
			"spots": [[4, 28]]}],
		"spots": [[-14, 28, "r"]],
	}
	return out
