class_name Tutorial
extends RefCounted
## The guided first tower (#503): from an empty lot to 2 stars. Reads the sim and never writes to it; the
## player builds through the normal commands. Each step advances when the sim reports it done, never on a
## timer. Progress is not saved: loading a save ends the tutorial and gives a normal game.

const TowerSim := preload("res://scripts/sim/tower.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")

## The tutorial's tower: a fixed seed, and the normal starting funds (never the New game setting).
const SEED := 503
const GOAL_STARS := 2

## Set by the start menu, taken by main.gd when the scene reloads with a fresh tower.
static var pending: bool = false

## [title, hint] per step, in order. Our own wording.
const STEPS: Array[Array] = [
	["Lay the lobby", "Pick Lobby in the toolbar and drag a wide strip along floor 1: everyone enters here."],
	["Build floors and offices", "Build a floor above the lobby, then place two offices on it. Offices bring workers and pay rent."],
	["Add an elevator", "Place a local elevator on the lobby and the floor above, then add a car. Rooms no route reaches stay empty."],
	["Feed your workers", "Place a fast food restaurant near the offices, so workers have somewhere to eat."],
	["Add condos", "Place a condo on a reachable floor. Residents move in when it sells, and the money comes back."],
	["Grow to 300 people", "Keep adding offices and condos, and more floors with elevator service. Rent arrives at the start of each quarter, and running costs go out then too, so keep a cash cushion."],
	["Reach 2 stars", "The rating is checked through the day. Hold 300 people and your tower is promoted."],
]

const DONE_TITLE := "Tutorial complete"
const DONE_TEXT := "Two stars. Security, housekeeping and hotels are now unlocked. Build security offices to earn 3 stars. Carry on building."

var step: int = 0
var finished: bool = false
var skipped: bool = false


func is_active() -> bool:
	return not finished and not skipped


func title() -> String:
	return DONE_TITLE if finished else str(STEPS[step][0])


func hint() -> String:
	return DONE_TEXT if finished else str(STEPS[step][1])


## Ends the tutorial early and leaves a normal game.
func skip() -> void:
	if is_active():
		skipped = true


## Advances through every step the tower already satisfies. Safe to call every tick; reads only.
func update(tower: TowerSim) -> void:
	while is_active() and done(step, tower):
		step += 1
		if step >= STEPS.size():
			finished = true


## True when the sim reports step `index` as done.
static func done(index: int, tower: TowerSim) -> bool:
	match index:
		0:
			return tower.floors.has_lobby()
		1:
			return _count(tower, "office", false) >= 2
		2:
			return not tower.rooms.shaft_ids().is_empty() and _count(tower, "office", true) >= 1
		3:
			return _count(tower, "fast_food", false) >= 1
		4:
			return _count(tower, "condo", false) >= 1
		5:
			return tower.permanent_population() >= int(StarRulesScript.REQUIREMENTS[GOAL_STARS]["population"])
		6:
			return tower.stars >= GOAL_STARS
	return false


## Rooms of one kind in the tower; with `reached` only those a route reaches.
static func _count(tower: TowerSim, kind: String, reached: bool) -> int:
	var n := 0
	for id in tower.rooms.room_ids():
		if tower.rooms.kind_of(id) == kind and not (reached and tower.rooms.is_cut_off(id)):
			n += 1
	return n
