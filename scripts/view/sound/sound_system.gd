class_name SoundSystem
extends Node
## The game's sound (#247). View only: it reads the tower (its message record, cars, fires, rooms) and
## the camera, and never feeds anything back. Three buses: Ambience (room and street loops, mixed from
## what is on screen), Events (alarms, elevators, VIPs) and UI (build, refuse, demolish, promotion).
## The files are loaded at run time (see SoundCatalog.search_dirs); with none found nothing plays and
## nothing errors. The mute key is N (M is the message log).

const CatalogScript := preload("res://scripts/view/sound/sound_catalog.gd")
const MixerScript := preload("res://scripts/view/sound/sound_mixer.gd")
const SettingsScript := preload("res://scripts/view/sound/sound_settings.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const RecyclingScript := preload("res://scripts/sim/recycling.gd")
const ViewConsts := preload("res://scripts/view/view_consts.gd")
const ActivityScript := preload("res://scripts/view/activity_look.gd")

const SLOTS := 8  ## One-shot players.
const FADE_PER_SECOND := 0.7  ## Crossfade speed (gain change per second).
const AMBIENCE_EVERY := 0.5  ## Seconds between ambience mixes.
const ELEVATOR_EVERY := 0.05
const OPEN_GAP_MS := 350  ## At most one elevator-door sound per this long.
const SAME_GAP_MS := 120  ## The same one-shot is not restarted within this.
const MAX_PER_POLL := 3
const ELEVATOR_LEVEL := 0.3  ## The elevator hum is quiet.
const OFFICE_GAP_MS := 20000  ## Offices in view play their clip at most this often.
const CROWD_PEOPLE := 20  ## People in the tower before the lobby sounds busy.
const CROWD_FULL := 200

var _streams: Dictionary = {}  ## name -> AudioStream (empty: silent).
var _driver: SimDriver = null
var _camera: Camera2D = null
var _rng := RandomNumberGenerator.new()
var _loops: Dictionary = {}  ## loop name -> AudioStreamPlayer.
var _gain: Dictionary = {}  ## loop name -> current linear gain.
var _target: Dictionary = {}  ## loop name -> wanted gain.
var _slots: Array[AudioStreamPlayer] = []
var _last_played_ms: Dictionary = {}
var _cursor_tick: int = -1
var _cursor_count: int = 0
var _car_state: Dictionary = {}  ## shaft id * 1000 + car place -> last state.
var _last_open_ms: int = -100000
var _last_hour: int = -1
var _ambience_t: float = 0.0
var _elevator_t: float = 0.0
var _next_theater_ms: int = 0
var _next_office_ms: int = 0
var _bird_loop: String = CatalogScript.BIRD_LOOP
var _crowd_loop: String = CatalogScript.CROWD_LOOP
var _alias: Dictionary = {}  ## KIND_LOOPS name -> the variant picked for this session.


## Loads the sounds and starts listening. streams may be given (tests); otherwise they are found on disk.
func bind(driver: SimDriver, camera: Camera2D, streams: Dictionary = {}, load_from_disk: bool = true) -> void:
	_driver = driver
	_camera = camera
	_streams = streams
	if load_from_disk and streams.is_empty():
		_streams = CatalogScript.load_streams(CatalogScript.search_dirs())
	SettingsScript.load_settings()
	SettingsScript.apply()
	_rng.randomize()
	_bird_loop = _pick(CatalogScript.BIRD_CLIPS)
	_crowd_loop = _pick(CatalogScript.CROWD_CLIPS)
	_alias = {"Subway1": _pick(CatalogScript.SUBWAY_CLIPS), "Car1": _pick(CatalogScript.CAR_CLIPS)}
	for i in SLOTS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_slots.append(player)
	_sync_cursor()
	_next_theater_ms = Time.get_ticks_msec() + 3000
	play_one(CatalogScript.BUS_UI, "Intro")


## True when at least one sound file was found.
func has_sounds() -> bool:
	return not _streams.is_empty()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_N and not key.ctrl_pressed and not key.alt_pressed:
		SettingsScript.set_muted(not SettingsScript.muted)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _driver == null or _streams.is_empty():
		return
	var tower: Tower = _driver.tower
	if tower == null:
		return
	_elevator_t += delta
	if _elevator_t >= ELEVATOR_EVERY:
		_elevator_t = 0.0
		_messages(tower)
		_elevators(tower)
	_ambience_t += delta
	if _ambience_t >= AMBIENCE_EVERY:
		_ambience_t = 0.0
		_ambience(tower)
	_fade(delta)


## Plays one clip on a bus at a volume; false when the sound is missing or just played.
func play_one(bus: StringName, sound_name: String, volume: float = 1.0) -> bool:
	if not _streams.has(sound_name) or _slots.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(sound_name, -100000)) < SAME_GAP_MS:
		return false
	var chosen: AudioStreamPlayer = _slots[0]
	for player in _slots:
		if not player.playing:
			chosen = player
			break
	_last_played_ms[sound_name] = now
	chosen.stream = _streams[sound_name]
	chosen.bus = bus
	chosen.volume_db = linear_to_db(clampf(volume, 0.0, 1.0))
	chosen.play()
	return true


