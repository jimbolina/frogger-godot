class_name LevelStackView
extends Control
## The arcade level-select stack: the boxes, camera, spinning box, gold frogs and sprites drawn
## from a [StackSelector] stepped at 30 Hz.
##
## Player 1's bound UP and DOWN keys ([BindingInput]) are held directions; Enter or Space is go
## and Escape is back, each counted once per press. Each tick's events are raised through [signal stack_event]. Between
## ticks the camera, box slides, spinning box and sprites are interpolated from the last two
## committed states, which drawing never changes. The camera uses the source's fixed
## orientation and perspective 1000 on the 640x480 display, with the projection's unequal
## vertical focal length applied as a clip-space scale. With a [MenuWater] the stack's world
## also draws the front-end water through the stack camera, behind every box (SelectLevelUpdate
## calls HSUpdateWater).
##
## [method create_for_scores] draws the high-score view's stack instead: a [StackSelector] the
## [HighScoreTour] steps, followed with [method follow] after each tour tick, with no input or
## clock of its own. It shows the tour's prompt and title, the three score lines of the level
## being shown and, behind the stack, SelectLevelCreateBG's checker of two theme tiles tinted
## 0x202020, scrolled by the tour's background counter in a direction chosen at random.

## A selector event of [enum StackSelector.EventKind] [param kind]; [param level] is the level
## to play for ENTER_GAME, otherwise -1.
signal stack_event(kind: int, level: int)

## Seconds per selector tick.
const PERIOD: float = GameplayHost.PERIOD
## The display the source draws on.
const DISPLAY_SIZE: Vector2i = Vector2i(StackLayout.DISPLAY_WIDTH, StackLayout.DISPLAY_HEIGHT)
## Display width MRChangeViewport divides by for the X aspect on Windows.
const ASPECT_WIDTH: int = 320
## The level focused on the first entry.
const FIRST_LEVEL: String = "ORG1"
## Near clip distance in Godot units.
const CAMERA_NEAR: float = 0.05
## SelectLevelCreateBG's tile grid (SELECT_BG_ONSCREEN_TILES_X and _Y plus one), tile size and tint.
const BACKGROUND_TILES: Vector2i = Vector2i(9, 7)
const BACKGROUND_TILE_SIZE: Vector2i = Vector2i(96, 96)
const BACKGROUND_TINT: int = 0x20
## SELECT_BG_TILE_MOVE_SPEED.
const BACKGROUND_PERIOD: int = 24
## The checker's four texture pairs, two names each; SelectLevelCreateBG picks one with rand() & 3.
const BACKGROUND_PAIRS: PackedStringArray = ["jun_col", "des_col", "cav_col", "vol_col", "sky_col", "org_col", "for_col", "sub_col"]
## Far clip distance in Godot units.
const CAMERA_FAR: float = 256.0

## The selector being drawn.
var selector: StackSelector
## The layout of the stack.
var layout: StackLayout
## The fixed-orientation stack camera.
var camera: Camera3D
## One box per arcade row, in stack order.
var boxes: Array[MeshInstance3D] = []
## The spinning box, shown while [method StackSelector.spin_visible].
var spin_box: MeshInstance3D
## Gold-frog quads per Level_table slot; null where the slot has no block.
var gold_frogs: Array[MeshInstance3D] = []
## The 2D sprites.
var panel: StackPanel
## The water behind the stack, or null.
var water: MenuWaterView
## Player 1's key bindings, read for the UP and DOWN keys.
var input: BindingInput = BindingInput.new()
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## True for the high-score view's stack (see [method create_for_scores]).
var score_mode: bool = false
## The checker behind the high-score view's stack, or null.
var checker: Control
## The checker's texture pair index and its BG_LEFT and BG_UP directions.
var background_pair: int = 0
var background_left: bool = true
var background_up: bool = true
## Time since the last tick.
var elapsed: float = 0.0

var _assets: FrontEndAssets
var _stack: LevelStack
var _progress: LevelProgress
var _background: Color = Color.BLACK
var _water: MenuWater
var _world: Node3D
var _box_materials: Array[ShaderMaterial] = []
var _spin_materials: Array[ShaderMaterial] = []
var _spin_row: int = -1
var _previous: _Frame
var _current: _Frame
var _up_held: bool = false
var _down_held: bool = false
var _up_tapped: bool = false
var _down_tapped: bool = false
var _go_pressed: bool = false
var _back_pressed: bool = false
var _board: HighScoreBoard
var _prompt: String = ""
var _title_visible: bool = true
var _shown_level: int = -1
var _background_counter: int = 0


