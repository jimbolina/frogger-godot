class_name AnimatedModelInstance
extends Node3D
## Draws a player's integer pose with reusable meshes and optional motion interpolation.
## The owner advances the player at the game tick rate, then renders between ticks.
##
## A mesh drawn through the lit shaders of the modern rendering profile
## ([method ModelShaders.is_lit]) is shaded by the scene's lights: its parts
## join [constant SceneLightingSpec.SHADOW_CASTER_LAYER], and colour scaling
## and custom ambient reach it as a [SceneTint] in instance uniforms, so it
## shares its materials and only flipbook parts get per-instance copies.

## Unlit tint baseline: the options-screen ambient and parallel light bytes, summing to 4096 after the << 4.
const TINT_AMBIENT: float = 0x60
const TINT_PARALLEL: float = 0xA0

## The player supplying transforms, flipbook cels and texture entries.
var player: ModelAnimationPlayer
## Resources built once for this instance.
var model_mesh: ModelMesh
## One node per part, including parts without geometry.
var part_nodes: Array[MeshInstance3D] = []
## The tint of a lit mesh's last [method set_source_lighting] or [method set_tint];
## identity for a mesh on the retail shaders.
var scene_tint: SceneTint = SceneTint.new()
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
var _changed_blends: Array[PackedInt32Array] = []
var _has_texture_tracks: bool = false
var _sampled_frame: int = -1
var _sampled_action: int = -1
var _geometry_constant: bool = true
var _rendered_weight: float = -1.0
var _tinted: bool = false
var _tint_light: Vector3 = Vector3.ZERO
var _tint_flags: int = 0
var _tint_scale: Vector3i = Vector3i.ZERO
var _tint_ambient: Vector3i = Vector3i.ZERO
var _part_scales: Dictionary[int, float] = {}
var _scene_lit: bool = false
var _scene_tint_inputs: Array = []


## Attaches prebuilt resources and samples the player's current state.
func setup(mesh: ModelMesh, animation_player: ModelAnimationPlayer) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for node: MeshInstance3D in part_nodes:
		remove_child(node)
		node.queue_free()
	part_nodes.clear()
	_blend_values.clear()
	_changed_blends.clear()
	_materials.clear()
	_rendered_weight = -1.0
	_lighting = null
	_tinted = false
	_tint_flags = 0
	_part_scales.clear()
	scene_tint = SceneTint.new()
	_scene_tint_inputs = [Vector3i.ZERO, Vector3i.ZERO, false, false]
	_scene_lit = has_lit_materials(mesh)
	model_mesh = mesh
	if mesh.morph_meshes.is_empty():
		mesh.morph_meshes.resize(mesh.part_meshes.size())
	player = animation_player
	_has_texture_tracks = false
	for tracks: Array in mesh.texture_tracks:
		_has_texture_tracks = _has_texture_tracks or not tracks.is_empty()
	for index: int in mesh.part_meshes.size():
		var node := MeshInstance3D.new()
		node.name = "Part%d" % index
		node.mesh = mesh.morph_meshes[index].mesh if mesh.morph_meshes[index] != null else mesh.part_meshes[index]
		if index < mesh.part_bounds.size():
			node.custom_aabb = mesh.part_bounds[index]
		if _scene_lit:
			node.layers |= SceneLightingSpec.SHADOW_CASTER_LAYER
		add_child(node)
		part_nodes.append(node)
		var values := PackedFloat32Array()
		values.resize(mesh.part_meshes[index].get_blend_shape_count() if mesh.part_meshes[index] != null else 0)
		_blend_values.append(values)
		_changed_blends.append(PackedInt32Array())
	apply_exact()

## True when [param mesh] draws any surface through a lit model shader.
static func has_lit_materials(mesh: ModelMesh) -> bool:
	if mesh == null:
		return false
	for part: ArrayMesh in mesh.part_meshes:
		if part == null:
			continue
		for surface: int in part.get_surface_count():
			var material: ShaderMaterial = part.surface_get_material(surface) as ShaderMaterial
			if material != null and ModelShaders.is_lit(material.shader):
				return true
	return false


