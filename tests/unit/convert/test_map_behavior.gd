extends GutTest
## Synthetic C map clocks, water displacement, and model/cave lighting.


func _polygon(kind: int, flags: int, vertices: Array[int]) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = kind
	polygon.flags = flags
	polygon.vertex_indices = PackedInt32Array(vertices)
	return polygon


func _light(kind: int, colour: Color, direction: Vector3i = Vector3i.ZERO) -> MapLight:
	var light := MapLight.new()
	light.light_type = kind
	light.color = colour
	light.direction = direction
	light.enabled = true
	return light


func test_model_lighting_world_normal_and_negative_dot() -> void:
	var lighting := MapLighting.new()
	lighting.configure([_light(1, Color8(64, 64, 64)), _light(2, Color8(128, 64, 32), Vector3i(4096, 0, 0))])
	var base := Color8(128, 128, 128)
	assert_eq(lighting.shade(base, Vector3.RIGHT), Color8(96, 64, 48))
	assert_eq(lighting.shade(base, Vector3.LEFT), Color8(32, 32, 32))
	assert_eq(lighting.shade(base, Vector3.UP, Basis(Vector3.BACK, -PI / 2.0)), Color8(96, 64, 48))


func test_only_last_three_parallel_lights_and_ambient_sum() -> void:
	var lighting := MapLighting.new()
	lighting.configure([_light(2, Color8(200, 0, 0), Vector3i(1, 0, 0)),
		_light(2, Color8(0, 16, 0), Vector3i(1, 0, 0)),
		_light(2, Color8(0, 16, 0), Vector3i(1, 0, 0)),
		_light(2, Color8(0, 16, 0), Vector3i(1, 0, 0)),
		_light(4, Color.WHITE), _light(8, Color.WHITE),
		_light(1, Color8(16, 0, 0)), _light(1, Color8(16, 0, 0))])
	assert_eq(lighting.directions.size(), 3)
	assert_eq(lighting.shade(Color8(128, 128, 128), Vector3.RIGHT), Color8(16, 24, 0))


func test_cave_grey_replaces_authored_colour_and_initial_radii() -> void:
	assert_eq(MapLighting.cave_colour(Vector3i.ZERO, Vector3i.ZERO, 0, 65536), Color8(128, 128, 128))
	assert_eq(MapLighting.cave_colour(Vector3i(128, 0, 0), Vector3i.ZERO, 0, 65536), Color8(96, 96, 96))
	assert_eq(MapLighting.cave_colour(Vector3i(257, 0, 0), Vector3i.ZERO, 0, 65536), Color.BLACK)
	assert_eq(MapLighting.initial_cave_radii(1), PackedInt64Array([1, 65536]))
	assert_eq(MapLighting.initial_cave_radii(2), PackedInt64Array([1, 262144]))
	assert_eq(MapLighting.initial_cave_radii(8), PackedInt64Array([3145728, 4194304]))
	assert_eq(MapLighting.initial_cave_radii(182), PackedInt64Array([2169765888, 2170814464]))
	assert_eq(MapLighting.initial_cave_radii(256), PackedInt64Array([1, 0]))


func test_parallel_direction_normalization_quantizes_to_c_fixed_point() -> void:
	var lighting := MapLighting.new()
	lighting.configure([_light(2, Color.WHITE, Vector3i(1, 1, 1))])
	assert_eq(lighting.directions[0], Vector3(2365, -2365, -2365) / 4096.0)
	assert_ne(lighting.directions[0].length(), 1.0, "C normalization rounds each component")
	lighting.configure([_light(2, Color.WHITE, Vector3i.ZERO)])
	assert_eq(lighting.directions[0], Vector3.ZERO)


func test_ambient_registration_wraps_colour_bytes() -> void:
	var lighting := MapLighting.new()
	lighting.configure([_light(1, Color8(200, 200, 200)), _light(1, Color8(100, 100, 100))])
	assert_eq(lighting.shade(Color8(128, 128, 128), Vector3.UP), Color8(22, 22, 22))


func test_water_unique_encounter_order_threshold_reset_seek() -> void:
	var source: Array[Vector3i] = [Vector3i(0, 100, 0), Vector3i(0, 151, 0), Vector3i(20, 150, 0), Vector3i(30, 200, 40)]
	var polygons: Array[MapPolygon] = [_polygon(3, 2, [0, 0, 0, 0]),
		_polygon(3, 4, [3, 1, 2, 3]), _polygon(7, 4, [1, 3, 2, 1])]
	var water := MapWaterState.new()
	water.configure(source, polygons)
	assert_eq(water.vertex_indices, PackedInt32Array([3, 1]))
	water.step()
	var snapshot: Array[Vector3i] = water.vertices()
	assert_eq(snapshot[3], Vector3i(31, 200, 39))
	assert_eq(snapshot[1], Vector3i(2, 151, 0))
	assert_eq(source[3], Vector3i(30, 200, 40), "source is immutable")
	water.seek(63)
	assert_eq(water.vertices(), source, "differential table closes after 64 ticks")
	water.seek(0)
	assert_eq(water.vertices(), snapshot)
	water.reset()
	assert_eq(water.vertices(), source)
	water.enabled = false
	water.seek(20)
	assert_eq(water.vertices(), source, "map slice disables water")
	water.configure(source, polygons, 3)
	assert_eq(water.vertex_indices.size(), 0)


