class_name WaterModelSet
extends Node3D
## Front-end models placed on the menu water from 12-integer source matrices, with the frog's jump
## shadow and the landing ripple splashes, shared by the high-score pages and the main menu's
## scrolly table.
##
## Models come from [OptionsModels] by FrogLord name and are lit by the options viewport's lights;
## each is drawn from this set's own copy of its mesh ([ModelMeshCopy]), so the projection set on
## its materials never reaches the shared imported materials.
## Splashes play High_score_splash_animlist on an anchor matrix at scale 10 in the XZ plane; the
## shadow and splashes draw in layers after the water in the options page's ordering-table order,
## each sprite lit on its normal as the options page lights its sprites. Without usable
## [OptionsModels] nothing is built and drawing does nothing.
##
## The models draw through the lit shaders under the options lights
## ([method MenuWaterView.options_spec], no shadows) of the set's own [member scene_lighting] child.
## On entering the tree inside a [MenuWaterView] with its own camera the set takes over that
## world's environment ([method MenuWaterView.release_environment]); the lights are cleared when it
## leaves the tree and applied again when it returns. The shadow and splash sprites keep their CPU
## light.

## Sprite layers, ordered as the options page's shadow and splash layers.
enum Layer { SHADOW, SPLASHES }
## Sorting offset and render priority of each layer, matching [OptionsView]'s.
const LAYER_SORTING: PackedFloat32Array = [3000.0, 4000.0]
const LAYER_PRIORITY: PackedInt32Array = [3, 4]

## The models, or null.
var models: OptionsModels
## Interpolate between ticks; passed to every model instance.
var smoothing_enabled: bool = true
## The light the models draw under, or null without usable models.
var scene_lighting: SceneLighting

var _layers: Array[MeshInstance3D] = []
var _image_materials: Dictionary[String, ShaderMaterial] = {}
var _splashes: Array[_Splash] = []
var _projection: Vector2 = Vector2.ONE
var _drawn: Dictionary[ModelMesh, ModelMesh] = {}


class _Splash:
	extends RefCounted
	var anchor: int = 0
	var timeline: SplashTimeline


## A set drawing with [param with_models]; usable only when they loaded without error.
static func create(with_models: OptionsModels) -> WaterModelSet:
	var model_set := WaterModelSet.new()
	model_set.setup(with_models)
	return model_set


## The splash animation list (High_score_splash_animlist): ripples 3-5 at speed 3, ripple 6 at
## speed 2 fading through three greys, then killed.
static func splash_commands() -> Array[SplashTimeline.Command]:
	var images: PackedStringArray = OptionsModels.SPLASH_SYMBOLS
	var list: Array[SplashTimeline.Command] = [
		SplashTimeline.Command.new(SplashTimeline.Op.SETSPEED, 3),
		SplashTimeline.Command.new(SplashTimeline.Op.SETIMAGE, 0, images[0]),
		SplashTimeline.Command.new(SplashTimeline.Op.SETIMAGE, 0, images[1]),
		SplashTimeline.Command.new(SplashTimeline.Op.SETIMAGE, 0, images[2]),
		SplashTimeline.Command.new(SplashTimeline.Op.SETSPEED, 2),
		SplashTimeline.Command.new(SplashTimeline.Op.SETIMAGE, 0, images[3]),
	]
	for grey: int in [0x606060, 0x404040, 0x202020]:
		list.append(SplashTimeline.Command.new(SplashTimeline.Op.SETCOLOUR, grey))
		list.append(SplashTimeline.Command.new(SplashTimeline.Op.SETIMAGE, 0, images[3]))
	list.append(SplashTimeline.Command.new(SplashTimeline.Op.KILL))
	return list


