class_name MapMesh
extends RefCounted
## Immutable map group geometry, prepared materials, and instance playback.

## Shared source/dependencies; rendering never changes parsed records.
var scene: MapSceneData
var groups: Array[ArrayMesh] = []
var surface_specs: Array[Array] = []
## One surface keeps sky tile drawing in source row-major order.
var sky_mesh: ArrayMesh
## The sky's tile images, one layer per sky slot ([MapSkyTiles]); null without a sky.
var sky_tiles: Texture2DArray
var group_count: int = 0
var triangle_count: int = 0
var surface_count: int = 0
var missing_texture_ids := PackedInt32Array()
var bounds := AABB()
var diagnostics := PackedStringArray()
## True when instances start with linear, mipmapped sampling.
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
	## Share of an environment-mapped water surface's colour drawn as emission,
	## so it reads as a partial reflection.
	const WATER_REFLECTION: float = 0.35
	## Blinn specular strength of water surfaces; the highlight's peak adds
	## this times the light colour, which Godot scales by pi.
	const WATER_SPECULAR: float = 0.2
	## Blinn specular exponent of water surfaces, high enough that the
	## highlight on a flat water plane stays a glint rather than a wash.
	const WATER_SHININESS: float = 512.0
	var source: MapMesh
	var animation := MapAnimationPlayer.new()
	var water := MapWaterState.new()
	var sky := MapSkyState.new()
	var diagnostics := PackedStringArray()
	var tick: int = -1
	var projection_scale: Vector2 = Vector2.ONE
	var _nodes: Array[MeshInstance3D] = []
	var _sky_node: MeshInstance3D
	var _material_copies: Dictionary[ShaderMaterial, ShaderMaterial] = {}
	var _selection := PackedInt32Array()
	var _linear_filter: bool = false
	var _show_hidden: bool = false
	var _configured: Dictionary[ShaderMaterial, bool] = {}
	var _animation_values: Dictionary[ShaderMaterial, Vector3i] = {}
	var _camera_materials: Dictionary[ShaderMaterial, bool] = {}
	var _camera_presentation: Vector3 = Vector3.ZERO
	var _sky_external: bool = false
	var _sky_override: Vector3 = Vector3.ZERO
	var _vertex_tint: float = 1.0
	var _water_reflection: float = WATER_REFLECTION
	var _water_specular: float = WATER_SPECULAR
	var _water_shininess: float = WATER_SHININESS
	var _emission_scale: float = 1.0
	var _emissive_materials: Dictionary[ShaderMaterial, EmissiveImage] = {}

	## Prepares overrides once; no mesh/material allocation during playback.
	func configure(mesh: MapMesh) -> void:
		source = mesh
		_linear_filter = source.linear_filter
		diagnostics = source.diagnostics.duplicate()
		animation.configure(source.scene.map.polygons, source.scene.map.animations,
			source.scene.remap, source.scene.library, source.scene.preferred)
		water.configure(source.scene.map.vertices, source.scene.map.polygons)
		sky.reset()
		for index: int in source.groups.size():
			var node := MeshInstance3D.new()
			node.name = "Group%d" % index
			node.mesh = source.groups[index]
			node.layers |= SceneLightingSpec.SHADOW_CASTER_LAYER
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
			_sky_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

	## Clip-space XY scale of the gameplay viewport's aspect; ordinary cameras keep Vector2.ONE.
	func set_projection_scale(value: Vector2) -> void:
		projection_scale = value
		_configured.clear()
		_update_materials()

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

	## Blends the baked vertex shading toward white on every surface except
	## cave Gouraud terrain: 0 ignores the stored colours, 1 applies them fully.
	## Cave terrain stays at 0 because the cave light replaces its stored
	## shading, as in C.
	func set_vertex_tint(value: float) -> void:
		if _vertex_tint == value:
			return
		_vertex_tint = value
		for index: int in source.surface_specs.size():
			for spec: Surface in source.surface_specs[index]:
				if spec.cave:
					continue
				_material_copies[spec.original].set_shader_parameter("vertex_tint", value)
				for frame: ShaderMaterial in spec.frames.values():
					_material_copies[frame].set_shader_parameter("vertex_tint", value)

	## Sets the look of environment-mapped water surfaces: the share of colour
	## drawn as reflection emission and the Blinn specular strength and
	## exponent. Riverbeds are untouched.
	func set_water_look(reflection: float, specular: float, shininess: float) -> void:
		_water_reflection = reflection
		_water_specular = specular
		_water_shininess = shininess
		for index: int in source.surface_specs.size():
			for spec: Surface in source.surface_specs[index]:
				if not spec.environment:
					continue
				_set_water_look(_material_copies[spec.original])
				for frame: ShaderMaterial in spec.frames.values():
					_set_water_look(_material_copies[frame])

	## The water look as [code][reflection, specular, shininess][/code].
	func water_look() -> PackedFloat32Array:
		return PackedFloat32Array([_water_reflection, _water_specular, _water_shininess])

	## Scales the glow of every surface drawing an emissive image
	## ([member MapSceneData.emissive]): each draws its entry's strength times
	## [param value]; 0 turns the glow off.
	func set_emission_scale(value: float) -> void:
		_emission_scale = value
		for material: ShaderMaterial in _emissive_materials:
			_set_emission(material, _emissive_materials[material])

	## The scale [method set_emission_scale] last set (1 by default).
	func emission_scale() -> float:
		return _emission_scale

	## Switches nearest or linear, mipmapped sampling; textures and geometry are retained.
	func set_filtering(value: bool) -> void:
		_linear_filter = value
		_configured.clear()
		_update_materials()

	## Currently selected nonempty mesh groups, for diagnostics and capture counts.
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
					_configure(material, spec, image)
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
					material.set_shader_parameter("linear_filter", _linear_filter)
					material.set_shader_parameter("projection_scale", projection_scale)
					_configured[material] = true
			_refresh_sky_drift()

	func _configure(material: ShaderMaterial, spec: Surface, image: VloImage) -> void:
		var blend: ModelShaders.Blend = spec.blend
		if image != null and spec.blend != ModelShaders.Blend.OPAQUE:
			blend = ModelShaders.blend_for_mode(image.blend_mode())
		material.shader = MapShaders.shader(blend, spec.layer >= 0)
		var texture: Texture2D = material.get_shader_parameter("image_nearest") if image != null else null
		material.set_shader_parameter("missing_image", spec.textured and (image == null or texture == null))
		material.set_shader_parameter("linear_filter", _linear_filter)
		material.set_shader_parameter("environment_uv", spec.environment)
		material.set_shader_parameter("camera_game", _camera_presentation)
		if spec.environment:
			_camera_materials[material] = true
		material.set_shader_parameter("projection_scale", projection_scale)
		material.set_shader_parameter("water_enabled", water.enabled)
		material.set_shader_parameter("vertex_tint", 0.0 if spec.cave else _vertex_tint)
		material.set_shader_parameter("omni_wrap", 1.0 if spec.cave else 0.0)
		if spec.environment:
			_set_water_look(material)
		var glowing: EmissiveImage = source.scene.emissive.get(image.texture_id, null) if image != null else null
		if glowing != null:
			_emissive_materials[material] = glowing
			_set_emission(material, glowing)
		_configured[material] = true

	func _set_water_look(material: ShaderMaterial) -> void:
		material.set_shader_parameter("reflection_emission", _water_reflection)
		material.set_shader_parameter("specular_strength", _water_specular)
		material.set_shader_parameter("shininess", _water_shininess)

	func _set_emission(material: ShaderMaterial, glowing: EmissiveImage) -> void:
		material.set_shader_parameter("emission_strength", glowing.strength * _emission_scale)
		material.set_shader_parameter("emission_colour", glowing.colour)

	func _refresh_sky_drift() -> void:
		if _sky_node == null:
			return
		_set_sky_position(_sky_translation())

	func _sky_translation() -> Vector3:
		return _sky_override if _sky_external else Vector3(sky.translation())

	func _set_sky_position(drift: Vector3) -> void:
		var position_game: Vector3 = _camera_presentation + drift
		_sky_node.position = Vector3(position_game.x, -position_game.y, -position_game.z) / GameSpace.UNITS_PER_SQUARE

	func _update_visibility() -> void:
		for index: int in _nodes.size():
			var visible_group: bool = index < source.scene.map.groups.size() and source.scene.map.groups[index].visible
			var selected: bool = _selection.is_empty() or _selection.has(index)
			_nodes[index].visible = source.groups[index].get_surface_count() > 0 and (
				selected if visible_group else _show_hidden)
