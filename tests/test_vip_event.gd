extends RefCounted
## The VIP as a full event (#219): Events.open for a manual kind that draws nothing, the
## arrival notice and its choices (standard rate, discount, turn away, timeout), the verdict's reasons and saving.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const EventsScript := preload("res://scripts/sim/events.gd")
const VipScript := preload("res://scripts/sim/vip.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const MessageLog := preload("res://scripts/view/message_log.gd")
const EventWindow := preload("res://scripts/view/event_window.gd")
const TestVip := preload("res://tests/test_vip.gd")
const TestHotel := preload("res://tests/test_hotel.gd")
const TestEvents := preload("res://tests/test_events.gd")

const MANUAL := 77  ## A made-up manual kind for the scheduler tests.


static func _manual(timeout: int = 50) -> Dictionary:
	return {"id": MANUAL, "class": EventsScript.ORDINARY, "manual": true, "choices": 3, "timeout": timeout, "floor": 0, "default": 2}


## A VIP tower stopped with the arrival notice open (18:30 day 0).
static func _noticed(mood: Dictionary) -> TowerSim:
	var t := TestVip._tower(mood)
	TestVip._run_to(t, 18 * 60 + 30, 0)
	return t


## Answers the open notice through the command and lets the sim apply it.
static func _answer(t: TowerSim, choice: int) -> void:
	var id: int = t.events.open_events()[0][0]
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, choice] as Array[int]))
	for _i in 20:  # the VIP reads the answer on its own cadence
		t.step()


static func _verdict(t: TowerSim) -> void:
	TestHotel._jump(t, 9 * 60 + 30, 1)
	TestHotel._step_to(t, 10 * 60 + 10, 1)


static func _hotel_dollars(t: TowerSim) -> int:
	var total := 0
	for line: Array in TestHotel._hotel_lines(t):
		total += line[1]
	return total


static func run(check: Callable) -> void:
	_scheduler(check)
	_choices(check)
	_reasons(check)
	_saving(check)


static func _scheduler(check: Callable) -> void:
	# Events.open starts a card at once, with the kind's deadline and choices, and no draw.
	var t := TestEvents._tower(3, [TestEvents._kind(1, 0), _manual()] as Array[Dictionary])
	var rolls := t.events.rolls
	var id := t.events.open(MANUAL, 12, 100)
	var card := t.events.event_of(id)
	check.call(id == 1 and card[1] == MANUAL and card[2] == 12 and card[4] == 100 and card[5] == 150 and card[6] == 3, "Events.open: a card with the kind, floor, deadline and choices")
	check.call(t.events.rolls == rolls and t.events.open(999, 0, 100) == 0, "Events.open: no draw, and an unknown kind opens nothing")
	t.events.open(MANUAL, 0, 100)
	t.events.open(MANUAL, 0, 100)
	check.call(t.events.open_count() == 3 and t.events.open(MANUAL, 0, 100) == 0, "Events.open: the open cap holds")
	check.call(t.events.withdraw(2) and t.events.event_of(2).is_empty() and t.events.resolved().is_empty() and not t.events.withdraw(2), "Events.withdraw drops a card unlogged")
	t.events.tick(t.clock, 3, 150)
	var gone := t.events.resolved()
	check.call(not gone.is_empty() and gone[0][2] == 2, "a manual card times out to its kind's default, not necessarily decline")

	# Registering a manual kind shifts no fire or threat draw: the same seed gives the same rolls and events.
	var plain := TestEvents._tower(7, TestEvents._mixed())
	var kinds := TestEvents._mixed()
	kinds.insert(1, _manual())
	var with_manual := TestEvents._tower(7, kinds)
	TestEvents._run(plain, 7000)
	TestEvents._run(with_manual, 7000)
	check.call(plain.events.rolls > 10 and plain.events.rolls == with_manual.events.rolls, "a manual kind adds no roll")
	check.call(not plain.events.resolved().is_empty() and plain.events.state_ints() == with_manual.events.state_ints() and plain.events.resolved() == with_manual.events.resolved(), "a manual kind leaves the other kinds' draws and events exactly unchanged")
	var real := TowerSim.new(7)
	check.call(real.events.kind_def(VipScript.KIND).get("manual", false) and real.events.kinds.size() == 3, "the tower registers the VIP notice as a manual kind")


