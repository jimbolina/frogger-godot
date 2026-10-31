class_name MapMesh
extends RefCounted
## Immutable map group geometry, prepared materials, and instance playback.

## Shared source/dependencies; rendering never changes parsed records.
var scene: MapSceneData
var groups: Array[ArrayMesh] = []
var surface_specs: Array[Array] = []
var sky_mesh: ArrayMesh
## One immutable page atlas keeps sky tile drawing in source row-major order.
var sky_atlas: Texture2D
var group_count: int = 0
var triangle_count: int = 0
var surface_count: int = 0
var missing_texture_ids := PackedInt32Array()
var bounds := AABB()
var diagnostics := PackedStringArray()
var linear_filter: bool = false

## One surface's prepared image variants and identity.
class Surface extends RefCounted:
	var animation_index: int = -1
	var polygon_index: int = -1
	var original: ShaderMaterial
	var image: VloImage
	var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
	var layer: int = -1
	var environment: bool = false
	var cave: bool = false
	var textured: bool = false
	var water: bool = false
	var frames: Dictionary[int, ShaderMaterial] = {}


## Creates a node subtree with independent clocks and material parameters.
func create_instance() -> Instance:
	var instance := Instance.new()
	instance.configure(self)
	return instance


## Rendering subtree with no autonomous clock; the viewer calls step/set_tick.
class Instance extends Node3D:
	var source: MapMesh
	var animation := MapAnimationPlayer.new()
	var water := MapWaterState.new()
	var sky := MapSkyState.new()
	var diagnostics := PackedStringArray()
	var tick: int = -1
	var reference_mode: bool = false
	var camera_position: Vector3i = Vector3i.ZERO
	var reference_target: Vector3i = Vector3i.ZERO
	var cave_frog: Vector3i = Vector3i.ZERO
	## Live unsigned squared cave light radii; reconfiguration keeps these values.
	var cave_min_r2: int = 0
	var cave_max_r2: int = 0
	var projection_scale: Vector2 = Vector2.ONE
	var reference_projection: bool = false
	var _nodes: Array[MeshInstance3D] = []
	var _sky_node: MeshInstance3D
	var _material_copies: Dictionary[ShaderMaterial, ShaderMaterial] = {}
	var _selection := PackedInt32Array()
	var _linear_filter: bool = false
	var _show_hidden: bool = false
	var _configured: Dictionary[ShaderMaterial, bool] = {}
	var _animation_values: Dictionary[ShaderMaterial, Vector3i] = {}
	var _camera_materials: Dictionary[ShaderMaterial, bool] = {}
	var _cave_materials: Dictionary[ShaderMaterial, bool] = {}
	var _camera_presentation: Vector3 = Vector3.ZERO
	var _sky_external: bool = false
	var _sky_override: Vector3 = Vector3.ZERO

	## Prepares overrides once; no mesh/material allocation during playback.
	func configure(mesh: MapMesh) -> void:
		source = mesh
		_linear_filter = source.linear_filter
		diagnostics = source.diagnostics.duplicate()
		reference_target = source.scene.midpoint
		cave_frog = _start_position()
		cave_min_r2 = source.scene.cave_min_r2 & 0xffffffff
		cave_max_r2 = source.scene.cave_max_r2 & 0xffffffff
		animation.configure(source.scene.map.polygons, source.scene.map.animations,
			source.scene.remap, source.scene.library, source.scene.preferred)
		water.configure(source.scene.map.vertices, source.scene.map.polygons)
		sky.reset()
		for index: int in source.groups.size():
			var node := MeshInstance3D.new()
			node.name = "Group%d" % index
			node.mesh = source.groups[index]
			_nodes.append(node)
			add_child(node)
			for surface_index: int in source.surface_specs[index].size():
				var spec: Surface = source.surface_specs[index][surface_index]
				_copy_material(spec.original)
				for material: ShaderMaterial in spec.frames.values():
					_copy_material(material)
		if source.sky_mesh != null:
			_sky_node = MeshInstance3D.new()
			_sky_node.name = "SkyLand"
			_sky_node.mesh = source.sky_mesh
			add_child(_sky_node)
			for index: int in source.sky_mesh.get_surface_count():
				var material: ShaderMaterial = source.sky_mesh.surface_get_material(index)
				_sky_node.set_surface_override_material(index, _copy_material(material))
		_update_materials()
		_update_visibility()

	## One deterministic 30 Hz update of all map-only behavior.
	func step() -> void:
		tick += 1
		animation.step()
		water.step()
		if not _sky_external:
			sky.step()
		_update_materials()

	## Seek by restarting clocks; shared geometry/material templates stay unchanged.
	func set_tick(to_tick: int) -> void:
		animation.seek(to_tick)
		water.seek(to_tick)
		if not _sky_external:
			sky.seek(to_tick)
		tick = maxi(-1, to_tick)
		_update_materials()

	## Tick zero includes the first update, matching capture update count one.
	func reset() -> void:
		set_tick(0)

	## Uses the frozen driver's stable nearest128 group cap and disables water.
	func set_reference_mode(value: bool) -> void:
		reference_mode = value
		water.enabled = not value
		water.seek(tick)
		_configured.clear()
		_update_visibility()
		_update_materials()

	## Environment UVs and sky backdrop camera translation use raw game position.
	func set_camera_position(value: Vector3i) -> void:
		camera_position = value
		set_camera_presentation(Vector3(value))

	## Floating source coordinates keep environment UVs and sky on the render timeline.
	func set_camera_presentation(value: Vector3) -> void:
		if _camera_presentation == value:
			return
		_camera_presentation = value
		for material: ShaderMaterial in _camera_materials:
			material.set_shader_parameter("camera_game", value)
		if _sky_node != null:
			_set_sky_position(_sky_translation())

	## Gameplay-committed drift in game units; the internal sky clock stops from now on.
	func set_sky_drift(translation: Vector3) -> void:
		if _sky_external and _sky_override == translation:
			return
		_sky_external = true
		_sky_override = translation
		_refresh_sky_drift()

	## Reference-only C viewport aspect matrix; ordinary cameras keep Vector2.ONE.
	func set_projection_scale(value: Vector2) -> void:
		projection_scale = value
		_configured.clear()
		_update_materials()

	## Exact frozen map-slice integer projection; custom cameras keep this off.
	func set_reference_projection(value: bool) -> void:
		reference_projection = value
		_camera_materials.clear()
		_configured.clear()
		_update_materials()

	## Raw target of the reference group's distance selection (default midpoint).
	func set_reference_target(value: Vector3i) -> void:
		reference_target = value
		_update_visibility()

	## Empty selects every visible group; otherwise selects these group identities.
	func set_group_selection(indices: PackedInt32Array) -> void:
		_selection = indices.duplicate()
		_update_visibility()

	## Optional diagnostic geometry: invisible group and unreferenced polygons.
	func set_inspection_visibility(value: bool) -> void:
		_show_hidden = value
		_update_visibility()

	## Alias for callers using the hidden-polygon inspection control name.
	func set_inspection_hidden(value: bool) -> void:
		set_inspection_visibility(value)

	## Moves the cave terrain lamp independently of models and gameplay entities.
	func set_cave_frog(value: Vector3i) -> void:
		if cave_frog == value:
			return
		cave_frog = value
		for material: ShaderMaterial in _cave_materials:
			material.set_shader_parameter("cave_frog", Vector3(value))

	## Replaces the live squared cave light radii on cave terrain materials only.
	func set_cave_radii(min_r2: int, max_r2: int) -> void:
		var minimum: int = min_r2 & 0xffffffff
		var maximum: int = max_r2 & 0xffffffff
		if cave_min_r2 == minimum and cave_max_r2 == maximum:
			return
		cave_min_r2 = minimum
		cave_max_r2 = maximum
		for material: ShaderMaterial in _cave_materials:
			material.set_shader_parameter("cave_min_r2", float(minimum))
			material.set_shader_parameter("cave_max_r2", float(maximum))

	## Changes cached shader variants; textures and geometry are retained.
	func set_filtering(value: bool) -> void:
		_linear_filter = value
		_configured.clear()
		_update_materials()

	## Currently selected nonempty mesh groups, for diagnostics and reference gates.
	func visible_group_indices() -> PackedInt32Array:
		var found := PackedInt32Array()
		for index: int in _nodes.size():
			if _nodes[index].visible:
				found.append(index)
		return found

	func _copy_material(original: ShaderMaterial) -> ShaderMaterial:
		if not _material_copies.has(original):
			_material_copies[original] = original.duplicate()
		return _material_copies[original]

	func _update_materials() -> void:
		var water_offsets: PackedVector2Array = water.phase_offsets()
		for index: int in source.surface_specs.size():
			for surface_index: int in source.surface_specs[index].size():
				var spec: Surface = source.surface_specs[index][surface_index]
				var template: ShaderMaterial = spec.original
				var image: VloImage = spec.image
				var offset := Vector2i.ZERO
				if spec.animation_index >= 0 and tick >= 0:
					var id: int = animation.track_image_id(spec.animation_index)
					template = spec.frames.get(id, spec.original)
					image = source.scene.library.image_for_id(id, source.scene.preferred) if spec.textured else null
					offset = animation.track_offset(spec.animation_index)
				var material: ShaderMaterial = _material_copies[template]
				if not _configured.has(material):
					var blend: ModelShaders.Blend = spec.blend
					if image != null and spec.blend != ModelShaders.Blend.OPAQUE:
						blend = ModelShaders.blend_for_mode(image.blend_mode())
					material.shader = MapShaders.shader(image != null, blend, _linear_filter, spec.layer >= 0)
					var texture: Texture2D = material.get_shader_parameter("image") if image != null else null
					material.set_shader_parameter("missing_image", spec.textured and (image == null or texture == null))
					material.set_shader_parameter("environment_uv", spec.environment)
					material.set_shader_parameter("camera_game", _camera_presentation)
					if spec.environment or reference_projection:
						_camera_materials[material] = true
					material.set_shader_parameter("projection_scale", projection_scale)
					material.set_shader_parameter("reference_projection", reference_projection)
					material.set_shader_parameter("water_enabled", water.enabled)
					material.set_shader_parameter("cave_enabled", spec.cave)
					material.set_shader_parameter("cave_frog", Vector3(cave_frog))
					if spec.cave:
						_cave_materials[material] = true
					material.set_shader_parameter("cave_min_r2", float(cave_min_r2))
					material.set_shader_parameter("cave_max_r2", float(cave_max_r2))
					_configured[material] = true
				var animated: bool = spec.animation_index >= 0 and tick >= 0
				var animation_value := Vector3i(offset.x, offset.y, int(animated))
				if not _animation_values.has(material) or _animation_values[material] != animation_value:
					material.set_shader_parameter("animated", animated)
					material.set_shader_parameter("animation_offset", Vector2(offset))
					_animation_values[material] = animation_value
				if spec.water:
					material.set_shader_parameter("water_offsets", water_offsets)
				if _nodes[index].get_surface_override_material(surface_index) != material:
					_nodes[index].set_surface_override_material(surface_index, material)
		if _sky_node != null:
			for index: int in source.sky_mesh.get_surface_count():
				var original: ShaderMaterial = source.sky_mesh.surface_get_material(index)
				var material: ShaderMaterial = _material_copies[original]
				if not _configured.has(material):
					material.shader = MapShaders.sky_shader(_linear_filter)
					material.set_shader_parameter("projection_scale", projection_scale)
					material.set_shader_parameter("reference_projection", reference_projection)
					material.set_shader_parameter("sky_backdrop", true)
					_configured[material] = true
			_refresh_sky_drift()

	func _refresh_sky_drift() -> void:
		if _sky_node == null:
			return
		var drift: Vector3 = _sky_translation()
		_set_sky_position(drift)
		for index: int in source.sky_mesh.get_surface_count():
			var original: ShaderMaterial = source.sky_mesh.surface_get_material(index)
			_material_copies[original].set_shader_parameter("sky_drift", drift)

	func _sky_translation() -> Vector3:
		return _sky_override if _sky_external else Vector3(sky.translation())

	func _set_sky_position(drift: Vector3) -> void:
		var position_game: Vector3 = _camera_presentation + drift
		_sky_node.position = Vector3(position_game.x, -position_game.y, -position_game.z) / GameSpace.UNITS_PER_SQUARE

	func _update_visibility() -> void:
		var chosen: PackedInt32Array = _selection
		if reference_mode and chosen.is_empty():
			chosen = _reference_groups()
		for index: int in _nodes.size():
			var visible_group: bool = index < source.scene.map.groups.size() and source.scene.map.groups[index].visible
			var selected: bool = (chosen.is_empty() and not reference_mode) or chosen.has(index)
			_nodes[index].visible = source.groups[index].get_surface_count() > 0 and (
				selected if visible_group else _show_hidden)

	func _reference_groups() -> PackedInt32Array:
		var map: MapFile = source.scene.map
		var indices: Array[int] = []
		for index: int in map.groups.size():
			if map.groups[index].visible:
				indices.append(index)
		if indices.size() > 128:
			indices.sort_custom(func(a: int, b: int) -> bool:
				var distance_a: int = _group_distance(a)
				var distance_b: int = _group_distance(b)
				return a < b if distance_a == distance_b else distance_a < distance_b)
		return reference_budget(map.groups, PackedInt32Array(indices.slice(0, mini(128, indices.size()))))

	## Initial CreateMapGroups allocation (mapdisp.c:962, ExpandMapGroup:388).
	## Entire oversized groups are skipped; later smaller groups may still fit.
	static func reference_budget(map_groups: Array[MapGroup], ordered: PackedInt32Array) -> PackedInt32Array:
		var selected := PackedInt32Array()
		var remaining: int = 2500
		for index: int in ordered:
			if remaining <= 0:
				break
			var total: int = 0
			for type_index: int in mini(8, map_groups[index].counts.size()):
				total += map_groups[index].counts[type_index]
			if total > remaining:
				continue
			selected.append(index)
			remaining -= total
		return selected

	func _group_distance(index: int) -> int:
		var map: MapFile = source.scene.map
		var coordinates: Vector2i = map.groups[index].coordinates
		@warning_ignore("integer_division")
		var x: int = map.group_base.x + coordinates.x * map.group_size.x + map.group_size.x / 2
		@warning_ignore("integer_division")
		var z: int = map.group_base.z + coordinates.y * map.group_size.y + map.group_size.y / 2
		return (x - reference_target.x) * (x - reference_target.x) + (z - reference_target.z) * (z - reference_target.z)

	func _start_position() -> Vector3i:
		var map: MapFile = source.scene.map
		var grid: Vector2i = map.general.start_grid
		return Vector3i(map.group_base.x + grid.x * 256 + 128, 0,
			map.group_base.z + grid.y * 256 + 128)
