extends RefCounted
## Detailed people (#304): the G Lit mock-up's figures (mockups/detail_drawer.gd person(), _head(),
## sleeper(), _zzz()) ported to the sub-pixel pen. A standing figure is 12 by 32 sub-pixels, which is the
## same box as Classic's FIGURE_W by FIGURE_H native pixels, so rooms, spots and picking are unchanged.
## Everything is drawn from a figure's id and its state (who), never from the clock or a random draw, so
## the same person looks the same on every machine and every frame; animation takes a frame number from
## the caller (the tick for people at rest, distance walked for walkers).
##
## who: {"id", "age" (Names.BAND_*), "child", "job" (the room kind they work in, or ""), "band" (stress
## band), "shirt" (stress colour when band is not 0), "dir" (-1 or 1), "still" (standing, not walking)}.
## Coordinates below are sub-pixels from the figure's left edge and feet row: x 0 to 12, up is negative.

const Pen := preload("res://scripts/view/detail_pen.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const NamesScript := preload("res://scripts/sim/names.gd")

const INK := Color("2a1f2b")
const NONE := Color(0.0, 0.0, 0.0, 0.0)  ## "No cap, no apron": alpha 0.
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const SHADOW := Color("1a1220")

const WALK := 0  ## Mirrors PeopleView.POSE_*.
const STAIRS := 1
const ESCALATOR := 2

const SKINS: Array[Color] = [Color("f0c59a"), Color("d9a074"), Color("8a5a3c"), Color("f4d2b0"), Color("e8b88c"), Color("6a4228"), Color("c58a5e"), Color("a06a44")]
const HAIRS: Array[Color] = [Color("3a2418"), Color("1c1414"), Color("141010"), Color("c98a3c"), Color("7a4a2a"), Color("a8502a"), Color("5a3a22"), Color("e6d08a")]
const GREY := Color("8a8a90")
const WHITE_HAIR := Color("d8d8dc")
const SHIRTS: Array[Color] = [Color("c8453c"), Color("3f7fb0"), Color("e0a83a"), Color("6aa06a"), Color("9a55b0"), Color("eeeae0"), Color("d0708a"), Color("4aa0a0"), Color("e07a3a"), Color("7a86c8")]
const KID_SHIRTS: Array[Color] = [Color("e8503c"), Color("f0c030"), Color("40a0e0"), Color("60c070"), Color("e070b0")]
const PANTS: Array[Color] = [Color("3d4660"), Color("4a3a52"), Color("2f3a4a"), Color("5a4a6a"), Color("46506a"), Color("2a2f3c"), Color("5a4a38")]
const SHOES: Array[Color] = [Color("2a1f2b"), Color("3a2a2a"), Color("1c1618"), Color("2a2a30")]
const SUITS: Array[Color] = [Color("2e3a58"), Color("3a3a44"), Color("4a3a3a"), Color("2a4a4a"), Color("4a4458")]
const TIES: Array[Color] = [Color("c8453c"), Color("3f7fb0"), Color("e0a83a"), Color("6aa06a"), Color("9a55b0")]

## Uniform colours by the room kind the person works in: [top, trousers, cap, apron] (NONE for none).
const UNIFORMS: Dictionary = {
	"fast_food": [Color("d8483a"), Color("3a3a44"), Color("d8483a"), Color("f4f0e6")],
	"restaurant": [Color("f4f0e6"), Color("23232b"), NONE, Color("23232b")],
	"retail": [Color("5a9a5a"), Color("3a3a44"), Color("5a9a5a"), NONE],
	"housekeeping": [Color("3f9aa0"), Color("2a4a50"), Color("f4f0e6"), Color("f4f0e6")],
	"security": [Color("2e3a58"), Color("232b40"), Color("2e3a58"), NONE],
	"medical": [Color("e6f0f0"), Color("4a8a9a"), NONE, NONE],
}

const LEG_H := 10
const TORSO_H := 13
const KID_LEG_H := 6
const KID_TORSO_H := 10


static func _hash(id: int, salt: int) -> int:
	var h := (id * 374761393 + salt * 668265263 + 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return (h ^ (h >> 16)) & 0xffff


## What a person looks like, from the id, the age band and the job: skin, hair (style and colour), top,
## trousers, shoes, and the outfit kind ("suit", "uniform" or "casual") with its extras.
static func look_of(who: Dictionary) -> Dictionary:
	var id: int = who.get("id", 0)
	var age: int = who.get("age", NamesScript.BAND_ADULT)
	var child: bool = who.get("child", false)
	var job: String = who.get("job", "")
	var skin: Color = SKINS[_hash(id, 1) % SKINS.size()]
	var hair: Color = HAIRS[_hash(id, 2) % HAIRS.size()]
	var style := _hash(id, 3) % 4  # 0 short, 1 long, 2 bald, 3 bun
	if style == 2 and age != NamesScript.BAND_SENIOR and _hash(id, 4) % 4 != 0:
		style = 0  # baldness is rare outside the seniors
	if child and style == 2:
		style = 0
	if age == NamesScript.BAND_SENIOR and not child:
		hair = GREY if _hash(id, 5) % 3 != 0 else WHITE_HAIR
	var look := {"skin": skin, "hair": hair, "style": style, "top": SHIRTS[_hash(id, 6) % SHIRTS.size()],
		"pants": PANTS[_hash(id, 7) % PANTS.size()], "shoe": SHOES[_hash(id, 8) % SHOES.size()],
		"outfit": "casual", "tie": NONE, "cap": NONE, "apron": NONE, "child": child}
	if child:
		look["top"] = KID_SHIRTS[_hash(id, 6) % KID_SHIRTS.size()]
	elif job == "office":
		var suit: Color = SUITS[_hash(id, 9) % SUITS.size()]
		look["outfit"] = "suit"
		look["top"] = suit
		look["pants"] = suit.darkened(0.12)
		look["tie"] = TIES[_hash(id, 10) % TIES.size()]
	elif UNIFORMS.has(job):
		var u: Array = UNIFORMS[job]
		look["outfit"] = "uniform"
		look["top"] = u[0]
		look["pants"] = u[1]
		look["cap"] = u[2]
		look["apron"] = u[3]
	if who.get("band", 0) != 0 and who.has("shirt"):
		look["top"] = who["shirt"]  # the stress cue still reads: an uneasy or angry person wears the band colour
	return look


# ---------------------------------------------------------------- primitives (the mock-up's helpers, sub-pixels)

## The pixel range a float span covers: pixels whose centre lies inside it, as a rasteriser fills.
static func _span(a: float, extent: float) -> Vector2i:
	return Vector2i(ceili(a - 0.5), ceili(a + extent - 0.5))


static func _r(pen: Object, x: float, y: float, w: float, h: float, c: Color) -> void:
	var sx := _span(x, w)
	var sy := _span(y, h)
	if sx.y > sx.x and sy.y > sy.x:
		pen.R(sx.x, sy.x, sx.y - sx.x, sy.y - sy.x, c)


## The mock-up's item(): a hard outline (corners cut when r > 0), light top edge, dark bottom edge and a
## shaded right side, so a figure part reads in three tones.
static func _item(pen: Object, x: float, y: float, w: float, h: float, c: Color, r: float = 0.0, outline: bool = true) -> void:
	if w <= 0.0 or h <= 0.0:
		return
	var cut := 1.0 if r > 0.0 else 0.0
	if outline:
		var dark := c.darkened(0.55)
		_r(pen, x - 1.0 + cut, y - 1.0, w + 2.0 - 2.0 * cut, h + 2.0, dark)
		_r(pen, x - 1.0, y - 1.0 + cut, w + 2.0, h + 2.0 - 2.0 * cut, dark)
	_r(pen, x, y, w, h, c)
	if h >= 3.0 and w >= 3.0:
		_r(pen, x + cut, y, w - 2.0 * cut, 1.0, c.lightened(0.3))
		_r(pen, x, y + h - 1.0, w, 1.0, c.darkened(0.28))
		if w >= 6.0:
			_r(pen, x + w - 1.0, y + 1.0, 1.0, h - 2.0, c.darkened(0.14))
	if h >= 5.0 and w >= 4.0:
		_r(pen, x, y + 1.0, 1.0, h - 2.0, c.lightened(0.12))


## A filled ellipse scanned row by row, the mock-up's ell().
static func _ell(pen: Object, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var iy := ceili(ry)
	for dy in range(-iy, iy):
		var t := (float(dy) + 0.5) / ry
		if absf(t) >= 1.0:
			continue
		var hw := rx * sqrt(1.0 - t * t)
		var x0 := roundi(cx - hw)
		var x1 := roundi(cx + hw)
		if x1 > x0:
			pen.R(x0, floori(cy) + dy, x1 - x0, 1, c)


## The mock-up's soft shadow: two dithered rings under the feet. The dither is keyed to the world's
## sub-pixel grid (the pen's origin), so a figure's shadow does not shimmer as it moves a pixel.
static func _shadow(pen: Object, cx: float, y: float, rx: float, strength: float) -> void:
	var ry := maxf(1.5, rx * 0.16)
	var ox := roundi(pen.origin.x * 2.0)
	var oy := roundi(pen.origin.y * 2.0)
	for ring_i in 2:
		var k := 1.0 - float(ring_i) * 0.5
		var iy := ceili(ry * k)
		var dens := strength * (0.16 if ring_i == 0 else 0.3)
		for dy in range(-iy, iy):
			var t := (float(dy) + 0.5) / (ry * k)
			if absf(t) >= 1.0:
				continue
			var hw := rx * k * sqrt(1.0 - t * t)
			var yy := floori(y) + dy
			for px in range(roundi(cx - hw), roundi(cx + hw)):
				if (float(BAYER[((yy + oy) & 3) * 4 + ((px + ox) & 3)]) + 0.5) / 16.0 < dens:
					pen.R(px, yy, 1, 1, SHADOW)


## The mock-up's _head(): neck, hair (short, long, bald or bun), face, eyes and mouth. A cap covers the hair.
static func _head(pen: Object, cx: float, cy: float, look: Dictionary, d: float) -> void:
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var hs: int = look["style"]
	_r(pen, cx - 1.5, cy + 3.0, 3.0, 3.0, skin.darkened(0.12))
	if hs == 1:  # long hair falls behind the shoulders
		_item(pen, cx - 5.0, cy - 3.0, 10.0, 12.0, hair, 3.0, false)
	_ell(pen, cx, cy, 4.0, 4.6, skin)
	match hs:
		0, 1:
			_ell(pen, cx, cy - 2.2, 4.4, 3.2, hair)
			_r(pen, cx - 4.2, cy - 2.0, 2.0, 4.0, hair)
			_r(pen, cx + 2.2, cy - 2.0, 2.0, 4.0, hair)
		2:
			_ell(pen, cx, cy - 3.6, 3.0, 1.2, hair)
		3:
			_ell(pen, cx, cy - 2.4, 4.3, 3.0, hair)
			_ell(pen, cx - d * 3.2, cy - 5.0, 2.2, 2.2, hair)
	var cap: Color = look["cap"]
	if cap.a > 0.0:  # a uniform cap: a crown over the hair and a brim in front
		_ell(pen, cx, cy - 3.2, 4.6, 2.6, cap)
		_r(pen, cx + (0.0 if d > 0.0 else -5.0), cy - 2.0, 5.0, 1.0, cap.darkened(0.25))
	var ex := cx + d * 1.2
	_r(pen, ex - 2.0, cy - 0.5, 1.0, 1.4, INK)
	_r(pen, ex + 1.0, cy - 0.5, 1.0, 1.4, INK)
	_r(pen, ex - 0.5, cy + 2.2, 2.0, 1.0, skin.darkened(0.35))


## Jacket details over a torso: a white shirt front and a tie for suits, an apron for uniforms.
static func _outfit(pen: Object, look: Dictionary, cx: float, torso_y: float, torso_h: float) -> void:
	match look["outfit"]:
		"suit":
			_r(pen, cx - 1.0, torso_y + 1.0, 2.0, 5.0, Color("f4f0e6"))
			_r(pen, cx - 0.5, torso_y + 1.0, 1.0, 6.0, look["tie"])
		"uniform":
			var apron: Color = look["apron"]
			if apron.a > 0.0:
				_r(pen, cx - 3.0, torso_y + 4.0, 6.0, torso_h - 4.0, apron)
				_r(pen, cx - 3.0, torso_y + 4.0, 6.0, 1.0, apron.lightened(0.2))


# ---------------------------------------------------------------- figures

## A person standing or walking. pose is WALK, STAIRS or ESCALATOR; walk is the frame 0 to 3: legs apart,
## passing (one foot lifted, the body a step higher), legs apart with the arms swapped, passing again.
static func walker(canvas: Object, x: int, feet: int, who: Dictionary, pose: int, walk: int) -> void:
	var pen := Pen.new(canvas, Vector2(x, feet))
	var look := look_of(who)
	var d := float(who.get("dir", 1))
	if who.get("still", false):  # waiting in a queue: standing, feet a little apart
		_standing(pen, look, d, 1, 0, 0, 0, 0)
		return
	var f := ((walk % 4) + 4) % 4
	var stride := 0
	var lift_l := 0
	var lift_r := 0
	var arms := 0
	var bob := 0
	if pose == STAIRS:  # one foot up a step, the body bobbing
		stride = 1
		lift_l = 3 if f < 2 else 0
		lift_r = 3 if f >= 2 else 0
		bob = f % 2
		arms = 1 if f < 2 else -1
	elif pose == WALK:
		stride = 2 if f % 2 == 0 else 0
		lift_l = 1 if f == 1 else 0
		lift_r = 1 if f == 3 else 0
		bob = f % 2
		arms = 2 if f == 0 else (-2 if f == 2 else 0)
	_standing(pen, look, d, stride, lift_l, lift_r, arms, bob)


## A standing figure after the mock-up's person(): legs and shoes, torso with belt, arms and hands, head.
## stride spreads the legs, lift_* raise a foot, arms swing the hands in opposite directions, bob lifts the
## body a sub-pixel.
static func _standing(pen: Object, look: Dictionary, d: float, stride: int, lift_l: int, lift_r: int, arms: int, bob: int) -> void:
	var cx := 6.0
	var child: bool = look["child"]
	var leg_h := KID_LEG_H if child else LEG_H
	var torso_h := KID_TORSO_H if child else TORSO_H
	var pants: Color = look["pants"]
	var top: Color = look["top"]
	var shoe: Color = look["shoe"]
	var skin: Color = look["skin"]
	_shadow(pen, cx, 0.5, 6.0, 0.55)
	_item(pen, cx - 4.0 - stride, -leg_h - 2.0 - lift_l, 3.0, float(leg_h), pants, 1.0)
	_item(pen, cx + 1.0 + stride, -leg_h - 2.0 - lift_r, 3.0, float(leg_h), pants, 1.0)
	_item(pen, cx - 5.0 - stride, -3.0 - lift_l, 5.0, 3.0, shoe, 1.0, false)
	_item(pen, cx + 0.5 + stride, -3.0 - lift_r, 5.0, 3.0, shoe, 1.0, false)
	var torso_y := float(-leg_h - 2 - torso_h + 1 - bob)
	_item(pen, cx - 4.0, torso_y, 8.0, float(torso_h), top, 2.5)
	_r(pen, cx - 4.0, torso_y + float(torso_h) - 3.0, 8.0, 1.0, pants.darkened(0.1))
	_outfit(pen, look, cx, torso_y, float(torso_h))
	var arm_h := 7.0 if child else 9.0
	var sleeve := top.darkened(0.08)
	_item(pen, cx - 6.5, torso_y + 1.0 + float(arms) * 0.5, 2.0, arm_h, sleeve, 1.0)
	_item(pen, cx + 4.5, torso_y + 1.0 - float(arms) * 0.5, 2.0, arm_h, sleeve, 1.0)
	_r(pen, cx - 6.5, torso_y + arm_h - 1.0 + float(arms) * 0.5, 2.0, 2.0, skin)
	_r(pen, cx + 4.5, torso_y + arm_h - 1.0 - float(arms) * 0.5, 2.0, 2.0, skin)
	_head(pen, cx, torso_y - 4.0, look, d)


## A person at rest doing an activity (ActivityLook.*), at the pose box's left edge x and feet row `feet`.
## frame is ActivityLook.frame(): 0 to 3, each person on an offset of their own.
static func resting(canvas: Object, x: int, feet: int, who: Dictionary, act: int, frame: int) -> void:
	var look := look_of(who)
	var d := float(who.get("dir", 1))
	var f := ((frame % 4) + 4) % 4
	if act == ActivityLook.SLEEPING:
		_sleeping(Pen.new(canvas, Vector2(x, feet - ActivityLook.LYING_UP)), look, f)
		return
	if ActivityLook.SEATED.has(act):
		_seated(Pen.new(canvas, Vector2(x, feet)), look, d, act, f)
		return
	var pen := Pen.new(canvas, Vector2(x, feet))
	var tap := act == ActivityLook.QUEUEING and f % 2 == 1
	var arms := 0
	if act == ActivityLook.CLEANING:
		arms = 2 if f % 2 == 0 else -2
	_standing(pen, look, d, 1, 0, 1 if tap else 0, arms, 0)
	var top := -32.0 + (6.0 if look["child"] else 0.0)
	match act:
		ActivityLook.BREAK:  # a cup with steam, in the front hand
			_r(pen, 6.0 + d * 8.0 - 1.0, top + 16.0, 3.0, 4.0, Color("f4f0e6"))
			_r(pen, 6.0 + d * 8.0 - 1.0 + float(f % 2), top + 11.0, 1.0, 3.0, Color("f4f0e6").darkened(0.05))
		ActivityLook.SHOPPING:  # a bag
			_item(pen, 6.0 + d * 8.0 - 2.0, top + 17.0, 5.0, 8.0, Color("e0a83a"), 1.0)
		ActivityLook.CLEANING:  # a broom, bristles on the floor, swept side to side
			var sweep := float(f % 2) * 2.0
			_r(pen, 6.0 + d * (8.0 + sweep), top + 8.0, 1.0, -(top + 8.0), Color("b0814f"))
			_item(pen, 6.0 + d * (8.0 + sweep) - 2.0, -3.0, 5.0, 3.0, Color("e0c060"), 0.0, false)


## Seated after the mock-up's person() pose 2: thigh, shin and shoe forward, torso up, a forward arm. Hands
## type (a one sub-pixel bob) when working, lift a fork when eating or at lunch.
static func _seated(pen: Object, look: Dictionary, d: float, act: int, frame: int) -> void:
	var cx := 5.0 if d > 0.0 else 11.0
	var child: bool = look["child"]
	var leg_h := KID_LEG_H if child else LEG_H
	var pants: Color = look["pants"]
	var top: Color = look["top"]
	var skin: Color = look["skin"]
	var hip := float(-(leg_h - 1))
	_shadow(pen, cx, 0.5, 6.0, 0.55)
	_item(pen, cx - 4.0 if d > 0.0 else cx - 5.0, hip - 3.0, 9.0, 4.0, pants, 1.5)
	var knee_x := cx + d * 5.0
	_item(pen, knee_x - 1.5, hip - 3.0, 3.0, float(leg_h + 1), pants, 1.0)
	_item(pen, knee_x - 2.0 + (1.0 if d > 0.0 else 0.0), -2.0, 4.0, 2.0, look["shoe"], 0.5, false)
	var torso_h := 10.0 if child else 12.0
	var torso_y := hip - torso_h - 1.0
	_item(pen, cx - 4.0, torso_y, 8.0, torso_h, top, 2.5)
	_outfit(pen, look, cx, torso_y, torso_h)
	var arm_y := hip - torso_h + 1.0
	var hand_y := hip - 5.0 + float(frame % 2)
	if act != ActivityLook.WORKING and frame % 2 == 1:  # fork to the mouth
		hand_y = hip - 11.0
		_r(pen, cx + d * 4.0, hand_y - 3.0, 1.0, 3.0, Color("d8d8e0"))
	_item(pen, cx + d * 2.0 - 1.0, arm_y, 2.0, maxf(hand_y - arm_y + 1.0, 3.0), top.darkened(0.1), 1.0)
	_r(pen, cx + d * 4.0 - 1.0, hand_y, 2.0, 2.0, skin)
	_head(pen, cx, torso_y - 4.0, look, d)


## Someone asleep after the mock-up's sleeper(): head on a pillow, shoulders, a blanket over the rest that
## rises and falls with each breath, and Zs. The pen's origin is the pose box's top left (32 by 10
## sub-pixels), which is the mattress line.
static func _sleeping(pen: Object, look: Dictionary, frame: int) -> void:
	var hx := 5.0
	var hy := 5.0
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var rise := 1.0 if frame >= 2 else 0.0
	_item(pen, hx + 3.0, hy - 3.0, 9.0, 8.0, look["top"], 3.0, false)
	if look["style"] == 1:
		_item(pen, hx - 6.0, hy - 4.0, 8.0, 7.0, hair, 3.0, false)
	_ell(pen, hx, hy, 4.4, 4.4, skin)
	_ell(pen, hx - 1.5, hy - 1.8, 4.2, 3.0, hair)
	_r(pen, hx - 1.5, hy - 0.3, 2.0, 1.0, INK)
	_r(pen, hx + 1.5, hy - 0.3, 2.0, 1.0, INK)
	_r(pen, hx, hy + 2.2, 2.0, 1.0, skin.darkened(0.35))
	var blanket: Color = (look["top"] as Color).lerp(Color("5a6a9a"), 0.6)
	_item(pen, hx + 6.0, hy - 3.0 - rise, 32.0 - hx - 6.0, 8.0 + rise, blanket, 2.0)
	_r(pen, hx + 6.0, hy - 3.0 - rise, 2.0, 8.0 + rise, Color("f4f0e6"))
	_zzz(pen, hx + 3.0, hy - 9.0, 1 + frame % 3)


## The mock-up's _zzz(): rising Zs, drawn as light that is never darkened. `count` of them show (1 to 3).
static func _zzz(pen: Object, x: float, y: float, count: int) -> void:
	var col := Color("e8ecff")
	for i in mini(count, 3):
		var s := 3.0 + float(i) * 1.5
		var zx := x + float(i) * 7.0
		var zy := y - float(i) * 6.0
		var w := roundi(s)
		pen.E(roundi(zx), roundi(zy), w, 1, col)
		pen.E(roundi(zx), roundi(zy + s), w, 1, col)
		for k in w:
			pen.E(roundi(zx + s - float(k)), roundi(zy + float(k)), 1, 1, col)