class _Frame:
	extends RefCounted
	var camera_y: float = 0.0
	var current_z := PackedInt32Array()
	var spin_row: int = -1
	var spin_transform: Transform3D = Transform3D.IDENTITY
	var placement: StackPanel.Placement
	var background_counter: int = 0


## A view of [param stack]'s arcade rows under [param progress], focused on [param focus_level]
## (ORG1 when negative); [param first_time] is Sel_first_time. [param background] fills the
## screen behind the stack and [param water_animation], when given, draws the water over it.
static func create(assets: FrontEndAssets, stack: LevelStack, progress: LevelProgress, focus_level: int,
		first_time: bool, background: Color = Color.BLACK, water_animation: MenuWater = null) -> LevelStackView:
	var view := LevelStackView.new()
	view._assets = assets
	view._stack = stack
	view._progress = progress
	view._background = background
	view._water = water_animation
	view.layout = StackLayout.create(stack)
	var focus: int = focus_level if focus_level >= 0 else FroggerIds.level_from_code(FIRST_LEVEL)
	view.selector = StackSelector.create(view.layout, progress, focus, first_time, name_widths(assets, stack))
	view._build()
	return view


## The high-score view's stack over [param stack]'s arcade rows under [param progress], drawing
## [param scores_selector] (the tour's) and [param board]'s level rows; the checker pair and
## direction are chosen with [param random].
static func create_for_scores(assets: FrontEndAssets, stack: LevelStack, progress: LevelProgress,
		scores_selector: StackSelector, board: HighScoreBoard, random: RandomNumberGenerator = null) -> LevelStackView:
	var view := LevelStackView.new()
	view._assets = assets
	view._stack = stack
	view._progress = progress
	view._board = board
	view.score_mode = true
	view.layout = StackLayout.create(stack)
	view.selector = scores_selector
	var chance: RandomNumberGenerator = random
	if chance == null:
		chance = RandomNumberGenerator.new()
		chance.randomize()
	view.background_pair = chance.randi() & 3
	view.background_left = chance.randi() & 1 == 0
	view.background_up = chance.randi() & 1 != 0
	view._build()
	return view


## Each arcade row's level-name image width in [param stack], zero where missing.
static func name_widths(assets: FrontEndAssets, stack: LevelStack) -> PackedInt32Array:
	var widths := PackedInt32Array()
	for row: int in stack.arcade_count():
		var name_image: Texture2D = assets.level_texture(stack.arcade_row(row).level, FrontEndAssets.LevelImage.STACK_NAME)
		widths.append(name_image.get_width() if name_image != null else 0)
	return widths


## The checker's scroll along one axis at [param counter] (Select_bg_counter) for tiles
## [param length] long: toward the left or up, or else the other way (SelectLevelUpdateBG).
static func background_offset(counter: int, length: int, left_or_up: bool) -> int:
	var moved: int = (counter * length) / BACKGROUND_PERIOD
	return moved if left_or_up else length - moved


## Vertical field of view of a symmetric camera whose X focal length is the source's
## perspective times the display width over 320, on a display of [param size].
static func vertical_fov_degrees(size: Vector2i = DISPLAY_SIZE) -> float:
	var focal_x: float = float(StackLayout.PERSPECTIVE) * size.x / ASPECT_WIDTH
	return rad_to_deg(2.0 * atan(float(size.y) / (2.0 * focal_x)))


## The camera transform with the frame at source Y [param camera_y].
static func camera_transform(camera_y: float) -> Transform3D:
	var values: PackedInt32Array = StackLayout.camera_matrix()
	var at: Vector3i = StackLayout.camera_translation(0)
	values.append_array([at.x, at.y, at.z])
	var result: Transform3D = GameSpace.transform(values)
	result.origin.y = -camera_y / GameSpace.UNITS_PER_SQUARE
	return result


## Where a stack box sits when slid by [param current_z] source units.
static func box_position(current_z: float) -> Vector3:
	var origin: Vector3i = StackLayout.STACK_ORIGIN
	return Vector3(origin.x, -origin.y, -(origin.z + current_z)) / GameSpace.UNITS_PER_SQUARE


## The spinning box frame at [param position] with 4.12 axes [param axes] (X, Y, Z columns).
static func spin_transform(position: Vector3i, axes: Array[Vector3i]) -> Transform3D:
	var x: Vector3i = axes[0]
	var y: Vector3i = axes[1]
	var z: Vector3i = axes[2]
	return GameSpace.transform(PackedInt32Array([x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z,
		position.x, position.y, position.z]))


