extends "res://scripts/sim/tower.gd"
## A tower for tests that stands in for star facts the game cannot yet produce: the keys of
## star_fixture (not saved) override the facts the tower queries. Production code never reads it.

var star_fixture: Dictionary = {}


var fire_fixture: bool = false  ## True: the tower reports a fire (the wedding tests).


func fire_burning() -> bool:
	return fire_fixture or super.fire_burning()


func cathedral_ready() -> bool:
	return bool(star_fixture["cathedral"]) if star_fixture.has("cathedral") else super.cathedral_ready()


func star_facts() -> Dictionary:
	var facts := super.star_facts()
	facts.merge(star_fixture, true)
	return facts
