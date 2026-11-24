class_name StarRules
extends RefCounted
## Star requirements as data, and the promotion check. Integers only.
##
## REQUIREMENTS maps a star rating to what a tower needs to reach it (docs/gameplay-reference.md). What each star unlocks is the "star" column of the room catalogue.
## Population counts people in the tower at the moment of the check, not residents, so it
## swings with the time of day. Stars never drop (owner ruling 2026-11-14): promotion only.

## Each row lists what a tower needs for that star. A tower meets a row when every field holds:
##   population    the permanent population at the check: everyone registered with the tower, in or out (#456).
##   security      at least this many security offices.
##   suites        at least this many hotel suites.
##   demands_met   true: no open demand of any kind (medical, recycling, parking, transport; owner
##                 ruling on #166). Needs the demand systems; until they exist the fact is false.
##   vip_good      true: the last VIP visit ended well. Until the VIP exists the fact is false.
##   metro         at least this many metro stations.
## The facts a tower reports are a Dictionary with the same keys (see Tower.star_facts); a key that
## is missing counts as 0 or false. The top rank is TOP_RANK below.
const REQUIREMENTS: Dictionary = {
	2: {"population": 300},
	3: {"population": 1000, "security": 1},
	4: {"population": 5000, "suites": 2, "demands_met": true, "vip_good": true},
	5: {"population": 10000, "metro": 1},
}

## The top rank (#33): a gate, not a star. Keys as in REQUIREMENTS plus "stars" (the rating) and "cathedral" (true: a cathedral is
## reached and not charred). When it holds the wedding sets itself (Wedding); the rank itself comes when the wedding succeeds.
const TOP_RANK: Dictionary = {"stars": 5, "population": 15000, "cathedral": true}

## Ticks between checks. Population is read at the tick of the check, so it swings with the time
## of day, and a star once earned is kept (owner ruling on #166), so any tick can promote. Checking
## every tick would walk every person, so the sim checks on every 15th tick. Tunable.
const CHECK_EVERY := 15


## True on the ticks that run the promotion check.
static func is_check_tick(tick: int) -> bool:
	return tick % CHECK_EVERY == 0


## True if a tower with these facts qualifies for the star.
static func meets(star: int, facts: Dictionary) -> bool:
	if not REQUIREMENTS.has(star):
		return false
	var row: Dictionary = REQUIREMENTS[star]
	for field: String in row:
		var need: Variant = row[field]
		if typeof(need) == TYPE_BOOL:
			if bool(facts.get(field, false)) != need:
				return false
		elif int(facts.get(field, 0)) < int(need):
			return false
	return true


## True if the tower's facts open the way to the top-rank wedding: every field of TOP_RANK holds.
static func meets_top_rank(facts: Dictionary) -> bool:
	for field: String in TOP_RANK:
		var need: Variant = TOP_RANK[field]
		if typeof(need) == TYPE_BOOL:
			if bool(facts.get(field, false)) != need:
				return false
		elif int(facts.get(field, 0)) < int(need):
			return false
	return true


## The population the star needs (out of reach for a star with no row), for the cheap first test.
static func population_for(star: int) -> int:
	return int(REQUIREMENTS[star]["population"]) if REQUIREMENTS.has(star) else 1 << 30


## The star rating after a check: current, or higher by however many ranks are now earned in
## order. Never lower than current.
static func rating_after(current: int, facts: Dictionary) -> int:
	var star := current
	while star < 5 and meets(star + 1, facts):
		star += 1
	return star