## The transform between two source matrices [param before] and [param after] at [param weight];
## a half-turn between them (a flip) moves without turning.
static func blend_transform(before: PackedInt32Array, after: PackedInt32Array, weight: float) -> Transform3D:
	var now: Transform3D = GameSpace.transform(after)
	if weight >= 1.0 or before == after:
		return now
	var then: Transform3D = GameSpace.transform(before)
	if then.basis.x.dot(now.basis.x) < 0.0 or then.basis.z.dot(now.basis.z) < 0.0:
		return Transform3D(now.basis, then.origin.lerp(now.origin, weight))
	return then.interpolate_with(now, weight)


## Independent copies of [param matrices].
static func copies(matrices: Array[PackedInt32Array]) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for matrix: PackedInt32Array in matrices:
		result.append(matrix.duplicate())
	return result


## Places [param instances] between the matrices [param before] and [param after] at [param weight],
## each first turned by [param local] (the model's own pre-rotation).
static func place(instances: Array[AnimatedModelInstance], before: Array[PackedInt32Array], after: Array[PackedInt32Array],
		weight: float, local: Transform3D = Transform3D.IDENTITY) -> void:
	for index: int in mini(instances.size(), after.size()):
		if instances[index] == null:
			continue
		var from: PackedInt32Array = before[index] if index < before.size() else after[index]
		instances[index].transform = blend_transform(from, after[index], weight) * local
		instances[index].render(weight)


## The frog shadow's corners for the frog matrix [param frog] in [param phase], set onto the water
## at [param frame] (Frog_jump_shadow offsets turned by the frog's matrix).
static func shadow_corners(frog: PackedInt32Array, phase: int, frame: int) -> Array[Vector3i]:
	var corners: Array[Vector3i] = []
	for offset: Vector3i in FrogShadowGeometry.phase_offsets(phase):
		var corner := Vector3i.ZERO
		for row: int in 3:
			corner[row] = ((frog[row * 3] * offset.x + frog[row * 3 + 1] * offset.y + frog[row * 3 + 2] * offset.z) >> 12) + frog[9 + row]
		corner.y = OptionsScene.surface_height(corner.x, corner.z, frame)
		corners.append(corner)
	return corners


## Prepares the layers and images for [param with_models].
func setup(with_models: OptionsModels) -> void:
	name = "Models"
	models = with_models
	_projection = GameplayProjection.clip_scale(MenuWaterView.DISPLAY_SIZE)
	for layer: int in Layer.values():
		var instance := MeshInstance3D.new()
		instance.name = "Sprites" + str(Layer.keys()[layer]).capitalize()
		instance.mesh = ImmediateMesh.new()
		instance.sorting_offset = LAYER_SORTING[layer]
		add_child(instance)
		_layers.append(instance)
	if not available():
		return
	scene_lighting = SceneLighting.new()
	scene_lighting.name = "SceneLighting"
	add_child(scene_lighting)
	scene_lighting.apply(MenuWaterView.options_spec())
	for symbol: String in models.images:
		var record: VloImage = models.images[symbol]
		var blend: ModelShaders.Blend = EffectSpriteMaterial.image_blend(record)
		var bias: float = EffectSpriteMaterial.slots_bias(OptionsScene.SPLASH_OT_OFFSET)
		var layer: int = Layer.SPLASHES
		if FrogShadowGeometry.PHASE_TEXTURES.has(symbol):
			blend = EffectSpriteMaterial.semi_transparent_blend(record)
			bias = EffectSpriteMaterial.slots_bias(FrogShadowGeometry.OT_OFFSET)
			layer = Layer.SHADOW
		_image_materials[symbol] = EffectSpriteMaterial.textured(models.library, record, blend, bias, _projection)
		_image_materials[symbol].render_priority = LAYER_PRIORITY[layer]


## True when the models loaded and can be drawn.
func available() -> bool:
	return models != null and models.error.is_empty()


## A new instance of the model called [param file_name], or null when it is not available.
func add_model(file_name: String) -> AnimatedModelInstance:
	if not available():
		return null
	var kind: int = OptionsModels.kind_of(file_name)
	if kind < 0 or models.model_mesh(kind) == null:
		return null
	return _add_instance(models.model_mesh(kind), ModelAnimationPlayer.new(models.model_file(kind)))