func _animation_fixture() -> Dictionary:
	var remap := TextureRemap.new()
	remap.texture_ids = PackedInt32Array([100, 101, 102])
	var bank := VloFile.new()
	for id: int in [100, 101, 102]:
		var image := VloImage.new()
		image.texture_id = id
		image.width = 64 if id == 100 else 32
		image.height = 32
		image.u = 250 if id == 101 else 0
		image.v = 0
		bank.images.append(image)
	var library := TextureLibrary.new()
	library.add_bank(bank)
	var polygon := MapPolygon.new()
	polygon.texture_id = 0
	polygon.uvs = PackedVector2Array([Vector2(1, 1), Vector2.ZERO])
	var animation := MapAnimation.new()
	animation.type = 3
	animation.delta_u = 255
	animation.delta_v = 0
	animation.uv_frame_count = 3
	animation.frames_per_texture = 2
	animation.texture_ids = PackedInt32Array([1, 2])
	animation.target_polygon_indices = PackedInt32Array([0])
	var player := MapAnimationPlayer.new()
	player.configure([polygon], [animation], remap, library)
	return {"player": player, "source": animation, "polygon": polygon,
		"remap": remap, "library": library}


func test_animation_paired_delta_reset_period_and_initial_image() -> void:
	var fixture: Dictionary = _animation_fixture()
	var player: MapAnimationPlayer = fixture.player
	var source: MapAnimation = fixture.source
	assert_eq(player.image_id(0), 100, "load uses original target, not cel zero")
	assert_eq(player.base_pixel_uvs(0)[0], Vector2(64, 32))
	player.step()
	assert_eq(player.track_offset(0), Vector2i(255, 0))
	assert_eq(player.image_id(0), 100)
	player.step()
	assert_eq(player.track_offset(0), Vector2i(254, 1), "u carry goes into v")
	assert_eq(player.image_id(0), 102, "first transition increments cel before selection")
	assert_eq(player.pixel_uvs(0)[0], Vector2(62, 33), "original dimensions survive replacement")
	player.step()
	assert_eq(player.track_offset(0), Vector2i.ZERO)
	assert_eq(player.track_counters(0), PackedInt32Array([0, 1, 1]))
	player.seek(3)
	assert_eq(player.image_id(0), 101)
	assert_eq(player.pixel_uvs(0)[0], Vector2(-193, 32), "PC wraps each byte at page edge")
	assert_eq(source.initial_u, 0)
	assert_eq(source.texture_ids, PackedInt32Array([1, 2]))
	player.seek(1)
	assert_eq(player.track_offset(0), Vector2i(254, 1))
	player.reset()
	assert_eq(player.image_id(0), 100)
	assert_eq(player.tick, -1)


func test_shared_cel_lists_have_independent_counters_and_zero_uv_duration() -> void:
	var fixture: Dictionary = _animation_fixture()
	var first: MapAnimation = fixture.source
	var second := MapAnimation.new()
	second.type = 3
	second.delta_u = 1
	second.uv_frame_count = 0
	second.frames_per_texture = 0
	second.texture_ids = first.texture_ids
	var polygon: MapPolygon = fixture.polygon
	var remap: TextureRemap = fixture.remap
	var library: TextureLibrary = fixture.library
	var player := MapAnimationPlayer.new()
	player.configure([polygon], [first, second], remap, library)
	player.seek(1)
	assert_eq(player.track_counters(0), PackedInt32Array([2, 1, 0]))
	assert_eq(player.track_counters(1), PackedInt32Array([2, 0, 0]))
	assert_eq(player.track_offset(1), Vector2i(2, 0), "zero duration uses equality, not >=")
	assert_eq(first.texture_ids, PackedInt32Array([1, 2]))


func test_sky_timer_rng_and_seek_are_instance_local() -> void:
	var sky := MapSkyState.new()
	sky.reset()
	sky.seek(126)
	assert_eq(sky.position, Vector3i.ZERO, "timer 127 has not selected acceleration")
	sky.step()
	assert_eq(sky.tick, 127)
	assert_eq(sky.position, Vector3i.ZERO, "timer128 selects acceleration without accelerating")
	assert_ne(sky.acceleration, Vector3i.ZERO)
	var selected: Vector3i = sky.acceleration
	sky.seek(256)
	var position: Vector3i = sky.position
	assert_eq(sky.velocity, sky.acceleration, "timer257 accelerates after selection at256")
	sky.seek(127)
	assert_eq(sky.acceleration, selected)
	sky.seek(256)
	assert_eq(sky.position, position)
	var other := MapSkyState.new()
	other.reset()
	assert_eq(other.position, Vector3i.ZERO)
	assert_eq(other.random_state, 0)
