extends RefCounted
## Room recipes, batch 2 (10.4): food, shops, services, parking, recycling, culture, and the transport kinds.
## The format and the coordinate rules are in room_recipes.gd. Each kind has one strong silhouette and its own
## hue: a counter and menu board (fast food), tablecloths and a bottle wall (restaurant), an awning and shelves
## (shop), seat rows facing a screen (cinema), a glitter ball and stage (party hall), beds and a red cross
## (medical), a monitor wall and barrier (security), bins and a baler (recycling), a ramp and a car (parking),
## a train beside a platform (metro), pews, stained glass and an altar (cathedral).
## Stairs, escalators, shafts and cars are drawn by transport_look.gd; their recipe is the hue only.
## Pure data: build() only appends to a dictionary, and its two loops run over fixed ranges.

const TRANSPORT: Dictionary = {
	"floor": ["floor", "slab"], "stairs": ["stairs", "link"], "escalator": ["escalator", "link"],
	"local_shaft": ["shaft", "shaft"], "service_shaft": ["shaft", "shaft"], "express_shaft": ["shaft", "shaft"],
	"local_car": ["car", "car"], "service_car": ["car", "car"], "express_car": ["car", "car"],
}


static func build() -> Dictionary:
	var out: Dictionary = {}
	for kind: String in TRANSPORT:
		var entry: Array = TRANSPORT[kind]
		out[kind] = {"hue": entry[0], "drawn_by": entry[1], "look": "full"}
	var chairs: Array = [[-6, 17, 1, 7, "furn"], [-6, 24, 4, 1, "furn"], [-6, 25, 1, 5, "furn"], [-3, 25, 1, 5, "furn"],
		[19, 17, 1, 7, "furn"], [16, 24, 4, 1, "furn"], [16, 25, 1, 5, "furn"], [19, 25, 1, 5, "furn"]]
	out["fast_food"] = {
		"hue": "food", "look": "full",
		"fixed": [
			[-36, 19, 30, 11, "furn", "r"], [-37, 18, 32, 1, "furn", "r"], [-35, 26, 28, 1, "red", "r"], [-35, 27, 28, 1, "gold", "r"],
			[-32, 14, 5, 3, "furn", "r"], [-22, 15, 2, 2, "accent", "r"],
			[-44, 22, 5, 1, "furn", "r"], [-42, 23, 1, 7, "furn", "r"], [-44, 29, 5, 1, "furn", "r"],
			[-52, 22, 5, 1, "furn", "r"], [-50, 23, 1, 7, "furn", "r"], [-52, 29, 5, 1, "furn", "r"],
			[-34, 5, 26, 10, "accent", "r"], [-34, 5, 26, 10, "furn", "r"],
			[-31, 8, 12, 1, "furn", "r"], [-31, 10, 17, 1, "furn", "r"], [-31, 12, 12, 1, "furn", "r"], [-14, 8, 3, 1, "furn", "r"], [-11, 12, 3, 1, "furn", "r"],
		],
		"repeats": [{"pad": 14, "every": 34, "lo": -6, "hi": 20, "reserve": 52, "shapes": [
			[0, 20, 14, 1, "furn"], [6, 21, 2, 8, "furn"], [3, 29, 8, 1, "furn"], [5, 19, 4, 1, "accent"],
			[7, 2, 1, 7, "furn"], [3, 9, 9, 2, "lamp"], [3, 9, 9, 2, "furn"]] + chairs,
			"spots": [[-5, 30], [16, 30]]}],
		"spots": [[-43, 30, "r"], [-51, 30, "r"], [-15, 30, "r"]],
	}
	out["restaurant"] = {
		"hue": "dining", "look": "full",
		"fixed": [
			[-36, 19, 30, 11, "furn", "r"], [-37, 18, 32, 1, "furn", "r"],
			[-34, 5, 26, 10, "furn", "r"], [-32, 7, 2, 6, "red", "r"], [-28, 7, 2, 6, "gold", "r"], [-24, 7, 2, 6, "green", "r"],
			[-20, 7, 2, 6, "red", "r"], [-16, 7, 2, 6, "gold", "r"], [-12, 7, 2, 6, "white", "r"],
		],
		"repeats": [{"pad": 16, "every": 34, "lo": -6, "hi": 20, "reserve": 46, "shapes": [
			[0, 20, 14, 1, "furn"], [1, 21, 12, 3, "white"], [6, 24, 2, 5, "furn"], [3, 29, 8, 1, "furn"],
			[7, 18, 1, 2, "white"], [7, 17, 1, 1, "lamp"],
			[7, 2, 1, 6, "furn"], [3, 8, 9, 3, "gold"], [3, 8, 9, 3, "furn"], [1, 10, 2, 1, "gold"], [12, 10, 2, 1, "gold"],
			[-6, 16, 1, 8, "furn"], [-6, 24, 4, 1, "furn"], [-6, 25, 1, 5, "furn"], [-3, 25, 1, 5, "furn"],
			[19, 16, 1, 8, "furn"], [16, 24, 4, 1, "furn"], [16, 25, 1, 5, "furn"], [19, 25, 1, 5, "furn"]],
			"spots": [[-5, 30], [16, 30]]}],
		"spots": [[-15, 30, "r"]],
	}
	out["retail"] = {
		"hue": "shop", "look": "full",
		"fixed": [[4, 9, 30, 21, "furn"], [4, 16, 30, 1, "furn"], [4, 23, 30, 1, "furn"],
			[40, 22, 16, 8, "furn"], [42, 19, 4, 3, "accent"], [48, 18, 4, 4, "red"],
			[-34, 20, 30, 10, "furn", "r"], [-35, 19, 32, 1, "furn", "r"], [-30, 16, 6, 3, "furn", "r"], [-29, 17, 4, 1, "lamp", "r"], [-18, 15, 6, 4, "gold", "r"]],
		"repeats": [
			{"pad": 0, "every": 12, "lo": 0, "hi": 12, "shapes": [[0, 0, 6, 4, "red"], [6, 0, 6, 4, "white"], [1, 4, 4, 1, "red"], [7, 4, 4, 1, "white"]]},
			{"pad": 6, "every": 12, "lo": 0, "hi": 4, "max": 3, "shapes": [[0, 12, 4, 4, "red"], [0, 19, 4, 4, "gold"], [0, 26, 4, 4, "accent"]]},
		],
		"spots": [[36, 30], [57, 30], [-20, 30, "r"]],
	}
	var seat: Array = [[0, 19, 1, 7, "furn"], [0, 26, 6, 1, "furn"], [1, 27, 1, 3, "furn"], [5, 27, 1, 3, "furn"]]
	var screen: Array = [[-28, 0, 4, 30, "red", "r"], [-14, 0, 4, 30, "red", "r"], [-24, 3, 10, 27, "lamp", "r"], [-24, 3, 10, 27, "furn", "r"], [-38, 27, 30, 3, "furn", "r"]]
	out["movie_theatre"] = {
		"hue": "cinema", "look": "full",
		"fixed": screen,
		"repeats": [
			{"pad": 14, "every": 12, "lo": 0, "hi": 6, "reserve": 44, "shapes": seat, "spots": [[2, 30]]},
			{"pad": 20, "every": 36, "lo": 0, "hi": 6, "reserve": 44, "shapes": [[0, 2, 6, 1, "lamp"]]},
		],
		"upper": {
			"fixed": screen + [[4, 8, 16, 14, "furn"], [6, 11, 6, 5, "lamp"], [14, 12, 4, 3, "furn"], [4, 22, 16, 8, "furn"]],
			"repeats": [
				{"pad": 36, "every": 12, "lo": 0, "hi": 6, "reserve": 44, "shapes": seat, "spots": [[2, 30]]},
				{"pad": 36, "every": 12, "lo": 0, "hi": 12, "reserve": 44, "shapes": [[0, 21, 12, 1, "furn"], [0, 21, 1, 9, "furn"]]},
			],
		},
	}
	out["party_hall"] = {
		"hue": "party", "look": "full",
		"fixed": [
			[-52, 24, 46, 6, "furn", "r"], [-50, 4, 42, 20, "accent", "r"], [-50, 4, 42, 20, "furn", "r"],
			[-58, 14, 7, 16, "furn", "r"], [-56, 17, 3, 3, "ink", "r"], [-56, 22, 3, 5, "ink", "r"],
			[0, 5, 1, 3, "furn", "c"], [-3, 8, 6, 6, "gold", "c"], [-6, 10, 1, 1, "white", "c"], [5, 12, 1, 1, "white", "c"], [-1, 15, 1, 1, "white", "c"],
			[-3, 28, 6, 1, "lamp", "c"],
		],
		"repeats": [
			{"pad": 4, "every": 12, "lo": 0, "hi": 12, "shapes": [[0, 2, 12, 1, "furn"], [0, 3, 4, 2, "red"], [4, 3, 4, 2, "gold"], [8, 3, 4, 2, "green"]]},
			{"pad": 8, "every": 30, "lo": 0, "hi": 14, "reserve": 60, "avoid": 8, "shapes": [
				[0, 23, 14, 1, "furn"], [6, 24, 2, 6, "furn"], [3, 29, 8, 1, "furn"], [2, 21, 3, 2, "red"], [8, 21, 3, 2, "gold"],
				[11, 13, 1, 10, "furn"], [9, 8, 5, 5, "red"]], "spots": [[-3, 30], [15, 30]]},
		],
		"spots": [[-40, 24, "r"], [-26, 24, "r"], [-4, 30, "c"]],
	}
	out["medical"] = {
		"hue": "medical", "look": "full",
		"fixed": [[10, 6, 4, 14, "red"], [5, 10, 14, 4, "red"],
			[-16, 12, 12, 18, "furn", "r"], [-16, 21, 12, 1, "furn", "r"], [-11, 15, 2, 5, "red", "r"], [-13, 17, 6, 2, "red", "r"]],
		"repeats": [{"pad": 28, "every": 38, "lo": 0, "hi": 30, "reserve": 20, "shapes": [
			[0, 16, 2, 14, "furn"], [1, 23, 22, 4, "furn"], [2, 24, 20, 2, "white"], [3, 21, 6, 2, "white"], [2, 27, 1, 3, "furn"], [22, 27, 1, 3, "furn"],
			[26, 6, 1, 24, "furn"], [24, 6, 5, 1, "furn"], [24, 8, 5, 6, "white"], [24, 8, 5, 6, "furn"], [24, 29, 5, 1, "furn"],
			[10, 6, 10, 6, "furn"], [11, 7, 8, 4, "lamp"], [4, 2, 14, 1, "lamp"]], "spots": [[10, 30], [30, 30]]}],
		"spots": [[22, 30]],
	}
	out["security"] = {
		"hue": "security", "look": "full",
		"fixed": [[4, 22, 48, 8, "furn"], [3, 21, 50, 1, "furn"], [10, 19, 10, 2, "furn"], [34, 16, 1, 9, "furn"], [32, 24, 4, 1, "furn"], [34, 25, 1, 4, "furn"], [32, 29, 5, 1, "furn"],
			[-4, 5, 9, 8, "gold", "c"], [-3, 13, 7, 3, "gold", "c"], [-1, 16, 3, 2, "gold", "c"], [-1, 8, 3, 2, "furn", "c"],
			[-38, 14, 2, 16, "furn", "r"], [-10, 14, 2, 16, "furn", "r"], [-36, 18, 24, 2, "white", "r"], [-32, 18, 4, 2, "red", "r"], [-24, 18, 4, 2, "red", "r"], [-16, 18, 4, 2, "red", "r"]],
		"repeats": [{"pad": 6, "every": 9, "lo": 0, "hi": 8, "max": 5, "shapes": [
			[0, 6, 8, 4, "lamp"], [0, 6, 8, 4, "furn"], [0, 11, 8, 4, "lamp"], [0, 11, 8, 4, "furn"]]}],
		"spots": [[33, 30], [-42, 30, "r"], [-6, 30, "r"]],
	}
	out["recycling"] = {
		"hue": "recycling", "look": "full",
		"fixed": [[-32, 8, 28, 22, "furn", "r"], [-30, 6, 24, 3, "ink", "r"], [-26, 13, 10, 8, "lamp", "r"], [-26, 13, 10, 8, "furn", "r"],
			[-12, 12, 6, 5, "lamp", "r"], [-12, 12, 6, 5, "furn", "r"], [-28, 23, 18, 4, "ink", "r"]],
		"repeats": [{"pad": 6, "every": 20, "lo": 0, "hi": 12, "reserve": 36, "shapes": [
			[0, 17, 12, 13, "furn"], [-1, 15, 14, 3, "ink"], [5, 22, 2, 5, "white"], [4, 24, 4, 1, "white"]], "spots": [[13, 30]]}],
		"upper": {
			"fixed": [[-26, 0, 20, 6, "ink", "r"], [-20, 6, 8, 10, "furn", "r"], [4, 4, 28, 8, "furn"], [5, 5, 26, 6, "green"], [8, 7, 4, 2, "white"], [14, 7, 10, 2, "white"]],
			"repeats": [
				{"pad": 8, "every": 16, "lo": 0, "hi": 6, "shapes": [[0, 18, 4, 4, "gold"], [6, 19, 3, 3, "red"]]},
				{"pad": 8, "every": 32, "lo": 0, "hi": 2, "shapes": [[0, 24, 2, 6, "furn"]]},
			],
		},
	}
	var ramp: Array = []
	for i: int in 8:
		ramp.append([i * 4, 27 - i * 3, 4, 3 + i * 3, "ink"])
		ramp.append([i * 4, 27 - i * 3, 4, 1, "gold"])
	out["parking_ramp"] = {
		"hue": "parking", "look": "full",
		"fixed": ramp + [[2, 4, 10, 8, "window"], [2, 4, 10, 8, "furn"], [5, 6, 1, 5, "white"], [5, 6, 4, 1, "white"], [8, 7, 1, 2, "white"], [5, 9, 4, 1, "white"], [4, 2, 8, 1, "lamp"]],
	}
	out["parking_space"] = {
		"hue": "parking", "look": "full",
		"fixed": [[0, 22, 1, 8, "white"], [-1, 22, 1, 8, "white", "r"], [8, 2, 16, 1, "lamp"],
			[3, 20, 26, 6, "car"], [8, 14, 14, 6, "car"], [10, 15, 4, 4, "window"], [16, 15, 4, 4, "window"],
			[6, 25, 5, 5, "ink"], [21, 25, 5, 5, "ink"], [8, 27, 1, 1, "white"], [23, 27, 1, 1, "white"], [28, 21, 2, 2, "lamp"], [2, 21, 1, 2, "red"]],
	}
	out["metro"] = {
		"hue": "civic", "look": "full",
		"fixed": [[6, 9, 0, 16, "car"], [6, 9, 0, 16, "furn"], [0, 29, 0, 1, "furn"], [-16, 2, 32, 5, "furn", "c"], [-15, 3, 30, 3, "lamp", "c"], [8, 7, 0, 1, "lamp"]],
		"repeats": [
			{"pad": 12, "every": 20, "lo": 0, "hi": 10, "shapes": [[0, 12, 10, 7, "window"], [0, 12, 10, 7, "furn"]]},
			{"pad": 14, "every": 24, "lo": 0, "hi": 5, "shapes": [[0, 25, 5, 4, "ink"]]},
			{"pad": 20, "every": 64, "lo": 0, "hi": 16, "avoid": 20, "shapes": [[0, 25, 16, 1, "furn"], [1, 26, 1, 4, "furn"], [14, 26, 1, 4, "furn"]], "spots": [[6, 30]]},
		],
		"upper": {
			"fixed": [[-16, 2, 32, 5, "furn", "c"], [-15, 3, 30, 3, "lamp", "c"]],
			"repeats": [
				{"pad": 0, "every": 64, "lo": 0, "hi": 4, "shapes": [[0, 0, 4, 30, "furn"]]},
				{"pad": 20, "every": 48, "lo": 0, "hi": 14, "avoid": 20, "shapes": [[0, 18, 2, 12, "furn"], [12, 18, 2, 12, "furn"], [2, 20, 10, 1, "lamp"]], "spots": [[4, 30]]},
				{"pad": 30, "every": 96, "lo": 0, "hi": 20, "avoid": 20, "shapes": [[0, 8, 20, 12, "furn"], [1, 9, 18, 10, "accent"], [3, 14, 14, 1, "red"], [9, 10, 1, 8, "gold"]]},
			],
		},
	}
	out["cathedral"] = {
		"hue": "civic", "look": "full",
		"fixed": [[-9, 2, 18, 12, "window", "c"], [-9, 2, 18, 12, "furn", "c"], [0, 2, 1, 12, "furn", "c"], [-9, 8, 18, 1, "furn", "c"],
			[-7, 4, 4, 3, "red", "c"], [3, 4, 4, 3, "gold", "c"], [-7, 10, 4, 3, "gold", "c"], [3, 10, 4, 3, "green", "c"],
			[-30, 22, 18, 8, "furn", "r"], [-29, 23, 16, 2, "white", "r"], [-22, 6, 2, 16, "gold", "r"], [-26, 9, 10, 2, "gold", "r"],
			[-32, 18, 2, 4, "white", "r"], [-12, 18, 2, 4, "white", "r"], [-32, 16, 2, 2, "gold", "r", "use"], [-12, 16, 2, 2, "gold", "r", "use"]],
		"repeats": [
			{"pad": 12, "every": 24, "lo": 0, "hi": 10, "reserve": 44, "avoid": 14, "shapes": [
				[0, 2, 10, 18, "window"], [0, 2, 10, 18, "furn"], [4, 2, 1, 18, "furn"], [0, 10, 10, 1, "furn"], [1, 12, 3, 4, "red"], [6, 5, 3, 4, "gold"], [1, 5, 3, 4, "green"], [2, 0, 6, 2, "furn"]]},
			{"pad": 20, "every": 14, "lo": 0, "hi": 10, "reserve": 48, "shapes": [[0, 19, 1, 11, "furn"], [0, 26, 10, 1, "furn"], [1, 27, 1, 3, "furn"], [8, 27, 1, 3, "furn"]], "spots": [[4, 30]]},
		],
		"spots": [[-24, 30, "r"]],
	}
	return out
