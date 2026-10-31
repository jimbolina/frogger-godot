class_name OptionsView
extends Control
## The options page: the front-end water seen through the sweeping options camera, with the
## OPTIONS.WAD lilies, volume logs, spinning volume models and static extras, the frog, the title
## 3D sprites and their reflections, the landing splash, the frog's shadow and the prompt, placed
## by an [OptionsScene] stepped with an [OptionsMenu] at 30 Hz.
##
## The view drives its water: each tick advances the shared frame count, then the menu and scene
## step with that count, so the models sit on the heights being drawn. Models are drawn from the
## view's own mesh copies ([ModelMeshCopy]) and lit by the options viewport's lights; the volume models take the menu's glow as their custom ambient, and
## each log shows its volume through its 64 animated polygons (cels 10, 11 and 12). The frog plays
## the actions the scene chooses at update period 2, holding the last frame while one-shot, with
## the croak sack shown at its smallest. Title sprites stand 0x40 above their lily rows at scale
## 10; their reflections lie flat 0x48 behind at colour 0x40 and are subtracted when the image is
## translucent. Sprites are lit on the source's sprite normal, flipped when the sprite faces away,
## and drawn in layers after the water in the source's ordering-table order: reflections, titles,
## the frog shadow, splashes.
## Without [OptionsModels] (tests without player data) no model or effect sprite is drawn.
## Under the modern rendering profile the models draw through the lit shaders under the options
## lights without shadows, applied through [method MenuWaterView.light_scene] on the page's water;
## the volume models' glow still reaches them as their custom ambient, and the water and the
## CPU-lit sprites stay unlit.
##
## The menu keys are fixed: Up/Down held, Left/Right, Enter or Space (fire) and Escape (back)
## pressed. Each tick's events are raised through [signal menu_event]; the page asks to leave
## with [constant OptionsMenu.EventKind].LEAVE and its [member OptionsMenu.request]. Between ticks
## the camera, water and models are interpolated from the last two ticks, which drawing never
## changes.

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
## Menu image of each titled [enum OptionsMenu.Row].
const TITLE_IMAGES: Dictionary[int, String] = {
	OptionsMenu.Row.EXIT: "opt_exit",
	OptionsMenu.Row.VIEW_SCORES: "opt_view_hs",
	OptionsMenu.Row.CONTROLS: "opt_ctrl_config",
}
## The prompt image under the rows.
const PROMPT_IMAGE: String = "select7"
## Base colour of a 3D sprite (MRCreate3DSprite).
const SPRITE_COLOUR: int = 0x80
## Sprite layers, drawn after the water in the source's ordering-table order.
enum Layer { REFLECTIONS, TITLES, SHADOW, SPLASHES }
## Sorting offset between sprite layers, in Godot units.
const LAYER_SORTING_STEP: float = 1000.0

## The menu being drawn.
var menu: OptionsMenu
## The model placement stepped with the menu.
var scene: OptionsScene
## The shared options camera.
var camera_rig: OptionsCamera
## The water and its camera.
var water: MenuWaterView
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## Time since the last tick.
var elapsed: float = 0.0

var _assets: FrontEndAssets
var _models: OptionsModels
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
var _drawn_source: Vector3i = Vector3i.ZERO
var _drawn_target: Vector3i = Vector3i.ZERO
var _drawn_prompt: float = 0.0
var _lilies: Array[AnimatedModelInstance] = []
var _logs: Array[AnimatedModelInstance] = []
var _volume_models: Array[AnimatedModelInstance] = []
var _extras: Array[AnimatedModelInstance] = []
var _frog: AnimatedModelInstance
var _log_volumes: PackedInt32Array = PackedInt32Array()
var _layers: Array[MeshInstance3D] = []
var _title_materials: Array[ShaderMaterial] = []
var _reflection_materials: Array[ShaderMaterial] = []
var _title_images: Array[VloImage] = []
var _image_materials: Dictionary[String, ShaderMaterial] = {}
var _splashes: Array[_Splash] = []
var _drawn: Dictionary[ModelMesh, ModelMesh] = {}


class _Frame:
	extends RefCounted
	var source: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	var lilies: Array[PackedInt32Array] = []
	var titles: Array[PackedInt32Array] = []
	var logs: Array[PackedInt32Array] = []
	var volume_models: Array[PackedInt32Array] = []
	var extras: Array[PackedInt32Array] = []
	var frog: PackedInt32Array = PackedInt32Array()
	var shadow: Array[Vector3i] = []
	var prompt: int = 0


class _Splash:
	extends RefCounted
	var lily: int = 0
	var timeline: SplashTimeline


