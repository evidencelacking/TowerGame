class_name PersonNames
extends RefCounted
## Person names (5.9). A generated name is derived from the tower's seed and the person's id, so
## it is never saved; only the player's renames are. Integers only: a rename is stored as code
## points. Our own name lists, original to this game.

## Names are two or three invented syllables each, so 2,000 people almost never share one.
const FIRST_START: Array[String] = [
	"Al", "Be", "Ca", "Do", "El", "Fi", "Ga", "Ha", "Io", "Ju", "Ka", "Le", "Mi", "Ne", "Or", "Pa",
	"Qu", "Ri", "So", "Ta", "Ul", "Ve", "Wi", "Yo", "Zan", "Bri", "Cle", "Dra", "Fen", "Gri", "Tam", "Sef",
]
const FIRST_END: Array[String] = [
	"na", "ra", "lo", "mi", "vin", "dra", "ne", "to", "ric", "sa", "lin", "ko", "ber", "dan", "la", "mon",
	"ta", "del", "ven", "sie", "ro", "bel", "nik", "una", "ras", "ty", "ken", "mar", "lou", "pha", "zi", "ek",
]
const LAST_START: Array[String] = [
	"Ash", "Birk", "Cal", "Dun", "Ell", "Fen", "Gar", "Hol", "Ing", "Jes", "Kes", "Low", "Mar", "Nor",
	"Oak", "Pry", "Row", "Sab", "Tho", "Van", "Wil", "Yar", "Brand", "Crane", "Dale", "Ever", "Flin",
	"Gro", "Har", "Lin", "Pell", "Stan",
]
const LAST_END: Array[String] = [
	"by", "ford", "der", "more", "ery", "wick", "row", "lis", "ham", "sup", "trel", "ry", "ton", "well",
	"ley", "gate", "dale", "croft", "son", "shaw", "mont", "field", "wood", "stead", "ner", "ling", "wyn", "cott",
]
const LAST_MID: Array[String] = ["", "", "", "en", "er", "ing", "or", "al"]  ## Mostly none: a short surname.

const BAND_YOUNG := 0
const BAND_ADULT := 1
const BAND_SENIOR := 2
const BAND_NAMES: Array[String] = ["Young", "Adult", "Senior"]
## Out of 100: below YOUNG_PERCENT is young, below YOUNG_PERCENT + ADULT_PERCENT adult, else senior.
const YOUNG_PERCENT := 25
const ADULT_PERCENT := 55

## Job titles by room kind and age band (young, adult, senior). A kind not listed has none.
const TITLES: Dictionary = {
	"office": [
		["Clerk", "Junior Analyst", "Assistant", "Intern"],
		["Analyst", "Accountant", "Manager", "Designer", "Engineer", "Planner"],
		["Director", "Senior Manager", "Senior Analyst", "Partner"],
	],
	"fast_food": [["Cashier", "Fry Cook", "Runner"], ["Cook", "Shift Lead", "Counter Server"], ["Manager", "Head Cook"]],
	"restaurant": [["Busser", "Dishwasher", "Server"], ["Cook", "Server", "Host", "Sous Chef"], ["Head Chef", "Floor Captain", "Manager"]],
	"retail": [["Stocker", "Cashier", "Sales Assistant"], ["Sales Associate", "Buyer", "Shopkeeper"], ["Store Manager", "Senior Buyer"]],
	"medical": [["Orderly", "Trainee Nurse"], ["Nurse", "Technician", "Doctor"], ["Senior Doctor", "Head Nurse"]],
	"gym": [["Desk Attendant", "Trainee Coach"], ["Personal Trainer", "Coach", "Instructor"], ["Head Coach", "Gym Manager"]],
	"daycare": [["Helper", "Trainee Carer"], ["Childminder", "Nursery Nurse", "Play Leader"], ["Head Carer", "Nursery Manager"]],
	"nightclub": [["Cloakroom Attendant", "Glass Collector"], ["Barman", "Bouncer", "DJ"], ["Head Barman", "Club Manager"]],
	"casino": [["Chip Runner", "Coat Check"], ["Croupier", "Pit Boss", "Cashier"], ["Floor Manager", "Casino Director"]],
	"pool": [["Towel Attendant", "Pool Cleaner"], ["Lifeguard", "Swim Coach", "Lifeguard"], ["Head Lifeguard", "Pool Manager"]],
	"cafe": [["Dishwasher", "Barista Trainee"], ["Barista", "Baker"], ["Cafe Manager", "Head Barista"]],
	"pizza": [["Dough Hand", "Delivery Runner"], ["Pizza Chef", "Waiter"], ["Pizzeria Owner", "Head Pizzaiolo"]],
	"sushi": [["Kitchen Hand", "Rice Cook"], ["Sushi Chef", "Waiter"], ["Head Sushi Chef", "Restaurant Manager"]],
	"fine_dining": [["Commis Chef", "Busser"], ["Sommelier", "Sous Chef", "Maitre d'"], ["Executive Chef", "General Manager"]],
	"bar": [["Glass Collector", "Barback"], ["Bartender", "Waiter"], ["Head Bartender", "Bar Manager"]],
	"observation_deck": [["Ticket Clerk", "Telescope Attendant"], ["Guide", "Deck Host"], ["Deck Manager", "Head of Visitor Experience"]],
	"coworking": [["Front Desk Assistant", "Trainee Host"], ["Community Host", "Events Coordinator"], ["Space Manager", "Head of Community"]],
	"clinic": [["Receptionist", "Trainee Nurse"], ["Nurse", "GP", "Physiotherapist"], ["Senior GP", "Practice Manager"]],
	"security": [["Junior Guard"], ["Guard", "Patrol Officer"], ["Chief of Security"]],
	"housekeeping": [["Trainee Maid"], ["Housekeeper", "Linen Porter"], ["Head Housekeeper"]],
	"condo": [["Student", "Apprentice", "Young Professional"], ["Resident", "Commuter", "Homeowner"], ["Retiree", "Pensioner", "Elder"]],
	"hotel_single": [["Backpacker", "Guest"], ["Guest", "Traveller"], ["Guest", "Retired Traveller"]],
	"hotel_twin": [["Guest", "Backpacker"], ["Guest", "Traveller"], ["Guest", "Retired Traveller"]],
	"hotel_suite": [["Guest"], ["Guest", "Executive Guest"], ["Guest", "Honoured Guest"]],
}

