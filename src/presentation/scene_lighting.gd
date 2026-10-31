class_name SceneLighting
extends Node3D
## The modern profile's scene light: one [WorldEnvironment] and up to three
## [DirectionalLight3D] children built from a [SceneLightingSpec], plus the
## frogger_model_ambient shader global, and in caves one [OmniLight3D].
##
## Nothing is created until [method apply], so a view that never applies a
## spec draws exactly as before. The environment's ambient colour is an sRGB
## property the renderer converts to linear, so the spec's linear ambient is
## passed through [method Color.linear_to_srgb].
##
## [method set_cave_light] switches the scene to cave mode: the directional
## lights go, the ambient dims to [constant CaveLightShape.CAVE_AMBIENT] and
## the omni light shaped by [CaveLightShape] follows the frog;
## [method clear_cave_light] restores the applied spec.

## Shader global carrying the linear ambient to the lit model shaders.
const AMBIENT_GLOBAL: StringName = &"frogger_model_ambient"
## Largest number of directional lights applied.
const MAX_LIGHTS: int = 3

## The environment applied with the first spec, or null before one; later
## features extend it rather than adding a second [WorldEnvironment].
var environment: Environment = null
## Linear ambient last sent to [constant AMBIENT_GLOBAL].
var applied_ambient: Vector3 = Vector3.ONE
## The spec last applied, or null when cleared.
var applied_spec: SceneLightingSpec = null
var _world_environment: WorldEnvironment = null
var _lights: Array[DirectionalLight3D] = []
var _cave_light: OmniLight3D = null
var _cave_key: PackedInt64Array = PackedInt64Array()


## Replaces the lights with those of [param spec] and sets the environment and
## ambient global; in cave mode the spec is kept for [method clear_cave_light]
## and the scene stays dark around the cave light.
func apply(spec: SceneLightingSpec) -> void:
	applied_spec = spec
	_free_lights()
	if _cave_light != null:
		_enter_cave_mode()
		return
	for index: int in mini(spec.lights.size(), MAX_LIGHTS):
		var light := _light(spec, spec.lights[index])
		add_child(light)
		_lights.append(light)
	_apply_environment(spec.ambient, 1.0)
	_set_ambient(spec.ambient)


## Frees the lights and the cave light and resets the ambient global to one; the environment stays.
func clear() -> void:
	_free_cave_light()
	_free_lights()
	_set_ambient(Vector3.ONE)
	if environment != null:
		environment.ambient_light_energy = 1.0
	applied_spec = null


## Places the cave light [constant CaveLightShape.HEIGHT] above [param position]
## with the range and energy [CaveLightShape] gives the radii under
## [param mode], creating it and entering cave mode on the first call.
func set_cave_light(position: Vector3, min_r2: int, max_r2: int, mode: CaveLightShape.Mode = CaveLightShape.DEFAULT_MODE) -> void:
	if _cave_light == null:
		_cave_light = OmniLight3D.new()
		_cave_light.name = "CaveLight"
		_cave_light.omni_attenuation = 0.0
		_cave_light.shadow_enabled = false
		_cave_light.light_specular = 0.0
		_cave_light.light_color = Color.WHITE
		add_child(_cave_light)
		_cave_key = PackedInt64Array()
		_free_lights()
		_enter_cave_mode()
	_cave_light.position = position + Vector3.UP * CaveLightShape.HEIGHT
	var key := PackedInt64Array([min_r2, max_r2, mode])
	if key == _cave_key:
		return
	_cave_key = key
	_cave_light.omni_range = CaveLightShape.range_of(max_r2, mode)
	_cave_light.light_energy = CaveLightShape.energy_of(min_r2, max_r2, mode)


## Frees the cave light and restores the applied spec's lights and ambient.
func clear_cave_light() -> void:
	if _cave_light == null:
		return
	_free_cave_light()
	if applied_spec != null:
		apply(applied_spec)
	elif environment != null:
		environment.ambient_light_energy = 1.0
		_set_ambient(Vector3.ONE)


## The cave light, or null outside cave mode.
func cave_light_node() -> OmniLight3D:
	return _cave_light


## The directional lights currently applied.
func light_nodes() -> Array[DirectionalLight3D]:
	return _lights.duplicate()


## The [WorldEnvironment] child, or null before the first [method apply].
func world_environment() -> WorldEnvironment:
	return _world_environment


func _exit_tree() -> void:
	_set_ambient(Vector3.ONE)


func _light(spec: SceneLightingSpec, source: SceneLightingSpec.Light) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.transform.basis = source.basis
	light.light_color = source.colour
	light.light_energy = source.energy
	light.light_angular_distance = 0.0
	light.shadow_enabled = source.casts_shadow and spec.shadows
	light.directional_shadow_mode = _shadow_mode(spec.shadow_splits)
	light.directional_shadow_split_1 = spec.split_1
	light.directional_shadow_max_distance = spec.max_distance
	light.directional_shadow_fade_start = spec.fade_start
	light.shadow_bias = spec.bias
	light.shadow_normal_bias = spec.normal_bias
	light.shadow_blur = spec.blur
	light.shadow_caster_mask = SceneLightingSpec.SHADOW_CASTER_LAYER
	return light


func _shadow_mode(splits: int) -> DirectionalLight3D.ShadowMode:
	match splits:
		1:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		4:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func _enter_cave_mode() -> void:
	var ambient: Vector3 = applied_spec.ambient if applied_spec != null else Vector3.ONE
	_apply_environment(ambient, CaveLightShape.CAVE_AMBIENT)
	_set_ambient(ambient * CaveLightShape.CAVE_AMBIENT)


func _apply_environment(ambient: Vector3, energy: float) -> void:
	if environment == null:
		environment = Environment.new()
	if _world_environment == null:
		_world_environment = WorldEnvironment.new()
		add_child(_world_environment)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(ambient.x, ambient.y, ambient.z).linear_to_srgb()
	environment.ambient_light_energy = energy
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = false
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.ssr_enabled = false
	environment.sdfgi_enabled = false
	_world_environment.environment = environment


func _set_ambient(ambient: Vector3) -> void:
	applied_ambient = ambient
	RenderingServer.global_shader_parameter_set(AMBIENT_GLOBAL, ambient)


func _free_cave_light() -> void:
	if _cave_light == null:
		return
	remove_child(_cave_light)
	_cave_light.free()
	_cave_light = null
	_cave_key = PackedInt64Array()


func _free_lights() -> void:
	for light: DirectionalLight3D in _lights:
		remove_child(light)
		light.free()
	_lights.clear()
