extends RefCounted
## Detailed people (#304): each figure draws from its id and state alone (the same twice, different for
## different people), every activity and pose draws inside its pose box, the age, job and stress cues show,
## children are shorter, the walk cycle has distinct frames, and Classic is unchanged.

const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const DetailPeople := preload("res://scripts/view/detail_people.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const NamesScript := preload("res://scripts/sim/names.gd")

const ACTS: Array[int] = [ActivityLook.IDLE, ActivityLook.WORKING, ActivityLook.BREAK, ActivityLook.LUNCH, ActivityLook.EATING,
	ActivityLook.SLEEPING, ActivityLook.CLEANING, ActivityLook.QUEUEING, ActivityLook.SHOPPING]
const JOBS: Array[String] = ["", "office", "fast_food", "restaurant", "retail", "housekeeping", "security", "medical"]
const X := 40
const FEET := 60


## Records draw_rect calls: the rectangles and their colours, in order.
class Recorder:
	extends RefCounted
	var rects: Array[Rect2] = []
	var colours: Array[Color] = []

	func draw_rect(r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		rects.append(Rect2(r))
		colours.append(c)

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		pass

	func same_as(other: Recorder) -> bool:
		return rects == other.rects and colours == other.colours

	func bounds() -> Rect2:
		var all := rects[0]
		for r: Rect2 in rects:
			all = all.merge(r)
		return all


static func _walker(style: GraphicsStyle, who: Dictionary, pose: int, walk: int) -> Recorder:
	var rec := Recorder.new()
	style.person(rec, X, FEET, Color.WHITE, Color.WHITE, false, 0, 0, who, pose, walk)
	return rec


static func _rest(style: GraphicsStyle, who: Dictionary, act: int, frame: int) -> Recorder:
	var rec := Recorder.new()
	style.activity(rec, X, FEET, act, frame, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, who)
	return rec


static func run(check: Callable) -> void:
	var detailed := GraphicsStyle.for_detailed(true)
	var classic := GraphicsStyle.for_detailed(false)
	_deterministic(check, detailed)
	_every_activity(check, detailed)
	_variety(check)
	_cues(check, detailed)
	_walk_cycle(check, detailed)
	_classic_unchanged(check, detailed, classic)


## The same person and state draw the same, twice; different ids give different looks.
static func _deterministic(check: Callable, style: GraphicsStyle) -> void:
	var same := true
	for id in 24:
		var who := {"id": id, "age": id % 3, "job": JOBS[id % JOBS.size()], "dir": 1}
		same = same and _walker(style, who, 0, id % 4).same_as(_walker(style, who, 0, id % 4))
		for act: int in ACTS:
			same = same and _rest(style, who, act, id % 4).same_as(_rest(style, who, act, id % 4))
	check.call(same, "detail people: the same person and state draw the same every time")
	var looks: Dictionary = {}
	for id in 40:
		looks[str(DetailPeople.look_of({"id": id, "age": 1}))] = true
	check.call(looks.size() >= 30, "detail people: 40 ids give at least 30 distinct looks (%d)" % looks.size())


## Every activity at every frame, for every job, draws something and stays inside its pose box.
static func _every_activity(check: Callable, style: GraphicsStyle) -> void:
	var drew := true
	var inside := true
	for act: int in ACTS:
		for frame in 4:
			for job: String in JOBS:
				var rec := _rest(style, {"id": 5 + frame, "age": frame % 3, "child": frame == 3, "job": job, "dir": 1}, act, frame)
				if rec.rects.is_empty():
					drew = false
					continue
				var box := Rect2(X - 3, FEET - 20, 24, 24)
				if act == ActivityLook.SLEEPING:
					box = Rect2(X - 3, FEET - ActivityLook.LYING_UP - 12, 40, ActivityLook.LYING_UP + 14)
				if not box.encloses(rec.bounds()):
					inside = false
					print("  out of box: act ", act, " frame ", frame, " job ", job, " ", rec.bounds())
	check.call(drew, "detail people: every activity draws at every frame and job")
	check.call(inside, "detail people: every activity stays inside its pose box")
	var walkers := true
	var walkers_inside := true
	for pose in 3:
		for frame in 4:
			for dir in [-1, 1]:
				var rec := _walker(style, {"id": 3, "age": 1, "dir": dir}, pose, frame)
				walkers = walkers and not rec.rects.is_empty()
				walkers_inside = walkers_inside and Rect2(X - 3, FEET - 20, 24, 24).encloses(rec.bounds())
	check.call(walkers and walkers_inside, "detail people: walking, stairs and escalator draw inside the figure box, both ways")
	var asleep := _rest(style, {"id": 9, "age": 1, "dir": 1}, ActivityLook.SLEEPING, 0)
	var breathing := _rest(style, {"id": 9, "age": 1, "dir": 1}, ActivityLook.SLEEPING, 2)
	check.call(not asleep.same_as(breathing), "detail people: a sleeper breathes (the blanket moves between frames)")


## Variety is by id: all hair styles, many skins and hair colours; seniors go grey; children are not bald.
static func _variety(check: Callable) -> void:
	var styles: Dictionary = {}
	var skins: Dictionary = {}
	var hairs: Dictionary = {}
	for id in 64:
		var look := DetailPeople.look_of({"id": id, "age": 1})
		styles[look["style"]] = true
		skins[look["skin"]] = true
		hairs[look["hair"]] = true
	check.call(styles.size() == 4, "detail people: all four hair styles occur (%d)" % styles.size())
	check.call(skins.size() >= 6 and hairs.size() >= 6, "detail people: skin and hair colours vary (%d, %d)" % [skins.size(), hairs.size()])
	var grey := true
	var kids_ok := true
	for id in 64:
		var senior := DetailPeople.look_of({"id": id, "age": NamesScript.BAND_SENIOR})
		grey = grey and (senior["hair"] == DetailPeople.GREY or senior["hair"] == DetailPeople.WHITE_HAIR)
		kids_ok = kids_ok and DetailPeople.look_of({"id": id, "age": NamesScript.BAND_YOUNG, "child": true})["style"] != 2
	check.call(grey, "detail people: seniors have grey or white hair")
	check.call(kids_ok, "detail people: children are never bald")


## Job, age, stress and facing show: an office worker wears a suit and tie, a uniform differs from casual
## clothes, children stand shorter, a stressed person wears the band colour, a figure faces its way.
static func _cues(check: Callable, style: GraphicsStyle) -> void:
	var suit := DetailPeople.look_of({"id": 4, "age": 1, "job": "office"})
	check.call(suit["outfit"] == "suit" and (suit["tie"] as Color).a > 0.0, "detail people: office workers wear a suit and tie")
	var uniform := DetailPeople.look_of({"id": 4, "age": 1, "job": "fast_food"})
	check.call(uniform["outfit"] == "uniform" and uniform["top"] != DetailPeople.look_of({"id": 4, "age": 1})["top"], "detail people: a job wears its uniform")
	var adult := _walker(style, {"id": 4, "age": 1, "dir": 1}, 0, 0).bounds()
	var child := _walker(style, {"id": 4, "age": 0, "child": true, "dir": 1}, 0, 0).bounds()
	check.call(child.size.y < adult.size.y, "detail people: a child is shorter than an adult")
	var red := Color("c04040")
	var stressed := DetailPeople.look_of({"id": 4, "age": 1, "band": 2, "shirt": red})
	check.call(stressed["top"] == red, "detail people: a stressed person wears the band colour")
	var calm := _walker(style, {"id": 4, "age": 1, "dir": 1}, 0, 0)
	var upset := _walker(style, {"id": 4, "age": 1, "dir": 1, "band": 2, "shirt": red}, 0, 0)
	check.call(not calm.same_as(upset), "detail people: stress changes the figure")
	var left := _walker(style, {"id": 4, "age": 1, "dir": -1}, 0, 0)
	check.call(not calm.same_as(left), "detail people: a figure faces the way it walks")


## The walk cycle has four frames, at least three of which differ, and repeats; stairs differ from walking.
static func _walk_cycle(check: Callable, style: GraphicsStyle) -> void:
	var frames: Array[Recorder] = []
	for f in 4:
		frames.append(_walker(style, {"id": 12, "age": 1, "dir": 1}, 0, f))
	var distinct := 0
	for a in 4:
		var unique := true
		for b in a:
			unique = unique and not frames[a].same_as(frames[b])
		if unique:
			distinct += 1
	check.call(distinct >= 3, "detail people: the walk cycle has at least three distinct frames (%d)" % distinct)
	check.call(frames[0].same_as(_walker(style, {"id": 12, "age": 1, "dir": 1}, 0, 4)), "detail people: the walk cycle repeats every four frames")
	var stairs := _walker(style, {"id": 12, "age": 1, "dir": 1}, 1, 0)
	check.call(not stairs.same_as(frames[0]), "detail people: climbing stairs looks different from walking")


## Classic ignores who and draws what it always did; Detailed with no who falls back to Classic's figure.
static func _classic_unchanged(check: Callable, detailed: GraphicsStyle, classic: GraphicsStyle) -> void:
	var plain := Recorder.new()
	classic.person(plain, X, FEET, Color.RED, Color.WHITE, true, 0, 1)
	var with_who := Recorder.new()
	classic.person(with_who, X, FEET, Color.RED, Color.WHITE, true, 0, 1, {"id": 3, "age": 2, "job": "office", "dir": -1}, 1, 3)
	check.call(plain.same_as(with_who), "detail people: Classic draws the same whoever the person is")
	var direct := Recorder.new()
	ActivityLook.draw_person(direct, X, FEET, Color.RED, Color.WHITE, true, 0, 1)
	check.call(plain.same_as(direct), "detail people: Classic's person is still the activity look's figure")
	var fallback := Recorder.new()
	detailed.person(fallback, X, FEET, Color.RED, Color.WHITE, true, 0, 1)
	check.call(plain.same_as(fallback), "detail people: Detailed without a who falls back to Classic's figure")
	var all_same := true
	for act: int in ACTS:
		var a := Recorder.new()
		classic.activity(a, X, FEET, act, 1, Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
		var b := Recorder.new()
		classic.activity(b, X, FEET, act, 1, Color.RED, Color.WHITE, Color.GOLD, Color.WHITE, {"id": 8, "age": 2, "dir": 1})
		var c := Recorder.new()
		ActivityLook.draw(c, X, FEET, act, 1, Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
		all_same = all_same and a.same_as(b) and a.same_as(c)
	check.call(all_same, "detail people: Classic's activities are unchanged")
