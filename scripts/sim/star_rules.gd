class_name StarRules
extends RefCounted
## Star requirements as data, and the promotion check. Integers only.
##
## REQUIREMENTS maps a star rating to what a tower needs to reach it. Today only star 2 is
## here (population 300; docs/gameplay-reference.md). Ranks 3 to 5 (#20, 7.1) add rows with more
## fields (security, services, VIP, metro) and a matching test in meets(); rating_after is
## already generic over rows. What each star unlocks is the "star" column of the room catalogue.
## Population counts people in the tower at the moment of the check, not residents, so it
## swings with the time of day. Stars never drop (owner ruling 2026-11-14): promotion only.

const Clock := preload("res://scripts/sim/clock.gd")

const REQUIREMENTS: Dictionary = {
	2: {"population": 300},
}

## In-game minute of the day whose period start runs the check, once per day. The reference
## does not say when ranks are evaluated (unverified); 14:00 is the start of the afternoon
## period, when workers are in. Tunable.
const CHECK_MINUTE := 840


## True on the single tick of each day that begins the period starting at CHECK_MINUTE.
static func is_check_tick(clock: Clock) -> bool:
	return clock.ticks_in_period() == 0 and Clock.period_start(clock.period() - 1) == CHECK_MINUTE


## True if a tower with this population qualifies for the star.
static func meets(star: int, population: int) -> bool:
	if not REQUIREMENTS.has(star):
		return false
	return population >= int(REQUIREMENTS[star]["population"])


## The star rating after a check: current, or higher by however many ranks are now earned in
## order. Never lower than current.
static func rating_after(current: int, population: int) -> int:
	var star := current
	while star < 5 and meets(star + 1, population):
		star += 1
	return star
