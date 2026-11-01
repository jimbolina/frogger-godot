extends GutTest
## Lava emission: surfaces drawing an emissive image glow with its colour and
## strength times the live scale, frame by frame on animated tracks.

const GLOWING_ID: int = 101
const STRENGTH: float = 1.5
const COLOUR: Color = Color(1.0, 0.6, 0.4)


func test_only_the_emissive_image_glows() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_scene())
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	var glowing: ShaderMaterial = _material(built, instance, 1)
	assert_eq(_float(glowing, "emission_strength"), STRENGTH)
	assert_eq(_colour(glowing), COLOUR)
	var plain: ShaderMaterial = _material(built, instance, 0)
	assert_true(_unset(plain, "emission_strength"), "a plain surface keeps the shader's zero strength")
	assert_true(_unset(plain, "emission_colour"))
	assert_eq(instance.emission_scale(), 1.0)
	instance.free()


func test_an_animated_track_glows_only_on_the_emissive_frame() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_animated_scene())
	var instance: MapMesh.Instance = built.create_instance()
	var seen: Dictionary[int, bool] = {}
	for tick: int in 4:
		instance.set_tick(tick)
		var id: int = instance.animation.track_image_id(0)
		seen[id] = true
		var material: ShaderMaterial = _material(built, instance, 2)
		if id == GLOWING_ID:
			assert_eq(_float(material, "emission_strength"), STRENGTH, "tick %d" % tick)
		else:
			assert_true(_unset(material, "emission_strength"), "tick %d" % tick)
	assert_eq(seen.size(), 2, "both frames were shown")
	instance.free()


func test_the_scale_updates_every_emissive_material_live() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_animated_scene())
	var instance: MapMesh.Instance = built.create_instance()
	var glowing_tick: int = -1
	var plain_tick: int = -1
	for tick: int in 4:
		instance.set_tick(tick)
		if instance.animation.track_image_id(0) == GLOWING_ID:
			glowing_tick = tick
		else:
			plain_tick = tick
	instance.set_tick(plain_tick)
	instance.set_emission_scale(2.0)
	assert_eq(instance.emission_scale(), 2.0)
	assert_eq(_float(_material(built, instance, 1), "emission_strength"), STRENGTH * 2.0)
	instance.set_tick(glowing_tick)
	assert_eq(_float(_material(built, instance, 2), "emission_strength"), STRENGTH * 2.0,
		"the frame configured earlier followed while it was inactive")
	instance.set_emission_scale(0.0)
	assert_eq(_float(_material(built, instance, 1), "emission_strength"), 0.0)
	assert_true(_unset(_material(built, instance, 0), "emission_strength"))
	instance.free()


func test_the_glow_survives_reconfiguration() -> void:
	var built: MapMesh = MapMeshBuilder.new().build(_scene())
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	instance.set_emission_scale(0.5)
	instance.set_projection_scale(Vector2(1.0, 0.75))
	assert_eq(_float(_material(built, instance, 1), "emission_strength"), STRENGTH * 0.5)
	instance.set_filtering(true)
	var glowing: ShaderMaterial = _material(built, instance, 1)
	assert_eq(_float(glowing, "emission_strength"), STRENGTH * 0.5)
	assert_eq(_colour(glowing), COLOUR)
	assert_true(_unset(_material(built, instance, 0), "emission_strength"))
	instance.free()


func test_a_scene_without_emissive_images_never_sets_the_glow() -> void:
	var scene: MapSceneData = _scene()
	scene.emissive = {}
	var built: MapMesh = MapMeshBuilder.new().build(scene)
	var instance: MapMesh.Instance = built.create_instance()
	instance.set_tick(0)
	instance.set_emission_scale(3.0)
	for polygon: int in 2:
		assert_true(_unset(_material(built, instance, polygon), "emission_strength"), "polygon %d" % polygon)
	instance.free()


func test_include_adds_the_glow_as_emission() -> void:
	var include: String = FileAccess.get_file_as_string(MapShaders.INCLUDE_PATH)
	assert_string_contains(include, "uniform float emission_strength = 0.0;")
	assert_string_contains(include, "uniform vec3 emission_colour : source_color = vec3(1.0);")
	assert_string_contains(include, "vec3 glow = (textured ? texel.rgb : to_linear(COLOR.rgb)) * emission_colour * emission_strength;")
	assert_string_contains(include, "EMISSION += glow;")
	assert_lt(include.find("EMISSION += glow;"), include.find("EMISSION = vec3(1.0, 0.0, 1.0);"),
		"a missing image still shows plain magenta")


