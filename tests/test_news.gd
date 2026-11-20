extends RefCounted
## Tower news ticker tests (12.4): every story kind renders a sentence with the names, tower events
## join the feed, the feed is newest first, a click target resolves to a person, room or floor, and a
## click does the right thing. Clicking never changes the sim hash.

const TowerSim := preload("res://scripts/sim/tower.gd")
const LifeScript := preload("res://scripts/sim/life.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const NewsFeed := preload("res://scripts/view/news_feed.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestPersonWindow := preload("res://tests/test_person_window.gd")


static func run(check: Callable) -> void:
	var t := TestPersonWindow._fixture()
	var a: int = t.people.id_at(0)
	var b: int = t.people.id_at(1)
	var condo: int = t.rooms.room_ids()[0]
	var run: Array[int] = t.grid.run_of(condo)
	var floor_number: int = run[0]

	# Every life story kind renders a sentence with the person's name.
	var all_named := true
	for kind in LifeScript.KIND_COUNT:
		t.life._record(100 + kind, kind, a, b, condo)
		var item := NewsFeed.life_item(t, t.life.story_count() - 1)
		var sentence: String = item["text"]
		all_named = all_named and sentence.contains(t.names.name_of(a)) and sentence.contains(LifeScript.KIND_NAMES[kind]) and (item["people"] as Array).has(a)
	check.call(all_named, "news: each of the %d life story kinds renders a sentence with the name" % LifeScript.KIND_COUNT)
	var couple := NewsFeed.life_item(t, 0)
	check.call((couple["people"] as Array) == [a, b] and (couple["text"] as String).contains(t.names.name_of(b)), "news: a couple story names and targets both people")
	check.call((couple["text"] as String).ends_with("on floor %d" % floor_number), "news: a story with a room says its floor")

	# Tower events: each news code renders, other codes are not news.
	var rendered := true
	for code: int in NewsFeed.TOWER_STORIES:
		var item := NewsFeed.message_item(t, [500, code, condo, floor_number] as Array[int])
		rendered = rendered and not item.is_empty() and (item["text"] as String) != "Something happened" and item["tick"] == 500
	check.call(rendered, "news: each tower event kind (%d) renders a sentence" % NewsFeed.TOWER_STORIES.size())
	check.call(NewsFeed.message_item(t, [500, Msg.ROOM_BUILT, 1, 2] as Array[int]).is_empty(), "news: building a room is not news")

	# The feed merges both and is newest first, capped at the limit.
	t.messages.add(900, Msg.FIRE_STARTED, 0, floor_number)
	t.life._record(950, LifeScript.PROMOTION, b, -1, condo)
	var feed := NewsFeed.latest(t, 3)
	check.call(feed.size() == 3 and feed[0]["tick"] == 950 and feed[1]["tick"] == 900 and feed[2]["tick"] == 105, "news: the feed is newest first and merges life stories with tower events")
	check.call(NewsFeed.latest(TowerSim.new(1, 0), 5).is_empty(), "news: a new tower has no news")

	# Click targets.
	var fire := NewsFeed.message_item(t, [900, Msg.FIRE_STARTED, 0, floor_number] as Array[int])
	var fire_at := NewsFeed.place_of(t, fire)
	check.call(fire_at.x < 0.0 and is_equal_approx(fire_at.y, (VC.floor_to_row(floor_number) + 0.5) * VC.CELL_H), "news: a floor story targets its floor row")
	var room_at := NewsFeed.place_of(t, NewsFeed.life_item(t, t.life.story_count() - 1))
	check.call(is_equal_approx(room_at.x, (run[1] + run[2] / 2.0) * VC.CELL_W), "news: a story with a room targets the middle of the room")
	check.call(NewsFeed.place_of(t, NewsFeed.message_item(t, [1, Msg.STAR_PROMOTED, 3, 0] as Array[int])) == Vector2.INF, "news: a story with no place has no target")

	# The ticker: shows the newest stories, a click on a person's story opens and follows, a tower story jumps.
	var camera := TowerCamera.new()
	var window := TestPersonWindow._window(t)
	window.camera = camera
	var ticker := NewsTicker.new()
	ticker.bind(t, camera, window, null)
	check.call(ticker.items().size() == NewsTicker.SHOWN and ticker.story_buttons[0].text == feed[0]["text"], "news ticker: the strip shows the newest stories first")
	var hash_before := t.state_hash()
	check.call(ticker.activate(0) and window.person_id == b and window.is_following(), "news ticker: clicking a person's story opens their window and follows them")
	window.close()
	check.call(ticker.activate(1) and not camera.is_following() and is_equal_approx(camera._focus.y, fire_at.y), "news ticker: clicking a tower story jumps the camera to its floor")
	check.call(not ticker.activate(9), "news ticker: a click past the last story does nothing")
	ticker.set_open(false)
	check.call(not ticker.is_open() and not ticker.toggle_button.button_pressed, "news ticker: the News button hides the strip")
	ticker.set_open(true)
	check.call(ticker.is_open(), "news ticker: and shows it again")
	check.call(t.state_hash() == hash_before, "news ticker: clicking stories leaves the sim hash unchanged")

	# The person window lists their recent stories.
	window.open_person(a)
	var recent := window.recent_lines(a)
	check.call(recent.size() == 1 + PersonWindow.RECENT_STORIES and recent[0] == "Recent:" and recent[1].contains(t.names.name_of(a)), "news: the person window lists their recent stories")
	check.call(window.recent_lines(-5).is_empty(), "news: a person with no stories lists none")
	check.call(window.panel.body_text().contains("Recent:"), "news: the open window shows them")
	ticker.free()
	window.free()
	camera.free()