func _pick(clips: Array) -> String:
	return str(clips[_rng.randi() % clips.size()])


func _sync_cursor() -> void:
	if _driver == null or _driver.tower == null:
		return
	var cursor := MixerScript.new_messages(_driver.tower.messages, -1, 0)
	_cursor_tick = cursor["tick"]
	_cursor_count = cursor["count"]


## Sounds for the messages logged since last time.
func _messages(tower: Tower) -> void:
	var found := MixerScript.new_messages(tower.messages, _cursor_tick, _cursor_count)
	_cursor_tick = found["tick"]
	_cursor_count = found["count"]
	var played := 0
	for entry: Array in found["entries"]:
		if played >= MAX_PER_POLL:
			break
		var row: Variant = CatalogScript.MESSAGE_SOUNDS.get(entry[1])
		if row == null:
			continue
		var clips: Array = row[1]
		if entry[1] == Messages.ROOM_BUILT and _is_condo(entry[2]):
			clips = [CatalogScript.BUY_CLIP]
		if play_one(row[0], _pick(clips)):
			played += 1


func _is_condo(catalogue_index: int) -> bool:
	return catalogue_index >= 0 and catalogue_index < CatalogueScript.IDS.size() and CatalogueScript.IDS[catalogue_index] == CatalogScript.CONDO_KIND


## The world rectangle on screen, and the zoom.
func _view() -> Dictionary:
	if _camera == null or not _camera.is_inside_tree():
		return {"rect": Rect2(), "zoom": 1}
	var viewport := _camera.get_viewport()
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var rect := to_world * viewport.get_visible_rect()
	return {"rect": rect, "zoom": maxi(1, int(round(_camera.zoom.x)))}


func _elevators(tower: Tower) -> void:
	var view := _view()
	var rect: Rect2 = view["rect"]
	var moving := false
	var opened := false
	var seen: Dictionary = {}
	for shaft in tower.rooms.shaft_ids():
		var column_x := float(tower.rooms.shaft_x(shaft) * ViewConsts.CELL_W)
		var place := 0
		for car: Array in tower.rooms.cars_of(shaft):
			var key := shaft * 1000 + place
			place += 1
			seen[key] = true
			var state: int = car[CarsScript.STATE]
			var before: int = _car_state.get(key, state)
			_car_state[key] = state
			var at := Vector2(column_x + 8.0, (ViewConsts.floor_to_row(car[CarsScript.FLOOR]) + 0.5) * ViewConsts.CELL_H)
			if not rect.has_point(at):
				continue
			if state == CarsScript.MOVING:
				moving = true
			var doors_now := state == CarsScript.DOORS_OPENING or state == CarsScript.DOORS_OPEN
			var doors_before := before == CarsScript.DOORS_OPENING or before == CarsScript.DOORS_OPEN
			if doors_now and not doors_before:
				opened = true
	for key: int in _car_state.keys():
		if not seen.has(key):
			_car_state.erase(key)
	var factor := MixerScript.zoom_factor(view["zoom"])
	_target[CatalogScript.ELEVATOR_LOOP] = ELEVATOR_LEVEL * factor if moving else 0.0
	if opened:
		var now := Time.get_ticks_msec()
		if now - _last_open_ms >= OPEN_GAP_MS and play_one(CatalogScript.BUS_EVENTS, _pick(CatalogScript.ELEVATOR_OPEN_CLIPS), 0.6 * factor):
			_last_open_ms = now


