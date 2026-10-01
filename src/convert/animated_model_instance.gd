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


## Attaches prebuilt resources and samples the player's current state.
func setup(mesh: ModelMesh, animation_player: ModelAnimationPlayer) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for node: MeshInstance3D in part_nodes:
		remove_child(node)
		node.queue_free()
	part_nodes.clear()
	model_mesh = mesh
	player = animation_player
	for index: int in mesh.part_meshes.size():
		var node := MeshInstance3D.new()
		node.name = "Part%d" % index
		node.mesh = mesh.part_meshes[index]
		if index < mesh.part_bounds.size():
			node.custom_aabb = mesh.part_bounds[index]
		add_child(node)
		part_nodes.append(node)
	apply_exact()


## Advances one integer game tick and retains the previous sample for drawing.
func advance_tick() -> void:
	if player == null:
		return
	_previous = _current
	player.advance_tick()
	_current = player.sample_pose()
	if player.wrapped or player.revision != _revision or _previous == null:
		_previous = _current
	_revision = player.revision
	render(1.0 if not smoothing_enabled else 0.0)


## Resets interpolation after a seek, action change, pause, step or restart.
func apply_exact() -> void:
	if player == null:
		return
	_current = player.sample_pose()
	_previous = _current
	_revision = player.revision
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
	for index: int in part_nodes.size():
		var node: MeshInstance3D = part_nodes[index]
		var now: Transform3D = _current.transforms[index] if index < _current.transforms.size() else Transform3D.IDENTITY
		var before: Transform3D = _previous.transforms[index] if _previous != null and index < _previous.transforms.size() else now
		if weight == 0.0:
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
			for blend: int in mesh.get_blend_shape_count():
				var amount: float = (weight if current_cel == blend + 1 else 0.0) + (1.0 - weight if previous_cel == blend + 1 else 0.0)
				node.set_blend_shape_value(blend, amount)
		if index >= model_mesh.texture_tracks.size():
			continue
		for track: ModelMesh.TextureTrack in model_mesh.texture_tracks[index]:
			var entry: int = -1
			if index < _current.texture_entries.size() and track.target < _current.texture_entries[index].size():
				entry = _current.texture_entries[index][track.target]
			node.set_surface_override_material(track.surface, track.frames[entry] if entry >= 0 and entry < track.frames.size() else track.original)