## Applies source colour-matrix scaling and custom ambient to instance-local materials.
##
## A lit mesh ignores [param lighting]'s directions and colours, which the
## scene's lights stand in for, and takes the scale and ambient as its
## [member scene_tint].
func set_source_lighting(lighting: MapLighting, scale: Vector3i, ambient: Vector3i, scaled: bool, custom: bool) -> void:
	if _scene_lit:
		_set_scene_tint(scale, ambient, scaled, custom)
		return
	if _lighting == lighting and _colour_scale == scale and _ambient == ambient and _scaled == scaled and _custom == custom and _lighting_ambient == lighting.ambient and _lighting_directions == lighting.directions and _lighting_colours == lighting.colours:
		return
	var first_lighting: bool = _lighting == null
	var directions_changed: bool = first_lighting or _lighting_directions != lighting.directions
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
	var source_ambient: Vector3 = (base * multiplier).floor() * 16.0
	var ambient_changed: bool = first_lighting or source_ambient != _source_ambient
	_source_ambient = source_ambient
	var source_colours: Array[Vector3] = []
	for colour: Vector3 in lighting.colours:
		source_colours.append((colour * multiplier).floor())
	var colours_changed: bool = first_lighting or source_colours != _source_colours
	_source_colours = source_colours
	if first_lighting:
		_prepare_materials()
	for original: ShaderMaterial in _materials:
		_update_lighting(_materials[original], original, first_lighting, directions_changed, ambient_changed, colours_changed)
	if first_lighting:
		refresh_materials()

## Applies committed source mesh colour scaling and custom ambient to an otherwise unlit model.
##
## [param flags] holds [constant FrogTint.CUSTOM_AMBIENT] and
## [constant FrogTint.SCALED_COLOURS]. Without either flag the model draws
## exactly as before: its own polygon colours. With them, instance-local
## materials light every vertex by [method tint_light], an approximation that
## keeps the directional map lights off; it is meant for models drawn without
## [method set_source_lighting]. A lit mesh takes them as its [member scene_tint].
func set_tint(scale: Vector3i, ambient: Vector3i, flags: int) -> void:
	flags &= FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS
	if _scene_lit:
		_set_scene_tint(scale, ambient, (flags & FrogTint.SCALED_COLOURS) != 0, (flags & FrogTint.CUSTOM_AMBIENT) != 0)
		return
	if flags == 0 and not _tinted:
		return
	if flags == _tint_flags and scale == _tint_scale and ambient == _tint_ambient and _tinted:
		return
	_tint_flags = flags
	_tint_scale = scale
	_tint_ambient = ambient
	_tint_light = tint_light(scale, ambient, flags)
	if not _tinted:
		_tinted = true
		_prepare_materials()
		for original: ShaderMaterial in _materials:
			_apply_tint(_materials[original])
		refresh_materials()
		return
	for original: ShaderMaterial in _materials:
		_apply_tint(_materials[original])


## Per-channel light, 4096 being unlit, for a tint of [param scale] and
## [param ambient] bytes under [param flags]. The unlit model is taken as the
## options-screen split of ambient 0x60 plus one parallel light 0xA0 (together
## 4096); a custom ambient replaces the 0x60 part, and a colour scale
## multiplies both by scale / 128, as the source colour matrix does.
static func tint_light(scale: Vector3i, ambient: Vector3i, flags: int) -> Vector3:
	if flags & (FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS) == 0:
		return Vector3(4096.0, 4096.0, 4096.0)
	var multiplier: Vector3 = Vector3(scale) / 128.0 if flags & FrogTint.SCALED_COLOURS else Vector3.ONE
	var base: Vector3 = Vector3(ambient) if flags & FrogTint.CUSTOM_AMBIENT else Vector3(TINT_AMBIENT, TINT_AMBIENT, TINT_AMBIENT)
	var parallel := Vector3(TINT_PARALLEL, TINT_PARALLEL, TINT_PARALLEL)
	return ((base * multiplier).floor() + (parallel * multiplier).floor()) * 16.0


## Scales part [param part] by [param scale] in its own space after its pose, as a source imported part transform does.
func set_part_scale(part: int, scale: float) -> void:
	if _part_scales.get(part, 1.0) == scale and (_part_scales.has(part) or scale == 1.0):
		return
	_part_scales[part] = scale
	_rendered_weight = -1.0


