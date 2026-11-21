class_name Helipad
extends RefCounted
## The helicopter pad's daily income (#409). The pad's other hooks live with the systems they touch: the fire
## rescue discount and speed (fire.gd), the VIP's air arrival (vip.gd) and the roof noise (noise.gd).
##
## Each new day, while the pad stands and is reachable (Rooms.helipad_reachable: not cut off, #368, and not
## burned out), it earns DAILY_INCOME through the ledger as an INCOME line against the pad's room id.
## Nothing is saved: the day boundary comes from the clock. All numbers are tunable.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")

const DAILY_INCOME := 5000  ## Dollars a day (landing fees); the $2,000 a day upkeep is in the catalogue row.


## Credits one day's income when a reachable pad stands. Returns the dollars credited (0 for none).
static func collect(rooms: RoomsScript, ledger: LedgerScript, at_tick: int) -> int:
	if not rooms.helipad_reachable():
		return 0
	ledger.income(at_tick, DAILY_INCOME, rooms.helipad_id())
	return DAILY_INCOME
