extends RefCounted
## Promotion moment (7.2, #167): notices when the tower's star rating rises and says what it
## unlocked. View only; it reads the sim and keeps its own memory of the rank already shown, so a
## rank is announced once. A new or loaded tower is adopted silently: loading a saved game at
## 3 stars shows no banner. Two ranks earned in one tick give one announcement for the higher
## rank, listing every unlock (owner ruling).

const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")

var _tower_id: int = 0
var _shown: int = 0


## Call once per frame with the tower. Returns {} when nothing is new, or
## {"stars": the new rank, "unlocks": [catalogue ids newly open, in toolbar order]}.
func observe(tower: Object) -> Dictionary:
	var id := tower.get_instance_id()
	var stars: int = tower.stars
	if id != _tower_id or stars < _shown:
		_tower_id = id
		_shown = stars
		return {}
	if stars == _shown:
		return {}
	var announced := {"stars": stars, "unlocks": unlocks_between(_shown, stars)}
	_shown = stars
	return announced


## Catalogue ids whose star is above from_star and at most to_star, in toolbar order.
static func unlocks_between(from_star: int, to_star: int) -> Array[String]:
	var found: Array[String] = []
	for entry: Array in ToolbarScript.CATEGORIES:
		for id: String in entry[1]:
			if CatalogueScript.has(id) and CatalogueScript.star(id) > from_star and CatalogueScript.star(id) <= to_star:
				found.append(id)
	return found


## Banner wording: our own, with no rank names from elsewhere.
static func headline(stars: int) -> String:
	return "Your tower is now a %d-star tower" % stars


static func unlock_line(ids: Array) -> String:
	var names: Array[String] = []
	for id: String in ids:
		names.append(ToolbarScript.display_name(id))
	return "New to build: " + ", ".join(names) if not names.is_empty() else "No new buildings this time."
