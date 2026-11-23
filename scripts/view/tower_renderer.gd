class_name TowerRenderer
extends Node2D
const VC := preload("res://scripts/view/view_consts.gd")
const Suites := preload("res://scripts/view/suites.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const TransportLook := preload("res://scripts/view/transport_look.gd")
const TransportGlass := preload("res://scripts/view/transport_glass.gd")
const EventLook := preload("res://scripts/view/event_look.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const DetailLight := preload("res://scripts/view/detail_light.gd")
const DetailRooms := preload("res://scripts/view/detail_rooms.gd")
const Palette := preload("res://scripts/view/palette.gd")
const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const PixelLayer := preload("res://scripts/view/pixel_layer.gd")
const ExteriorLayer := preload("res://scripts/view/exterior_layer.gd")
## Draws the tower on a low-resolution canvas (10.2). World space is native pixels (8 px per column,
## 24 px per floor, see view_consts.gd). The rooms, links, floors and shafts go into one SubViewport
## that is redrawn only when the floors or rooms change or every STATIC_REFRESH_TICKS ticks (the in-use
## look follows people); the elevator cars, queues and people go into a second one redrawn each sim
## tick and while cars slide. Each is shown as a nearest-filtered sprite, and the camera zooms by whole
## numbers, so a native pixel is always a whole number of screen pixels. Sky and ground are flat
## rectangles drawn directly. Reads the Tower read-only; never mutates sim state.

const MARGIN: int = 4000  ## Sky and ground extend this far past the tower, in pixels.
const IN_USE_CHECK_TICKS: int = 6  ## How often the set of rooms in use is compared; a change redraws the static layer.
const STATIC_REFRESH_TICKS: int = 60  ## Redraw even when nothing moved, so sim state (dirty, vacant) shows within this.
const FIGURE_W: int = VC.FIGURE_W
const FIGURE_H: int = VC.FIGURE_H
const GLIDE_MAX_COLUMNS := 12.0  ## A move longer than this between two ticks is a new trip, not a glide.

## Back to front; every name is a method taking the canvas item to paint on. Links (stairs,
## escalators) and shafts sit in front of the rooms behind them (#126); the floor slabs come after
## rooms because a room fills its whole row and would hide its own slab.
const STATIC_LAYERS: Array[String] = ["_draw_backdrop", "_draw_lobby", "_draw_rooms", "_draw_links", "_draw_floors", "_draw_shafts", "_draw_exterior"]
const DYNAMIC_LAYERS: Array[String] = ["_draw_belts", "_draw_queues", "_draw_cars", "_draw_events", "_draw_people"]
const DRAW_ORDER: Array[String] = ["_draw_backdrop", "_draw_lobby", "_draw_rooms", "_draw_links", "_draw_floors", "_draw_shafts", "_draw_exterior", "_draw_belts", "_draw_queues", "_draw_cars", "_draw_events", "_draw_people"]

var tower: Tower = null
var _people_view := PeopleView.new()
var _elevators := ElevatorView.new()
var _seen_tick: int = -1
var _shafts_key: Array = []  ## What _shafts_seen was built for: [links.revision, route_revision, shaft ids].
var _shafts_seen: Array[Dictionary] = []
var _seen_rain: bool = false
var _since_tick: float = 0.0  ## Seconds since the sim last ticked.
var _tick_len: float = 1.0 / 30.0  ## Seconds the last tick took; cars slide over this long.
var _seen_revision: int = -1
var _seen_see_through: bool = false
var _label_step: int = ShaftNumbers.FAR_STEP  ## Floor-number spacing in the shafts at the current zoom (#431).
var _seen_glass: bool = false  ## TransportGlass.on as last painted (#367).
var _seen_style: GraphicsStyle = null
var _seen_occupants: int = -1
var _figures: Array[Dictionary] = []
var _from: Dictionary = {}  ## Person id -> Vector2(column, row) at the previous tick, to glide from.
var _has_moving: bool = false
var _in_use: Dictionary = {}  ## Room id -> true for rooms with someone resting in them.
var _asleep: Dictionary = {}  ## Room id -> true for rooms where everyone present is asleep: lights off.
var _checked_tick: int = -1000000
var _floor_rects: Array[Rect2i] = []  ## Runs of built floor units, one row tall; rebuilt when the layout changes.
var _room_runs: Array[Array] = []  ## [id, owning room id, rect] per placed room run.
var _sky_key: Array = []  ## The sky lobby floors' flags when _sky_wanted was scanned.
var _sky_wanted: Dictionary = {}  ## Piece key -> spec for the sky lobby slices, as _sync_pieces wants them.
var _row_cache: Array = []  ## Per floor index: [what the floor looked like, its scanned runs], so a layout change rescans only the floors it touched (#349).
var _link_runs: Array[Array] = []  ## [kind, two-floor rect] per stairs or escalator.
const CANVAS_GRAIN: Vector2i = Vector2i(128, 128)  ## Canvas edges snap to this many native pixels, so growing the tower reallocates rarely.
const CANVAS_PAD: Vector2i = Vector2i(64, 64)  ## Room around the built tower for shaft caps, cars and figures at the edge.
const ZOOM_SHARP_ABOVE: float = 1.5  ## Detailed is filtered (an exact 2x2 average) below this camera zoom, point-sampled at or above it.

var _canvas: Rect2i = Rect2i(0, 0, 128, 128)  ## The part of the world the two canvases cover, in native pixels (#307).
const TILE: Vector2i = Vector2i(256, 128)  ## The static picture is shown through a grid of tiles this many native pixels across (#346).
const TILE_PAD: int = 32  ## A piece marks the tiles within this distance of it for a fresh render, for glows that spill past a room.
const REPAIR_BUDGET_US: int = 5000  ## Estimated script cost of the pieces repainted in one frame; at least one piece is always repainted.
const UNKNOWN_PIECE_COST_US: int = 1500
const URGENT_BUDGET_US: int = 9000  ## Like REPAIR_BUDGET_US, for the pieces the player's last action touched (#372): they go first.
const TILE_RENDERS_PER_FRAME: int = 2  ## Tiles re-rendered per frame at most; the rest wait their turn, the longest-waiting first.
const URGENT_TILE_RENDERS_PER_FRAME: int = 2  ## The same for tiles the player's last action touched, which always go before the rest (#372).
const FRAME_LAYERS: Array[String] = ["_draw_backdrop", "_draw_links", "_draw_floors", "_draw_shafts", "_draw_exterior"]
const FRAME_Z: Dictionary = {"_draw_backdrop": 0, "_draw_links": 3, "_draw_floors": 4, "_draw_shafts": 5, "_draw_exterior": 6}
const OUTDOOR_REDRAWS_PER_FRAME: int = 1  ## Skyline slices (or the street) redrawn per frame after the outdoors changed.
const LOBBY_Z: int = 1
const LOBBY_SLICE: int = 192  ## World pixels wide: the Detailed lobby is painted in slices this wide, one piece each, so no single repaint is long.
const ROOM_Z: int = 2  ## Between the lobby and the links: the order of STATIC_LAYERS.


## One retained piece of the static picture (#346): a canvas item that records its draw commands once and
## keeps them until it is marked stale. A room (or a joined suite) is one piece; the floors, shafts, links,
## lobby, backdrop and facade are one piece each. Repainting a piece costs only that piece's script time.
class Piece extends RefCounted:
	var node: Node2D = null
	var rect: Rect2i = Rect2i()  ## World native pixels it paints in; the tiles it touches are rendered again after it repaints.
	var stale: bool = true
	var cost_us: int = 0  ## Script time of its last paint. 0 = never painted.
	var sig: Array = []  ## The state it was last marked for (rooms): look state, fill, lit, dark.
	var uid: int = 0  ## Owner id of the lights it records.
	var layer_name: String = ""  ## A frame piece's painter method; empty for a room.
	var runs: Array = []  ## A room piece's runs: [id, owner room, rect], one for a room or several for a suite.
	var suite_kind: String = ""
	var painted_frame: int = 0  ## The repair frame of its last repaint, for tests: a tile must render after it.
	var urgent: bool = false  ## Built or changed by the player's action: repainted before background work, its tiles rendered first (#372).


## One window onto the static world: a SubViewport sharing the world the pieces live in, looking at its rect.
class Tile extends RefCounted:
	var rect: Rect2i = Rect2i()
	var view: SubViewport = null
	var sprite: Sprite2D = null
	var pending: bool = true  ## Needs a fresh render.
	var urgent: bool = false  ## Pending because of the player's action: rendered before the background tiles.
	var rendered_frame: int = 0  ## The repair frame it was last rendered in, for tests.
	var since: int = 0  ## The repair frame it became pending; the oldest is rendered first, so none starves.


var _world: SubViewport = null  ## Holds the pieces; never rendered itself. The tiles share its world.
var _statics: Node2D = null
var _tile_root: Node2D = null  ## Holds the tile sprites; carries the night ambient colour and the zoom filter.
var _tiles: Array[Tile] = []
var _frame_pieces: Array[Piece] = []
var _room_pieces: Dictionary = {}  ## Key -> Piece, for the rooms and suites in the layout.
var _next_uid: int = 1
var _repair_frame: int = 0
var _synced_once: bool = false  ## False until the first layout is in: loading a tower is background work, not the player's action.
var _urgent_rects: Array[Rect2i] = []  ## Where the layout just changed (floors, links, shafts); the frame pieces' tiles there are urgent.
var _seen_floors: Dictionary = {}  ## The floors, links and shafts as they were at the last layout change, to find what changed.
var _seen_links: Dictionary = {}
var _seen_shafts: Dictionary = {}
var _plan_workers: Dictionary = {}  ## Office room id -> workers, for the vacancy look (#358).
var _plan_broken: Array[int] = []
var _frame_due: int = 0  ## Tick at which the frame pieces (shafts and so on) are marked stale again.
var _dynamic_view: SubViewport = null
var figures_version: int = 0  ## Counts the times the figures were built, so a layer on top can follow a camera move while paused.
var _figures_for: Rect2 = Rect2()  ## World rect the figures were built for; empty when built for everyone.
var _people_painted_for: Rect2 = Rect2()  ## World rect the people were last drawn for (culled to it); empty when not culled.
var _dynamic_layer: Node2D = null
var _outdoors: Array[Node2D] = []  ## The far and near skylines and the street (#306), behind everything else.
var _outdoors_todo: Array[Node2D] = []  ## Outdoor layers waiting for their redraw.
var _outdoors_key: Array = []  ## What the outdoors were last drawn for: stars, daylight, rain, density, layout.
var _dynamic_sprite: Sprite2D = null
var _glow: Node2D = null  ## Detailed night lights, added on top of the world (#305).


## U toggles the Detailed see-through transport option (#367).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and KeyBindings.is_key(key, "transport_glass") and not key.ctrl_pressed and not key.alt_pressed:
		TransportGlass.toggle()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	TransportLook.load_setting()
	TransportGlass.load_setting()
	ViewSettings.load_settings()
	_seen_style = GraphicsStyle.current()
	_seen_see_through = TransportLook.see_through
	_seen_glass = TransportGlass.on
	_make_outdoors()
	_world = SubViewport.new()
	_world.size = Vector2i(2, 2)
	_world.transparent_bg = true
	_world.disable_3d = true
	_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_world)
	_statics = Node2D.new()
	_world.add_child(_statics)
	_tile_root = Node2D.new()
	_tile_root.name = "StaticTiles"
	add_child(_tile_root)  # before the dynamic sprite, so the people draw over the rooms
	_dynamic_layer = _make_layer(_canvas.size, _paint_dynamic)
	_dynamic_view = _dynamic_layer.get_parent()
	_dynamic_sprite = _sprite_of(_dynamic_view)
	_glow = DetailLight.new()
	add_child(_glow)
	add_child(SynergyOverlay.new())  # the synergy filter (#294), above the layers; idle while off
	add_child(HeatOverlay.new())  # the income and mood heat maps (#376); idle while off
	_apply_density()
	queue_redraw()


## The skylines and the street (#306): drawn by the style, so Classic shows nothing. Added before the
## layer sprites, they sit in front of the sky and behind the rooms.
func _make_outdoors() -> void:
	var world_w := int(VC.world_rect().size.x)
	var span := ExteriorLayer.SLICE_W
	for spec: Array in [[0, 0.55], [1, 0.8], [ExteriorLayer.STREET, 1.0]]:
		var from := -2000 if spec[0] != ExteriorLayer.STREET else 0  # the skylines start at the street's left end
		while true:  # a skyline is several slices, so a redraw of it can be spread over frames (#346); the street is one
			var layer: Node2D = ExteriorLayer.new()
			layer.set("depth", spec[0])
			layer.set("factor", spec[1])
			if spec[0] != ExteriorLayer.STREET:
				layer.set("slice", Vector2i(from, from + span))
			add_child(layer)
			_outdoors.append(layer)
			from += span
			if spec[0] == ExteriorLayer.STREET or from >= world_w + 2000:
				break


## Keeps the outdoors in step: skylines trail the camera, and everything redraws when the star rating, the
## daylight, the rain, the style or the floor layout changed.
func _follow_outdoors() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_x := camera.position.x if camera != null else VC.world_rect().size.x * 0.5
	for layer: Node2D in _outdoors:
		layer.call("follow", camera_x)
	for _i: int in mini(OUTDOOR_REDRAWS_PER_FRAME, _outdoors_todo.size()):
		_outdoors_todo.pop_front().queue_redraw()
	var key: Array = [tower.stars, SkyLook.daylight, SkyLook.rain, GraphicsStyle.current().density(), tower.floors.revision]
	if key == _outdoors_key:
		return
	_outdoors_key = key
	var built: Dictionary = {}
	for column: int in Tower.Grid.WIDTH_UNITS:
		if tower.floors.has_floor(1, column):
			built[column] = true
	for layer: Node2D in _outdoors:
		layer.set("stars", tower.stars)
		layer.set("daylight", SkyLook.daylight)
		layer.set("raining", SkyLook.rain)
		layer.set("built", built)
	_outdoors_todo = _outdoors.duplicate()  # redrawn a couple per frame, the skyline slices first



## A SubViewport at native size with a layer in it, shown by a nearest-filtered sprite at the origin.
func _make_layer(size: Vector2i, painter: Callable) -> Node2D:
	var view := SubViewport.new()
	view.size = size
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var layer: Node2D = PixelLayer.new()
	layer.set("painter", painter)
	view.add_child(layer)
	var sprite := Sprite2D.new()
	sprite.texture = view.get_texture()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return layer


## The sprite that shows a layer's SubViewport.
func _sprite_of(view: SubViewport) -> Sprite2D:
	for child: Node in get_children():
		if child is Sprite2D and (child as Sprite2D).texture == view.get_texture():
			return child as Sprite2D
	return null


## Sizes the static canvas for the style in use (#302): Classic is one pixel per native pixel; a style at
## density 2 gets a canvas twice as wide and tall, its layer scaled 2 so every Classic call still paints the
## same world rect, and its sprite scaled a half so it covers the same world. Detailed rooms then paint in
## half-pixel steps that land on whole pixels of the bigger canvas. The dynamic layer (people, cars) gets
## the same treatment (#304), so Detailed people paint in half-pixel steps; everything else on it still
## paints in native pixels and lands as before.
func _apply_density(restale: bool = true) -> void:
	var density := GraphicsStyle.current().density()
	_canvas = _canvas_bounds()
	_dynamic_view.size = _canvas.size * density  # people are drawn at the style's density too (#304)
	_dynamic_layer.scale = Vector2(density, density)
	_dynamic_layer.position = -Vector2(_canvas.position * density)
	_dynamic_sprite.scale = Vector2(1.0 / density, 1.0 / density)
	_dynamic_sprite.position = Vector2(_canvas.position)
	_rebuild_tiles(density)
	if restale:  # growing the canvas keeps the pieces as they are: they live in the world, not on a canvas
		_mark_all_stale()
	_apply_ambient()


## Cuts the view of the static world into TILE-sized windows over _canvas (#346). Each is a SubViewport
## that shares the pieces' world, scaled by the style's density, and is rendered alone when something in it
## changed. Total pixels equal one canvas of _canvas size, so the memory saving of #307 stays.
func _rebuild_tiles(density: int) -> void:
	for tile: Tile in _tiles:
		tile.view.queue_free()
		tile.sprite.queue_free()
	_tiles.clear()
	var y := _canvas.position.y
	while y < _canvas.end.y:
		var x := _canvas.position.x
		while x < _canvas.end.x:
			var tile := Tile.new()
			tile.rect = Rect2i(Vector2i(x, y), TILE).intersection(_canvas)
			tile.view = SubViewport.new()
			tile.view.size = tile.rect.size * density
			tile.view.transparent_bg = true
			tile.view.disable_3d = true
			tile.view.world_2d = _world.world_2d
			tile.view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(tile.view)
			tile.view.canvas_transform = Transform2D(Vector2(density, 0), Vector2(0, density), -Vector2(tile.rect.position * density))  # needs the view in the tree
			tile.sprite = Sprite2D.new()
			tile.sprite.texture = tile.view.get_texture()
			tile.sprite.centered = false
			tile.sprite.scale = Vector2(1.0 / density, 1.0 / density)
			tile.sprite.position = Vector2(tile.rect.position)
			_tile_root.add_child(tile.sprite)
			_tiles.append(tile)
			x += TILE.x
		y += TILE.y


## Everything needs repainting (style, palette, daylight, rain): every piece is marked, and repainted a few
## per frame, the ones near the view first.
func _mark_all_stale() -> void:
	for piece: Piece in _frame_pieces:
		piece.stale = true
	for key: Variant in _room_pieces:
		(_room_pieces[key] as Piece).stale = true


## Marks the tiles near a rect for a fresh render.
func _mark_tiles(rect: Rect2i, urgent: bool = false) -> void:
	var grown := rect.grow(TILE_PAD)
	for tile: Tile in _tiles:
		if tile.rect.intersects(grown):
			if not tile.pending:
				tile.since = _repair_frame
			tile.pending = true
			tile.urgent = tile.urgent or urgent


## Work not yet done near the view: pieces to repaint and tiles to render. A bench waits for this to reach 0.
func pending_work() -> int:
	var count := 0
	var near := _view_rect()
	for piece: Piece in _frame_pieces:
		if piece.stale:
			count += 1
	for key: Variant in _room_pieces:
		var piece: Piece = _room_pieces[key]
		if piece.stale and piece.rect.intersects(near):
			count += 1
	for tile: Tile in _tiles:
		if tile.pending and tile.rect.intersects(near):
			count += 1
	return count + _outdoors_todo.size()


## The part of the world on screen, grown by a tile so a pan finds its neighbours already drawn.
func _view_rect() -> Rect2i:
	var seen := get_canvas_transform().affine_inverse() * get_viewport_rect()
	return Rect2i(seen.grow(TILE.x * 2)).intersection(Rect2i(VC.world_rect()))


## Makes the pieces the layout calls for: the frame pieces once, and a piece per room or joined suite,
## reusing the ones whose room, position and suite membership are unchanged (they keep what they drew).
func _sync_pieces() -> void:
	if _frame_pieces.is_empty():
		for layer_name: String in FRAME_LAYERS:
			var piece := _new_piece()
			piece.layer_name = layer_name
			piece.rect = _canvas
			piece.node.z_index = FRAME_Z[layer_name]
			_frame_pieces.append(piece)
	_plan_broken = Parking.broken_ids(tower.rooms, tower.grid)  # cut-off parking is crossed out
	var entries := Suites.entries_for(tower, _room_runs, Suites.tenanted_rooms(tower))  # neighbours of one kind, both in use, draw as one suite (#276)
	var joined: Dictionary = {}  # run index -> true for rooms drawn inside a suite
	var wanted: Dictionary = {}
	for group: Array[int] in Suites.groups(entries):
		var first: Array = _room_runs[group[0]]
		var bounds := Suites.span(entries, group)
		var floor_rect: Rect2i = first[2]
		var union := Rect2i(bounds[0], floor_rect.position.y, bounds[1], floor_rect.size.y)
		var runs: Array = []
		var key := "s%d_%d_%d_%d" % [first[0], union.position.x, union.position.y, union.size.x]
		for index: int in group:
			joined[index] = true
			runs.append(_room_runs[index])
			key += "_%d" % (_room_runs[index][0] as int)
		wanted[key] = [union, runs, entries[group[0]]["kind"]]
	for index: int in _room_runs.size():
		if joined.has(index):
			continue
		var run: Array = _room_runs[index]
		var rect: Rect2i = run[2]
		wanted["r%d_%d_%d_%d_%d" % [run[0], rect.position.x, rect.position.y, rect.size.x, rect.size.y]] = [rect, [run], ""]
	var span := tower.floors.lobby_span()
	if not span.is_empty():  # the lobby: one piece, or in Detailed slices side by side (#346)
		var lobby := Rect2i(span[0] * VC.CELL_W, VC.floor_to_row(span[2]) * VC.CELL_H, (span[1] - span[0] + 1) * VC.CELL_W, span[2] * VC.CELL_H)
		var slice := LOBBY_SLICE if GraphicsStyle.current().density() > 1 else lobby.size.x
		var from := lobby.position.x
		while from < lobby.end.x:
			var to := mini(from + slice, lobby.end.x)
			wanted["lobby_%d_%d_%d_%d" % [from, to, lobby.position.y, lobby.size.y]] = [Rect2i(from, lobby.position.y, to - from, lobby.size.y), [], "lobby"]
			from = to
	if GraphicsStyle.current().density() > 1:  # sky lobbies (#357): Detailed only, each run of lobby cells in slices
		_want_sky_lobbies(wanted)
	var player_made := _synced_once
	for key: Variant in _room_pieces.keys():
		if not wanted.has(key):
			_free_piece(_room_pieces[key] as Piece, player_made)
			_room_pieces.erase(key)
	for key: Variant in wanted:
		var spec: Array = wanted[key]
		var piece: Piece = _room_pieces.get(key)
		var fresh := false
		if piece == null:
			piece = _new_piece()
			piece.node.z_index = LOBBY_Z if (spec[2] as String) in ["lobby", DetailRooms.SKY_LOBBY] else ROOM_Z
			_room_pieces[key] = piece
			piece.urgent = player_made  # a new or moved piece is the player's work: it draws first (#372)
			fresh = true
		piece.rect = spec[0]
		piece.runs = spec[1]
		piece.suite_kind = spec[2]
		if fresh:  # the layout frame skips the room comparison (#349), so a new piece is marked here
			piece.sig = _signature(piece)
			piece.stale = true
		piece.node.set("painter", _paint_room_piece.bind(piece))
	for piece: Piece in _frame_pieces:
		piece.rect = _canvas  # the canvas may have grown since the piece was made: its tiles are all of them (#365)
		piece.stale = true  # floors, shafts and the rest are cheap: repainted whenever the layout changes
		piece.urgent = not _urgent_rects.is_empty()
	_synced_once = true
	_frame_due = tower.tick + STATIC_REFRESH_TICKS


func _new_piece() -> Piece:
	var piece := Piece.new()
	piece.uid = _next_uid
	_next_uid += 1
	piece.node = PixelLayer.new()
	piece.node.set("painter", _paint_frame_piece.bind(piece))
	_statics.add_child(piece.node)
	return piece


func _free_piece(piece: Piece, urgent: bool = false) -> void:
	DetailLight.drop(piece.uid)
	_mark_tiles(piece.rect, urgent)
	piece.node.set("painter", Callable())  # a redraw already queued must not paint a room that is gone before the node is freed
	piece.node.queue_free()
	_glow.queue_redraw()


## What a room piece's look hangs on: the room's state, fill and whether it is lit or dark. A change repaints it.
func _signature(piece: Piece) -> Array:
	var out: Array = []
	for run: Array in piece.runs:
		var id := tower.rooms.room_of(run[0])
		var kind := tower.rooms.kind_of(id)
		out.append_array(RoomLook.state_facts(tower, id, kind, _plan_broken, _plan_workers))
		out.append(_in_use.has(run[1]))
		out.append(_asleep.has(run[1]))
		if kind == RoomLook.PoolLifeScript.KIND:
			out.append(RoomLook._pool_life(tower, id)["anim"])
	return out


## Marks the room pieces whose state changed since they were last marked.
func _mark_changed_rooms() -> void:
	_plan_workers = tower.people.worker_counts()  # one pass, so each office's vacancy is a lookup
	for key: Variant in _room_pieces:
		var piece: Piece = _room_pieces[key]
		var now := _signature(piece)
		if now != piece.sig:
			piece.sig = now
			piece.stale = true


## Finds what the last layout change touched: the floors, links and shafts that are new, gone or different.
## The frame pieces' tiles there are rendered before the background ones (#372). Nothing is urgent while a
## tower is being loaded.
func _note_layout_changes() -> void:
	var floors: Dictionary = {}  # sets, so what changed is found in one pass each way
	for rect: Rect2i in _floor_rects:
		floors[rect] = true
	var links: Dictionary = {}
	for link: Array in _link_runs:
		links[link] = true
	var shafts: Dictionary = {}
	for shaft: Dictionary in _shaft_list():
		var top_row := VC.floor_to_row(shaft["top"])
		var rect := Rect2i((shaft["x"] as int) * VC.CELL_W, top_row * VC.CELL_H, (shaft["width"] as int) * VC.CELL_W, (VC.floor_to_row(shaft["bottom"]) - top_row + 1) * VC.CELL_H)
		shafts[[rect, shaft["stops"], shaft["disabled"]]] = rect
	if _synced_once:
		for rect: Rect2i in floors:
			if not _seen_floors.has(rect):
				_urgent_rects.append(rect)
		for rect: Rect2i in _seen_floors:
			if not floors.has(rect):
				_urgent_rects.append(rect)
		for link: Array in links:
			if not _seen_links.has(link):
				_urgent_rects.append(link[1] as Rect2i)
		for link: Array in _seen_links:
			if not links.has(link):
				_urgent_rects.append(link[1] as Rect2i)
		for shaft: Array in shafts:
			if not _seen_shafts.has(shaft):
				_urgent_rects.append(shafts[shaft] as Rect2i)
		for shaft: Array in _seen_shafts:
			if not shafts.has(shaft):
				_urgent_rects.append(_seen_shafts[shaft] as Rect2i)
		if _urgent_rects.size() > 8:  # a big change (a bulldozed block): one box around it
			var all := _urgent_rects[0]
			for rect: Rect2i in _urgent_rects:
				all = all.merge(rect)
			_urgent_rects = [all]
	_seen_floors = floors
	_seen_links = links
	_seen_shafts = shafts


## Repaints stale pieces near the view, as many as the frame's budget allows (always one), then renders the
## tiles they touched, a few per frame. The player's own work goes first (#372): pieces just built or moved,
## then the frame pieces, then the rest, with a bigger budget for the first group; tiles wait their turn
## oldest first, so a steady refresh of the others cannot starve one. Frame pieces come due every
## STATIC_REFRESH_TICKS ticks.
func _repair() -> void:
	_repair_frame += 1
	if tower.tick >= _frame_due or _frame_due - tower.tick > STATIC_REFRESH_TICKS:
		_frame_due = tower.tick + STATIC_REFRESH_TICKS
		for piece: Piece in _frame_pieces:
			piece.stale = true
	var near := _view_rect()
	var first: Array[Piece] = []
	var frame: Array[Piece] = []
	var rest: Array[Piece] = []
	for piece: Piece in _frame_pieces:
		if piece.stale:
			(first if piece.urgent else frame).append(piece)
	for key: Variant in _room_pieces:
		var piece: Piece = _room_pieces[key]
		if piece.stale and piece.rect.intersects(near):
			(first if piece.urgent else rest).append(piece)
	var queue: Array[Piece] = first + frame + rest
	var spent := 0
	var finished := true
	for piece: Piece in queue:
		var cost := piece.cost_us if piece.cost_us > 0 else UNKNOWN_PIECE_COST_US
		if spent > 0 and spent + cost > (URGENT_BUDGET_US if piece.urgent else REPAIR_BUDGET_US):
			finished = false
			break
		spent += cost
		_repaint(piece)
	if finished:
		_urgent_rects.clear()
	var ready: Array[Tile] = []
	for tile: Tile in _tiles:
		if tile.pending and tile.rect.intersects(near):
			ready.append(tile)
	ready.sort_custom(func(a: Tile, b: Tile) -> bool: return a.urgent if a.urgent != b.urgent else a.since < b.since)
	var renders := 0
	for tile: Tile in ready:
		if renders >= (URGENT_TILE_RENDERS_PER_FRAME if tile.urgent else TILE_RENDERS_PER_FRAME):
			break
		tile.pending = false
		tile.urgent = false
		tile.rendered_frame = _repair_frame
		tile.view.render_target_update_mode = SubViewport.UPDATE_ONCE
		renders += 1


func _repaint(piece: Piece) -> void:
	piece.stale = false
	piece.painted_frame = _repair_frame
	piece.node.queue_redraw()
	_mark_tiles(piece.rect)
	if piece.urgent:
		piece.urgent = false
		if piece.layer_name.is_empty():
			_mark_tiles(piece.rect, true)
		else:
			for rect: Rect2i in _urgent_rects:
				_mark_tiles(rect, true)


## The world rect the canvases need (#307): the built floors, rooms and links, padded and snapped out to
## CANVAS_GRAIN, inside the world. A Detailed canvas holds 4 native pixels per world pixel and costs memory
## in step with its area, so a small or short tower no longer pays for all 110 floors by 400 columns.
## Nothing is drawn outside the built tower except the sky and ground, which are flat rects on this node.
func _canvas_bounds() -> Rect2i:
	var world := Rect2i(VC.world_rect())
	var used := Rect2i()
	var first := true
	var groups: Array = [_floor_rects]
	for run: Array in _room_runs:
		groups.append([run[2]])
	for run: Array in _link_runs:
		groups.append([run[1]])
	for group: Array in groups:
		for rect: Rect2i in group:
			used = rect if first else used.merge(rect)
			first = false
	if first:
		return Rect2i(Vector2i.ZERO, CANVAS_GRAIN).intersection(world)
	var low := used.position - CANVAS_PAD
	var high := used.end + CANVAS_PAD
	low = Vector2i(floori(float(low.x) / CANVAS_GRAIN.x) * CANVAS_GRAIN.x, floori(float(low.y) / CANVAS_GRAIN.y) * CANVAS_GRAIN.y)
	high = Vector2i(ceili(float(high.x) / CANVAS_GRAIN.x) * CANVAS_GRAIN.x, ceili(float(high.y) / CANVAS_GRAIN.y) * CANVAS_GRAIN.y)
	return Rect2i(low, high - low).intersection(world)


## Detailed at zoom 1 shows a 2x canvas at half size: point sampling would drop every other pixel, but
## linear sampling lands exactly between texels there and averages each 2x2 block. At even zooms the scale is
## a whole number, so nearest stays crisp. (The camera skips zoom 3 in Detailed, where the scale would be 1.5.)
func _follow_zoom() -> void:
	var detailed := GraphicsStyle.current().density() > 1
	var filter := CanvasItem.TEXTURE_FILTER_LINEAR if detailed and get_canvas_transform().get_scale().x < ZOOM_SHARP_ABOVE else CanvasItem.TEXTURE_FILTER_NEAREST
	if _tile_root.texture_filter != filter:
		_tile_root.texture_filter = filter
		_dynamic_sprite.texture_filter = filter


## Detailed lights the world instead of painting it dark (#305): by night the static canvas is multiplied by
## the sky's ambient colour (people, who are on the dynamic canvas, by half of it) and the glow layer adds the
## lit rooms' lights over it. Classic is left as it was.
func _apply_ambient() -> void:
	var detailed := GraphicsStyle.current().density() > 1
	var ambient := DetailLight.ambient(SkyLook.daylight) if detailed else Color.WHITE
	_tile_root.modulate = ambient
	_dynamic_sprite.modulate = Color.WHITE.lerp(ambient, 0.5)
	_glow.visible = detailed
	_glow.queue_redraw()


## Redraws what changed; the view never polls the whole tower.
func _process(delta: float) -> void:
	if tower == null or _tile_root == null:
		return
	_since_tick += delta
	_follow_sky()
	_follow_zoom()
	_follow_outdoors()
	var new_tick := tower.tick != _seen_tick
	if _elevators.observe(tower):
		_tick_len = maxf(_since_tick, 0.001)
		_since_tick = 0.0
	var gliding := _elevators.glide(delta)
	var occupants := tower.grid.occupant_count() + tower.rooms.links.occupant_count() + tower.rooms.links_over.occupant_count()
	var layout_changed := tower.floors.revision != _seen_revision or occupants != _seen_occupants
	if layout_changed:
		_seen_revision = tower.floors.revision
		_seen_occupants = occupants
		_people_view.route_cache.clear()
		_rebuild_runs()
		if _canvas != _canvas_bounds():
			_apply_density(false)
		_in_use = _rooms_in_use()
		_note_layout_changes()
		_sync_pieces()
	var area := _people_area()
	if new_tick or layout_changed or _view_left_figures(area):  # also when the camera moved past the people built for (#451)
		if new_tick or layout_changed:
			_remember_positions()
		_figures_for = area
		figures_version += 1
		_figures = _people_view.figures(tower, area)
		_has_moving = false
		for figure: Dictionary in _figures:
			if figure["moving"]:
				_has_moving = true
				break
	var label_step := ShaftNumbers.step_for_zoom(get_canvas_transform().get_scale().x)
	if label_step != _label_step:  ## Zoomed across the threshold: the shaft numbers change (#431).
		_label_step = label_step
		layout_changed = true
		_mark_all_stale()
	if TransportLook.see_through != _seen_see_through or TransportGlass.on != _seen_glass:  ## A view option changed: repaint the shafts and links.
		_seen_see_through = TransportLook.see_through
		_seen_glass = TransportGlass.on
		layout_changed = true
		_mark_all_stale()
	if GraphicsStyle.current() != _seen_style:  ## Graphics Classic/Detailed changed: repaint everything.
		_seen_style = GraphicsStyle.current()
		_apply_density()
		layout_changed = true
		queue_redraw()
	if layout_changed:
		_checked_tick = tower.tick
	elif tower.tick - _checked_tick >= IN_USE_CHECK_TICKS or tower.tick < _checked_tick:
		_checked_tick = tower.tick
		_in_use = _rooms_in_use()
		_sync_pieces()  # tenancy can join or split suites without a layout change
	if not layout_changed:  # a layout frame already did the layout's work; the next frame compares room states (#349)
		_mark_changed_rooms()
	_repair()
	var sliding := (tower.rooms.total_cars() > 0 and _since_tick <= _tick_len * 2.0) or (_has_moving and _since_tick <= _tick_len) or gliding
	if sliding and not new_tick and not layout_changed:
		sliding = _motion_in_view()  # between ticks, repaint only for motion the player can see (#399)
	if not (new_tick or layout_changed or sliding) and _view_left_painted():
		sliding = true  # the camera panned or zoomed past the culled people: repaint, also while paused (#418)
	if new_tick or layout_changed or sliding:
		_dynamic_layer.queue_redraw()
		_dynamic_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_seen_tick = tower.tick


## The world rect the camera sees, or an empty rect when it is unknown (then nothing is culled).
func _visible_world() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	var view := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	return view if view.size.x > 0.0 and view.size.y > 0.0 else Rect2()


## The world rect people are built and painted for: the camera's view with half a view of margin on each
## side, so small pans change nothing. Empty when the view is unknown (then nobody is culled).
func _people_area() -> Rect2:
	var view := _visible_world()
	if view.size == Vector2.ZERO:
		return Rect2()
	return view.grow_individual(view.size.x * 0.5, view.size.y * 0.5, view.size.x * 0.5, view.size.y * 0.5).grow(float(VC.CELL_H * 2))


## True when the camera sees beyond the area the figures were built for, so people must be built again.
func _view_left_figures(area: Rect2) -> bool:
	if _figures_for.size == Vector2.ZERO:
		return area.size != Vector2.ZERO  # built for everyone, or not at all, and now the view is known
	var view := _visible_world()
	return view.size != Vector2.ZERO and not _figures_for.encloses(view)


## True when the camera now sees beyond the area the people were last painted for.
func _view_left_painted() -> bool:
	if _people_painted_for.size == Vector2.ZERO:
		return false  # painted without culling
	var view := _visible_world()
	return view.size != Vector2.ZERO and not _people_painted_for.encloses(view)


## True when a car or a moving figure is inside the visible part of the tower (or the view is unknown), so
## the dynamic layer is worth repainting between ticks to slide it. Off-screen motion repaints at the next tick.
func _motion_in_view() -> bool:
	if not is_inside_tree():
		return true
	var view := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return true
	view = view.grow(float(VC.CELL_H * 2))
	for car: Dictionary in _elevators.cars(tower, 0.0, _shaft_list()):
		var top := ElevatorView.level_to_y(car["level"], VC.CELL_H)
		if view.intersects(Rect2(float((car["x"] as int) * VC.CELL_W), top, float((car["width"] as int) * VC.CELL_W), float(VC.CELL_H))):
			return true
	for figure: Dictionary in _figures:
		if figure["moving"] and view.intersects(Rect2(float(figure["fx"]) * VC.CELL_W, float(figure["frow"]) * VC.CELL_H, float(VC.CELL_W), float(VC.CELL_H))):
			return true
	return false


## Copies the time of day into SkyLook (rooms read it when drawn) and redraws the sky and every room when
## daylight has moved a step or the rain flag changed, so night falls in a few dozen steps a day.
func _follow_sky() -> void:
	var step := SkyLook.quantized(tower.clock.minute_of_day())
	if step == SkyLook.daylight and _seen_rain == SkyLook.rain:
		return
	SkyLook.daylight = step
	_seen_rain = SkyLook.rain
	_apply_ambient()
	_mark_all_stale()
	queue_redraw()


func set_tower(value: Tower) -> void:
	tower = value
	_synced_once = false
	_row_cache.clear()
	_sky_key = []
	_shafts_key = []
	_urgent_rects.clear()
	_mark_all_stale()
	_seen_revision = -1
	_seen_tick = -1
	queue_redraw()


## Redraws everything after the palette in use changed.
func refresh_palette() -> void:
	_outdoors_key = []
	_mark_all_stale()  # the layout is unchanged, so the runs need no rebuild
	queue_redraw()


## Rooms with someone resting in them, from the figures drawn this tick.
func _rooms_in_use() -> Dictionary:
	_asleep = _people_view.asleep  # filled by figures() for everyone, on screen or not (#451)
	return _people_view.in_use


## The floor, room and link runs as rects, found once per layout change and reused by every redraw. Only the
## floors whose cells differ from the last call are scanned again (#349); the rest keep their runs.
func _rebuild_runs() -> void:
	if _row_cache.size() != Tower.Grid.FLOOR_COUNT:
		_row_cache.clear()
		for _i in Tower.Grid.FLOOR_COUNT:
			_row_cache.append([])
	_floor_rects.clear()
	_room_runs.clear()
	_link_runs.clear()
	for index: int in Tower.Grid.FLOOR_COUNT:
		var floor_number := Tower.Grid.index_to_floor(index)
		var key: Array = [tower.floors.row_flags(floor_number), tower.grid.row_cells(floor_number), tower.rooms.links.row_cells(floor_number), tower.rooms.links_over.row_cells(floor_number)]
		var cached: Array = _row_cache[index]
		if cached.is_empty() or cached[0] != key:
			cached = [key, _scan_floor(floor_number)]
			_row_cache[index] = cached
		var found: Array = cached[1]
		_floor_rects.append_array(found[0] as Array[Rect2i])
		_room_runs.append_array(found[1] as Array[Array])
		_link_runs.append_array(found[2] as Array[Array])


## One floor's floor rects, room runs and link runs: [Array[Rect2i], Array[Array], Array[Array]].
func _scan_floor(floor_number: int) -> Array:
	var rects: Array[Rect2i] = []
	var rooms: Array[Array] = []
	var links: Array[Array] = []
	var links_seen: Dictionary = {}
	var row_y := VC.floor_to_row(floor_number) * VC.CELL_H
	var column := 0
	var floor_start := -1
	while column <= Tower.Grid.WIDTH_UNITS:
		var built := column < Tower.Grid.WIDTH_UNITS and tower.floors.has_floor(floor_number, column)
		if built and floor_start < 0:
			floor_start = column
		elif not built and floor_start >= 0:
			rects.append(Rect2i(floor_start * VC.CELL_W, row_y, (column - floor_start) * VC.CELL_W, VC.CELL_H))
			floor_start = -1
		column += 1
	var seen: Dictionary = {}
	column = 0
	while column < Tower.Grid.WIDTH_UNITS:
		var id := tower.grid.cell_at(floor_number, column)
		if id == Tower.Grid.EMPTY or seen.has(id):
			column += 1
			continue
		seen[id] = true
		var run := tower.grid.run_of(id)
		var owner_room: int = tower.rooms.room_of(id)
		if owner_room != 0:
			rooms.append([id, owner_room, Rect2i(run[1] * VC.CELL_W, row_y, run[2] * VC.CELL_W, VC.CELL_H)])
		column += maxi(run[2], 1)
	for layer: Tower.Grid in [tower.rooms.links, tower.rooms.links_over]:  # a stacked flight's lower half sits in the second layer (#259)
		column = 0
		while column < Tower.Grid.WIDTH_UNITS:
			var link := layer.cell_at(floor_number, column)
			if link == Tower.Grid.EMPTY or links_seen.has(link) or not Tower.RoomsScript.is_stair_kind(tower.rooms.kind_of(link)):
				column += 1
				continue
			links_seen[link] = true
			var link_run := layer.run_of(link)
			var top := VC.floor_to_row(Tower.RoomsScript.floor_above(floor_number)) * VC.CELL_H
			links.append([tower.rooms.kind_of(link), Rect2i(link_run[1] * VC.CELL_W, top, link_run[2] * VC.CELL_W, 2 * VC.CELL_H)])
			column += maxi(link_run[2], 1)
	return [rects, rooms, links]


## Paints a frame piece: one of the static layers that are not rooms (backdrop, lobby, links, floors,
## shafts, facade).
func _paint_frame_piece(canvas: CanvasItem, piece: Piece) -> void:
	if tower == null:
		return
	var started := Time.get_ticks_usec()
	DetailLight.drop(piece.uid)
	DetailLight.painter_id = piece.uid
	call(piece.layer_name, canvas)
	DetailLight.painter_id = 0
	_glow.queue_redraw()
	piece.cost_us = Time.get_ticks_usec() - started


## Paints a room, or a joined suite, into its own rect. Its lights are dropped first and recorded afresh.
func _paint_room_piece(canvas: CanvasItem, piece: Piece) -> void:
	if tower == null:
		return
	var started := Time.get_ticks_usec()
	DetailLight.drop(piece.uid)
	DetailLight.painter_id = piece.uid
	if piece.suite_kind == DetailRooms.SKY_LOBBY:
		_paint_sky_lobby_slice(canvas, piece)
		DetailLight.painter_id = 0
		_glow.queue_redraw()
		piece.cost_us = Time.get_ticks_usec() - started
		return
	if piece.suite_kind == "lobby":
		_paint_lobby_slice(canvas, piece.rect)
		DetailLight.painter_id = 0
		_glow.queue_redraw()
		piece.cost_us = Time.get_ticks_usec() - started
		return
	var first: Array = piece.runs[0]
	if piece.suite_kind != "":
		GraphicsStyle.current().suite(canvas, piece.suite_kind, piece.rect, first[0])
	else:
		GraphicsStyle.current().room(canvas, tower, first[0], first[2], _plan_broken, _in_use.has(first[1]), _asleep.has(first[1]) and not _in_use.has(first[1]))
	DetailLight.painter_id = 0
	_glow.queue_redraw()
	piece.cost_us = Time.get_ticks_usec() - started


func _paint_dynamic(canvas: CanvasItem) -> void:
	if tower == null:
		return
	for layer: String in DYNAMIC_LAYERS:
		call(layer, canvas)


## Sky above the ground line and earth below, in the palette in use. Flat colour, so no low-res
## canvas is needed; the tower's own sprites sit in front.
func _draw() -> void:
	var p := Palette.get_palette()
	var world := Rect2i(VC.world_rect())
	var ground_y := Tower.Grid.FLOOR_MAX * VC.CELL_H  # bottom of floor 1, top of B1
	var left := -MARGIN
	var width := world.size.x + 2 * MARGIN
	var minute := tower.clock.minute_of_day() if tower != null else 12 * 60
	GraphicsStyle.current().sky(self, p, minute, left, world.position.y - MARGIN, width, ground_y, world.size.x)
	draw_rect(Rect2i(left, ground_y, width, world.size.y - ground_y + MARGIN), p["earth"])
	draw_rect(Rect2i(left, ground_y, width, 3), p["ground"])


## A dim wall behind every built floor unit, so an empty floor reads as an empty box in the cutaway.
func _draw_backdrop(canvas: CanvasItem) -> void:
	var wall: Color = (Palette.get_palette()["wall"] as Color).lightened(0.12)
	for rect: Rect2i in _floor_rects:
		canvas.draw_rect(rect, wall)


## Facade edges and roofs on the built floor runs (#306); Classic draws none.
func _draw_exterior(canvas: CanvasItem) -> void:
	GraphicsStyle.current().exterior(canvas, _floor_rects, SkyLook.daylight)


## Built floor units: a thin slab along the bottom of each floor's row.
func _draw_floors(canvas: CanvasItem) -> void:
	var slab: Color = Palette.get_palette()["slab"]
	var highlight: Color = Palette.get_palette()["slab_hi"]
	for rect: Rect2i in _floor_rects:
		canvas.draw_rect(Rect2i(rect.position.x, rect.end.y - VC.SLAB_H, rect.size.x, VC.SLAB_H), slab)
		canvas.draw_rect(Rect2i(rect.position.x, rect.end.y - VC.SLAB_H, rect.size.x, 1), highlight)  # 1 px lit edge


## The ground lobby over floors 1 to its height, with the lobby recipe on its bottom floor.
func _draw_lobby(canvas: CanvasItem) -> void:
	var span := tower.floors.lobby_span()
	if span.is_empty():
		return
	var rect := Rect2i(span[0] * VC.CELL_W, VC.floor_to_row(span[2]) * VC.CELL_H, (span[1] - span[0] + 1) * VC.CELL_W, span[2] * VC.CELL_H)
	GraphicsStyle.current().recipe(canvas, "lobby", rect, Palette.hue("lobby"), true)


## One slice of the lobby: the whole lobby recipe confined to the slice's x range, so slices side by side are
## the one picture, and a slice costs only its share.
func _paint_lobby_slice(canvas: CanvasItem, slice: Rect2i) -> void:
	var span := tower.floors.lobby_span()
	if span.is_empty():
		return
	var rect := Rect2i(span[0] * VC.CELL_W, VC.floor_to_row(span[2]) * VC.CELL_H, (span[1] - span[0] + 1) * VC.CELL_W, span[2] * VC.CELL_H)
	DetailRooms.window = Vector2i(slice.position.x, slice.end.x) if slice.size.x < rect.size.x else Vector2i.ZERO
	GraphicsStyle.current().recipe(canvas, "lobby", rect, Palette.hue("lobby"), true)
	DetailRooms.window = Vector2i.ZERO


## Adds a slice piece to `wanted` for every run of lobby cells on every sky lobby floor. A piece's runs hold
## [floor, whole run rect], so each slice paints its share of the one picture.
func _want_sky_lobbies(wanted: Dictionary) -> void:
	var key: Array = []
	for floor_number: int in tower.floors.SKY_LOBBY_FLOORS:
		key.append(tower.floors.row_flags(floor_number))
	if key != _sky_key:  # the scan walks every cell of six floors: redone only when one of them changed (#349)
		_sky_key = key
		_sky_wanted = {}
		_scan_sky_lobbies(_sky_wanted)
	wanted.merge(_sky_wanted)


func _scan_sky_lobbies(wanted: Dictionary) -> void:
	for floor_number: int in tower.floors.SKY_LOBBY_FLOORS:
		var row_y := VC.floor_to_row(floor_number) * VC.CELL_H
		var column := 0
		while column < Tower.Grid.WIDTH_UNITS:
			if not tower.floors.has_lobby_at(floor_number, column):
				column += 1
				continue
			var start := column
			while column < Tower.Grid.WIDTH_UNITS and tower.floors.has_lobby_at(floor_number, column):
				column += 1
			var run := Rect2i(start * VC.CELL_W, row_y, (column - start) * VC.CELL_W, VC.CELL_H)
			var from := run.position.x
			while from < run.end.x:
				var to := mini(from + LOBBY_SLICE, run.end.x)
				wanted["sky_%d_%d_%d" % [floor_number, from, to]] = [Rect2i(from, row_y, to - from, VC.CELL_H), [[floor_number, run]], DetailRooms.SKY_LOBBY]
				from = to


## One slice of a sky lobby's hall, confined to the slice's x range like the ground lobby's.
func _paint_sky_lobby_slice(canvas: CanvasItem, piece: Piece) -> void:
	var info: Array = piece.runs[0]
	var run: Rect2i = info[1]
	DetailRooms.window = Vector2i(piece.rect.position.x, piece.rect.end.x) if piece.rect.size.x < run.size.x else Vector2i.ZERO
	DetailRooms.draw(canvas, DetailRooms.SKY_LOBBY, run, Palette.hue("lobby"), true, false, info[0] as int)
	DetailRooms.window = Vector2i.ZERO


func _draw_rooms(canvas: CanvasItem) -> void:
	var broken: Array[int] = Parking.broken_ids(tower.rooms, tower.grid)  # cut-off parking is crossed out
	var entries := Suites.entries_for(tower, _room_runs, Suites.tenanted_rooms(tower))  # neighbours of one kind, both in use, draw as one suite (#276)
	var joined: Dictionary = {}  # run index -> true for rooms drawn inside a suite
	for group: Array[int] in Suites.groups(entries):
		var first: Array = _room_runs[group[0]]
		var bounds := Suites.span(entries, group)
		var floor_rect: Rect2i = first[2]
		GraphicsStyle.current().suite(canvas, entries[group[0]]["kind"], Rect2i(bounds[0], floor_rect.position.y, bounds[1], floor_rect.size.y), first[0])
		for index: int in group:
			joined[index] = true
	for index: int in _room_runs.size():
		if joined.has(index):
			continue
		var run: Array = _room_runs[index]
		GraphicsStyle.current().room(canvas, tower, run[0], run[2], broken, _in_use.has(run[1]), _asleep.has(run[1]) and not _in_use.has(run[1]))


## Stairs and escalators (the link layer) in front of the rooms: each spans its own floor and the one
## above, climbing to the right across its width.
func _draw_links(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	for run: Array in _link_runs:
		_draw_link(canvas, p, run[0], run[1])


## The escalators' moving steps and handrail dashes, redrawn each tick from the sim tick (so they scroll
## the same on every run); the fixed frame is in the link layer.
func _draw_belts(canvas: CanvasItem) -> void:
	for run: Array in _link_runs:
		if run[0] == "escalator":
			GraphicsStyle.current().belt(canvas, run[1], tower.tick, Palette.hue("escalator"))


## One link in its two-floor rect, drawn without a background (transport_look.gd) so the room behind shows.
func _draw_link(canvas: CanvasItem, _p: Dictionary, kind: String, span: Rect2i) -> void:
	GraphicsStyle.current().link(canvas, kind, span)


## Remembers where the moving figures were, so the next tick's positions can be glided to.
func _remember_positions() -> void:
	_from.clear()
	for figure: Dictionary in _figures:
		if figure["moving"]:
			_from[figure["id"]] = Vector2(figure["fx"], figure["frow"])


## Where a figure is drawn now, as a fractional column and row: a moving one glides from its last
## tick's spot, but a jump of more than a few columns or a floor (a new trip) snaps instead.
func _shown_at(figure: Dictionary) -> Vector2:
	var now := Vector2(figure["fx"], figure["frow"])
	if not figure["moving"] or not _from.has(figure["id"]):
		return now
	var before: Vector2 = _from[figure["id"]]
	if absf(now.x - before.x) > GLIDE_MAX_COLUMNS or absf(now.y - before.y) > 1.5:
		return now
	return before.lerp(now, clampf(_since_tick / _tick_len, 0.0, 1.0))


## One figure, FIGURE_W x FIGURE_H, feet at `feet`: head, body, legs, then the stress marks above.
## Everything is sized from the figure constants so a bigger figure needs no change here. pose and
## phase choose the frame: walking alternates legs apart and together every half column, stairs
## lift one leg and bob, an escalator rider stands with legs together.
func _draw_figure(canvas: CanvasItem, x: int, feet: int, shirt: Color, band: int, skin: Color, pose: int = 0, phase: int = 0, who: Dictionary = {}, walk: int = 0) -> void:
	var bob := 1 if pose == PeopleView.POSE_STAIRS and phase % 2 == 1 else 0
	var top := feet - FIGURE_H - bob
	var apart := (pose == PeopleView.POSE_WALK and phase % 2 == 0) or pose == PeopleView.POSE_STAIRS
	var raised_left := 1 if pose == PeopleView.POSE_STAIRS and phase < 2 else 0
	var raised_right := 1 if pose == PeopleView.POSE_STAIRS and phase >= 2 else 0
	GraphicsStyle.current().person(canvas, x, feet - bob, shirt, skin, apart, raised_left, raised_right, who, pose, walk)
	for mark in PeopleView.marks_of(band):  # shape cue: one dot uneasy, two angry
		canvas.draw_rect(Rect2i(x + mark * 2 - 1, top - 2, 1, 1), shirt)


## Who a figure is, for styles that draw people individually (#304): its id, age band, job and facing, and
## the stress colour when it is not calm. Empty for a figure the view knows nothing about.
func _who_of(figure: Dictionary, band: int, shirt: Color, facing: int) -> Dictionary:
	var who := {"id": figure["id"], "age": figure.get("age", 1), "child": figure.get("child", false), "job": figure.get("job", ""), "band": band, "dir": facing}
	if band != 0:
		who["shirt"] = shirt
	return who


## Which way a walker faces: along its last move, to the right when it has not moved.
func _facing_of(figure: Dictionary) -> int:
	if _from.has(figure["id"]):
		var dx: float = figure["fx"] - (_from[figure["id"]] as Vector2).x
		if dx < -0.01:
			return -1
	return 1


## Fire and smoke, guards on their way, the rescue craft and the threat search (event_look.gd); each draws
## only while its sim state is active.
func _draw_events(canvas: CanvasItem) -> void:
	EventLook.draw_fire(canvas, tower, tower.tick)
	EventLook.draw_search(canvas, tower, tower.tick)
	EventLook.draw_guards(canvas, tower, tower.tick)
	EventLook.draw_rescue(canvas, tower, tower.tick)


## The figures drawn at the last tick, for layers that sit on top of the tower (thought icons).
func figures() -> Array[Dictionary]:
	return _figures


func _draw_people(canvas: CanvasItem) -> void:
	var skin: Color = Palette.get_palette()["skin"]
	var types: Array = Palette.get_palette()["people"]
	var keep := _people_area()  # a margin, so small pans need no repaint
	var cull := keep.size != Vector2.ZERO
	_people_painted_for = keep
	for figure: Dictionary in _figures:
		if cull:
			var where := Vector2(figure["px"], figure["pfeet"]) if figure.has("px") else Vector2(float(figure["fx"]) * VC.CELL_W, float(figure["frow"]) * VC.CELL_H)
			if not keep.has_point(where):
				continue
		var band: int = figure["band"]
		if not figure["moving"]:  # resting: on a spot of its room, doing what the sim says
			var rest_shirt: Color = types[(figure["id"] as int) % types.size()] if band == 0 else PeopleView.color_of(band)
			var p := Palette.get_palette()
			GraphicsStyle.current().activity(canvas, figure["px"], figure["pfeet"], figure["act"], ActivityLook.frame(figure["id"], tower.tick), rest_shirt, skin, p["gold"], p["white"], _who_of(figure, band, rest_shirt, 1))
			continue
		var at := _shown_at(figure)
		var x := roundi(at.x * VC.CELL_W) + (VC.CELL_W - FIGURE_W) / 2
		var feet := roundi((at.y + 1.0) * VC.CELL_H) - 3
		var pose: int = figure["pose"]
		var phase := int(at.x * 2.0) & 1
		if pose == PeopleView.POSE_STAIRS:
			phase = int(at.x * 4.0) & 3
		# A colour per type (a stand-in until the sim has types: the person's id); a stressed
		# person wears the band colour instead, so the mood still reads at a glance.
		var shirt: Color = types[(figure["id"] as int) % types.size()] if band == 0 else PeopleView.color_of(band)
		var facing := _facing_of(figure)
		_draw_figure(canvas, x, feet, shirt, band, skin, pose, phase, _who_of(figure, band, shirt, facing), int(at.x * 8.0) & 3)


## Each shaft across its span; a floor it stops at has doors and an indicator, a disabled one a red cross.
func _draw_shafts(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var shaft_color := Palette.hue("shaft")
	for shaft: Dictionary in _shaft_list():
		var top_row := VC.floor_to_row(shaft["top"])
		var bottom_row := VC.floor_to_row(shaft["bottom"])
		var rect := Rect2i((shaft["x"] as int) * VC.CELL_W, top_row * VC.CELL_H, (shaft["width"] as int) * VC.CELL_W, (bottom_row - top_row + 1) * VC.CELL_H)
		var caps: Array[Rect2i] = []
		for machine: int in Tower.RoomsScript.machine_floors(shaft["bottom"], shaft["top"]):  # the machine-room caps (#228)
			caps.append(Rect2i(rect.position.x, VC.floor_to_row(machine) * VC.CELL_H, rect.size.x, VC.CELL_H - VC.SLAB_H))
		var door_rows: Array[int] = []
		for floor_number: int in shaft["stops"]:
			door_rows.append(_floor_bottom(floor_number))
		GraphicsStyle.current().shaft(canvas, rect, shaft_color, caps, door_rows, TransportLook.see_through)
		ShaftNumbers.draw(canvas, rect, shaft["bottom"], shaft["top"], _label_step, shaft_color)
		for floor_number: int in shaft["disabled"]:
			var top := VC.floor_to_row(floor_number) * VC.CELL_H
			var red: Color = p["red"]
			for n in 8:  # a pixel-stepped cross
				canvas.draw_rect(Rect2i(rect.position.x + 6 + n, top + 6 + n, 1, 1), red)
				canvas.draw_rect(Rect2i(rect.position.x + 13 - n, top + 6 + n, 1, 1), red)


## The pixel row of a floor's surface (the top of its slab).
func _floor_bottom(floor_number: int) -> int:
	return (VC.floor_to_row(floor_number) + 1) * VC.CELL_H - VC.SLAB_H


## The pixel row of the surface of the floor at a car level (see ElevatorView.level_to_y).
func _level_bottom(level: int) -> int:
	return roundi(ElevatorView.level_to_y(float(level), VC.CELL_H)) + VC.CELL_H - VC.SLAB_H


## Cars at their interpolated place, each showing its riders as figures and lighting the indicator at the floor it is at.
func _draw_cars(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var car_color := Palette.hue("car")
	var t := clampf(_since_tick / _tick_len, 0.0, 1.0)
	for car: Dictionary in _elevators.cars(tower, t, _shaft_list()):
		var shaft_rect := Rect2i((car["x"] as int) * VC.CELL_W, 0, (car["width"] as int) * VC.CELL_W, VC.CELL_H)
		var x: int = (car["x"] as int) * VC.CELL_W + 3
		var y := roundi(ElevatorView.level_to_y(car["level"], VC.CELL_H)) + 3
		var w: int = (car["width"] as int) * VC.CELL_W - 6
		var h := VC.CELL_H - VC.SLAB_H - 3
		GraphicsStyle.current().car(canvas, shaft_rect, Rect2i(x, y, w, h), car["level"], car["step"], car["load"], car_color, p["people"], p["lamp"], _level_bottom)


## ElevatorView.shafts for the tower as it stands, rebuilt only when the layout moves: it walks every floor
## of every shaft, and the queue and car layers asked for it on every redraw (#399).
func _shaft_list() -> Array[Dictionary]:
	var key: Array = [tower.rooms.links.revision, tower.rooms.route_revision, tower.rooms.shaft_ids()]
	if key != _shafts_key:
		_shafts_key = key
		_shafts_seen = ElevatorView.shafts(tower)
	return _shafts_seen


## Hall queues: people going up wait left of the shaft, going down right of it; a long queue shows
## its first figures and a +N count.
func _draw_queues(canvas: CanvasItem) -> void:
	var p := Palette.get_palette()
	var ink: Color = p["ink"]
	var skin: Color = p["skin"]
	for queue: Dictionary in ElevatorView.queues(tower, _shaft_list()):
		var side: int = queue["side"]
		var feet := (VC.floor_to_row(queue["floor"]) + 1) * VC.CELL_H - 3
		var edge: int = (queue["x"] as int) * VC.CELL_W if side < 0 else ((queue["x"] as int) + (queue["width"] as int)) * VC.CELL_W
		for n: int in queue["shown"]:
			var x := edge - (n + 1) * (FIGURE_W + 2) if side < 0 else edge + 2 + n * (FIGURE_W + 2)
			var waiting := {"id": (queue["floor"] as int) * 31 + (queue["x"] as int) * 7 + n, "age": 1, "child": false, "job": "", "band": 0, "dir": 1 if side < 0 else -1, "still": true}
			_draw_figure(canvas, x, feet, ink.lightened(0.35), 0, skin, 0, 0, waiting)
		var label: String = queue["label"]
		if label != "":
			var shown_px: int = (queue["shown"] as int) * (FIGURE_W + 2)
			var label_x := edge - shown_px - 16 if side < 0 else edge + shown_px + 4
			canvas.draw_string(ThemeDB.fallback_font, Vector2(label_x, feet), label, HORIZONTAL_ALIGNMENT_LEFT, 16, 8, ink)
