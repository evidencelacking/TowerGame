class_name VacantLook
extends RefCounted
## What an unrented or abandoned unit looks like (#358), drawn over the room in both graphics styles:
## a dark storefront with a pulled shutter, padlock and a Closed or Out of Business sign (shops), dark empty
## desks and a For Lease sign (offices), drawn blinds and no lights (condos and hotel rooms). Original
## pixel lettering, no font and no images. View only: RoomLook.describe() says which rooms are empty.
## `fine` is the Detailed style, which adds slats, a door frame and a sign outline in half-pixel steps.
## Every loop below steps by at least 2 pixels toward a fixed bound, so each one ends.

const VC := preload("res://scripts/view/view_consts.gd")
const CommerceScript := preload("res://scripts/sim/commerce.gd")

const GLYPH_W := 3
const GLYPH_H := 5
const ADVANCE := 4
## 3x5 pixel letters, one int per row (top to bottom), bit 2 the left column. Only the letters the signs use.
const GLYPHS: Dictionary = {
	"A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6], "C": [7, 4, 4, 4, 7], "D": [6, 5, 5, 5, 6],
	"E": [7, 4, 6, 4, 7], "F": [7, 4, 6, 4, 4], "I": [7, 2, 2, 2, 7], "L": [4, 4, 4, 4, 7],
	"N": [5, 7, 7, 5, 5], "O": [7, 5, 5, 5, 7], "R": [6, 5, 6, 5, 5], "S": [3, 4, 2, 1, 6],
	"T": [7, 2, 2, 2, 2], "U": [5, 5, 5, 5, 7],
}

const DARK := Color(0.02, 0.03, 0.08)
const SIGN_PLATE := Color(0.90, 0.88, 0.80)
const SIGN_INK := Color(0.62, 0.10, 0.10)
const LEASE_INK := Color(0.12, 0.30, 0.62)
const SHUTTER := Color(0.46, 0.48, 0.52)
const SHUTTER_LINE := Color(0.30, 0.32, 0.36)
const LOCK := Color(0.88, 0.72, 0.25)
const BLIND := Color(0.82, 0.78, 0.66)
const BLIND_GAP := Color(0.52, 0.48, 0.40)

const SHOP := "shop"
const OFFICE := "office"
const HOME := "home"


## Which vacant look a kind gets: SHOP, OFFICE, HOME or "" (none).
static func family(kind: String) -> String:
	if CommerceScript.is_shop(kind):
		return SHOP
	if kind == "office":
		return OFFICE
	if kind == "condo" or kind.begins_with("hotel_"):
		return HOME
	return ""


## The sign wording for a vacant unit of this kind and width: "OUT OF BUSINESS", "CLOSED" or "FOR LEASE", or ""
## when the room is too narrow to hold it.
static func sign_text(kind: String, width: int) -> String:
	var fam := family(kind)
	var wanted: Array[String] = []
	if fam == SHOP:
		wanted = ["OUT OF BUSINESS", "CLOSED"]
	elif fam == OFFICE:
		wanted = ["FOR LEASE"]
	for text: String in wanted:
		if text_width(text) + 4 <= width:
			return text
	return ""


static func text_width(text: String) -> int:
	return text.length() * ADVANCE - 1


## Paints the vacant look over a room's interior. rect is the room's world rect, as for RoomLook.draw_marks.
static func draw(canvas: Object, kind: String, rect: Rect2i, fine: bool = false) -> void:
	var fam := family(kind)
	if fam == "":
		return
	var inner := Rect2i(rect.position.x + 1, rect.end.y - VC.CELL_H, rect.size.x - 1, VC.CELL_H - VC.SLAB_H)
	if fam == SHOP:
		_shop(canvas, kind, inner, fine)
	elif fam == OFFICE:
		_office(canvas, kind, inner, fine)
	else:
		_blinds(canvas, inner, fine)


static func _shop(canvas: Object, kind: String, inner: Rect2i, fine: bool) -> void:
	canvas.draw_rect(inner, Color(DARK, 0.55))
	var door_w: int = mini(8, maxi(inner.size.x - 4, 2))
	var door := Rect2(inner.position.x + (inner.size.x - door_w) / 2.0, inner.end.y - 20.0, door_w, 20.0)
	canvas.draw_rect(door, SHUTTER)
	var y: float = door.position.y + 2.0
	while y < door.end.y:  # the pulled shutter's slats
		canvas.draw_rect(Rect2(door.position.x, y, door.size.x, 1), SHUTTER_LINE)
		y += 2.0 if fine else 3.0
	canvas.draw_rect(Rect2(door.position.x + door.size.x / 2.0 - 1.0, door.end.y - 5.0, 2, 2), LOCK)  # the padlock
	if fine:  # a frame round the door
		canvas.draw_rect(door.grow(0.5), SHUTTER_LINE, false, 0.5)
	_sign(canvas, sign_text(kind, inner.size.x), inner, 3, SIGN_INK, fine)


static func _office(canvas: Object, kind: String, inner: Rect2i, fine: bool) -> void:
	canvas.draw_rect(inner, Color(DARK, 0.45))
	var dusty := Color(0.35, 0.33, 0.30, 0.8)
	var x: int = inner.position.x + 3
	while x + 6 <= inner.end.x - 2:  # bare desks, nobody at them
		canvas.draw_rect(Rect2(x, inner.end.y - 9, 6, 1), dusty)
		canvas.draw_rect(Rect2(x + 1, inner.end.y - 8, 1, 6), dusty)
		canvas.draw_rect(Rect2(x + 4, inner.end.y - 8, 1, 6), dusty)
		x += 9
	_sign(canvas, sign_text(kind, inner.size.x), inner, 4, LEASE_INK, fine)


static func _blinds(canvas: Object, inner: Rect2i, fine: bool) -> void:
	canvas.draw_rect(inner, Color(DARK, 0.4))  # no lights
	var w: int = inner.size.x - 8
	if w < 4:
		return
	var step: float = 2.0 if fine else 3.0
	var y: float = inner.position.y + 4.0
	var bottom: float = inner.position.y + 15.0
	while y < bottom:  # drawn blinds across the window
		canvas.draw_rect(Rect2(inner.position.x + 4, y, w, step - 1.0), BLIND)
		canvas.draw_rect(Rect2(inner.position.x + 4, y + step - 1.0, w, 1), BLIND_GAP)
		y += step


## The sign: a plate with the lettering, hung `top` pixels into the room. Without text it draws nothing.
static func _sign(canvas: Object, text: String, inner: Rect2i, top: int, ink: Color, fine: bool) -> void:
	if text == "":
		return
	var w := text_width(text)
	var x: int = inner.position.x + (inner.size.x - w) / 2
	var y: int = inner.position.y + top
	canvas.draw_rect(Rect2(x - 2, y - 1, w + 4, GLYPH_H + 2), SIGN_PLATE)
	if fine:
		canvas.draw_rect(Rect2(x - 2, y - 1, w + 4, GLYPH_H + 2), ink.darkened(0.4), false, 0.5)
	var pen := x
	for ch: String in text:
		if GLYPHS.has(ch):
			var rows: Array = GLYPHS[ch]
			for r in GLYPH_H:
				for c in GLYPH_W:
					if (((rows[r] as int) >> (GLYPH_W - 1 - c)) & 1) == 1:
						canvas.draw_rect(Rect2(pen + c, y + r, 1, 1), ink)
		pen += ADVANCE