## Removes every part scale override.
func clear_part_scales() -> void:
	if _part_scales.is_empty():
		return
	_part_scales.clear()
	_rendered_weight = -1.0


func _set_scene_tint(scale: Vector3i, ambient: Vector3i, scaled: bool, custom: bool) -> void:
	var inputs: Array = [scale if scaled else Vector3i.ZERO, ambient if custom else Vector3i.ZERO, scaled, custom]
	if inputs == _scene_tint_inputs:
		return
	_scene_tint_inputs = inputs
	scene_tint = SceneTint.of(scale, ambient, scaled, custom)
	for node: MeshInstance3D in part_nodes:
		node.set_instance_shader_parameter(ModelShaders.TINT_SCALE, scene_tint.scale)
		node.set_instance_shader_parameter(ModelShaders.TINT_AMBIENT, scene_tint.ambient)


func _apply_tint(material: ShaderMaterial) -> void:
	material.set_shader_parameter("source_lighting", _tint_flags != 0)
	material.set_shader_parameter("source_ambient", _tint_light)
	for index: int in 3:
		material.set_shader_parameter("source_colour%d" % index, Vector3.ZERO)


func _prepare_materials() -> void:
	for mesh: ArrayMesh in model_mesh.part_meshes:
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				_prepare_material(mesh.surface_get_material(surface) as ShaderMaterial)
	for tracks: Array in model_mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			_prepare_material(track.original)
			for material: ShaderMaterial in track.frames:
				_prepare_material(material)

func _prepare_material(original: ShaderMaterial) -> void:
	if original != null and not _materials.has(original):
		_materials[original] = original.duplicate() as ShaderMaterial

func _material(original: ShaderMaterial, local: bool = false) -> ShaderMaterial:
	if (_lighting == null and not _tinted and not local) or original == null:
		return original
	if not _materials.has(original):
		_materials[original] = original.duplicate() as ShaderMaterial
		if _lighting != null:
			_update_lighting(_materials[original], original)
		elif _tinted:
			_apply_tint(_materials[original])
	var projection: Variant = original.get_shader_parameter("projection_scale")
	if _materials[original].get_shader_parameter("projection_scale") != projection:
		_materials[original].set_shader_parameter("projection_scale", projection)
	return _materials[original]

func _update_lighting(material: ShaderMaterial, original: ShaderMaterial, initialize: bool = true, directions_changed: bool = true, ambient_changed: bool = true, colours_changed: bool = true) -> void:
	if initialize:
		material.set_shader_parameter("projection_scale", original.get_shader_parameter("projection_scale"))
		material.set_shader_parameter("source_lighting", true)
	if ambient_changed:
		material.set_shader_parameter("source_ambient", _source_ambient)
	for index: int in 3:
		if directions_changed:
			material.set_shader_parameter("source_direction%d" % index, _lighting.directions[index] if index < _lighting.directions.size() else Vector3.ZERO)
		if colours_changed:
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
	if _current != null and not _has_texture_tracks and player.revision == _revision and player.frame == _sampled_frame and player.action_index == _sampled_action:
		_current.visible = player.visible
	else:
		_current = player.sample_pose()
	var textures_changed: bool = _previous == null or _current.texture_entries != _previous.texture_entries
	if collapse or player.wrapped or player.revision != _revision or _previous == null:
		_previous = _current
	_revision = player.revision
	_sampled_frame = player.frame
	_sampled_action = player.action_index
	_geometry_constant = _previous.transforms == _current.transforms and _previous.partcels == _current.partcels
	_rendered_weight = -1.0
	_prepare_blends()
	if textures_changed:
		refresh_materials(true)


