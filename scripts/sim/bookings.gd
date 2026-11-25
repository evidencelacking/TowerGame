class_name Bookings
extends RefCounted
## Bookable event rooms (#359, our own design, every number an unverified tunable): the ballroom and the
## conference center. Pure and stateless. Bookings are automatic: every window a room's needs are met, it is
## booked (Commerce._serve_booking does the serving; the guests and the fee are in Commerce.PROFILES).
## Needs: the ballroom needs a kitchen (a restaurant or fine dining room) and the conference center a hotel room
## in the tower; without one it takes no bookings. A room no route reaches does not count.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")

const BALLROOM := "ballroom"
const CONFERENCE := "conference_center"
const PARTY_HALL := "party_hall"
const KINDS: Array[String] = [BALLROOM, CONFERENCE, PARTY_HALL]
const KITCHEN_KINDS: Array[String] = ["restaurant", "fine_dining"]


static func is_bookable(kind: String) -> bool:
	return KINDS.has(kind)


## The kinds, any one of which meets the room's need.
static func needed_kinds(kind: String) -> Array[String]:
	if kind == BALLROOM:
		return KITCHEN_KINDS
	if kind == CONFERENCE or kind == PARTY_HALL:
		return HotelScript.KINDS
	return []


## A short phrase for the need, shown in the room panel.
static func need_text(kind: String) -> String:
	if kind == BALLROOM:
		return "a kitchen (a restaurant or fine dining room)"
	if kind == CONFERENCE or kind == PARTY_HALL:
		return "a hotel room"
	return ""


static func needs_met(kind: String, rooms: RoomsScript) -> bool:
	var needed := needed_kinds(kind)
	if needed.is_empty():
		return true
	for id in rooms.room_ids():
		if needed.has(rooms.kind_of(id)) and not rooms.is_cut_off(id):
			return true
	return false
