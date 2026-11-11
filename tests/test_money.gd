extends RefCounted
## Money tests: starting funds setting, refusal when short, exact balance, refunds, ledger.

const Harness := preload("res://tests/harness.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const LedgerScript := preload("res://scripts/sim/ledger.gd")


## Queues one money command for the next tick and steps, so it applies.
static func _send(tower: TowerSim, kind: int, amount: int) -> void:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, kind, [amount, 1])])
	tower.step()


static func run(check: Callable) -> void:
	var tower := Harness.make(1)
	check.call(tower.ledger.balance == 2000000, "a new game starts with $2,000,000")
	check.call(TowerSim.new(1, 750000).ledger.balance == 750000, "starting funds can be set per game")

	_send(tower, Command.PURCHASE, 5000)
	check.call(tower.ledger.balance == 1995000 and tower.last_refusal == LedgerScript.OK, "an affordable purchase is charged")
	check.call(tower.ledger.balance == tower.ledger.line_sum(), "a fresh game's ledger sums to its balance")

	var poor := TowerSim.new(1, 1000)
	_send(poor, Command.PURCHASE, 1001)
	check.call(poor.ledger.balance == 1000 and poor.last_refusal == LedgerScript.SHORT_OF_FUNDS, "a purchase over the balance is refused with a reason")
	check.call(poor.ledger.lines.size() == 1, "a refused purchase adds no ledger line")
	_send(poor, Command.PURCHASE, 1000)
	check.call(poor.ledger.balance == 0 and poor.last_refusal == LedgerScript.OK, "a purchase of exactly the balance succeeds")

	var ledger := LedgerScript.new(100)
	check.call(ledger.charge(1, 101, 1) == LedgerScript.SHORT_OF_FUNDS, "the API refuses a charge over the balance")
	check.call(ledger.charge(1, -5, 1) == LedgerScript.BAD_AMOUNT, "a negative charge is refused")
	check.call(ledger.charge(1, 100, 1) == LedgerScript.OK and ledger.balance == 0, "the API accepts an exact-balance charge")
	ledger.refund(2, -150, 9)
	check.call(ledger.balance == -150, "a refund always applies and the balance can go negative")
	check.call(ledger.balance == ledger.line_sum(), "the ledger sums to the balance when negative")

	var t2 := TowerSim.new(1, 100)
	_send(t2, Command.PURCHASE, 100)
	_send(t2, Command.REFUND, 30)
	_send(t2, Command.PURCHASE, 500)
	check.call(t2.ledger.balance == 30 and t2.ledger.balance == t2.ledger.line_sum(), "the ledger sums to the balance after commands")
	check.call(t2.ledger.lines.size() == 3, "each applied charge and refund is one line, plus the opening line")

	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(t2.save()) and loaded.ledger.balance == 30 and loaded.state_hash() == t2.state_hash(), "the ledger survives save and load")
