class_name RunningCosts
extends RefCounted
## Quarterly running costs (5.4). Once a quarter, at the same tick rent is collected, every placed
## room and link with an "upkeep" in its catalogue row costs that many dollars, and a built ground
## lobby costs the lobby row's upkeep once. Elevators are charged per shaft (cars are free); stairs
## are free (a row without "upkeep" costs nothing). The money goes through Ledger.running_cost, a
## line that is never refused, so the balance may go negative.
##
## All amounts are tunable catalogue data (owner ruling, 2026-11-14). Only the elevator figure of
## about $10,000 is in the reference; the rest are UNVERIFIED and listed in
## RoomCatalogue.UPKEEP_UNVERIFIED. Nothing here is saved: the cost follows from the rooms.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")


## Dollars per quarter for one room kind; 0 when the row has no upkeep.
static func upkeep_of(kind: String) -> int:
	return int(CatalogueScript.row(kind).get("upkeep", 0))


## What the tower would pay now: every placed room and link, plus the lobby if built.
static func quarterly_total(rooms: RoomsScript, floors: FloorsScript) -> int:
	var total := 0
	for id in rooms.room_ids():
		total += upkeep_of(rooms.kind_of(id))
	if floors.has_lobby():
		total += upkeep_of("lobby")
	return total


## Charges one quarter's running costs, one ledger line per room (ref: room id) and one for the
## lobby (ref: 0). Returns the total.
static func charge(rooms: RoomsScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int) -> int:
	var total := 0
	for id in rooms.room_ids():
		var amount := upkeep_of(rooms.kind_of(id))
		if amount > 0:
			ledger.running_cost(at_tick, amount, id)
			total += amount
	var lobby := upkeep_of("lobby")
	if floors.has_lobby() and lobby > 0:
		ledger.running_cost(at_tick, lobby, 0)
		total += lobby
	return total
