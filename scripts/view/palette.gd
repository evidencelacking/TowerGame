extends RefCounted
## The tower's colours as a swappable data table (10.2). The owner has not yet picked a mock-up
## direction (#240), so all three are kept: A warm and chunky, B muted and thin-lined, C flat and
## bold. Change DEFAULT_INDEX (or set `index` at run time) to switch; nothing else names a colour.
## Drawing code asks for colours by role, e.g. Palette.get_palette()["wall"]; room hues are looked up
## by the recipe's hue key in "hues". Pure data: reads nothing from the sim.

const DEFAULT_INDEX := 3  ## 0 = A, 1 = B, 2 = C, 3 = D (the owner's pick: A's colours, B's lines).
const NAMES: Array[String] = ["A", "B", "C", "D"]

## Outline styles for furniture boxes (the "mode" field).
const MODE_OUTLINED := 0  ## A: a dark outline around each box.
const MODE_LINE := 1  ## B: box edges only, no fill.
const MODE_FLAT := 2  ## C: plain fills.

## The palette in use. A plain static so a settings screen (10.12) can switch it.
static var index: int = DEFAULT_INDEX

const PALETTES: Array[Dictionary] = [
	{  # A: warm, saturated, chunky dark outlines
		"sky_day": Color("5cb8f0"), "sky_horizon": Color("f8e4a8"), "sky_night": Color("1a1440"),
		"wall": Color("3a2216"), "slab": Color("22120c"), "outline": Color("160a06"), "slab_hi": Color("5a3a28"),
		"hues": {
			"lobby": Color("e8b458"), "office": Color("58a0e0"), "condo": Color("c880d8"), "hotel": Color("e0648c"),
			"food": Color("f08030"), "shop": Color("88cc58"), "service": Color("48b8b0"), "medical": Color("e8f0f0"),
			"recycling": Color("78a850"), "parking": Color("8c8c98"), "civic": Color("d8a8e8"), "stairs": Color("c8b070"),
			"escalator": Color("58c0c8"), "shaft": Color("2a1a12"), "car": Color("e4c43c"), "floor": Color("22120c"),
			"dining": Color("d85850"), "security": Color("7078c8"), "cinema": Color("b06888"), "party": Color("f070b8"),
		},
		"dim": 0.45, "furn": 0.38, "mode": 0, "wall_w": 1,
		"ground": Color("4a8a30"), "earth": Color("5a3a22"), "lamp": Color("fff0a0"), "lamp_off": Color("30303a"),
		"skin": Color("f0c090"), "ink": Color("160a06"), "white": Color("f4f0e8"), "red": Color("d83030"),
		"gold": Color("f8d030"), "green": Color("3c9a48"), "wood": Color("6a4428"),
		"grid": Color(0, 0, 0, 0.10),
		"people": [Color("d03030"), Color("3050c8"), Color("30a040"), Color("f0f0f0"), Color("8a38a8")],
	},
	{  # B: muted architectural, thin lines, cool tones
		"sky_day": Color("b4c6d4"), "sky_horizon": Color("e0e6ea"), "sky_night": Color("0a1222"),
		"wall": Color("1e242c"), "slab": Color("303a46"), "outline": Color("7a8c9e"), "slab_hi": Color("46525f"),
		"hues": {
			"lobby": Color("b4a88e"), "office": Color("86a0b2"), "condo": Color("a898a8"), "hotel": Color("c09e76"),
			"food": Color("c8a078"), "shop": Color("9ab096"), "service": Color("88aeb0"), "medical": Color("dce4e6"),
			"recycling": Color("98ac84"), "parking": Color("9aa0a8"), "civic": Color("b8a8c4"), "stairs": Color("9a9484"),
			"escalator": Color("8ab4bc"), "shaft": Color("161c22"), "car": Color("9aaab6"), "floor": Color("303a46"),
			"dining": Color("b87870"), "security": Color("8088b0"), "cinema": Color("a08090"), "party": Color("c898b4"),
		},
		"dim": 0.5, "furn": 0.3, "mode": 1, "wall_w": 1,
		"ground": Color("6a7882"), "earth": Color("2c343c"), "lamp": Color("f4e8c0"), "lamp_off": Color("30343c"),
		"skin": Color("d8c0a8"), "ink": Color("1e242c"), "white": Color("e8ecee"), "red": Color("b85858"),
		"gold": Color("d8bc70"), "green": Color("6a8a70"), "wood": Color("6e5a48"),
		"grid": Color(0, 0, 0, 0.08),
		"people": [Color("5a6a7a"), Color("8a7a6a"), Color("6a8a8a"), Color("a0a0a8"), Color("7a6a8a")],
	},
	{  # C: bold flat colour, black walls, high contrast
		"sky_day": Color("38a0ff"), "sky_horizon": Color("38a0ff"), "sky_night": Color("0c0c2c"),
		"wall": Color("000000"), "slab": Color("000000"), "outline": Color("000000"), "slab_hi": Color("000000"),
		"hues": {
			"lobby": Color("ffd000"), "office": Color("2850ff"), "condo": Color("a040ff"), "hotel": Color("ff2a88"),
			"food": Color("ff5a00"), "shop": Color("00d060"), "service": Color("00c8d0"), "medical": Color("ffffff"),
			"recycling": Color("30b030"), "parking": Color("a0a0a0"), "civic": Color("ff80c0"), "stairs": Color("ffffff"),
			"escalator": Color("00e0ff"), "shaft": Color("101010"), "car": Color("ffffff"), "floor": Color("000000"),
			"dining": Color("ff3030"), "security": Color("6060ff"), "cinema": Color("c04080"), "party": Color("ff60d0"),
		},
		"dim": 0.7, "furn": 0.92, "mode": 2, "wall_w": 2,
		"ground": Color("00c060"), "earth": Color("101010"), "lamp": Color("ffffff"), "lamp_off": Color("303040"),
		"skin": Color("ffffff"), "ink": Color("000000"), "white": Color("ffffff"), "red": Color("ff2020"),
		"gold": Color("ffe000"), "green": Color("00c060"), "wood": Color("804020"),
		"grid": Color(0, 0, 0, 0.0),
		"people": [Color("ffffff"), Color("000000"), Color("ffe000"), Color("ff2a88"), Color("00e0ff")],
	},
	{  # D: A's warm colours with B's thin lines (owner pick)
		"sky_day": Color("5cb8f0"), "sky_horizon": Color("f8e4a8"), "sky_night": Color("1a1440"),
		"wall": Color("3a2216"), "slab": Color("22120c"), "outline": Color("160a06"), "slab_hi": Color("75645c"),
		"hues": {
			"lobby": Color("e8b458"), "office": Color("58a0e0"), "condo": Color("c880d8"), "hotel": Color("e0648c"),
			"food": Color("f08030"), "shop": Color("88cc58"), "service": Color("48b8b0"), "medical": Color("e8f0f0"),
			"recycling": Color("78a850"), "parking": Color("8c8c98"), "civic": Color("d8a8e8"), "stairs": Color("c8b070"),
			"escalator": Color("58c0c8"), "shaft": Color("2a1a12"), "car": Color("e4c43c"), "floor": Color("22120c"),
			"dining": Color("d85850"), "security": Color("7078c8"), "cinema": Color("b06888"), "party": Color("f070b8"),
		},
		"dim": 0.45, "furn": 0.38, "mode": 1, "wall_w": 1,
		"ground": Color("4a8a30"), "earth": Color("5a3a22"), "lamp": Color("fff0a0"), "lamp_off": Color("30303a"),
		"skin": Color("f0c090"), "ink": Color("160a06"), "white": Color("f4f0e8"), "red": Color("d83030"),
		"gold": Color("f8d030"), "green": Color("3c9a48"), "wood": Color("6a4428"),
		"grid": Color(0, 0, 0, 0.10),
		"people": [Color("d03030"), Color("3050c8"), Color("30a040"), Color("f0f0f0"), Color("8a38a8")],
	},
]


## The palette in use, as a dictionary of roles to colours.
static func get_palette() -> Dictionary:
	return PALETTES[clampi(index, 0, PALETTES.size() - 1)]


## A room hue by key ("office", "hotel", ...) in the palette in use.
static func hue(key: String) -> Color:
	var hues: Dictionary = get_palette()["hues"]
	return hues[key]


## Every hue key a recipe may use (the first palette's keys; the others must match, see the tests).
static func hue_keys() -> Array:
	var hues: Dictionary = PALETTES[0]["hues"]
	return hues.keys()
