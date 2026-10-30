class_name OptionsView
extends Control
## The options page: the front-end water seen through the sweeping options camera, with the
## lily rows, titles, volume logs, frog and prompt drawn from an [OptionsMenu] stepped at 30 Hz.
##
## The lily, log and frog models of OPTIONS.WAD are not loaded yet: lilies and the frog are
## flat stand-in shapes on the water and each volume log is a bar of eight cels, all projected
## through the options camera. Titles are the named menu images lying flat on the water. The
## menu keys are fixed: Up/Down held, Left/Right, Enter or Space (fire) and Escape (back)
## pressed. Each tick's events are raised through [signal menu_event]; the page asks to leave
## with [constant OptionsMenu.EventKind].LEAVE and its [member OptionsMenu.request]. Between ticks
## the camera and models are interpolated from the last two ticks, which drawing never changes.

## An [enum OptionsMenu.EventKind] raised by the last tick.
signal menu_event(kind: int)

## Seconds per menu tick.
const PERIOD: float = GameplayHost.PERIOD
## Horizontal focal length of the options viewport (perspective 256 on the 640x480 display).
const FOCAL_X: float = 512.0
## Vertical focal length, the horizontal one times the projection's clip-space scale.
const FOCAL_Y: float = 480.0
## Centre of the 640x480 display.
const CENTRE: Vector2 = Vector2(320.0, 240.0)
## Nearest depth drawn, in game units.
const NEAR_DEPTH: float = 16.0
## Stand-in lily radius before its model scale.
const LILY_RADIUS: int = 0xa8
## Stand-in frog radius before its model scale.
const FROG_RADIUS: int = 0x50
## Half the stand-in log's length before its model scale.
const LOG_HALF_LENGTH: int = 0x200
## Half the stand-in log's depth before its model scale.
const LOG_HALF_DEPTH: int = 0x60
## The title's left edge (the vendored title x rule: -0x200 + (te_w >> 1) * 8 at its centre).
const TITLE_LEFT: int = -0x200
## World units per title image pixel.
const TITLE_UNITS_PER_PIXEL: int = 8
## Model scales of KEY_FACTS KF-110 (4.12).
const LILY_SCALE: int = 5632
const LOG_SCALE: int = 4864
const FROG_SCALE: int = 5120
const TITLE_SCALES: PackedInt32Array = [4096, 5120, 4096]
## Menu image of each titled [enum OptionsMenu.Row].
const TITLE_IMAGES: Dictionary[int, String] = {
	OptionsMenu.Row.EXIT: "opt_exit",
	OptionsMenu.Row.VIEW_SCORES: "opt_view_hs",
	OptionsMenu.Row.CONTROLS: "opt_ctrl_config",
}
## The prompt image under the rows.
const PROMPT_IMAGE: String = "select7"
## Distance of the prompt's bottom from the display's bottom.
const PROMPT_MARGIN: float = 16.0
const LILY_COLOUR: Color = Color(0.22, 0.62, 0.2)
const LILY_EDGE: Color = Color(0.1, 0.35, 0.1)
const LOG_COLOUR: Color = Color(0.36, 0.2, 0.08)
const CEL_BLANK: Color = Color(0.2, 0.11, 0.04)
const CEL_FULL: Color = Color(0.95, 0.78, 0.3)
const FROG_COLOUR: Color = Color(0.3, 0.85, 0.2)
const FROG_EDGE: Color = Color(0.05, 0.3, 0.05)
const LABEL_COLOUR: Color = Color(1.0, 1.0, 0.85)

## The menu being drawn.
var menu: OptionsMenu
## The shared options camera.
var camera_rig: OptionsCamera
## The water and its camera.
var water: MenuWaterView
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## Time since the last tick.
var elapsed: float = 0.0

var _assets: FrontEndAssets
var _from_row: int = 0
var _previous: _Frame
var _current: _Frame
var _up_held: bool = false
var _down_held: bool = false
var _up_tapped: bool = false
var _down_tapped: bool = false
var _left: bool = false
var _right: bool = false
var _fire: bool = false
var _back: bool = false
var _drawn: _Frame
var _drawn_source: Vector3i = Vector3i.ZERO
var _drawn_target: Vector3i = Vector3i.ZERO


