class_name PersonNames
extends RefCounted
## Person names (5.9). A generated name is derived from the tower's seed and the person's id, so
## it is never saved; only the player's renames are. Integers only: a rename is stored as code
## points. Our own name lists, original to this game.

const FIRST: Array[String] = [
	"Ada", "Bram", "Cora", "Dov", "Edda", "Finn", "Gale", "Hana", "Ivo", "Juno", "Kit", "Lena",
	"Milo", "Nell", "Orrin", "Pia", "Quin", "Rhea", "Sol", "Tove", "Una", "Vik", "Wren", "Xia",
	"Yuri", "Zeke", "Bea", "Cal", "Dina", "Eli", "Fay", "Gus",
]
const LAST: Array[String] = [
	"Ashby", "Birch", "Calder", "Dunmore", "Ellery", "Fenwick", "Garrow", "Hollis", "Ingram",
	"Jessup", "Kestrel", "Lowry", "Marlow", "Norcross", "Oakes", "Pryor", "Quill", "Rowan",
	"Sable", "Thorne", "Upshaw", "Vance", "Wick", "Yarrow", "Ames", "Brandt", "Crane", "Dale",
	"Evers", "Flint", "Grove", "Hart",
]
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
	var first := (h & 0x7FFFFFFF) % FIRST.size()
	var last := ((h >> 32) & 0x7FFFFFFF) % LAST.size()
	return "%s %s" % [FIRST[first], LAST[last]]


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