## Resets interpolation after a seek, action change, pause, step or restart.
func apply_exact() -> void:
	if player == null:
		return
	_current = player.sample_pose()
	_previous = _current
	_revision = player.revision
	_sampled_frame = player.frame
	_sampled_action = player.action_index
	_geometry_constant = true
	_rendered_weight = -1.0
	_prepare_blends()
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
	if _rendered_weight >= 0.0 and (_geometry_constant or weight == _rendered_weight):
		return
	_rendered_weight = weight
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
			node.transform = Transform3D(Basis(before.basis.x.lerp(now.basis.x, weight),
				before.basis.y.lerp(now.basis.y, weight), before.basis.z.lerp(now.basis.z, weight)), before.origin.lerp(now.origin, weight))
		else:
			node.transform = before.interpolate_with(now, weight)
		if _part_scales.has(index):
			var posed: Transform3D = node.transform
			node.transform = Transform3D(posed.basis * Basis.from_scale(Vector3.ONE * _part_scales[index]), posed.origin)
		if node.mesh != null:
			var current_cel: int = _current.partcels[index] if index < _current.partcels.size() else 0
			var previous_cel: int = _previous.partcels[index] if _previous != null and index < _previous.partcels.size() else current_cel
			for blend: int in _changed_blends[index]:
				var amount: float = (weight if current_cel == blend + 1 else 0.0) + (1.0 - weight if previous_cel == blend + 1 else 0.0)
				if _blend_values[index][blend] != amount:
					if model_mesh.morph_meshes[index] == null:
						node.set_blend_shape_value(blend, amount)
					_blend_values[index][blend] = amount

			if model_mesh.morph_meshes[index] != null:
				for surface: int in node.mesh.get_surface_count():
					var material := node.get_surface_override_material(surface) as ShaderMaterial
					_set_cel_pose(material, previous_cel, current_cel, weight)

func _set_cel_pose(material: ShaderMaterial, previous_cel: int, current_cel: int, weight: float) -> void:
	material.set_shader_parameter("cel_pair", Vector2i(previous_cel, current_cel))
	material.set_shader_parameter("cel_weight", weight)

func _prepare_blends() -> void:
	for index: int in part_nodes.size():
		var current_cel: int = _current.partcels[index] if index < _current.partcels.size() else 0
		var previous_cel: int = _previous.partcels[index] if _previous != null and index < _previous.partcels.size() else current_cel
		var active := PackedInt32Array()
		for cel: int in [current_cel, previous_cel]:
			if cel > 0 and cel <= _blend_values[index].size() and not active.has(cel - 1):
				active.append(cel - 1)
		for blend: int in _changed_blends[index]:
			if _blend_values[index][blend] != 0.0 and not active.has(blend):
				active.append(blend)
		_changed_blends[index] = active

## Refreshes bindings; tick-only texture changes leave static bindings and projection alone.
func refresh_materials(textures_only: bool = false) -> void:
	if _current == null:
		return
	for index: int in part_nodes.size():
		var node: MeshInstance3D = part_nodes[index]
		var mesh: ArrayMesh = node.mesh as ArrayMesh
		if mesh == null:
			continue
		var overrides: Dictionary[int, ShaderMaterial] = {}
		if (_lighting != null or _tinted or model_mesh.morph_meshes[index] != null) and not textures_only:
			for surface: int in mesh.get_surface_count():
				overrides[surface] = mesh.surface_get_material(surface) as ShaderMaterial
		if index < model_mesh.texture_tracks.size():
			for track: ModelMesh.TextureTrack in model_mesh.texture_tracks[index]:
				var entry: int = -1
				if index < _current.texture_entries.size() and track.target < _current.texture_entries[index].size():
					entry = _current.texture_entries[index][track.target]
				overrides[track.surface] = track.frames[entry] if entry >= 0 and entry < track.frames.size() else track.original
		for surface: int in overrides:
			if textures_only and node.get_surface_override_material(surface) == _materials.get(overrides[surface], overrides[surface]):
				continue
			var morph: ModelMorphMesh = model_mesh.morph_meshes[index]
			var material: ShaderMaterial = _material(overrides[surface], morph != null)
			if morph != null:
				material.set_shader_parameter("cel_enabled", true)
				material.set_shader_parameter("cel_texture", morph.textures[surface])
				material.set_shader_parameter("cel_vertex_count", morph.vertex_counts[surface])
				var now: int = _current.partcels[index] if index < _current.partcels.size() else 0
				var before: int = _previous.partcels[index] if _previous != null and index < _previous.partcels.size() else now
				_set_cel_pose(material, before, now, maxf(0.0, _rendered_weight))
			if node.get_surface_override_material(surface) != material:
				node.set_surface_override_material(surface, material)