class _Frame:
	extends RefCounted
	var source: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	var lilies: Array[Vector3] = []
	var titles: Array[Vector3] = []
	var logs: Array[Vector3] = []
	var frog: Vector3 = Vector3.ZERO
	var prompt_drop: float = 0.0


## A page over [param water_animation] seen through [param rig], with volume steps [param music]
## and [param effects], the frog on [param start_row] and the hidden high-score row unless
## [param show_scores].
static func create(assets: FrontEndAssets, water_animation: MenuWater, rig: OptionsCamera, music: int, effects: int,
		start_row: int = OptionsMenu.Row.EXIT, show_scores: bool = false) -> OptionsView:
	var view := OptionsView.new()
	view._assets = assets
	view.camera_rig = rig
	view.menu = OptionsMenu.create(music, effects, start_row, show_scores)
	view._from_row = view.menu.row
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.water = MenuWaterView.create_with_camera(water_animation, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	view.add_child(view.water)
	view._current = view._capture()
	view.render(1.0)
	return view


## The display position and depth of game position [param at] seen from [param source] looking
## at [param target]; depth is not positive behind the eye.
static func project(source: Vector3i, target: Vector3i, at: Vector3) -> Vector3:
	var local: Vector3 = MenuWaterView.camera_transform(source, target).affine_inverse() * (Vector3(at.x, -at.y, -at.z) / GameSpace.UNITS_PER_SQUARE)
	var depth: float = -local.z * GameSpace.UNITS_PER_SQUARE
	if depth <= 0.0:
		return Vector3(CENTRE.x, CENTRE.y, depth)
	var inverse: float = GameSpace.UNITS_PER_SQUARE / depth
	return Vector3(CENTRE.x + FOCAL_X * local.x * inverse, CENTRE.y - FOCAL_Y * local.y * inverse, depth)


## Advances the menu one tick with [param buttons], moves the camera, raises the events and
## returns them.
func tick(buttons: OptionsMenu.Buttons) -> PackedInt32Array:
	var row_before: int = menu.row
	var events: PackedInt32Array = menu.step(buttons, water.water.frame_count)
	if menu.row != row_before:
		_from_row = row_before
	camera_rig.move(menu.camera, menu.camera_timer)
	_previous = _current
	_current = _capture()
	render(0.0 if smoothing_enabled else 1.0)
	for kind: int in events:
		menu_event.emit(kind)
	return events


## Draws [param fraction] of the way from the previous tick to the last one.
func render(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	var before: _Frame = _previous if _previous != null else _current
	var source := Vector3i(before.source.lerp(_current.source, weight).round())
	var target := Vector3i(before.target.lerp(_current.target, weight).round())
	water.camera.transform = MenuWaterView.camera_transform(source, target)
	_drawn = _blend(before, _current, weight)
	_drawn_source = source
	_drawn_target = target
	queue_redraw()


## The menu buttons for the next tick from the keys since the last one.
func sample_buttons() -> OptionsMenu.Buttons:
	var held: int = 0
	if _up_held or _up_tapped:
		held |= OptionsMenu.Buttons.UP
	if _down_held or _down_tapped:
		held |= OptionsMenu.Buttons.DOWN
	var pressed: int = 0
	if _left:
		pressed |= OptionsMenu.Buttons.LEFT
	if _right:
		pressed |= OptionsMenu.Buttons.RIGHT
	if _fire:
		pressed |= OptionsMenu.Buttons.FIRE
	if _back:
		pressed |= OptionsMenu.Buttons.BACK
	_up_tapped = false
	_down_tapped = false
	_left = false
	_right = false
	_fire = false
	_back = false
	return OptionsMenu.Buttons.new(held, pressed)


func _process(delta: float) -> void:
	if menu.finished:
		return
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick(sample_buttons())
	if not menu.finished:
		render(elapsed / PERIOD)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	match key.physical_keycode:
		KEY_UP:
			_up_held = key.pressed
			_up_tapped = _up_tapped or key.pressed
		KEY_DOWN:
			_down_held = key.pressed
			_down_tapped = _down_tapped or key.pressed
		KEY_LEFT:
			_left = _left or key.pressed
		KEY_RIGHT:
			_right = _right or key.pressed
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_fire = _fire or key.pressed
		KEY_ESCAPE:
			_back = _back or key.pressed
		_:
			return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _capture() -> _Frame:
	var frame := _Frame.new()
	frame.source = Vector3(camera_rig.source)
	frame.target = Vector3(camera_rig.target)
	var drop: float = 0.0
	if menu.fly_on != 0:
		drop = minf(0.0, OptionsMenu.FLY_ON_HEIGHT + (OptionsMenu.FLY_ON_TIME - menu.fly_on) * OptionsMenu.FLY_ON_SPEED)
	var slide: float = 0.0
	if menu.fly_off != 0:
		slide = (OptionsMenu.FLY_OFF_TIME - menu.fly_off) * OptionsMenu.FLY_OFF_SPEED
	var rows: PackedInt32Array = menu.rows()
	for index: int in rows.size():
		var z: float = OptionsMenu.lily_z(index)
		frame.lilies.append(Vector3(OptionsMenu.LILY_X - slide, drop, z))
		var kind: int = rows[index]
		if TITLE_IMAGES.has(kind):
			var image: Texture2D = _assets.texture(TITLE_IMAGES[kind])
			var width: int = image.get_width() if image != null else 0
			var centre: float = TITLE_LEFT + (width >> 1) * TITLE_UNITS_PER_PIXEL
			frame.titles.append(Vector3(centre - slide if centre < 0.0 else centre + slide, drop, z))
		else:
			frame.titles.append(Vector3.INF)
		if kind == OptionsMenu.Row.MUSIC or kind == OptionsMenu.Row.EFFECTS:
			frame.logs.append(Vector3(OptionsMenu.LOG_X + slide, drop, z))
		else:
			frame.logs.append(Vector3.INF)
	var progress: float = 1.0
	if menu.jumping:
		progress = float(OptionsMenu.FROG_JUMP_TIME - menu.jump_count) / OptionsMenu.FROG_JUMP_TIME
	var from_z: float = OptionsMenu.lily_z(_from_row)
	var to_z: float = OptionsMenu.lily_z(menu.row)
	frame.frog = Vector3(OptionsMenu.LILY_X - slide, drop + menu.lift, lerpf(from_z, to_z, progress))
	if menu.fly_on != 0:
		frame.prompt_drop = menu.fly_on * OptionsMenu.PROMPT_STEP
	elif menu.fly_off != 0:
		frame.prompt_drop = (OptionsMenu.FLY_OFF_TIME - menu.fly_off) * OptionsMenu.PROMPT_STEP
	return frame


static func _blend(before: _Frame, after: _Frame, weight: float) -> _Frame:
	var frame := _Frame.new()
	for index: int in after.lilies.size():
		frame.lilies.append(_mix(before.lilies, after.lilies, index, weight))
		frame.titles.append(_mix(before.titles, after.titles, index, weight))
		frame.logs.append(_mix(before.logs, after.logs, index, weight))
	frame.frog = before.frog.lerp(after.frog, weight)
	frame.prompt_drop = lerpf(before.prompt_drop, after.prompt_drop, weight)
	return frame


static func _mix(before: Array[Vector3], after: Array[Vector3], index: int, weight: float) -> Vector3:
	var end: Vector3 = after[index]
	if index >= before.size() or not end.is_finite() or not before[index].is_finite():
		return end
	return before[index].lerp(end, weight)


func _draw() -> void:
	if _drawn == null:
		return
	var rows: PackedInt32Array = menu.rows()
	for index: int in _drawn.lilies.size():
		_draw_disc(_drawn.lilies[index], LILY_RADIUS * LILY_SCALE / 4096.0, LILY_COLOUR, LILY_EDGE)
	for index: int in _drawn.logs.size():
		if _drawn.logs[index].is_finite():
			_draw_log(_drawn.logs[index], rows[index])
	var titled: int = 0
	for index: int in _drawn.titles.size():
		if _drawn.titles[index].is_finite():
			_draw_title(_drawn.titles[index], rows[index], TITLE_SCALES[mini(titled, TITLE_SCALES.size() - 1)])
			titled += 1
	_draw_frog(_drawn.frog)
	var prompt: Texture2D = _assets.texture(PROMPT_IMAGE)
	if prompt != null:
		var at := Vector2(CENTRE.x - prompt.get_width() * 0.5,
			CENTRE.y * 2.0 - PROMPT_MARGIN - prompt.get_height() + _drawn.prompt_drop)
		draw_texture(prompt, at)


func _point(at: Vector3) -> Vector3:
	return project(_drawn_source, _drawn_target, at)


func _draw_disc(centre: Vector3, radius: float, fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 20:
		var angle: float = TAU * step / 20.0
		var at: Vector3 = _point(centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		if at.z <= NEAR_DEPTH:
			return
		points.append(Vector2(at.x, at.y))
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 2.0, true)


func _draw_quad(corners: Array[Vector3], fill: Color) -> void:
	var points := PackedVector2Array()
	for corner: Vector3 in corners:
		var at: Vector3 = _point(corner)
		if at.z <= NEAR_DEPTH:
			return
		points.append(Vector2(at.x, at.y))
	draw_colored_polygon(points, fill)


func _draw_log(centre: Vector3, kind: int) -> void:
	var half: float = LOG_HALF_LENGTH * LOG_SCALE / 4096.0
	var depth: float = LOG_HALF_DEPTH * LOG_SCALE / 4096.0
	_draw_quad(_rect(centre, -half, half, depth), LOG_COLOUR)
	var glow: float = clampf((menu.glow(kind) - OptionsMenu.GLOW_IDLE) / 224.0, 0.0, 1.0)
	var cels: PackedInt32Array = OptionsMenu.log_cels(menu.volume(kind))
	var width: float = 2.0 * half / OptionsMenu.SOUND_STAGES
	for stage: int in cels.size():
		var left: float = -half + stage * width + width * 0.12
		var right: float = left + width * 0.76
		_draw_quad(_rect(centre, left, right, depth * 0.7), CEL_BLANK.lerp(Color.WHITE, glow * 0.3))
		if cels[stage] == OptionsMenu.LOG_CEL_BLANK:
			continue
		if cels[stage] == OptionsMenu.LOG_CEL_HALF:
			right = left + (right - left) * 0.5
		_draw_quad(_rect(centre, left, right, depth * 0.7), CEL_FULL.lerp(Color.WHITE, glow * 0.5))
	var label: Vector3 = _point(centre + Vector3(half + 48.0, 0.0, 0.0))
	if label.z > NEAR_DEPTH:
		var text: String = "MUSIC" if kind == OptionsMenu.Row.MUSIC else "EFFECTS"
		draw_string(ThemeDB.fallback_font, Vector2(label.x, label.y + 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LABEL_COLOUR)


static func _rect(centre: Vector3, left: float, right: float, half_depth: float) -> Array[Vector3]:
	return [centre + Vector3(left, 0.0, -half_depth), centre + Vector3(right, 0.0, -half_depth),
		centre + Vector3(right, 0.0, half_depth), centre + Vector3(left, 0.0, half_depth)]


func _draw_title(centre: Vector3, kind: int, title_scale: int) -> void:
	var image: Texture2D = _assets.texture(TITLE_IMAGES[kind])
	if image == null:
		return
	var half_width: float = image.get_width() * TITLE_UNITS_PER_PIXEL * 0.5 * title_scale / 4096.0
	var half_height: float = image.get_height() * TITLE_UNITS_PER_PIXEL * 0.5 * title_scale / 4096.0
	var corners: Array[Vector3] = _rect(centre, -half_width, half_width, half_height)
	var points := PackedVector2Array()
	for corner: Vector3 in corners:
		var at: Vector3 = _point(corner)
		if at.z <= NEAR_DEPTH:
			return
		points.append(Vector2(at.x, at.y))
	var uvs := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)])
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, image)


func _draw_frog(centre: Vector3) -> void:
	var radius: float = FROG_RADIUS * FROG_SCALE / 4096.0
	_draw_disc(centre, radius, FROG_COLOUR, FROG_EDGE)
	for side: float in [-0.45, 0.45]:
		var eye: Vector3 = _point(centre + Vector3(side * radius, 0.0, radius * 0.55))
		var rim: Vector3 = _point(centre + Vector3(side * radius + radius * 0.22, 0.0, radius * 0.55))
		if eye.z <= NEAR_DEPTH:
			continue
		var eye_size: float = maxf(1.5, absf(rim.x - eye.x))
		draw_circle(Vector2(eye.x, eye.y), eye_size, Color.WHITE)
		draw_circle(Vector2(eye.x, eye.y), eye_size * 0.5, Color.BLACK)
