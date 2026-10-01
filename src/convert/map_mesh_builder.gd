class_name MapMeshBuilder
extends RefCounted
## Builds each visible map group once; animated targets keep distinct surfaces.

class Collected extends RefCounted:
	var spec: MapMesh.Surface
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var water_ranks := PackedVector2Array()
	var reference_depths := PackedFloat32Array()
	var lines: bool = false

var _material_cache: Dictionary[String, ShaderMaterial] = {}


## Converts immutable parsed maps and texture dependencies to shared geometry.
func build(scene: MapSceneData, linear_filter: bool = false) -> MapMesh:
	var result := MapMesh.new()
	result.scene = scene
	result.linear_filter = linear_filter
	result.diagnostics = scene.diagnostics.duplicate()
	scene.texture_pages.configure(scene.library)
	_material_cache.clear()
	var animation := MapAnimationPlayer.new()
	animation.configure(scene.map.polygons, scene.map.animations, scene.remap, scene.library, scene.preferred)
	result.diagnostics.append_array(animation.diagnostics)
	var water := MapWaterState.new()
	water.configure(scene.map.vertices, scene.map.polygons)
	var ranks: Dictionary[int, int] = {}
	for rank: int in water.vertex_indices.size():
		ranks[water.vertex_indices[rank]] = rank & 31
	var animated: Dictionary[int, int] = {}
	for index: int in scene.map.animations.size():
		for target: int in scene.map.animations[index].target_polygon_indices:
			animated[target] = index
	var missing: Dictionary[int, bool] = {}
	var first: bool = true
	var source_groups: Array[MapGroup] = scene.map.groups.duplicate()
	var referenced: Dictionary[int, bool] = {}
	for group: MapGroup in source_groups:
		for index: int in group.polygon_indices:
			referenced[index] = true
	var unreferenced := MapGroup.new()
	unreferenced.visible = false
	for index: int in scene.map.polygons.size():
		if not referenced.has(index):
			unreferenced.polygon_indices.append(index)
	if not unreferenced.polygon_indices.is_empty():
		source_groups.append(unreferenced)
	for group: MapGroup in source_groups:
		var mesh := ArrayMesh.new()
		var specifications: Array[MapMesh.Surface] = []
		result.groups.append(mesh)
		result.surface_specs.append(specifications)
		if group.visible:
			result.group_count += 1
		var collected: Dictionary[String, Collected] = {}
		var order: Array[String] = []
		for index: int in group.polygon_indices:
			var polygon: MapPolygon = scene.map.polygons[index]
			var track: int = animated.get(index, -1)
			var image: VloImage = scene.image_for_local(polygon.texture_id)
			var environment: bool = (polygon.flags & 2) != 0 and polygon.texture_id >= 0
			if polygon.texture_id >= 0 and image == null:
				missing[scene.remap.global_id(polygon.texture_id)] = true
			var blend: ModelShaders.Blend = ModelShaders.Blend.OPAQUE
			if polygon.flags & 1:
				blend = ModelShaders.blend_for_mode(image.blend_mode() if image != null else 0)
			var layer: int = 2 if environment else (1 if polygon.flags & 4 else -1)
			var cave: bool = scene.cave_enabled and polygon.type_index in [4, 5, 6, 7]
			var key: String = "%d/%d/%d/%s/%s/%s/%s" % [image.texture_id if image != null else -1,
				blend, layer, environment, cave, polygon.type_index == 8, polygon.texture_id >= 0]
			if track >= 0:
				key = "animation/%d" % index
			if not collected.has(key):
				var surface := Collected.new()
				surface.lines = polygon.type_index == 8
				surface.spec = MapMesh.Surface.new()
				surface.spec.image = image
				surface.spec.blend = blend
				surface.spec.layer = layer
				surface.spec.environment = environment
				surface.spec.cave = cave
				surface.spec.textured = polygon.texture_id >= 0
				surface.spec.animation_index = track
				surface.spec.polygon_index = index
				surface.spec.original = _material(scene, image, blend, linear_filter, layer,
					key)
				if surface.spec.textured and image == null:
					surface.spec.original.set_shader_parameter("missing_image", true)
				if track >= 0:
					var source: MapAnimation = scene.map.animations[track]
					var image_ids: PackedInt32Array = source.texture_ids.duplicate()
					for local_id: int in image_ids:
						var global_id: int = scene.remap.global_id(local_id)
						var replacement: VloImage = scene.library.image_for_id(global_id, scene.preferred) if surface.spec.textured else null
						var frame_blend: ModelShaders.Blend = blend
						if replacement != null and blend != ModelShaders.Blend.OPAQUE:
							frame_blend = ModelShaders.blend_for_mode(replacement.blend_mode())
						surface.spec.frames[global_id] = _material(scene, replacement, frame_blend, linear_filter, layer, "%s/%d" % [key, global_id])
					# Before the first threshold C keeps the last target's image.
					var initial_id: int = animation.track_image_id(track)
					var initial_image: VloImage = scene.library.image_for_id(initial_id, scene.preferred) if surface.spec.textured else null
					var initial_blend: ModelShaders.Blend = blend
					if initial_image != null and blend != ModelShaders.Blend.OPAQUE:
						initial_blend = ModelShaders.blend_for_mode(initial_image.blend_mode())
					surface.spec.frames[initial_id] = _material(scene, initial_image, initial_blend, linear_filter, layer, "%s/initial" % key)
				collected[key] = surface
				order.append(key)
			var surface: Collected = collected[key]
			var corners: PackedInt32Array = triangle_corners(polygon.vertex_indices.size())
			if surface.lines:
				corners = PackedInt32Array([0, 1])
			else:
				result.triangle_count += corners.size() / 3
			var base_uv: PackedVector2Array = animation.base_pixel_uvs(index)
			var reference_depths := PackedFloat32Array()
			for vertex_index: int in polygon.vertex_indices:
				reference_depths.append(float(MapReferenceProjection.rotate(scene.map.vertices[vertex_index]).z))
			while reference_depths.size() < 4:
				reference_depths.append(0.0)
			for corner: int in corners:
				var vertex_index: int = polygon.vertex_indices[corner]
				var raw: Vector3i = scene.map.vertices[vertex_index]
				var position: Vector3 = GameSpace.position(raw.x, raw.y, raw.z)
				surface.vertices.append(position)
				result.bounds = AABB(position, Vector3.ZERO) if first else result.bounds.expand(position)
				first = false
				var colour: Color = Color8(128, 128, 128)
				if not polygon.colors.is_empty():
					colour = polygon.colors[mini(corner, polygon.colors.size() - 1)]
				surface.colours.append(colour)
				var uv := Vector2.ZERO
				if corner < base_uv.size():
					uv = base_uv[corner]
				surface.uvs.append(uv)
				var rank: int = ranks.get(vertex_index, -1)
				surface.water_ranks.append(Vector2(rank, polygon.vertex_indices.size()))
				surface.reference_depths.append_array(reference_depths)
		for key: String in order:
			var surface: Collected = collected[key]
			_add_surface(mesh, surface)
			mesh.surface_set_material(mesh.get_surface_count() - 1, surface.spec.original)
			specifications.append(surface.spec)
			result.surface_count += 1
		# Water displacement is small, but culling must include it.
		if mesh.get_surface_count() > 0:
			mesh.custom_aabb = mesh.get_aabb().grow(0.1)
	for id: int in missing:
		result.missing_texture_ids.append(id)
		result.diagnostics.append("Map texture %d is unavailable; rendered magenta" % id)
	result.missing_texture_ids.sort()
	if scene.sky_land != null:
		result.sky_mesh = _build_sky(scene, linear_filter, result)
	result.diagnostics.append_array(scene.texture_pages.diagnostics)
	return result