## Replaces [param instance]'s model with the one called [param file_name] (or adds it when
## [param instance] is null) and returns the instance drawn.
func swap_model(instance: AnimatedModelInstance, file_name: String) -> AnimatedModelInstance:
	if instance != null:
		remove_child(instance)
		instance.queue_free()
	return add_model(file_name)


## A new instance of model [param file] with [param mesh] played at [param update_period], one
## shot, starting on [param action]; with [param croak_sack] the frog's throat part shows at its
## smallest and [param hidden_parts] are hidden.
func add_frog(file: MofFile, mesh: ModelMesh, action: int, update_period: int, croak_sack: bool = false,
		hidden_parts: PackedInt64Array = PackedInt64Array()) -> AnimatedModelInstance:
	if not available() or file == null or mesh == null:
		return null
	var player := ModelAnimationPlayer.new(file)
	player.update_period = update_period
	player.end_mode = ModelAnimationPlayer.EndMode.HOLD
	if action >= 0:
		player.set_action(action)
	player.restart()
	var frog: AnimatedModelInstance = _add_instance(mesh, player)
	frog.name = "Frog"
	for index: int in frog.part_nodes.size():
		frog.part_nodes[index].visible = not hidden_parts.has(index)
	if croak_sack and GameplayWorldView.THROAT_PART < frog.part_nodes.size():
		frog.part_nodes[GameplayWorldView.THROAT_PART].visible = true
		frog.set_part_scale(GameplayWorldView.THROAT_PART, FrogCroak.MIN_SCALE / 4096.0)
	return frog


## Starts a landing splash on anchor [param anchor].
func start_splash(anchor: int) -> void:
	var splash := _Splash.new()
	splash.anchor = anchor
	splash.timeline = SplashTimeline.new(splash_commands())
	splash.timeline.scale = OptionsScene.SPRITE_SCALE
	_splashes.append(splash)


## Advances every splash one tick and drops the finished ones.
func step_splashes() -> void:
	var kept: Array[_Splash] = []
	for splash: _Splash in _splashes:
		splash.timeline.update()
		if not splash.timeline.killed:
			kept.append(splash)
	_splashes = kept


## The anchors of the splashes still showing.
func splash_anchors() -> PackedInt32Array:
	var result := PackedInt32Array()
	for splash: _Splash in _splashes:
		result.append(splash.anchor)
	return result


## Draws the shadow between corners [param shadow_before] and [param shadow_now] in [param phase]
## (no shadow when [param shadow_now] is empty) and the splashes on anchors moved from
## [param anchors_before] to [param anchors_now], at [param weight], lit as seen from
## [param source] looking at [param target].
func draw_effects(shadow_before: Array[Vector3i], shadow_now: Array[Vector3i], phase: int, anchors_before: Array[PackedInt32Array],
		anchors_now: Array[PackedInt32Array], weight: float, source: Vector3i, target: Vector3i) -> void:
	var layers: Array[Dictionary] = []
	for _layer: int in Layer.size():
		var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = {}
		layers.append(batches)
	if not shadow_now.is_empty():
		var material: ShaderMaterial = _image_materials.get(FrogShadowGeometry.PHASE_TEXTURES[phase], null)
		if material != null:
			var corners: Array[Vector3] = []
			for index: int in 4:
				var now := Vector3(shadow_now[index])
				var then: Vector3 = Vector3(shadow_before[index]) if shadow_before.size() == 4 else now
				corners.append(EffectSpriteMaterial.world(then.lerp(now, weight)))
			var grey: Color = EffectSpriteMaterial.colour(Vector3i(FrogShadowGeometry.GREY, FrogShadowGeometry.GREY, FrogShadowGeometry.GREY))
			EffectSpriteMaterial.batch_for(layers[Layer.SHADOW], material).quad(corners, [grey, grey, grey, grey])
	for splash: _Splash in _splashes:
		var material: ShaderMaterial = _image_materials.get(splash.timeline.image, null)
		var record: VloImage = models.images.get(splash.timeline.image, null) if available() else null
		if material == null or record == null or not splash.timeline.drawn() or splash.anchor >= anchors_now.size():
			continue
		var from: PackedInt32Array = anchors_before[splash.anchor] if splash.anchor < anchors_before.size() else anchors_now[splash.anchor]
		var matrix: PackedFloat32Array = _blend_matrix(from, anchors_now[splash.anchor], weight)
		var half: Vector2i = SplashView.half_extents(record.width, record.height, splash.timeline.scale)
		var flat: Array[Vector3] = [Vector3(-half.x, 0.0, half.y), Vector3(half.x, 0.0, half.y),
			Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y)]
		_add_sprite(layers[Layer.SPLASHES], material, matrix, flat, splash.timeline.rgb().x, source, target)
	for layer: int in _layers.size():
		var batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch] = layers[layer]
		_layers[layer].visible = EffectSpriteMaterial.commit(_layers[layer].mesh as ImmediateMesh, batches)


