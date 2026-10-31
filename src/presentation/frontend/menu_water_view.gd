class_name MenuWaterView
extends Node3D
## The front-end water and riverbed drawn from a [MenuWater] stepped at 30 Hz.
##
## Each tick advances the shared frame count after the previous heights were drawn, so a newly
## created viewport first shows frame 0 and the wave continues across pages that share the
## [MenuWater]. Between ticks the heights are interpolated from the last two ticks. A view made
## with [method create_with_camera] has its own options camera at perspective 256 on the
## 640x480 display, snapped to the MAIN preset, and clears to black; otherwise it draws in the
## world and through the camera of its parent, as the level select does.
##
## Under the modern rendering profile one [SceneLighting] lights the models drawn in a camera
## view's world and owns that world's environment, still clearing to black: the view's own
## ([method light_scene]) or one drawn in it, after which the view gives up its environment
## ([method release_environment]). A view drawn through its parent's camera is lit by its
## parent's world. The water itself stays unlit. The view's own lights are cleared when it leaves
## the tree and applied again when it returns.

## Seconds per water tick.
const PERIOD: float = GameplayHost.PERIOD
## The display the source draws on.
const DISPLAY_SIZE: Vector2i = Vector2i(640, 480)
## The options camera's MAIN preset eye (tempopt.h OPTIONS_CAMERA_MAIN_SOURCE_OFS_*).
const MAIN_SOURCE: Vector3i = Vector3i(0, -2500, -1280)
## The options camera's MAIN preset target (tempopt.h OPTIONS_CAMERA_MAIN_TARGET_OFS_*).
const MAIN_TARGET: Vector3i = Vector3i(0, 1024, -800)
## The options camera's up vector (world Y).
const UP: Vector3i = Vector3i(0, 0x1000, 0)
## Near clip distance in Godot units.
const CAMERA_NEAR: float = 0.05

## The animation being drawn.
var water: MenuWater
## The meshes.
var meshes: MenuWaterMesh
## The water surface.
var surface: MeshInstance3D
## The riverbed.
var riverbed: MeshInstance3D
## The view's own options camera, or null when drawn through the parent's camera.
var camera: Camera3D
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## Time since the last tick.
var elapsed: float = 0.0
## The light of the view's world once [method light_scene] was called, or null.
var scene_lighting: SceneLighting
## The view's own environment from [method create_with_camera], or null once [member scene_lighting] owns the world's.
var world_environment: WorldEnvironment

var _scene_spec: SceneLightingSpec
var _previous := PackedInt32Array()
var _current := PackedInt32Array()


## A view of [param animation] drawn through the parent's camera, whose source projection is
## scaled by [param projection_scale]; [param surface_texture] and [param bed_texture] are
## im_opt_env_sky and im_opt_bank3.
static func create(animation: MenuWater, surface_texture: Texture2D, bed_texture: Texture2D,
		projection_scale: Vector2 = Vector2.ONE) -> MenuWaterView:
	var view := MenuWaterView.new()
	view.name = "Water"
	view.water = animation
	view._current = animation.current_heights()
	view.meshes = MenuWaterMesh.create(animation.frame_count)
	view.riverbed = MeshInstance3D.new()
	view.riverbed.name = "Riverbed"
	view.riverbed.mesh = view.meshes.riverbed
	view.riverbed.set_surface_override_material(0, MenuWaterMesh.riverbed_material(bed_texture, projection_scale))
	view.add_child(view.riverbed)
	view.surface = MeshInstance3D.new()
	view.surface.name = "Surface"
	view.surface.mesh = view.meshes.water
	view.surface.set_surface_override_material(0, MenuWaterMesh.water_material(surface_texture, projection_scale))
	view.add_child(view.surface)
	return view


