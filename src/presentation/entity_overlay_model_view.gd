class_name EntityOverlayModelView
extends Node3D
## Draws per-entity one-shot overlay flipbooks from committed entity snapshots.
##
## Desert falling and rolling rocks explode by hiding their own model and adding
## a separate static flipbook environment from Map_mof_ptrs[DES_FALL_ROCKROLL]
## at an identity matrix (ent_des.c). The overlay carries no entity colour
## scaling, so it takes plain map lighting. Drawing never advances gameplay:
## the committed overlay action and cel select the shown pose.

## Interpolate overlay cels between committed ticks.
var smoothing: bool = false:
	set(value):
		if smoothing == value:
			return
		smoothing = value
		reset_interpolation()

var _file: MofFile = null
var _mesh: ModelMesh = null
var _lighting: MapLighting = null
var _projection_scale := Vector2.ONE
var _instances: Array[AnimatedModelInstance] = []
var _active: Array[bool] = []
var _state: GameplayState = null

## Whether entities of `kind` publish an overlay flipbook this view draws.
static func uses_overlay(kind: EntityBehavior.Kind) -> bool:
	return kind == EntityBehavior.Kind.DES_FALLING_ROCK or kind == EntityBehavior.Kind.DES_ROLLING_ROCK

## Render transform of an overlay at identity rotation and game position `at`.
static func overlay_transform(at: Vector3i) -> Transform3D:
	return Transform3D(Basis.IDENTITY, GameSpace.position(at.x, at.y, at.z))

## Adopts the decoded overlay model and a drawing copy of its built mesh ([ModelMeshCopy]); returns a diagnostic when either is unusable.
func configure(file: MofFile, model_mesh: ModelMesh, lighting: MapLighting = null) -> String:
	clear()
	if file == null or not file.error.is_empty() or file.static_models.is_empty():
		return "Desert rock explosion model could not be decoded from the supplied archive"
	if model_mesh == null or model_mesh.part_meshes.is_empty():
		return "Desert rock explosion model has no drawable geometry"
	_file = file
	_mesh = ModelMeshCopy.of(model_mesh)
	_lighting = lighting
	set_projection_scale(_projection_scale)
	return ""

## Whether a usable overlay model is configured.
func is_configured() -> bool:
	return _mesh != null

## Releases instances, the borrowed model and any retained snapshot.
func clear() -> void:
	for instance: AnimatedModelInstance in _instances:
		if instance != null:
			remove_child(instance)
			instance.queue_free()
	_instances.clear()
	_active.clear()
	_state = null
	_file = null
	_mesh = null
	_lighting = null

## Applies the same source projection correction as terrain and models.
func set_projection_scale(scale: Vector2) -> void:
	_projection_scale = scale
	if _mesh == null:
		return
	for mesh: ArrayMesh in _mesh.part_meshes:
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("projection_scale", scale)
	for tracks: Array in _mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			if track.original != null:
				track.original.set_shader_parameter("projection_scale", scale)
			for material: ShaderMaterial in track.frames:
				material.set_shader_parameter("projection_scale", scale)
	for instance: AnimatedModelInstance in _instances:
		if instance != null:
			instance.refresh_materials()

## Collapses cel interpolation without changing the shown poses.
func reset_interpolation() -> void:
	for instance: AnimatedModelInstance in _instances:
		if instance != null:
			instance.smoothing_enabled = smoothing
			instance.apply_exact()

## Shows each slot's committed overlay at `fraction` between ticks; `collapse` drops cel history.
func draw_state(state: GameplayState, fraction: float = 1.0, collapse: bool = true) -> void:
	if _mesh == null:
		return
	var fresh: bool = state != _state
	_state = state
	var count: int = state.entities.entities.size() if state != null and state.entities != null else 0
	for slot: int in _instances.size():
		if slot >= count and _instances[slot] != null:
			_instances[slot].visible = false
			_active[slot] = false
	for slot: int in count:
		var entity: EntitySnapshot = state.entities.entities[slot]
		var overlay: EntityAnimationState = entity.custom_state.overlay_animation if entity.live and entity.custom_state != null else null
		var instance: AnimatedModelInstance = _instances[slot] if slot < _instances.size() else null
		if overlay == null:
			if instance != null:
				instance.visible = false
				_active[slot] = false
			continue
		if instance == null:
			instance = _create(slot)
		if fresh:
			var appearing: bool = not _active[slot]
			if overlay.action >= 0 and instance.player.action_index != overlay.action:
				instance.player.set_action(overlay.action)
			instance.player.frame = clampi(overlay.cel, 0, maxi(instance.player.action_frame_count(instance.player.action_index) - 1, 0))
			instance.capture_pose(collapse or appearing)
			var target: Transform3D = overlay_transform(entity.custom_state.overlay_position)
			if instance.transform != target:
				instance.transform = target
			_active[slot] = true
		instance.render(fraction)
		instance.visible = true

## Number of slots whose overlay is currently shown.
func shown_count() -> int:
	var count: int = 0
	for slot: int in _instances.size():
		if _instances[slot] != null and _instances[slot].visible:
			count += 1
	return count

func _create(slot: int) -> AnimatedModelInstance:
	while _instances.size() <= slot:
		_instances.append(null)
		_active.append(false)
	var instance := AnimatedModelInstance.new()
	add_child(instance)
	instance.setup(_mesh, ModelAnimationPlayer.new(_file))
	instance.smoothing_enabled = smoothing
	if _lighting != null:
		instance.set_source_lighting(_lighting, Vector3i.ZERO, Vector3i.ZERO, false, false)
	instance.refresh_materials()
	_instances[slot] = instance
	return instance
