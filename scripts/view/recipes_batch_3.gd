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
	return out