func _ambience(tower: Tower) -> void:
	var view := _view()
	var rect: Rect2 = view["rect"]
	var zoom: int = view["zoom"]
	var units: Dictionary = {}  ## loop name -> columns of rooms of that kind in view.
	var theatre_units := 0
	var office_units := 0
	for id in tower.rooms.room_ids():
		var kind := tower.rooms.kind_of(id)
		var loop_name: String = CatalogScript.KIND_LOOPS.get(kind, "")
		loop_name = _alias.get(loop_name, loop_name)
		var office := CatalogScript.OFFICE_KINDS.has(kind)
		if loop_name == "" and kind != CatalogScript.THEATER_KIND and not office:
			continue
		var run := tower.grid.run_of(id)
		if run.size() < 3:
			continue
		var box := Rect2(run[1] * ViewConsts.CELL_W, ViewConsts.floor_to_row(run[0]) * ViewConsts.CELL_H, run[2] * ViewConsts.CELL_W, ViewConsts.CELL_H)
		if not rect.intersects(box):
			continue
		if kind == CatalogScript.THEATER_KIND:
			theatre_units += run[2]
		elif office:
			office_units += run[2]
		else:
			units[loop_name] = int(units.get(loop_name, 0)) + run[2]
	var wanted: Dictionary = {}
	for loop_name: String in units:
		wanted[loop_name] = MixerScript.level_for(units[loop_name], zoom)
	# Street and lobby: only when the ground floor is in view.
	var ground := Rect2(rect.position.x, ViewConsts.floor_to_row(1) * ViewConsts.CELL_H, rect.size.x, ViewConsts.CELL_H)
	if rect.intersects(ground):
		var street := 0.6 * MixerScript.zoom_factor(zoom)
		if ActivityScript.is_night(tower.clock.minute_of_day()):
			wanted[CatalogScript.CRICKET_LOOP] = street
		else:
			wanted[_bird_loop] = street
		var people := tower.population()
		if people >= CROWD_PEOPLE:
			wanted[_crowd_loop] = MixerScript.level_for(MixerScript.FULL_UNITS * mini(people, CROWD_FULL) / CROWD_FULL, zoom)
	var chosen := MixerScript.strongest(wanted)
	for loop_name: String in _loops.keys():
		if not chosen.has(loop_name):
			_target[loop_name] = 0.0
	for loop_name: String in chosen:
		_target[loop_name] = chosen[loop_name]
	# A theatre in view plays a random film clip now and then (the sim has no "it opens" signal).
	var now := Time.get_ticks_msec()
	if theatre_units > 0 and now >= _next_theater_ms:
		_next_theater_ms = now + _rng.randi_range(20000, 60000)
		play_one(CatalogScript.BUS_AMBIENCE, _pick(CatalogScript.THEATER_CLIPS), MixerScript.level_for(theatre_units, zoom))
	# Offices in view: their clip once every OFFICE_GAP_MS, not a loop.
	if office_units > 0 and now >= _next_office_ms:
		_next_office_ms = now + OFFICE_GAP_MS
		play_one(CatalogScript.BUS_AMBIENCE, CatalogScript.OFFICE_CLIP, MixerScript.level_for(office_units, zoom))
	# Fire: a loop while anything burns, louder when it is in view.
	var fire_level := 0.0
	for id in tower.fire.burning_rooms():
		var run := tower.grid.run_of(id)
		var near := run.size() >= 3 and rect.intersects(Rect2(run[1] * ViewConsts.CELL_W, ViewConsts.floor_to_row(run[0]) * ViewConsts.CELL_H, run[2] * ViewConsts.CELL_W, ViewConsts.CELL_H))
		fire_level = maxf(fire_level, 0.9 if near else 0.4)
	_target[CatalogScript.FIRE_LOOP] = fire_level
	# The recycling truck leaves at its hour.
	var hour := tower.clock.hour()
	if _last_hour >= 0 and hour != _last_hour and hour == RecyclingScript.TRUCK_HOUR and not tower.recycling.centres().is_empty():
		play_one(CatalogScript.BUS_EVENTS, "Recycling")
	_last_hour = hour


## Moves every loop's gain toward its target, starting loops that are wanted and stopping ones faded out.
func _fade(delta: float) -> void:
	for loop_name: String in _target.keys():
		var gain := MixerScript.approach(float(_gain.get(loop_name, 0.0)), float(_target[loop_name]), FADE_PER_SECOND * delta)
		_gain[loop_name] = gain
		var player: AudioStreamPlayer = _loops.get(loop_name)
		if gain <= 0.0:
			if player != null and player.playing:
				player.stop()
			if float(_target[loop_name]) <= 0.0 and player == null:
				_gain.erase(loop_name)
				_target.erase(loop_name)
			continue
		if not _streams.has(loop_name):
			continue
		if player == null:
			player = AudioStreamPlayer.new()
			player.stream = CatalogScript.make_loop(_streams[loop_name])
			player.bus = _bus_of(loop_name)
			add_child(player)
			_loops[loop_name] = player
		player.volume_db = linear_to_db(gain)
		if not player.playing:
			player.play()


func _bus_of(loop_name: String) -> StringName:
	if loop_name == CatalogScript.FIRE_LOOP or loop_name == CatalogScript.ELEVATOR_LOOP:
		return CatalogScript.BUS_EVENTS
	return CatalogScript.BUS_AMBIENCE
