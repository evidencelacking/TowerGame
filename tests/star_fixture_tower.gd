extends "res://scripts/sim/tower.gd"
## A tower for tests that stands in for star facts the game cannot yet produce: the keys of
## star_fixture (not saved) override the facts the tower queries. Production code never reads it.

var star_fixture: Dictionary = {}


func star_facts() -> Dictionary:
	var facts := super.star_facts()
	facts.merge(star_fixture, true)
	return facts
