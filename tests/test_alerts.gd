extends RefCounted
## The alert list (#223): the sim lists a fire and an open VIP card with their floors, and the view's edge markers
## show off-screen ones and jump the camera on a click.

const TowerSim := preload("res://scripts/sim/tower.gd")
const AlertsScript := preload("res://scripts/sim/alerts.gd")
const VipScript := preload("res://scripts/sim/vip.gd")
const AlertMarkers := preload("res://scripts/view/alert_markers.gd")
const TowerCamera := preload("res://scripts/view/tower_camera.gd")
const TestVip := preload("res://tests/test_vip.gd")
const TestFire := preload("res://tests/test_fire.gd")


## A VIP tower stopped with the arrival notice open (18:30 day 0).
static func _noticed() -> TowerSim:
	var t := TestVip._tower({"stress": 0})
	TestVip._run_to(t, 18 * 60 + 30, 0)
	return t


static func run(check: Callable) -> void:
	# A fire: an alert at the burning room's floor.
	var f := TestFire._tower(3)
	TestFire._put(f, "security", 3, 100)
	TestFire._put(f, "office", 30, 100)
	TestFire._force(f)
	check.call(TestFire._until_burning(f), "a fire breaks out")
	var burning: int = f.fire.burning_rooms()[0]
	var floor_number: int = f.rooms.floors_of(f.grid, burning)[0]
	var found := false
	for alert: Array in AlertsScript.list(f):
		found = found or (alert[0] == AlertsScript.FIRE and alert[1] == floor_number and alert[2] == AlertsScript.ACTIVE and alert[3] == burning)
	check.call(found and AlertsScript.label_of([AlertsScript.FIRE, floor_number, 1, burning], f) == "Fire", "the alert list holds the fire, its floor and state")
	var before := f.state_hash()
	AlertsScript.list(f)
	check.call(f.state_hash() == before, "reading the alerts changes nothing")

	# An open VIP card: an event alert at the suite's floor.
	var t := _noticed()
	var alerts := AlertsScript.list(t)
	check.call(alerts.size() == 1 and alerts[0] == [AlertsScript.EVENT, 3, AlertsScript.OPEN, VipScript.KIND] and AlertsScript.label_of(alerts[0], t) == "VIP arrival", "the open VIP card is an alert on its floor")

	# Markers: off-screen located alerts only, above or below, and a click jumps the camera.
	var lobby_y := AlertMarkers.world_y_of(1)
	var top_y := AlertMarkers.world_y_of(30)
	check.call(AlertMarkers.side_of(top_y, lobby_y, 2.0, 1080.0) == -1 and AlertMarkers.side_of(AlertMarkers.world_y_of(-9), lobby_y, 2.0, 1080.0) == 1 and AlertMarkers.side_of(AlertMarkers.world_y_of(3), lobby_y, 2.0, 1080.0) == 0, "a floor above, below or in view is told apart")
	var all: Array = [[AlertsScript.FIRE, 30, 1, 5], [AlertsScript.EVENT, 3, 0, 103], [AlertsScript.THREAT, 0, 1, 0], [AlertsScript.EVENT, -9, 0, 9]]
	var shown := AlertMarkers.markers(all, lobby_y, 2.0, 1080.0)
	check.call(shown.size() == 2 and shown[0]["floor"] == 30 and shown[0]["side"] == -1 and shown[1]["floor"] == -9 and shown[1]["side"] == 1, "only located, off-screen alerts get a marker")
	var camera := TowerCamera.new()
	var markers := AlertMarkers.new()
	markers.bind(f, camera)
	markers.show_for(all, lobby_y, 2.0, 1080.0)
	var button := markers.root.find_child("Alert0", true, false) as Button
	check.call(button != null and markers.root.find_child("Alert1", true, false) == null and markers.root.find_child("Alert3", true, false) != null, "a button per marker")
	button.pressed.emit()
	check.call(is_equal_approx(camera._focus.y, top_y), "clicking a marker jumps the camera to the floor")
	markers.show_for(all, top_y, 2.0, 1080.0)
	check.call(markers.root.find_child("Alert0", true, false) == null, "the marker goes once the floor is in view")
	markers.free()
	camera.free()