## A view of [param animation] with its own options camera at the MAIN preset and a black
## background.
static func create_with_camera(animation: MenuWater, surface_texture: Texture2D, bed_texture: Texture2D) -> MenuWaterView:
	var view: MenuWaterView = create(animation, surface_texture, bed_texture, GameplayProjection.clip_scale(DISPLAY_SIZE))
	view.world_environment = WorldEnvironment.new()
	view.world_environment.environment = Environment.new()
	view.world_environment.environment.background_mode = Environment.BG_COLOR
	view.world_environment.environment.background_color = Color.BLACK
	view.add_child(view.world_environment)
	view.camera = Camera3D.new()
	view.camera.name = "OptionsCamera"
	view.camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	view.camera.fov = GameplayProjection.vertical_fov_degrees(DISPLAY_SIZE)
	view.camera.near = CAMERA_NEAR
	view.camera.far = MenuWaterMesh.CAMERA_FAR
	view.camera.transform = camera_transform(MAIN_SOURCE, MAIN_TARGET)
	view.add_child(view.camera)
	return view


## The camera frame's rotation, row-major 4.12, of MRPointMatrixAtVector looking from
## [param source] at [param target] with [constant UP] as up. Columns are the camera's X, Y and Z.
static func point_matrix(source: Vector3i, target: Vector3i) -> PackedInt32Array:
	var z: Vector3i = StackLayout.normalise(target - source)
	var x: Vector3i = StackLayout.normalise(StackLayout.outer12(UP, z))
	var y: Vector3i = StackLayout.outer12(z, x)
	var matrix := PackedInt32Array()
	for row: int in 3:
		matrix.append_array([StackLayout.s16(x[row]), StackLayout.s16(y[row]), StackLayout.s16(z[row])])
	return matrix


## The options camera transform at [param source] looking at [param target].
static func camera_transform(source: Vector3i, target: Vector3i) -> Transform3D:
	var values: PackedInt32Array = point_matrix(source, target)
	values.append_array([source.x, source.y, source.z])
	return GameSpace.transform(values)


## The modern scene light of the options viewport's lights ([method OptionsModels.options_lighting]),
## without shadows.
static func options_spec() -> SceneLightingSpec:
	return SceneLightingBuilder.from_lighting(OptionsModels.options_lighting(), false)


## Lights the view's world with [param spec] through [member scene_lighting], created on the first
## call, which replaces the view's own environment; later calls apply the new spec to it.
func light_scene(spec: SceneLightingSpec) -> SceneLighting:
	_scene_spec = spec
	if scene_lighting == null:
		release_environment()
		scene_lighting = SceneLighting.new()
		scene_lighting.name = "SceneLighting"
		add_child(scene_lighting)
	scene_lighting.apply(spec)
	return scene_lighting


## Gives up the view's own environment to a [SceneLighting] drawn in its world: the environment
## stops applying at once and its node is freed (at the end of the frame while in the tree, where
## it may be called as the tree is entered).
func release_environment() -> void:
	if world_environment == null:
		return
	world_environment.environment = null
	if is_inside_tree():
		world_environment.queue_free()
	else:
		remove_child(world_environment)
		world_environment.free()
	world_environment = null


## Advances the frame count one tick and draws the result.
func tick() -> void:
	water.advance()
	_previous = _current
	_current = water.current_heights()
	render(0.0 if smoothing_enabled else 1.0)


## Draws [param fraction] of the way from the previous tick's heights to the last ones.
func render(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	var before: PackedInt32Array = _previous if not _previous.is_empty() else _current
	var heights := PackedFloat32Array()
	heights.resize(_current.size())
	for index: int in _current.size():
		heights[index] = lerpf(before[index], _current[index], weight)
	meshes.set_heights(heights)


func _ready() -> void:
	if camera != null:
		camera.make_current()


func _enter_tree() -> void:
	if scene_lighting != null and scene_lighting.applied_spec == null and _scene_spec != null:
		scene_lighting.apply(_scene_spec)


func _exit_tree() -> void:
	if scene_lighting != null:
		scene_lighting.clear()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick()
	render(elapsed / PERIOD)