func _enter_tree() -> void:
	if scene_lighting == null:
		return
	if scene_lighting.applied_spec == null:
		scene_lighting.apply(MenuWaterView.options_spec())
	var water: MenuWaterView = _world_water()
	if water != null:
		water.release_environment()


func _exit_tree() -> void:
	if scene_lighting != null:
		scene_lighting.clear()


func _world_water() -> MenuWaterView:
	var node: Node = get_parent()
	while node != null and not (node is Viewport):
		var water: MenuWaterView = node as MenuWaterView
		if water != null and water.camera != null:
			return water
		node = node.get_parent()
	return null


func _add_instance(mesh: ModelMesh, player: ModelAnimationPlayer) -> AnimatedModelInstance:
	var instance := AnimatedModelInstance.new()
	add_child(instance)
	instance.setup(drawn_mesh(mesh), player)
	instance.smoothing_enabled = smoothing_enabled
	instance.set_source_lighting(models.lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	return instance


func _add_sprite(batches: Dictionary[ShaderMaterial, EffectSpriteMaterial.Batch], material: ShaderMaterial,
		matrix: PackedFloat32Array, local: Array[Vector3], base: int, source: Vector3i, target: Vector3i) -> void:
	var corners: Array[Vector3] = []
	var screen: Array[Vector3] = []
	for corner: Vector3 in local:
		var at := Vector3(
			(matrix[0] * corner.x + matrix[1] * corner.y + matrix[2] * corner.z) / 4096.0 + matrix[9],
			(matrix[3] * corner.x + matrix[4] * corner.y + matrix[5] * corner.z) / 4096.0 + matrix[10],
			(matrix[6] * corner.x + matrix[7] * corner.y + matrix[8] * corner.z) / 4096.0 + matrix[11])
		screen.append(OptionsView.project(source, target, at))
		corners.append(EffectSpriteMaterial.world(at))
	var facing: float = (screen[1].x - screen[0].x) * (screen[2].y - screen[0].y) - (screen[2].x - screen[0].x) * (screen[1].y - screen[0].y)
	var sign: float = 1.0 if facing > 0.0 else -1.0
	var normal := Vector3(matrix[2], -matrix[5], -matrix[8]) * sign / 4096.0
	var colour: Color = models.lighting.shade(EffectSpriteMaterial.colour(Vector3i(base, base, base)), normal)
	EffectSpriteMaterial.batch_for(batches, material).quad(corners, [colour, colour, colour, colour])


static func _blend_matrix(before: PackedInt32Array, after: PackedInt32Array, weight: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(12)
	for index: int in 12:
		result[index] = lerpf(before[index], after[index], weight)
	return result


## The drawing copy this set uses for [param shared], made on first use.
func drawn_mesh(shared: ModelMesh) -> ModelMesh:
	if shared == null:
		return null
	if not _drawn.has(shared):
		_drawn[shared] = ModelMeshCopy.of(shared)
		_set_projection(_drawn[shared], _projection)
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
