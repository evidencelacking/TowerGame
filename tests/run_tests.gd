extends SceneTree
## Headless game tests. Prints only failures, then a final summary line that
## tools/check.py requires. Exit code is the number of failures.

const TestTower := preload("res://tests/test_tower.gd")
const TestClock := preload("res://tests/test_clock.gd")
const TestGrid := preload("res://tests/test_grid.gd")
const TestCamera := preload("res://tests/test_camera.gd")
const TestDriver := preload("res://tests/test_driver.gd")
const TestHarness := preload("res://tests/test_harness.gd")
const TestRoomCatalogue := preload("res://tests/test_room_catalogue.gd")
const TestMoney := preload("res://tests/test_money.gd")
const TestHud := preload("res://tests/test_hud.gd")
const TestDisplay := preload("res://tests/test_display.gd")
const TestFloors := preload("res://tests/test_floors.gd")
const TestLobby := preload("res://tests/test_lobby.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestBulldoze := preload("res://tests/test_bulldoze.gd")
const TestReplace := preload("res://tests/test_replace.gd")
const TestStairs := preload("res://tests/test_stairs.gd")
const TestGhost := preload("res://tests/test_ghost.gd")
const TestMessages := preload("res://tests/test_messages.gd")
const TestToolbar := preload("res://tests/test_toolbar.gd")
const TestPeople := preload("res://tests/test_people.gd")
const TestRoutes := preload("res://tests/test_routes.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestStress := preload("res://tests/test_stress.gd")
const TestPeopleView := preload("res://tests/test_people_view.gd")

var failures := 0


func _initialize() -> void:
	TestTower.run(check)
	TestClock.run(check)
	TestGrid.run(check)
	TestCamera.run(check)
	TestDriver.run(check)
	TestHarness.run(check)
	TestRoomCatalogue.run(check)
	TestMoney.run(check)
	TestHud.run(check)
	TestDisplay.run(check)
	TestFloors.run(check)
	TestLobby.run(check)
	TestRooms.run(check)
	TestBulldoze.run(check)
	TestReplace.run(check)
	TestStairs.run(check)
	TestGhost.run(check)
	TestMessages.run(check)
	TestToolbar.run(check)
	TestPeople.run(check)
	TestRoutes.run(check)
	TestTenancy.run(check)
	TestOfficeDay.run(check)
	TestCondos.run(check)
	TestStress.run(check)
	TestPeopleView.run(check)
	print("TESTS FINISHED failures=%d" % failures)
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
