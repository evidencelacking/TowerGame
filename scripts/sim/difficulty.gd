class_name Difficulty
extends RefCounted
## Difficulty presets (#380): a small table of integer percent multipliers, one row per preset, applied where each knob
## is read as value * percent / 100. Normal is all 100, so it changes nothing. Chosen when a tower is built and saved
## with it; it never changes mid-game.
##
## Never scaled, under any preset: star population thresholds, the top rank, unlock order, structural rules, the clock.
## All numbers here are our own guesses (docs/tuning.md, Presets).

const EASY := 0
const NORMAL := 1
const HARD := 2
const DEFAULT := NORMAL
const NAMES: Array[String] = ["Easy", "Normal", "Hard"]

const FUNDS := "funds"  ## Starting funds.
const INCOME := "income"  ## Rent and hotel takings.
const CHANCE := "chance"  ## How often fire, threats and stuck elevators strike.
const COST := "cost"  ## What rescue, ransom, repair and the plumber cost.
const MOOD := "mood"  ## How far a mood moves in a day (Mood.STEP).

const TABLE: Array[Dictionary] = [
	{FUNDS: 150, INCOME: 120, CHANCE: 50, COST: 50, MOOD: 125},
	{FUNDS: 100, INCOME: 100, CHANCE: 100, COST: 100, MOOD: 100},
	{FUNDS: 75, INCOME: 90, CHANCE: 150, COST: 125, MOOD: 75},
]


static func is_valid(preset: Variant) -> bool:
	return typeof(preset) == TYPE_INT and preset >= EASY and preset <= HARD


## The percent for a knob; an unknown preset reads as Normal.
static func percent(preset: int, knob: String) -> int:
	if not is_valid(preset):
		return 100
	return int(TABLE[preset][knob])


## value * percent / 100 in whole numbers.
static func scale(value: int, preset: int, knob: String) -> int:
	return value * percent(preset, knob) / 100


## Whole dollars with thousands commas, for card texts that quote a scaled price: 25000 reads "$25,000".
static func money(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for n in digits.length():
		if n > 0 and (digits.length() - n) % 3 == 0:
			out += ","
		out += digits[n]
	return "$" + out


static func label(preset: int) -> String:
	return NAMES[preset] if is_valid(preset) else NAMES[DEFAULT]