func test_resolve_keys_entries_by_texture_id_and_reports_unknown_names() -> void:
	var names := NameBank.new()
	names.names_by_id = {297: "vol_lavani1", 224: "vol_lava6"}
	var table := EmissiveImageTable.new()
	table.entries = [_entry("VOL_LAVA6"), _entry("vol_lavani1"), _entry("vol_nothing")]
	var diagnostics := PackedStringArray()
	var found: Dictionary[int, EmissiveImage] = EmissiveSurfaces.resolve(table, names, diagnostics)
	assert_eq(found.keys(), [224, 297])
	assert_eq(found[224], table.entries[0])
	assert_eq(found[297], table.entries[1])
	assert_eq(diagnostics, PackedStringArray(["Emissive image vol_nothing is not in the image names; it does not glow"]))
	assert_eq(EmissiveSurfaces.resolve(EmissiveImageTable.new(), names, diagnostics).size(), 0)
	assert_eq(EmissiveSurfaces.resolve(null, names, diagnostics).size(), 0)
	assert_eq(EmissiveSurfaces.resolve(table, null, diagnostics).size(), 0)
	assert_eq(diagnostics.size(), 2)


func _material(built: MapMesh, instance: MapMesh.Instance, polygon: int) -> ShaderMaterial:
	var node: MeshInstance3D = instance.get_child(0)
	return node.get_surface_override_material(built.surface_specs[0].find(_surface(built, polygon)))


func _surface(built: MapMesh, polygon: int) -> MapMesh.Surface:
	for spec: MapMesh.Surface in built.surface_specs[0]:
		if spec.polygon_index == polygon:
			return spec
	return null


func _float(material: ShaderMaterial, parameter: String) -> float:
	return material.get_shader_parameter(parameter)


func _colour(material: ShaderMaterial) -> Color:
	return material.get_shader_parameter("emission_colour")


func _unset(material: ShaderMaterial, parameter: String) -> bool:
	return typeof(material.get_shader_parameter(parameter)) == TYPE_NIL


func _entry(image_name: String) -> EmissiveImage:
	var entry := EmissiveImage.new()
	entry.image_name = image_name
	entry.colour = COLOUR
	entry.strength = STRENGTH
	return entry


func _animated_scene() -> MapSceneData:
	var scene: MapSceneData = _scene()
	scene.map.polygons.append(_quad(0))
	scene.map.groups[0].polygon_indices.append(2)
	var track := MapAnimation.new()
	track.type = 2
	track.frames_per_texture = 1
	track.texture_ids = PackedInt32Array([0, 1])
	track.target_polygon_indices = PackedInt32Array([2])
	scene.map.animations.append(track)
	return scene


func _scene() -> MapSceneData:
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.vertices = [Vector3i(0, 0, 256), Vector3i(256, 0, 256),
		Vector3i(0, 0, 0), Vector3i(256, 0, 0)]
	scene.map.group_size = Vector2i(256, 256)
	scene.map.polygons.append_array([_quad(0), _quad(1)])
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0, 1])
	scene.map.groups.append(group)
	var pixels: Array[int] = []
	for _index: int in 10 * 6:
		pixels.append_array([200, 120, 40])
	var plain: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, 100, 0, SyntheticVlo.abgr(pixels))
	var lava: SyntheticVlo.Spec = SyntheticVlo.spec(8, 4, 2, GLOWING_ID, 0, SyntheticVlo.abgr(pixels))
	lava.vram_y = 256
	scene.preferred = SyntheticVlo.bank([plain, lava])
	scene.library.add_bank(scene.preferred)
	scene.remap = TextureRemap.new()
	scene.remap.texture_ids = PackedInt32Array([100, GLOWING_ID])
	scene.emissive = {GLOWING_ID: _entry("vol_lava6")}
	return scene


func _quad(texture: int) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	polygon.texture_id = texture
	polygon.visible = true
	return polygon
