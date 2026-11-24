extends RefCounted
## Cheats (#39): each cheat command's effect, the saved `cheated` flag (set by any cheat, survives save and load, never
## cleared), the setting that gates the panel and the commands, the replay hash, and the top-rank message noting cheats.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const TestRooms := preload("res://tests/test_rooms.gd")
const TestWedding := preload("res://tests/test_wedding.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const Log := preload("res://scripts/view/message_log.gd")


static func _cheat(t: TowerSim, kind: int, arg: int) -> void:
	TestRooms._send(t, kind, [arg] as Array[int])


static func run(check: Callable) -> void:
	_commands(check)
	_flag(check)
	_replay(check)
	_setting(check)
	_wedding(check)


static func _commands(check: Callable) -> void:
	var t := TowerSim.new(3, 2000000)
	check.call(not t.cheated, "cheats: a new tower has not cheated")
	var before := t.ledger.balance
	_cheat(t, Command.CHEAT_MONEY, 1000000)
	check.call(t.ledger.balance == before + 1000000 and t.cheated, "cheats: Add $1,000,000 adds exactly that and sets the flag")
	var b2 := t.ledger.balance
	_cheat(t, Command.CHEAT_MONEY, 0)
	_cheat(t, Command.CHEAT_MONEY, -5)
	check.call(t.ledger.balance == b2, "cheats: a zero or negative amount adds nothing")
	_cheat(t, Command.CHEAT_MONEY, 1 << 50)
	check.call(t.ledger.balance == b2 + TowerSim.CHEAT_MONEY_MAX, "cheats: one command adds at most CHEAT_MONEY_MAX")
	_cheat(t, Command.CHEAT_UNLOCK_ALL, 1)
	check.call(t.unlock_all and t.unlocked_stars() == 5 and t.stars == 1, "cheats: unlock all opens every kind and leaves the real stars")
	_cheat(t, Command.CHEAT_UNLOCK_ALL, 0)
	check.call(not t.unlock_all, "cheats: unlock all turns off again")
	_cheat(t, Command.CHEAT_SET_STARS, 4)
	check.call(t.stars == 4, "cheats: set stars raises the rating")
	_cheat(t, Command.CHEAT_SET_STARS, 2)
	check.call(t.stars == 2, "cheats: set stars can also lower it")
	_cheat(t, Command.CHEAT_SET_STARS, 99)
	check.call(t.stars == 5, "cheats: set stars clamps to 5")
	_cheat(t, Command.CHEAT_SET_STARS, -3)
	check.call(t.stars == 1, "cheats: set stars clamps to 1")


static func _flag(check: Callable) -> void:
	for kind: int in [Command.CHEAT_MONEY, Command.CHEAT_UNLOCK_ALL, Command.CHEAT_SET_STARS]:
		var each := TowerSim.new(3, 2000000)
		_cheat(each, kind, 1)
		check.call(each.cheated, "cheats: command %d sets the flag" % kind)
	var plain := TowerSim.new(3, 2000000)
	plain.step()
	check.call(not plain.cheated and plain.save()["cheated"] == 0, "cheats: an untouched tower saves cheated 0")
	var t := TowerSim.new(3, 2000000)
	_cheat(t, Command.CHEAT_SET_STARS, 3)
	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(t.save()) and loaded.cheated, "cheats: the flag survives save and load")
	check.call(loaded.state_hash() == t.state_hash(), "cheats: a loaded cheated tower hashes the same")
	_cheat(loaded, Command.CHEAT_SET_STARS, 1)
	for n in 5:
		loaded.step()
	check.call(loaded.cheated, "cheats: the flag is never cleared")
	var again := TowerSim.new(0)
	check.call(again.load_state(loaded.save()) and again.cheated, "cheats: still set after a second save and load")
	var bad := t.save()
	bad["cheated"] = 7
	check.call(not TowerSim.new(0).load_state(bad), "cheats: a damaged flag is refused")
	check.call(t.state_hash() != plain.state_hash(), "cheats: the flag is part of the state hash")


static func _replay(check: Callable) -> void:
	var a := TowerSim.new(5, 2000000)
	var b := TowerSim.new(5, 2000000)
	for t: TowerSim in [a, b]:
		t.step()
		_cheat(t, Command.CHEAT_MONEY, 1000000)
		_cheat(t, Command.CHEAT_UNLOCK_ALL, 1)
		_cheat(t, Command.CHEAT_SET_STARS, 3)
		for n in 20:
			t.step()
	check.call(a.tick == b.tick and a.state_hash() == b.state_hash(), "cheats: the same cheat commands replay to the same state hash")
	var other := TowerSim.new(5, 2000000)
	for n in a.tick:
		other.step()
	check.call(other.tick == a.tick and other.state_hash() != a.state_hash(), "cheats: a tower at the same tick without them hashes differently")


static func _setting(check: Callable) -> void:
	var was := CheatSettings.enabled
	var was_loaded := CheatSettings._loaded
	CheatSettings.enabled = false
	CheatSettings._loaded = true
	var t := TowerSim.new(3, 2000000)
	var panel := CheatsPanel.new()
	panel.bind(t)
	check.call(not panel.open() and not panel.is_open(), "cheats: with the setting off the panel cannot open")
	var before := t.ledger.balance
	check.call(not panel.add_money() and not panel.unlock_all(true) and not panel.set_stars(5), "cheats: with the setting off no command is sent")
	for n in 3:
		t.step()
	check.call(t.ledger.balance == before and not t.cheated and not t.unlock_all and t.stars == 1, "cheats: with the setting off the tower is untouched")
	CheatSettings.enabled = true
	check.call(panel.open() and panel.is_open(), "cheats: with the setting on the panel opens")
	check.call(panel.add_money() and panel.unlock_all(true) and panel.set_stars(4), "cheats: with the setting on the commands are queued")
	for n in 3:
		t.step()
	check.call(t.ledger.balance == before + CheatsPanel.MONEY and t.unlock_all and t.stars == 4 and t.cheated, "cheats: the panel's commands take effect")
	panel.close()
	check.call(not panel.is_open(), "cheats: close hides the panel")
	check.call(KeyBindings.default_key("cheats") == KEY_F9, "cheats: the panel key is F9")
	var taken := 0
	for row: Array in KeyBindings.ACTIONS:
		if row[2] == KEY_F9:
			taken += 1
	check.call(taken == 1, "cheats: F9 is bound to nothing else")
	panel.free()
	CheatSettings.enabled = was
	CheatSettings._loaded = was_loaded


static func _wedding(check: Callable) -> void:
	for cheated: bool in [false, true]:
		var t := TestWedding._tower()
		t.cheated = cheated
		TestWedding._step_to(t, 40)
		TestWedding._jump(t, TestWedding.WE_START + 20, 25)
		TestWedding._step_to(t, TestWedding.WE_START + 1420)
		check.call(t.wedding.top_rank(), "cheats wedding: the top rank still works (cheated %s)" % cheated)
		var done := TestWedding._last(t.messages, Messages.WEDDING_DONE)
		check.call(done.size() == 4 and done[3] == (1 if cheated else 0), "cheats wedding: the message records whether cheats were used (%s)" % cheated)
		var text := Log.describe(Messages.WEDDING_DONE, done[2], done[3])
		check.call(text.contains("cheats were used") == cheated, "cheats wedding: the text notes cheats only when used (%s)" % cheated)
