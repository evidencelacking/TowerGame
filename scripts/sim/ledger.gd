class_name Ledger
extends RefCounted
## The money ledger. Whole dollars, integers only. Every change to the balance is one line,
## so the balance always equals the sum of the lines. Rent and running costs come later (M3+).

const DEFAULT_STARTING_FUNDS := 2000000  ## Dollars; a setting, overridable per new game.

## Line kinds.
const OPENING := 1  ## The starting funds, tick 0.
const CHARGE := 2  ## A purchase: amount is negative.
const REFUND := 3  ## Any adjustment that always applies (positive money back, or negative).

## Results returned by charge().
const OK := 0
const SHORT_OF_FUNDS := 1
const BAD_AMOUNT := 2  ## A charge must be zero or more.

var balance: int = 0
## One entry per line: [tick, amount, kind, ref]. ref is a room id or other int reference.
var lines: Array = []


func _init(starting_funds: int = DEFAULT_STARTING_FUNDS) -> void:
	_add(0, starting_funds, OPENING, 0)


## Spends cost dollars. Refused (nothing recorded) when cost exceeds the balance; an exact
## balance succeeds. Returns OK or a refusal reason.
func charge(at_tick: int, cost: int, ref: int) -> int:
	if cost < 0:
		return BAD_AMOUNT
	if cost > balance:
		return SHORT_OF_FUNDS
	_add(at_tick, -cost, CHARGE, ref)
	return OK


## Applies amount dollars. Never refused: a refund is positive, but a negative amount (a
## clawback) is also accepted, so the balance may go negative.
func refund(at_tick: int, amount: int, ref: int) -> void:
	_add(at_tick, amount, REFUND, ref)


func line_sum() -> int:
	var total := 0
	for line: Array in lines:
		total += line[1]
	return total


func _add(at_tick: int, amount: int, kind: int, ref: int) -> void:
	lines.append([at_tick, amount, kind, ref])
	balance += amount


## Flat ints for hashing and saving: line count, then each line.
func state_ints() -> Array[int]:
	var ints: Array[int] = [lines.size()]
	for line: Array in lines:
		ints.append_array([line[0], line[1], line[2], line[3]])
	return ints


## Validates ints from state_ints(); the first line must be the opening line.
static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 5 or ints[0] < 1 or ints.size() != 1 + 4 * ints[0]:
		return false
	return ints[3] == OPENING


func load_ints(ints: Array) -> void:
	lines = []
	balance = 0
	for i in range(ints[0]):
		var base := 1 + 4 * i
		_add(ints[base], ints[base + 1], ints[base + 2], ints[base + 3])
