class_name AnimatedModelInstance
extends Node3D
## Draws a player's integer pose with reusable meshes and optional motion interpolation.
## The owner advances the player at the game tick rate, then renders between ticks.

## The player supplying transforms, flipbook cels and texture entries.
var player: ModelAnimationPlayer
## Resources built once for this instance.
var model_mesh: ModelMesh
## One node per part, including parts without geometry.
var part_nodes: Array[MeshInstance3D] = []
## Interpolate only geometry and transforms; textures always use the current tick.
var smoothing_enabled: bool = false:
	set(value):
		if smoothing_enabled == value:
			return
		smoothing_enabled = value
		apply_exact()

var _previous: ModelPose
var _current: ModelPose
var _revision: int = -1
var _lighting: MapLighting = null
var _materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}
var _source_ambient: Vector3 = Vector3.ZERO
var _source_colours: Array[Vector3] = []
var _lighting_directions: Array[Vector3] = []
var _lighting_colours: Array[Vector3] = []
var _lighting_ambient: Vector3 = Vector3.ZERO
var _colour_scale: Vector3i = Vector3i.ZERO
var _ambient: Vector3i = Vector3i.ZERO
var _scaled: bool = false
var _custom: bool = false
var _blend_values: Array[PackedFloat32Array] = []
var _active_blends: Array[PackedInt32Array] = []
var _static_pose: bool = false
var _static_drawn: bool = false


## Attaches prebuilt resources and samples the player's current state.
func setup(mesh: ModelMesh, animation_player: ModelAnimationPlayer) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for node: MeshInstance3D in part_nodes:
		remove_child(node)
		node.queue_free()
	part_nodes.clear()
	_blend_values.clear()
	_active_blends.clear()
	_materials.clear()
	_static_drawn = false
	_lighting = null
	model_mesh = mesh
	player = animation_player
	_static_pose = player.action_count() == 0
	for tracks: Array in mesh.texture_tracks:
		_static_pose = _static_pose and tracks.is_empty()
	for index: int in mesh.part_meshes.size():
		var node := MeshInstance3D.new()
		node.name = "Part%d" % index
		node.mesh = mesh.part_meshes[index]
		if index < mesh.part_bounds.size():
			node.custom_aabb = mesh.part_bounds[index]
		add_child(node)
		part_nodes.append(node)
		var values := PackedFloat32Array()
		values.resize(mesh.part_meshes[index].get_blend_shape_count() if mesh.part_meshes[index] != null else 0)
		_blend_values.append(values)
		_active_blends.append(PackedInt32Array())
	apply_exact()

## Applies source colour-matrix scaling and custom ambient to instance-local materials.
func set_source_lighting(lighting: MapLighting, scale: Vector3i, ambient: Vector3i, scaled: bool, custom: bool) -> void:
	if _lighting == lighting and _colour_scale == scale and _ambient == ambient and _scaled == scaled and _custom == custom and _lighting_ambient == lighting.ambient and _lighting_directions == lighting.directions and _lighting_colours == lighting.colours:
		return
	_lighting = lighting
	_colour_scale = scale
	_ambient = ambient
	_scaled = scaled
	_custom = custom
	_lighting_ambient = lighting.ambient
	_lighting_directions.assign(lighting.directions)
	_lighting_colours.assign(lighting.colours)
	var multiplier: Vector3 = Vector3(scale) / 128.0 if scaled else Vector3.ONE
	var base: Vector3 = Vector3(ambient) if custom else lighting.ambient / 16.0
	_source_ambient = (base * multiplier).floor() * 16.0
	_source_colours.clear()
	for colour: Vector3 in lighting.colours:
		_source_colours.append((colour * multiplier).floor())
	for original: ShaderMaterial in _materials:
		_update_lighting(_materials[original], original)
	refresh_materials()
	render(1.0)

func _material(original: ShaderMaterial) -> ShaderMaterial:
	if _lighting == null or original == null:
		return original
	if not _materials.has(original):
		_materials[original] = original.duplicate() as ShaderMaterial
		_update_lighting(_materials[original], original)
	var projection: Variant = original.get_shader_parameter("projection_scale")
	if _materials[original].get_shader_parameter("projection_scale") != projection:
		_materials[original].set_shader_parameter("projection_scale", projection)
	return _materials[original]

func _update_lighting(material: ShaderMaterial, original: ShaderMaterial) -> void:
	material.set_shader_parameter("projection_scale", original.get_shader_parameter("projection_scale"))
	material.set_shader_parameter("source_lighting", true)
	material.set_shader_parameter("source_ambient", _source_ambient)
	for index: int in 3:
		material.set_shader_parameter("source_direction%d" % index, _lighting.directions[index] if index < _lighting.directions.size() else Vector3.ZERO)
		material.set_shader_parameter("source_colour%d" % index, _source_colours[index] if index < _source_colours.size() else Vector3.ZERO)