## Map quads are a strip, unlike the perimeter order of model quads.
static func triangle_corners(count: int) -> PackedInt32Array:
	return PackedInt32Array([0, 1, 2, 1, 3, 2]) if count == 4 else PackedInt32Array([0, 1, 2])


func _material(scene: MapSceneData, image: VloImage, blend: ModelShaders.Blend,
		linear_filter: bool, layer: int, unique: String) -> ShaderMaterial:
	var key: String = "%d/%d/%d/%s" % [image.texture_id if image != null else -1, blend, layer, unique]
	if not _material_cache.has(key):
		_material_cache[key] = MapShaders.material(image, scene.library, blend, linear_filter, layer, scene.texture_pages)
	return _material_cache[key]


func _add_surface(mesh: ArrayMesh, surface: Collected) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface.vertices
	arrays[Mesh.ARRAY_COLOR] = surface.colours
	arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = surface.water_ranks
	arrays[Mesh.ARRAY_CUSTOM0] = surface.reference_depths
	var flags: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if surface.lines else Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)


func _build_sky(scene: MapSceneData, linear_filter: bool, result: MapMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var sky: SkyLandFile = scene.sky_land
	var surface := Collected.new()
	var pages: Dictionary[int, int] = {}
	var tile_images: Array[VloImage] = []
	for local_id: int in sky.texture_ids:
		var image: VloImage = scene.library.image_for_id(scene.sky_remap.global_id(local_id), scene.preferred)
		tile_images.append(image)
		var page: int = image.page() if image != null else -1
		if not pages.has(page):
			pages[page] = pages.size()
	# Each physical page clamps filtering independently; duplicate edge rows.
	var atlas: Image = Image.create(256, 258 * maxi(1, pages.size()), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.MAGENTA)
	for page: int in pages:
		var pixels: Image = scene.texture_pages.image_for_page(page)
		if pixels != null:
			var slot_y: int = pages[page] * 258
			atlas.blit_rect(pixels, Rect2i(0, 0, 256, 256), Vector2i(0, slot_y + 1))
			atlas.blit_rect(pixels, Rect2i(0, 0, 256, 1), Vector2i(0, slot_y))
			atlas.blit_rect(pixels, Rect2i(0, 255, 256, 1), Vector2i(0, slot_y + 257))
	result.sky_atlas = ImageTexture.create_from_image(atlas)
	var material := ShaderMaterial.new()
	material.shader = MapShaders.sky_shader(linear_filter)
	material.set_shader_parameter("image", result.sky_atlas)
	material.set_shader_parameter("pixel_scale", Vector2(1.0 / 256.0, 1.0 / atlas.get_height()))
	material.set_shader_parameter("far_layer", 0.0)
	material.render_priority = -127
	var rotation_orders: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 2, 3]),
		PackedInt32Array([2, 0, 3, 1]), PackedInt32Array([3, 2, 1, 0]), PackedInt32Array([1, 3, 0, 2])]
	var colour: Color = sky_colour(scene.level)
	for tile: int in sky.texture_ids.size():
		var id: int = scene.sky_remap.global_id(sky.texture_ids[tile])
		var image: VloImage = tile_images[tile]
		if image == null:
			result.diagnostics.append("Sky texture %d is unavailable; rendered magenta" % id)
		# RenderSkyLand links every tile in row-major order without depth sorting.
		# Preserve that order: clamped near-camera tiles can overlap on screen.
		@warning_ignore("integer_division")
		var row: int = tile / sky.dimensions.x
		var col: int = tile % sky.dimensions.x
		var x: int = col * 1024 - sky.dimensions.x * 512
		var z: int = row * 1024 - sky.dimensions.y * 512
		var positions: Array[Vector3i] = [Vector3i(x, 6144, z + 1024), Vector3i(x + 1024, 6144, z + 1024),
			Vector3i(x, 6144, z), Vector3i(x + 1024, 6144, z)]
		var pixels: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		if image != null:
			var span: Vector2i = sky_uv_span(image)
			pixels = [Vector2(0, 0), Vector2(span.x, 0), Vector2(0, span.y), Vector2(span.x, span.y)]
		var order: PackedInt32Array = rotation_orders[sky.rotations[tile]]
		var origin: Vector2 = Vector2(image.u, image.v) if image != null else Vector2.ONE
		var atlas_page: int = pages[image.page() if image != null else -1]
		for corner: int in triangle_corners(4):
			var point: Vector3i = positions[corner]
			surface.vertices.append(GameSpace.position(point.x, point.y, point.z))
			surface.colours.append(colour)
			surface.uvs.append(pixels[order[corner]] + origin)
			surface.water_ranks.append(Vector2(atlas_page, 0))
			surface.reference_depths.append_array(PackedFloat32Array([0, 0, 0, 0]))
		result.triangle_count += 2
	_add_surface(mesh, surface)
	mesh.surface_set_material(0, material)
	result.surface_count += 1
	return mesh


## Frozen sky backdrop RGB, indexed by the compiled level numbering.
static func sky_colour(level: int) -> Color:
	match level:
		43:
			return Color8(16, 32, 48)
		44:
			return Color8(112, 96, 64)
		45:
			return Color8(112, 64, 48)
	return Color8(96, 96, 96)

## MR_VRAM.C derives texture-record endpoints from HIT_X/HIT_Y flags.
## Sky polys copy those endpoints; ordinary map UVs use raw image dimensions.
static func sky_uv_span(image: VloImage) -> Vector2i:
	return Vector2i(image.width - (1 if image.has_flag(VloImage.FLAG_HIT_X) else 0),
		image.height - (1 if image.has_flag(VloImage.FLAG_HIT_Y) else 0))