const MAX_LENGTH := 16  ## Longest rename, in characters.
const FIRST_CODE := 32  ## Renames use printable ASCII only: space to tilde.
const LAST_CODE := 126

## The tower's seed (set by Tower in _init, before any load). Saved, so a loaded tower names people the same way.
var name_seed: int = 0
var _renames: Dictionary = {}  ## person id -> String


## splitmix64 finaliser: spreads a number over all 64 bits. Wraps on every machine.
static func _mix(x: int) -> int:
	x += -7046029254386353131  # 0x9E3779B97F4A7C15
	x = (x ^ ((x >> 30) & 0x3FFFFFFFF)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
	x = (x ^ ((x >> 27) & 0x1FFFFFFFFF)) * -7723592293110705685  # 0x94D049BB133111EB
	return x ^ ((x >> 31) & 0x1FFFFFFFF)


## The generated name for a seed and person id: always the same pair.
static func generated(seed_value: int, id: int) -> String:
	var h := _mix(seed_value ^ _mix(id))
	var h2 := _mix(h)
	var first := FIRST_START[(h & 0x7FFFFFFF) % FIRST_START.size()] + FIRST_END[((h >> 8) & 0x7FFFFFFF) % FIRST_END.size()]
	var last := LAST_START[(h2 & 0x7FFFFFFF) % LAST_START.size()] + LAST_MID[((h2 >> 8) & 0x7FFFFFFF) % LAST_MID.size()] + LAST_END[((h2 >> 16) & 0x7FFFFFFF) % LAST_END.size()]
	return "%s %s" % [first, last]


## The age band (BAND_YOUNG, BAND_ADULT or BAND_SENIOR) for a seed and person id: always the same.
static func age_band(seed_value: int, id: int) -> int:
	var roll := (_mix(seed_value ^ _mix(id + 0x5151)) & 0x7FFFFFFF) % 100
	if roll < YOUNG_PERCENT:
		return BAND_YOUNG
	return BAND_ADULT if roll < YOUNG_PERCENT + ADULT_PERCENT else BAND_SENIOR


## The job title for a seed, person id and the kind of room they work or live in ("" if the kind has none).
## band, when not -1, replaces the id's own age band (a promotion reads as a senior title).
static func title_for(seed_value: int, id: int, kind: String, band: int = -1) -> String:
	if not TITLES.has(kind):
		return ""
	var list: Array = (TITLES[kind] as Array)[age_band(seed_value, id) if band < 0 else band]
	return list[(_mix(seed_value ^ _mix(id + 0x7777)) & 0x7FFFFFFF) % list.size()]


## The name to show: the player's rename if there is one, else the generated name.
func name_of(id: int) -> String:
	return _renames[id] if _renames.has(id) else generated(name_seed, id)


func is_renamed(id: int) -> bool:
	return _renames.has(id)


## Keeps printable ASCII, trims the ends and cuts to MAX_LENGTH.
static func clean(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= FIRST_CODE and code <= LAST_CODE:
			out += char(code)
	return out.strip_edges().substr(0, MAX_LENGTH).strip_edges()


## Renames a person; an empty (cleaned) name returns them to the generated one.
func rename(id: int, text: String) -> void:
	var cleaned := clean(text)
	if cleaned == "":
		_renames.erase(id)
	else:
		_renames[id] = cleaned


## RENAME_PERSON args: the person id, then one code point per character.
static func args_for(id: int, text: String) -> Array[int]:
	var args: Array[int] = [id]
	var cleaned := clean(text)
	for i in cleaned.length():
		args.append(cleaned.unicode_at(i))
	return args


func apply_args(args: Array[int]) -> void:
	if args.is_empty():
		return
	var text := ""
	for i in range(1, args.size()):
		if args[i] >= FIRST_CODE and args[i] <= LAST_CODE:
			text += char(args[i])
	rename(args[0], text)


## Flat ints for hashing and saving: seed, rename count, then id, length, code points each.
func state_ints() -> Array[int]:
	var ints: Array[int] = [name_seed, _renames.size()]
	var ids: Array = _renames.keys()
	ids.sort()
	for id: int in ids:
		var text: String = _renames[id]
		ints.append(id)
		ints.append(text.length())
		for i in text.length():
			ints.append(text.unicode_at(i))
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 2 or ints[1] < 0:
		return false
	var at := 2
	var previous := -1
	for _n in ints[1]:
		if at + 2 > ints.size() or ints[at] <= previous:
			return false
		previous = ints[at]
		var length: int = ints[at + 1]
		if length < 1 or length > MAX_LENGTH or at + 2 + length > ints.size():
			return false
		for i in length:
			if ints[at + 2 + i] < FIRST_CODE or ints[at + 2 + i] > LAST_CODE:
				return false
		at += 2 + length
	return at == ints.size()


func load_ints(ints: Array) -> void:
	name_seed = ints[0]
	_renames = {}
	var at := 2
	for _n in ints[1]:
		var text := ""
		for i in ints[at + 1]:
			text += char(ints[at + 2 + i])
		_renames[ints[at]] = text
		at += 2 + ints[at + 1]
