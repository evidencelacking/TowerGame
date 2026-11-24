extends Node2D
## The top-rank celebration (#33): a short volley of fireworks over the sky when the wedding succeeds. Our own design, drawn by
## code in whole-pixel rects: each burst is a ring of sparks that fly out from a point, slow, fall and fade. It is cosmetic
## and view-only: the placement of bursts comes from a fixed table (no random numbers), it reads nothing from the sim except
## being started, and it saves nothing. The renderer starts it when the tower's top-rank flag turns on while playing.

const BURSTS := 14  ## How many bursts in the volley.
const GAP := 0.55  ## Seconds between one burst starting and the next.
const LIFE := 1.8  ## Seconds a burst lasts.
const SPARKS := 18
const RADIUS := 70.0  ## World pixels a spark flies at most.
const SIZE := 3  ## Drawn pixels per spark.
const COLORS: Array[Color] = [Color("ffd27a"), Color("ff7a8a"), Color("8ad0ff"), Color("b6f08a"), Color("e8a0ff")]
## Where each burst opens, as shares of the view (x, y): spread over the upper sky.
const SPOTS: Array[Vector2] = [
	Vector2(0.50, 0.22), Vector2(0.28, 0.30), Vector2(0.72, 0.28), Vector2(0.40, 0.14), Vector2(0.62, 0.16), Vector2(0.18, 0.18), Vector2(0.84, 0.20),
]

var _elapsed: float = -1.0  ## Seconds since the volley began, or -1 when it is not playing.
var _left: float = 0.0
var _top: float = 0.0
var _size := Vector2.ONE


## True while the volley plays.
func playing() -> bool:
	return _elapsed >= 0.0


## Total seconds of the volley.
static func duration() -> float:
	return (BURSTS - 1) * GAP + LIFE


func start() -> void:
	_elapsed = 0.0
	visible = true
	queue_redraw()


## Keeps the volley over the view the camera sees.
func follow(camera_pos: Vector2, view_size: Vector2) -> void:
	_left = camera_pos.x - view_size.x * 0.5
	_top = camera_pos.y - view_size.y * 0.5
	_size = view_size


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed > duration():
		_elapsed = -1.0
		visible = false
	queue_redraw()


## One spark's offset in world pixels, `age` seconds into its burst: out along its ray, slowing, then drooping.
static func spark_offset(index: int, age: float) -> Vector2:
	var angle: float = TAU * float(index) / float(SPARKS)
	var reach: float = RADIUS * (1.0 - pow(1.0 - clampf(age / LIFE, 0.0, 1.0), 2.0))
	return Vector2(cos(angle) * reach, sin(angle) * reach + 18.0 * age * age)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	for n in BURSTS:
		var age: float = _elapsed - n * GAP
		if age < 0.0 or age > LIFE:
			continue
		var spot: Vector2 = SPOTS[n % SPOTS.size()]
		var centre := Vector2(_left + _size.x * spot.x, _top + _size.y * spot.y)
		var color: Color = COLORS[n % COLORS.size()]
		color.a = 1.0 - age / LIFE
		for i in SPARKS:
			var at: Vector2 = centre + spark_offset(i, age)
			draw_rect(Rect2i(int(roundf(at.x)), int(roundf(at.y)), SIZE, SIZE), color)