## Advances one integer game tick and retains the previous sample for drawing.
func advance_tick() -> void:
	if player == null:
		return
	player.advance_tick()
	capture_pose()
	render(1.0 if not smoothing_enabled else 0.0)

## Samples a committed player pose without advancing its tick or drawing twice.
func capture_pose(collapse: bool = false) -> void:
	if player == null:
		return
	_previous = _current
	if _static_pose and player.revision == _revision:
		return
	_current = player.sample_pose()
	var textures_changed: bool = _previous == null or _current.texture_entries != _previous.texture_entries
	if collapse or player.wrapped or player.revision != _revision or _previous == null:
		_previous = _current
	_revision = player.revision
	if textures_changed:
		refresh_materials()


## Resets interpolation after a seek, action change, pause, step or restart.
func apply_exact() -> void:
	if player == null:
		return
	_current = player.sample_pose()
	_previous = _current
	_revision = player.revision
	_static_drawn = false
	refresh_materials()
	render(1.0)


## Draws the fraction between the last two ticks, without advancing the player.
func render(fraction: float) -> void:
	if player == null or _current == null:
		return
	if player.revision != _revision:
		apply_exact()
		return
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	visible = _current.visible
	if _static_pose and _static_drawn:
		return
	_static_drawn = true
	for index: int in part_nodes.size():
		var node: MeshInstance3D = part_nodes[index]
		var now: Transform3D = _current.transforms[index] if index < _current.transforms.size() else Transform3D.IDENTITY
		var before: Transform3D = _previous.transforms[index] if _previous != null and index < _previous.transforms.size() else now
		if before == now:
			if node.transform != now:
				node.transform = now
		elif weight == 0.0:
			node.transform = before
		elif weight == 1.0:
			node.transform = now
		elif absf(before.basis.determinant()) < 0.000001 or absf(now.basis.determinant()) < 0.000001:
			# A stored zero scale cannot be decomposed into a rotation quaternion.
			node.transform = Transform3D(Basis(before.basis.x.lerp(now.basis.x, weight),
				before.basis.y.lerp(now.basis.y, weight), before.basis.z.lerp(now.basis.z, weight)), before.origin.lerp(now.origin, weight))
		else:
			node.transform = before.interpolate_with(now, weight)
		if node.mesh != null:
			var mesh: ArrayMesh = node.mesh as ArrayMesh
			var current_cel: int = _current.partcels[index] if index < _current.partcels.size() else 0
			var previous_cel: int = _previous.partcels[index] if _previous != null and index < _previous.partcels.size() else current_cel
			var active := PackedInt32Array()
			for cel: int in [current_cel, previous_cel]:
				if cel > 0 and cel <= mesh.get_blend_shape_count() and not active.has(cel - 1):
					active.append(cel - 1)
			var changed: PackedInt32Array = active.duplicate()
			for blend: int in _active_blends[index]:
				if not changed.has(blend):
					changed.append(blend)
			for blend: int in changed:
				var amount: float = (weight if current_cel == blend + 1 else 0.0) + (1.0 - weight if previous_cel == blend + 1 else 0.0)
				if _blend_values[index][blend] != amount:
					node.set_blend_shape_value(blend, amount)
					_blend_values[index][blend] = amount
			_active_blends[index] = active

## Refreshes discrete texture bindings and instance materials after pose or projection changes.
func refresh_materials() -> void:
	if _current == null:
		return
	for index: int in part_nodes.size():
		var node: MeshInstance3D = part_nodes[index]
		var mesh: ArrayMesh = node.mesh as ArrayMesh
		if mesh == null:
			continue
		var overrides: Dictionary[int, ShaderMaterial] = {}
		if _lighting != null:
			for surface: int in mesh.get_surface_count():
				overrides[surface] = mesh.surface_get_material(surface) as ShaderMaterial
		if index < model_mesh.texture_tracks.size():
			for track: ModelMesh.TextureTrack in model_mesh.texture_tracks[index]:
				var entry: int = -1
				if index < _current.texture_entries.size() and track.target < _current.texture_entries[index].size():
					entry = _current.texture_entries[index][track.target]
				overrides[track.surface] = track.frames[entry] if entry >= 0 and entry < track.frames.size() else track.original
		for surface: int in overrides:
			var material: ShaderMaterial = _material(overrides[surface])
			if node.get_surface_override_material(surface) != material:
				node.set_surface_override_material(surface, material)
