extends RefCounted
## Detailed transport (#303): stairs, escalators, elevator shafts and cars in the G Lit look, composed from
## the mock-up's own drawing (mockups/detail_drawer.gd: _stairs, _shaft, _escalator and the car) on the
## 2x sub-pixel grid of detail_prims.gd. Stairs and escalators have a background panel on each floor of
## their span (the mock-up's), unlike Classic; they climb one floor over their width with the same slope
## and the same direction rule as Classic, so people ride where the treads are. A car's riders are Detailed
## figures (detail_people.gd).

const Prims := preload("res://scripts/view/detail_prims.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")
const DetailPeople := preload("res://scripts/view/detail_people.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const SUB := 2  ## Mock-up pixels per world pixel.
const SLAB := 4  ## Floor slab, mock-up pixels.
const FLOOR := 64
const DOOR_H := 36  ## Door height in mock-up pixels (Classic's 18).
const RISE := 60  ## A flight's climb, mock-up pixels: floor surface to floor surface.


static func _pen(canvas: Object, rect: Rect2i) -> Prims:
	var pen := Prims.new(canvas, Vector2(rect.position))
	pen.limit = Rect2i(0, 0, rect.size.x * SUB, rect.size.y * SUB)
	return pen


## The wall behind a flight of stairs, one panel per floor of its span: a blue-grey gradient with a light
## cornice, ticks, a baseboard and a pale floor strip (the mock-up's _stairs backdrop), and an exit sign.
static func _stair_panel(p: Prims, w: int) -> void:
	for f: int in 2:
		var y := float(f * FLOOR)
		p.gradv(0, y, w, 56, Color("6f7694"), Color("565c78"))
		p.R(0, y, w, 3, Color("8d93ae"))
		p.R(0, y + 3, w, 1, Color("3e4358"))
		for i: int in range(1, 5):
			p.R(w * i / 5.0, y + 4, 1, 50, Color("5a6080"))
		p.R(0, y + 54, w, 2, Color("3e4358"))
		p.R(0, y + 56, w, 4, Color("8a8498"))
		p.R(0, y + 56, w, 1, Color("aaa4b8"))
		p.R(6, y + 6, 12, 7, Color("2a3a30"))
		p.GR(7, y + 7, 10, 5, Color("5ae08a"))
		p.R(10, y + 9, 4, 1, Color("1a3a28"))


## One flight of stairs in its two-floor span: stepped treads with a solid underside, a handrail on posts.
## Even rows climb to the right, odd rows to the left (as Classic). Behind them a panel on each floor.
static func stairs(canvas: Object, span: Rect2i) -> void:
	var p := _pen(canvas, span)
	var w := span.size.x * SUB
	var fy := float(span.size.y * SUB - SLAB)  # the lower floor's surface
	_stair_panel(p, w)
	if TransportLook.flips(span):
		p.flip_around(w * 0.5)
	var n := maxi(w / 8, 2)
	var run := float(w) / n
	var rise := float(RISE) / n
	for i: int in n:
		var sx := i * run
		var top_y := fy - 2.0 - i * rise - rise
		var body_h := minf(fy - top_y - 8.0, 12.0)
		if body_h > 0.0:  # the solid underside, stepped
			p.R(sx, top_y + 8.0, run, body_h, Color("6a585c"))
			p.R(sx, top_y + 8.0, run, 1, Color("52403f"))
		p.R(sx, top_y + 3, run, 5, Color("7d6a6c"))
		p.R(sx, top_y + 3, run, 1, Color("5a484c"))
		p.item(sx, top_y, run, 3, Color("c2b0a4"), 0.5, false)
		p.R(sx, top_y, run, 1, Color("e8d8cc"))
	p.ln(Vector2(0, fy - 22.0), Vector2(w, fy - 22.0 - RISE), Color("3a2e2c"), 2.0)
	for i: int in range(0, n + 1, 2):  # a post every other step
		var nose := fy - 2.0 - i * rise
		var ry := maxf(nose - 20.0, 2.0)
		if nose - ry > 2.0:
			p.R(i * run, ry, 1, nose - ry, Color("484050"))
	p.flip_off()


## Height of the belt's surface above the lower floor at mock-up column x of a w-wide escalator.
static func _belt_y(yb: float, w: int, x: int) -> float:
	return yb - 2.0 - float(RISE) * (x + 1.0) / w


## An escalator's fixed frame: a dark truss under the belt, a lit belt bed, a glass balustrade panel, a
## handrail band, posts and a footplate at the top and bottom (the moving steps are belt()).
static func escalator(canvas: Object, span: Rect2i) -> void:
	var p := _pen(canvas, span)
	var w := span.size.x * SUB
	var yb := float(span.size.y * SUB - SLAB)
	var hall: Array = ["e6dac2", "b8a27c", "d8d0c4", "a8a0a8", "c8ad6a"]  # the mock-up's escalator hall
	for f: int in 2:
		Scenes.shell_room(p, 0, f * FLOOR, w, f, hall)
	if TransportLook.flips(span):
		p.flip_around(w * 0.5)
	var top_off := 24.0
	for x: int in range(0, w, 2):
		var y := _belt_y(yb, w, x)
		p.R(x, y + 2, 2, 12, Color("424a5e"))  # the truss
		p.R(x, y + 1, 2, 1, Color("8a94ac"))  # the belt bed
		p.R(x, y - top_off + 2, 2, top_off - 6, Color(0.75, 0.88, 0.95, 0.35))  # glass balustrade
		p.R(x, y - top_off, 2, 3, Color("23202a"))  # handrail band
		p.R(x, y - top_off - 1, 2, 1, Color("5a5664"))
	for i: int in 9:  # posts under the rail
		var px := 4 + i * (w - 12) / 8
		p.R(px, _belt_y(yb, w, px) - top_off + 4.0, 1, top_off - 6.0, Color("9aa4b8"))
	p.R(0, yb - 2.0, 16, 3, Color("8a94ac"))  # footplates
	p.R(w - 16.0, yb - 2.0 - RISE, 16, 3, Color("8a94ac"))
	for k: int in 8:
		p.R(k * 2, yb - 2.0, 1, 3, Color("3a4054"))
		p.R(w - 16.0 + k * 2, yb - 2.0 - RISE, 1, 3, Color("3a4054"))
	p.flip_off()


## The escalator's moving steps at a sim tick: a lit edge and a dark gap every 8 mock-up pixels, running up
## the incline one column (two mock-up pixels) a tick, as Classic's belt does.
static func belt(canvas: Object, span: Rect2i, tick: int) -> void:
	var p := _pen(canvas, span)
	var w := span.size.x * SUB
	var yb := float(span.size.y * SUB - SLAB)
	if TransportLook.flips(span):
		p.flip_around(w * 0.5)
	var phase := TransportLook.belt_phase(tick) * 2
	for x: int in range(16, w - 16, 2):
		var y := _belt_y(yb, w, x)
		var q := posmod(x - phase, 8)
		if q < 4:
			p.R(x, y - 3, 2, 1, Color("c8ccd8"))
			p.R(x, y - 2, 2, 2, Color("7a8298"))
		elif q < 6:
			p.R(x, y - 2, 2, 2, Color("3a4054"))
	p.flip_off()


## One shaft: a dark back wall with steel rails down both sides, machine-room caps with a counterweight, and
## at each stop a door with its frame, centre seam and a dark indicator over it. Outline only when see_through.
static func shaft(canvas: Object, rect: Rect2i, color: Color, caps: Array[Rect2i], door_rows: Array[int], see_through: bool) -> void:
	var p := _pen(canvas, rect)
	var w := rect.size.x * SUB
	var h := rect.size.y * SUB
	if see_through:
		var edge := color.lightened(0.4)
		p.R(0, 0, 1, h, edge)
		p.R(w - 1, 0, 1, h, edge)
		p.R(0, 0, w, 1, edge)
		p.R(0, h - 1, w, 1, edge)
		return
	p.gradv(0, 0, w, h, color.darkened(0.55), color.darkened(0.35))
	var rail := mini(3, w / 6)
	for sx: float in [float(w / 12), float(w - w / 12 - rail)]:
		p.R(sx, 0, rail, h, Color("5a6274"))
		p.R(sx, 0, 1, h, Color("8a92a6"))
	for cap: Rect2i in caps:
		var c := Rect2i((cap.position - rect.position) * SUB, cap.size * SUB)
		p.gradv(c.position.x, c.position.y, c.size.x, c.size.y, color.lightened(0.1), color.darkened(0.1))
		p.item(c.position.x + 4.0, c.position.y + 6.0, minf(8.0, c.size.x * 0.3), 22.0, Color("6a707e"), 1.0)
		for k: int in 4:
			p.R(c.position.x + 5.0, c.position.y + 9.0 + k * 5, minf(6.0, c.size.x * 0.25), 1, Color("4a505e"))
	for row: int in door_rows:
		var fy := float((row - rect.position.y) * SUB)
		var inset := 6.0 if w >= 24 else 2.0
		var dw := w - inset * 2.0
		p.item(inset, fy - DOOR_H, dw, DOOR_H, Color("565e70"), 1.0)
		p.R(w * 0.5 - 0.5, fy - DOOR_H + 1.0, 1, DOOR_H - 1.0, Color("2a303e"))
		p.R(inset, fy - DOOR_H, dw, 1, Color("8a92a6"))
		p.R(w * 0.5 - 7.0, fy - DOOR_H - 6.0, 14, 4, Color("1a1e28"))  # the indicator, dark until a car arrives
		p.R(0, fy, w, 2, Color("3a4052"))


## The arrival indicator over the doors of the floor a car stands at (shaft_rect is the top floor of the shaft).
static func arrival(canvas: Object, shaft_rect: Rect2i, level: float, floor_bottom_of: Callable) -> void:
	var nearest := roundi(level)
	if absf(level - nearest) > TransportLook.ARRIVED_SLACK:
		return
	var p := Prims.new(canvas, Vector2(shaft_rect.position.x, 0))
	var fy := float((floor_bottom_of.call(nearest) as int) * SUB)
	var mid := shaft_rect.size.x * SUB * 0.5
	for k: int in 3:
		p.GR(mid - 6.0 + k * 5.0, fy - DOOR_H - 5.0, 3, 2, Color("ff5030"))


## One car: a hanging frame on its cables, a warm panelled interior with a ceiling lamp and centre seam, and a
## floor strip; the riders (Classic's small figures) stand in front.
static func car(canvas: Object, car_rect: Rect2i, load: int, people: Array) -> void:
	var p := Prims.new(canvas, Vector2(car_rect.position))
	var w := car_rect.size.x * SUB
	var h := car_rect.size.y * SUB
	p.R(w * 0.25, -8.0, 1, 8, Color("90969e"))
	p.R(w * 0.75, -8.0, 1, 8, Color("90969e"))
	p.item(-2, -2, w + 4, 4, Color("606878"), 1.0)
	p.item(0, 0, w, h, Color("a4acb8"), 1.5)
	p.R(2, 2, w - 4, h - 4, Color("f0e0b0"))
	p.R(2, h * 0.62, w - 4, 1, Color("c8b486"))
	p.R(2, h * 0.62 + 1, w - 4, h * 0.38 - 5, Color("d8c490"))
	p.R(w * 0.5, 2, 1, h - 4, Color("d0bd88"))
	p.GR(w * 0.5 - 6.0, 2, 12, 2, Color("fffbe8"))
	p.R(2, h - 4, w - 4, 2, Color("6a6070"))
	riders(canvas, car_rect, load, people)


## Up to five riders as Detailed figures (detail_people.gd) inside a car rect, laid out as Classic's: three in
## front, two behind in the gaps, a few pixels higher. `people` only varies who they are.
static func riders(canvas: Object, rect: Rect2i, load: int, people: Array) -> void:
	var usable := rect.size.x - 4 - VC.FIGURE_W
	var feet := rect.end.y - 1
	var shown := mini(load, TransportLook.RIDERS_SHOWN)
	for back: bool in [true, false]:
		for n: int in shown:
			if (n % 2 == 1) != back:
				continue
			var slot := n / 2
			var fx := rect.position.x + 2 + (usable * (2 * slot + 1) / 4 if back else usable * slot / 2)
			var who := {"id": 17 * (n + 1) + people.size() * 5 + rect.position.x, "still": true, "dir": 1 if n % 2 == 0 else -1}
			DetailPeople.walker(canvas, fx, feet - (3 if back else 0), who, DetailPeople.WALK, 0)