## A page over [param water_animation] seen through [param rig], with volume steps [param music]
## and [param effects], the frog on [param start_row], the hidden high-score row unless
## [param show_scores], and the models of [param models].
static func create(assets: FrontEndAssets, water_animation: MenuWater, rig: OptionsCamera, music: int, effects: int,
		start_row: int = OptionsMenu.Row.EXIT, show_scores: bool = false, models: OptionsModels = null) -> OptionsView:
	var view := OptionsView.new()
	view._assets = assets
	view._models = models
	view.camera_rig = rig
	view.menu = OptionsMenu.create(music, effects, start_row, show_scores)
	var widths: Dictionary[int, int] = {}
	for kind: int in TITLE_IMAGES:
		var record: VloImage = assets.image_record(TITLE_IMAGES[kind])
		widths[kind] = record.width if record != null else 0
	view.scene = OptionsScene.create(view.menu, widths)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.water = MenuWaterView.create_with_camera(water_animation, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	view.add_child(view.water)
	if assets.texture_library.rendering_profile().is_modern():
		view.water.light_scene(MenuWaterView.options_spec())
	view._build_sprites()
	if models != null and models.error.is_empty():
		view._build_models()
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


## Advances the water, menu and scene one tick with [param buttons], moves the camera, raises the
## events and returns them.
func tick(buttons: OptionsMenu.Buttons) -> PackedInt32Array:
	if menu.finished:
		return PackedInt32Array()
	water.tick()
	var frame: int = water.water.frame_count
	var events: PackedInt32Array = menu.step(buttons, frame)
	scene.step(menu, buttons, events, frame)
	camera_rig.move(menu.camera, menu.camera_timer)
	_step_models()
	_step_splashes()
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
	_drawn_source = Vector3i(before.source.lerp(_current.source, weight).round())
	_drawn_target = Vector3i(before.target.lerp(_current.target, weight).round())
	water.camera.transform = MenuWaterView.camera_transform(_drawn_source, _drawn_target)
	water.render(weight)
	_place(_lilies, before.lilies, _current.lilies, weight)
	_place(_logs, before.logs, _current.logs, weight)
	_place(_volume_models, before.volume_models, _current.volume_models, weight)
	_place(_extras, before.extras, _current.extras, weight)
	if _frog != null:
		_frog.transform = _blend_transform(before.frog, _current.frog, weight)
		_frog.render(weight)
	_draw_sprites(before, weight)
	_drawn_prompt = lerpf(before.prompt, _current.prompt, weight)
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


## The model instances drawn for the lilies, logs, volume models, extras and frog, in that order;
## empty without [OptionsModels].
func model_instances() -> Array[AnimatedModelInstance]:
	var result: Array[AnimatedModelInstance] = []
	result.append_array(_lilies)
	result.append_array(_logs)
	result.append_array(_volume_models)
	result.append_array(_extras)
	if _frog != null:
		result.append(_frog)
	return result


## The landing splashes still showing, as their lily indices.
func splash_lilies() -> PackedInt32Array:
	var result := PackedInt32Array()
	for splash: _Splash in _splashes:
		result.append(splash.lily)
	return result


func _ready() -> void:
	water.set_process(false)


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


func _build_models() -> void:
	var projection: Vector2 = GameplayProjection.clip_scale(MenuWaterView.DISPLAY_SIZE)
	var root := Node3D.new()
	root.name = "OptionsModels"
	water.add_child(root)
	for _index: int in scene.lilies.size():
		_lilies.append(_instance(root, OptionsModels.Kind.LILY))
	for index: int in scene.log_rows.size():
		var log_model: AnimatedModelInstance = _instance(root, OptionsModels.Kind.LOG)
		log_model.player.texture_animation_paused = true
		_logs.append(log_model)
		_log_volumes.append(-1)
		var kind: int = OptionsModels.Kind.MUSIC if scene.rows[scene.log_rows[index]] == OptionsMenu.Row.MUSIC else OptionsModels.Kind.EFFECTS
		_volume_models.append(_instance(root, kind))
	for extra: int in OptionsScene.EXTRA_KINDS:
		_extras.append(_instance(root, OptionsModels.Kind.BULLRUSH if extra == OptionsScene.Extra.BULLRUSH else OptionsModels.Kind.STATIC_LILY))
	var player := ModelAnimationPlayer.new(_models.frog.model)
	player.update_period = OptionsScene.FROG_UPDATE_PERIOD
	player.end_mode = ModelAnimationPlayer.EndMode.HOLD
	player.set_action(scene.frog_action)
	player.restart()
	_frog = AnimatedModelInstance.new()
	_frog.name = "Frog"
	root.add_child(_frog)
	_frog.setup(_drawn_mesh(_models.frog.mesh), player)
	_frog.smoothing_enabled = smoothing_enabled
	_frog.set_source_lighting(_models.lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	for index: int in _frog.part_nodes.size():
		_frog.part_nodes[index].visible = not _models.frog.hidden_parts.has(index)
	if GameplayWorldView.THROAT_PART < _frog.part_nodes.size():
		_frog.part_nodes[GameplayWorldView.THROAT_PART].visible = true
		_frog.set_part_scale(GameplayWorldView.THROAT_PART, FrogCroak.MIN_SCALE / 4096.0)
	for symbol: String in _models.images:
		var record: VloImage = _models.images[symbol]
		var blend: ModelShaders.Blend = EffectSpriteMaterial.image_blend(record)
		var bias: float = EffectSpriteMaterial.slots_bias(OptionsScene.SPLASH_OT_OFFSET)
		var priority: int = Layer.SPLASHES
		if FrogShadowGeometry.PHASE_TEXTURES.has(symbol):
			blend = EffectSpriteMaterial.semi_transparent_blend(record)
			bias = EffectSpriteMaterial.slots_bias(FrogShadowGeometry.OT_OFFSET)
			priority = Layer.SHADOW
		_image_materials[symbol] = EffectSpriteMaterial.textured(_models.library, record, blend, bias, projection)
		_image_materials[symbol].render_priority = priority + 1
	_step_models()


func _instance(root: Node3D, kind: int) -> AnimatedModelInstance:
	var instance := AnimatedModelInstance.new()
	root.add_child(instance)
	instance.setup(_drawn_mesh(_models.model_mesh(kind)), ModelAnimationPlayer.new(_models.model_file(kind)))
	instance.smoothing_enabled = smoothing_enabled
	instance.set_source_lighting(_models.lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	return instance


func _drawn_mesh(shared: ModelMesh) -> ModelMesh:
	if shared == null:
		return null
	if not _drawn.has(shared):
		_drawn[shared] = ModelMeshCopy.of(shared)
		_set_projection(_drawn[shared], GameplayProjection.clip_scale(MenuWaterView.DISPLAY_SIZE))
	return _drawn[shared]


static func _set_projection(mesh: ModelMesh, projection: Vector2) -> void:
	if mesh == null:
		return
	for part: ArrayMesh in mesh.part_meshes:
		if part == null:
			continue
		for surface: int in part.get_surface_count():
			var material: ShaderMaterial = part.surface_get_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("projection_scale", projection)
	for tracks: Array in mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			if track.original != null:
				track.original.set_shader_parameter("projection_scale", projection)
			for material: ShaderMaterial in track.frames:
				material.set_shader_parameter("projection_scale", projection)


func _build_sprites() -> void:
	for layer: int in Layer.values():
		var instance := MeshInstance3D.new()
		instance.name = "Sprites" + str(Layer.keys()[layer]).capitalize()
		instance.mesh = ImmediateMesh.new()
		instance.sorting_offset = (layer + 1) * LAYER_SORTING_STEP
		water.add_child(instance)
		_layers.append(instance)
	var projection: Vector2 = GameplayProjection.clip_scale(MenuWaterView.DISPLAY_SIZE)
	for row: int in scene.title_rows:
		var kind: int = scene.rows[row]
		var record: VloImage = _assets.image_record(TITLE_IMAGES[kind]) if TITLE_IMAGES.has(kind) else null
		_title_images.append(record)
		if record == null:
			_title_materials.append(null)
			_reflection_materials.append(null)
			continue
		var title: ShaderMaterial = EffectSpriteMaterial.textured(_assets.texture_library, record, EffectSpriteMaterial.image_blend(record), 0.0, projection)
		title.render_priority = Layer.TITLES + 1
		_title_materials.append(title)
		var blend: ModelShaders.Blend = ModelShaders.Blend.SUBTRACT if record.has_flag(VloImage.FLAG_TRANSLUCENT) else ModelShaders.Blend.OPAQUE
		var reflection: ShaderMaterial = EffectSpriteMaterial.textured(_assets.texture_library, record, blend,
			EffectSpriteMaterial.slots_bias(OptionsScene.REFLECTION_OT_OFFSET), projection)
		reflection.render_priority = Layer.REFLECTIONS + 1
		_reflection_materials.append(reflection)


func _step_models() -> void:
	if _frog == null:
		return
	for instance: AnimatedModelInstance in _lilies + _extras:
		instance.advance_tick()
	for index: int in _logs.size():
		var kind: int = scene.rows[scene.log_rows[index]]
		var volume: int = menu.volume(kind)
		if volume != _log_volumes[index]:
			_log_volumes[index] = volume
			var cels: PackedInt32Array = OptionsScene.log_poly_cels(volume)
			for poly: int in cels.size():
				_logs[index].player.set_animated_poly_cel(poly, cels[poly])
		_logs[index].advance_tick()
		var glow: int = menu.glow(kind)
		_volume_models[index].set_source_lighting(_models.lighting, Vector3i.ZERO, Vector3i(glow, glow, glow), false, true)
		_volume_models[index].advance_tick()
	var player: ModelAnimationPlayer = _frog.player
	if scene.frog_action_set:
		player.set_action(scene.frog_action)
	player.end_mode = ModelAnimationPlayer.EndMode.LOOP if scene.frog_looping else ModelAnimationPlayer.EndMode.HOLD
	_frog.advance_tick()


func _step_splashes() -> void:
	for lily: int in scene.splashes:
		var splash := _Splash.new()
		splash.lily = lily
		splash.timeline = SplashTimeline.new(WaterModelSet.splash_commands())
		splash.timeline.scale = OptionsScene.SPRITE_SCALE
		_splashes.append(splash)
	var kept: Array[_Splash] = []
	for splash: _Splash in _splashes:
		splash.timeline.update()
		if not splash.timeline.killed:
			kept.append(splash)
	_splashes = kept


func _capture() -> _Frame:
	var frame := _Frame.new()
	frame.source = Vector3(camera_rig.source)
	frame.target = Vector3(camera_rig.target)
	frame.lilies = _copies(scene.lilies)
	frame.titles = _copies(scene.titles)
	frame.logs = _copies(scene.logs)
	frame.volume_models = _copies(scene.volume_models)
	frame.extras = _copies(scene.extras)
	frame.frog = scene.frog.duplicate()
	frame.prompt = scene.prompt_offset
	if scene.shadow_visible and _models != null:
		frame.shadow = scene.shadow_corners(FrogShadowGeometry.phase_offsets(scene.shadow_phase))
	return frame


static func _copies(matrices: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for matrix: PackedInt32Array in matrices:
		result.append(matrix.duplicate())
	return result


func _place(instances: Array[AnimatedModelInstance], before: Array[PackedInt32Array], after: Array[PackedInt32Array], weight: float) -> void:
	for index: int in instances.size():
		var from: PackedInt32Array = before[index] if index < before.size() else after[index]
		instances[index].transform = _blend_transform(from, after[index], weight)
		instances[index].render(weight)


static func _blend_transform(before: PackedInt32Array, after: PackedInt32Array, weight: float) -> Transform3D:
	var now: Transform3D = GameSpace.transform(after)
	if weight >= 1.0 or before == after:
		return now
	var then: Transform3D = GameSpace.transform(before)
	if then.basis.x.dot(now.basis.x) < 0.0 or then.basis.z.dot(now.basis.z) < 0.0:
		return Transform3D(now.basis, then.origin.lerp(now.origin, weight))
	return then.interpolate_with(now, weight)


static func _blend_matrix(before: PackedInt32Array, after: PackedInt32Array, weight: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(12)
	for index: int in 12:
		result[index] = lerpf(before[index], after[index], weight)
	return result


func _draw_sprites(before: _Frame, weight: float) -> void:
	var layers: Array[Dictionary] = []
	for _layer: int in Layer.size():
		var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
		layers.append(batches)
	for pass_index: int in 2:
		for index: int in _current.titles.size():
			var record: VloImage = _title_images[index] if index < _title_images.size() else null
			if record == null:
				continue
			var from: PackedInt32Array = before.titles[index] if index < before.titles.size() else _current.titles[index]
			var matrix: PackedFloat32Array = _blend_matrix(from, _current.titles[index], weight)
			var half: Vector2i = SplashView.half_extents(record.width, record.height, OptionsScene.SPRITE_SCALE)
			if pass_index == 0:
				var depth: float = OptionsScene.REFLECTION_OFFSET
				var flat: Array[Vector3] = [Vector3(-half.x, 0.0, depth + half.y), Vector3(half.x, 0.0, depth + half.y),
					Vector3(-half.x, 0.0, depth - half.y), Vector3(half.x, 0.0, depth - half.y)]
				_add_sprite(layers[Layer.REFLECTIONS], _reflection_materials[index], matrix, flat, OptionsScene.REFLECTION_COLOUR)
				continue
			var raise: float = OptionsScene.TITLE_RAISE
			var upright: Array[Vector3] = [Vector3(-half.x, raise - half.y, 0.0), Vector3(half.x, raise - half.y, 0.0),
				Vector3(-half.x, raise + half.y, 0.0), Vector3(half.x, raise + half.y, 0.0)]
			_add_sprite(layers[Layer.TITLES], _title_materials[index], matrix, upright, SPRITE_COLOUR)
	_add_shadow(layers[Layer.SHADOW], before, weight)
	for splash: _Splash in _splashes:
		var material: ShaderMaterial = _image_materials.get(splash.timeline.image, null)
		var record: VloImage = _models.images.get(splash.timeline.image, null) if _models != null else null
		if material == null or record == null or not splash.timeline.drawn():
			continue
		var lily: int = splash.lily
		var from: PackedInt32Array = before.lilies[lily] if lily < before.lilies.size() else _current.lilies[lily]
		var matrix: PackedFloat32Array = _blend_matrix(from, _current.lilies[lily], weight)
		var half: Vector2i = SplashView.half_extents(record.width, record.height, splash.timeline.scale)
		var flat: Array[Vector3] = [Vector3(-half.x, 0.0, half.y), Vector3(half.x, 0.0, half.y),
			Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y)]
		_add_sprite(layers[Layer.SPLASHES], material, matrix, flat, splash.timeline.rgb().x)
	for layer: int in _layers.size():
		var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = layers[layer]
		_layers[layer].visible = EffectSpriteMaterial.commit(_layers[layer].mesh as ImmediateMesh, batches)


func _add_shadow(batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch], before: _Frame, weight: float) -> void:
	if _current.shadow.is_empty():
		return
	var symbol: String = FrogShadowGeometry.PHASE_TEXTURES[scene.shadow_phase]
	var material: ShaderMaterial = _image_materials.get(symbol, null)
	if material == null:
		return
	var corners: Array[Vector3] = []
	for index: int in 4:
		var now := Vector3(_current.shadow[index])
		var then: Vector3 = Vector3(before.shadow[index]) if before.shadow.size() == 4 else now
		corners.append(EffectSpriteMaterial.world(then.lerp(now, weight)))
	var grey: Color = EffectSpriteMaterial.colour(Vector3i(FrogShadowGeometry.GREY, FrogShadowGeometry.GREY, FrogShadowGeometry.GREY))
	EffectSpriteMaterial.batch_for(batches, material).quad(corners, [grey, grey, grey, grey])


func _add_sprite(batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch], material: ShaderMaterial,
		matrix: PackedFloat32Array, local: Array[Vector3], base: int) -> void:
	if material == null:
		return
	var corners: Array[Vector3] = []
	var game: Array[Vector3] = []
	for corner: Vector3 in local:
		var at := Vector3(
			(matrix[0] * corner.x + matrix[1] * corner.y + matrix[2] * corner.z) / 4096.0 + matrix[9],
			(matrix[3] * corner.x + matrix[4] * corner.y + matrix[5] * corner.z) / 4096.0 + matrix[10],
			(matrix[6] * corner.x + matrix[7] * corner.y + matrix[8] * corner.z) / 4096.0 + matrix[11])
		game.append(at)
		corners.append(EffectSpriteMaterial.world(at))
	var colour: Color = _sprite_light(base, matrix, game)
	EffectSpriteMaterial.batch_for(batches, material).quad(corners, [colour, colour, colour, colour])


func _sprite_light(base: int, matrix: PackedFloat32Array, corners: Array[Vector3]) -> Color:
	var plain: Color = EffectSpriteMaterial.colour(Vector3i(base, base, base))
	if _models == null:
		return plain
	var screen: Array[Vector3] = []
	for index: int in 3:
		screen.append(project(_drawn_source, _drawn_target, corners[index]))
	var facing: float = (screen[1].x - screen[0].x) * (screen[2].y - screen[0].y) - (screen[2].x - screen[0].x) * (screen[1].y - screen[0].y)
	var sign: float = 1.0 if facing > 0.0 else -1.0
	var normal := Vector3(matrix[2], -matrix[5], -matrix[8]) * sign / 4096.0
	return _models.lighting.shade(plain, normal)


func _draw() -> void:
	var record: VloImage = _assets.image_record(PROMPT_IMAGE)
	var texture: Texture2D = _assets.texture(PROMPT_IMAGE)
	if record == null or texture == null:
		return
	var at := Vector2((MenuWaterView.DISPLAY_SIZE.x >> 1) - (record.width >> 1),
		MenuWaterView.DISPLAY_SIZE.y - record.height + _drawn_prompt)
	draw_texture_rect_region(texture, Rect2(at, Vector2(record.width, record.height)), TextureBuilder.texture_rect(record, texture))