static func _choices(check: Callable) -> void:
	var mood := {"stress": 0}
	# The notice: an event card with three choices, the suite held, and the floor of the suite.
	var t := _noticed(mood)
	var suite := TestHotel._room(t)
	var card: Array = t.events.open_events()[0]
	check.call(t.vip.awaiting_choice() and t.vip.reserved_suite() == suite and card[1] == VipScript.KIND and card[2] == 3 and card[6] == 3, "the arrival opens a notice card on the suite's floor and holds the suite")
	var shown := EventWindow.describe(t)
	check.call(shown.size() == 1 and shown[0]["labels"].size() == 3 and shown[0]["labels"][1].contains("$%d" % t.hotel.price(suite)) and shown[0]["text"].contains("%d days" % VipScript.RETRY_DAYS), "the card says the rates and the delay in plain words")

	# Standard rate: the stay pays the nightly price at the verdict.
	var standard := _noticed(mood)
	_answer(standard, VipScript.CHOICE_STANDARD)
	check.call(standard.vip.rate() == VipScript.CHOICE_STANDARD and not standard.vip.awaiting_choice(), "the standard rate starts the stay")
	_verdict(standard)
	check.call(standard.vip.is_good() and _hotel_dollars(standard) == standard.hotel.price(suite) and standard.hotel.price(suite) > 0, "the standard-rate stay pays the suite's nightly price at the verdict")

	# Discount: the stay pays nothing and the verdict is the same.
	var discount := _noticed(mood)
	_answer(discount, VipScript.CHOICE_DISCOUNT)
	check.call(discount.vip.rate() == VipScript.CHOICE_DISCOUNT, "the discount starts the stay")
	_verdict(discount)
	check.call(discount.vip.is_good() and _hotel_dollars(discount) == 0, "the discount stay pays nothing and the verdict is unchanged")

	# Turn away: no stay, no verdict, the suite free, the next visit RETRY_DAYS later, and a new notice then.
	var away := _noticed(mood)
	_answer(away, VipScript.CHOICE_DECLINE)
	check.call(not away.vip.is_visiting() and away.vip.reserved_suite() == -1 and away.vip.visits() == 0 and away.vip.next_day() == VipScript.RETRY_DAYS, "turning the VIP away delays the visit three days with no verdict")
	check.call(TestVip._has_message(away, Messages.VIP_DECLINED), "turning the VIP away is logged")
	TestHotel._jump(away, 17 * 60 + 30, 2)
	TestHotel._step_to(away, 19 * 60, 2)
	check.call(not away.vip.is_visiting(), "no VIP comes before the delay is over")
	away.hotel.remove_room(suite)  # forget any ordinary booking of the suite, so it is vacant again
	TestHotel._jump(away, 17 * 60 + 30, 3)
	TestHotel._step_to(away, 19 * 60, 3)
	check.call(away.vip.awaiting_choice(), "a new notice opens on the retry day")

	# No answer: the notice times out to the standard rate, never to turning the VIP away.
	var silent := _noticed(mood)
	TestHotel._step_to(silent, 23 * 60 + 30, 0)
	check.call(silent.vip.rate() == VipScript.CHOICE_STANDARD and silent.events.resolved()[0][2] == VipScript.CHOICE_STANDARD, "an unanswered notice times out to the standard rate")
	_verdict(silent)
	check.call(_hotel_dollars(silent) == silent.hotel.price(suite), "and that stay pays the standard rate")

	# Bulldozing the suite while the notice is open withdraws it.
	var razed := _noticed(mood)
	razed.rooms.bulldoze(razed.grid, razed.floors, razed.ledger, razed.tick, 3, 110)
	TestHotel._step_to(razed, 20 * 60, 0)
	check.call(not razed.vip.is_visiting() and razed.events.open_count() == 0 and razed.events.resolved().is_empty(), "bulldozing the suite withdraws the open notice")


static func _reasons(check: Callable) -> void:
	# A good verdict has no reason; a poor tower names the factors it used.
	var good := _noticed({"stress": 0})
	_answer(good, VipScript.CHOICE_STANDARD)
	_verdict(good)
	check.call(good.vip.is_good() and good.vip.why() == 0, "a good verdict has no reason")
	var poor := _noticed({"stress": 200})
	_answer(poor, VipScript.CHOICE_STANDARD)
	_verdict(poor)
	var both: int = VipScript.WHY_SUITE_OTHER | VipScript.WHY_TOWER_OTHER
	var logged := 0
	for i in poor.messages.count():
		if poor.messages.entry(i)[1] == Messages.VIP_BAD:
			logged = poor.messages.entry(i)[3]
	check.call(not poor.vip.is_good() and poor.vip.why() == both and logged == both, "bad quality that is not travel names the rents, noise and complaints, in the verdict's message")
	var text := MessageLog.describe(Messages.VIP_BAD, 1, both)
	check.call(text.contains("rents, noise or complaints") and not text.contains("elevators"), "the log words those reasons")

	# Travel stress alone: slow elevators.
	var slow := _noticed({"stress": 0})
	var suite := TestHotel._room(slow)
	slow.people.set_stress(0, 200)
	var travel: int = VipScript.WHY_SUITE_TRAVEL | VipScript.WHY_TOWER_TRAVEL
	check.call(VipScript.verdict_reasons(slow.rooms, slow.people, slow.grades, suite) == travel, "stress from travel names the slow elevators")
	check.call(MessageLog.vip_reasons(travel).contains("slow elevators") and MessageLog.vip_reasons(0) == "no reason recorded", "the log words that too")
	slow.people.set_stress(0, 0)
	check.call(VipScript.verdict_reasons(slow.rooms, slow.people, slow.grades, suite) == 0, "and no stress names nothing")


static func _saving(check: Callable) -> void:
	var t := _noticed({"stress": 0})
	var loaded := TowerSim.new(1, 100000000)
	check.call(loaded.load_state(t.save()) and loaded.state_hash() == t.state_hash() and loaded.vip.awaiting_choice(), "a tower saved with the notice open loads the same")
	_answer(t, VipScript.CHOICE_DISCOUNT)
	_answer(loaded, VipScript.CHOICE_DISCOUNT)
	check.call(loaded.state_hash() == t.state_hash() and loaded.vip.rate() == VipScript.CHOICE_DISCOUNT, "and carries on the same once answered")
	check.call(not VipScript.valid_ints([0, -1, 0, 0, 0, 0, 0, -1, 0]) and VipScript.valid_ints(t.vip.state_ints()) and not VipScript.valid_ints([2, 5, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0]), "the old 9-int VIP record and a notice with no event are refused")
	var quiet := TowerSim.new(1, 100000000)
	check.call(quiet.vip.hash_ints().size() == 9, "a tower with no notice hashes its VIP exactly as before")
	check.call(t.vip.hash_ints().size() == 12, "once a notice has run the new fields are hashed")