## Advances the selector one tick with [param buttons], raises its events and draws the result.
func tick(buttons: StackSelector.Buttons) -> Array[StackSelector.Event]:
	var events: Array[StackSelector.Event] = selector.step(buttons)
	_previous = _current
	_current = _capture()
	_apply_tints()
	render(0.0 if smoothing_enabled else 1.0)
	for event: StackSelector.Event in events:
		stack_event.emit(event.kind, event.level)
	return events


## Takes the tour's last tick in the high-score view: its prompt image [param prompt], whether
## the title shows ([param title_visible]), the level whose rows show ([param shown_level], -1
## for none) and the checker's [param background_counter].
func follow(prompt: String, title_visible: bool, shown_level: int, background_counter: int) -> void:
	_prompt = prompt
	_title_visible = title_visible
	_shown_level = shown_level
	_background_counter = background_counter
	_previous = _current
	_current = _capture()
	_apply_tints()
	render(0.0 if smoothing_enabled else 1.0)


## Draws [param fraction] of the way from the previous tick to the last one.
func render(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	var before: _Frame = _previous if _previous != null else _current
	camera.transform = camera_transform(lerpf(before.camera_y, _current.camera_y, weight))
	for row: int in boxes.size():
		boxes[row].position = box_position(lerpf(before.current_z[row], _current.current_z[row], weight))
		boxes[row].visible = row != _current.spin_row
	spin_box.visible = _current.spin_row >= 0
	if spin_box.visible:
		if before.spin_row == _current.spin_row and weight < 1.0:
			spin_box.transform = before.spin_transform.interpolate_with(_current.spin_transform, weight)
		else:
			spin_box.transform = _current.spin_transform
	panel.apply(before.placement.toward(_current.placement, weight) if before != _current else _current.placement)
	if checker != null:
		checker.queue_redraw()


## The selector buttons for the next tick from the keys since the last one.
func sample_buttons() -> StackSelector.Buttons:
	var buttons := StackSelector.Buttons.new(_up_held or _up_tapped, _down_held or _down_tapped, _go_pressed, _back_pressed)
	_up_tapped = false
	_down_tapped = false
	_go_pressed = false
	_back_pressed = false
	return buttons


func _ready() -> void:
	camera.make_current()


func _process(delta: float) -> void:
	if selector.finished or score_mode:
		return
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick(sample_buttons())
	if not selector.finished:
		render(elapsed / PERIOD)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo or score_mode:
		return
	match input.action(key):
		KeyBindings.Action.UP:
			_up_held = key.pressed
			_up_tapped = _up_tapped or key.pressed
			_handled()
			return
		KeyBindings.Action.DOWN:
			_down_held = key.pressed
			_down_tapped = _down_tapped or key.pressed
			_handled()
			return
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_go_pressed = _go_pressed or key.pressed
		KEY_ESCAPE:
			_back_pressed = _back_pressed or key.pressed
		_:
			return
	_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "Stack"
	add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = _background
	_world.add_child(environment)
	if score_mode:
		environment.environment.background_mode = Environment.BG_CANVAS
		environment.environment.background_canvas_max_layer = -1
		var layer := CanvasLayer.new()
		layer.name = "Checker"
		layer.layer = -1
		add_child(layer)
		checker = Control.new()
		checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		checker.size = Vector2(DISPLAY_SIZE)
		checker.draw.connect(_draw_background)
		layer.add_child(checker)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = vertical_fov_degrees()
	camera.near = CAMERA_NEAR
	camera.far = CAMERA_FAR
	_world.add_child(camera)
	var scale: Vector2 = GameplayProjection.clip_scale(DISPLAY_SIZE)
	if _water != null:
		water = MenuWaterView.create(_water, _assets.texture("opt_env_sky"), _assets.texture("opt_bank3"), scale)
		_world.add_child(water)
	for row: int in layout.row_count():
		var stack_row: LevelStack.Row = _stack.arcade_row(row)
		var image: Texture2D = _world_image(row)
		var box := MeshInstance3D.new()
		box.name = "Row%d" % row
		box.mesh = StackMeshBuilder.row_mesh(layout, row, image.get_height() if image != null else 0,
			stack_row.local_level, stack_row.levels_in_world)
		var material: ShaderMaterial = StackMeshBuilder.box_material(image, selector.tint(row), scale)
		box.set_surface_override_material(0, material)
		box.set_surface_override_material(1, material)
		_box_materials.append(material)
		_world.add_child(box)
		boxes.append(box)
	spin_box = MeshInstance3D.new()
	spin_box.name = "Spin"
	spin_box.visible = false
	_world.add_child(spin_box)
	var gold: Texture2D = _assets.texture("ls_gold_frog")
	for slot: int in StackLayout.GOLD_FROG_SLOTS:
		var corners: Array[Vector3i] = layout.gold_frog_quad(StackLayout.gold_frog_block(slot))
		if corners.is_empty():
			gold_frogs.append(null)
			continue
		var quad := MeshInstance3D.new()
		quad.name = "GoldFrog%d" % slot
		quad.mesh = StackMeshBuilder.quad_mesh(corners)
		quad.set_surface_override_material(0, StackMeshBuilder.quad_material(gold, scale))
		quad.visible = _progress.gold_frogs & (1 << (slot + 1)) != 0
		_world.add_child(quad)
		gold_frogs.append(quad)
	panel = StackPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.setup(_assets)
	_current = _capture()
	render(1.0)


func _world_image(row: int) -> Texture2D:
	var kind: FrontEndAssets.LevelImage = FrontEndAssets.LevelImage.WORLD_NOT_TRIED
	if row < _progress.arcade_flags.size() and StackLayout.shows_unlocked_image(_progress.arcade_flags[row]):
		kind = FrontEndAssets.LevelImage.WORLD_UNLOCKED
	return _assets.level_texture(_stack.arcade_row(row).level, kind)


func _capture() -> _Frame:
	var frame := _Frame.new()
	frame.camera_y = selector.camera_y
	for row: int in selector.row_count():
		frame.current_z.append(selector.current_z(row))
	frame.spin_row = selector.spin_row
	if frame.spin_row >= 0:
		if frame.spin_row != _spin_row:
			_build_spin(frame.spin_row)
		frame.spin_transform = spin_transform(selector.spin_position, selector.spin_axes())
	else:
		_spin_row = -1
	frame.placement = StackPanel.placement(selector)
	if score_mode:
		frame.placement.prompt = _prompt
		frame.placement.title_visible = _title_visible
		if _shown_level >= 0 and _board != null:
			frame.placement.score_lines = HighScoreText.lines(_board.level_rows(_shown_level))
		frame.background_counter = _background_counter
	return frame


func _draw_background() -> void:
	var tiles: Array[Texture2D] = [_assets.texture(BACKGROUND_PAIRS[background_pair * 2]), _assets.texture(BACKGROUND_PAIRS[background_pair * 2 + 1])]
	var counter: int = _current.background_counter if _current != null else 0
	var offset := Vector2(background_offset(counter, BACKGROUND_TILE_SIZE.x, background_left),
		background_offset(counter, BACKGROUND_TILE_SIZE.y, background_up))
	var tint: float = float(BACKGROUND_TINT) / StackPanel.NEUTRAL_COLOUR
	for row: int in BACKGROUND_TILES.y:
		for column: int in BACKGROUND_TILES.x:
			var at := Vector2(column * BACKGROUND_TILE_SIZE.x, row * BACKGROUND_TILE_SIZE.y) - offset
			var texture: Texture2D = tiles[(column + row) & 1]
			if texture == null:
				checker.draw_rect(Rect2(at, Vector2(BACKGROUND_TILE_SIZE)), Color(tint, tint, tint))
			else:
				checker.draw_texture_rect(texture, Rect2(at, Vector2(BACKGROUND_TILE_SIZE)), false, Color(tint, tint, tint))


func _build_spin(row: int) -> void:
	_spin_row = row
	var stack_row: LevelStack.Row = _stack.arcade_row(row)
	var image: Texture2D = _world_image(row)
	spin_box.mesh = StackMeshBuilder.spin_mesh(layout, row, image.get_height() if image != null else 0,
		stack_row.local_level, stack_row.levels_in_world)
	var scale: Vector2 = GameplayProjection.clip_scale(DISPLAY_SIZE)
	var screenshot: Texture2D = _assets.level_texture(stack_row.level, FrontEndAssets.LevelImage.SCREENSHOT)
	_spin_materials = [StackMeshBuilder.box_material(image, selector.tint(row), scale),
		StackMeshBuilder.box_material(screenshot, StackSelector.SPIN_IMAGE_COLOUR, scale)]
	spin_box.set_surface_override_material(0, _spin_materials[0])
	spin_box.set_surface_override_material(1, _spin_materials[1])
	panel.set_level_name(_assets.level_texture(stack_row.level, FrontEndAssets.LevelImage.STACK_NAME))


func _apply_tints() -> void:
	for row: int in _box_materials.size():
		var tint: int = selector.tint(row)
		if StackMeshBuilder.material_tint(_box_materials[row]) != tint:
			StackMeshBuilder.set_tint(_box_materials[row], tint)
