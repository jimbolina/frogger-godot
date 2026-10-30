extends GutTest
## Effect views build the source quads, colours, blends and depth biases from synthetic state.

const SHADOW_ID: int = 50
const SMOKE_ID: int = 51
const RIPPLE_ID: int = 52

func _scene() -> MapSceneData:
	var pixels: Array[int] = []
	for _index: int in 16 * 8:
		pixels.append_array([200, 120, 40])
	var specs: Array[SyntheticVlo.Spec] = []
	for identity: int in [SHADOW_ID, SMOKE_ID, RIPPLE_ID]:
		var spec: SyntheticVlo.Spec = SyntheticVlo.spec(16, 8, 0, identity, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(pixels))
		spec.blend_mode = 1
		specs.append(spec)
	var scene := MapSceneData.new()
	scene.library.add_bank(VloFile.parse(SyntheticVlo.build_vlo(specs)), "TEST.VLO")
	scene.effects = EffectResources.new()
	scene.effects.generators = ExeParticleGenerators.c_constants()
	for symbol: String in ["im_frog_shadow0", "im_frog_shadow1", "im_frog_shadow2", "im_gen_shadow"]:
		scene.effects.texture_ids[symbol] = SHADOW_ID
	scene.effects.texture_ids["im_frog_smoke1"] = SMOKE_ID
	scene.effects.texture_ids["im_wake2"] = SMOKE_ID
	for symbol: String in EffectResources.RIPPLE_SYMBOLS:
		scene.effects.texture_ids[symbol] = RIPPLE_ID
	var libraries: Array[TextureLibrary] = [scene.library]
	scene.effects.attach_images(libraries)
	return scene

func _grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(4, 4)
	for cell: int in 16:
		var stack := GridStackDefinition.new()
		stack.first_square_index = cell
		stack.square_count = 1
		grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		var y: int = -64 if cell < 4 else -128
		square.vertices.assign([Vector3i(0, y, 0), Vector3i(0, y, 0), Vector3i(0, y, 0), Vector3i(0, y, 0)])
		grid.squares.append(square)
	return grid

func _vertices(view: MeshInstance3D, surface: int = 0) -> PackedVector3Array:
	return view.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]

func _colours(view: MeshInstance3D, surface: int = 0) -> PackedColorArray:
	return view.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]

func _request(translation: Vector3i) -> FrogShadowView.Request:
	var request := FrogShadowView.Request.new()
	request.translation = translation
	request.offsets = FrogShadowGeometry.phase_offsets(0)
	request.symbol = "im_frog_shadow0"
	return request

func _bias(material: Material) -> float:
	var value: float = (material as ShaderMaterial).get_shader_parameter("depth_bias")
	return value

func test_shadow_quad_follows_grid_heights_with_grey_and_bias() -> void:
	var view := FrogShadowView.new()
	add_child_autofree(view)
	assert_eq(view.configure(_scene(), _grid(), PackedStringArray(["im_frog_shadow0", "im_missing"])), "Shadow image im_missing is unavailable")
	var requests: Array[FrogShadowView.Request] = [_request(Vector3i(384, -64, 360))]
	assert_eq(view.draw_shadows(requests), 1)
	assert_true(view.visible)
	var vertices: PackedVector3Array = _vertices(view)
	assert_eq(vertices.size(), 6)
	assert_eq(vertices[0], GameSpace.position(288, -128, 472))
	assert_eq(vertices[5], GameSpace.position(480, -128, 264))
	assert_eq(_colours(view)[0], Color(48 / 255.0, 48 / 255.0, 48 / 255.0))
	var material: Material = view.mesh.surface_get_material(0)
	assert_eq(_bias(material), FrogShadowView.DEPTH_BIAS)
	assert_eq(FrogShadowView.DEPTH_BIAS, 8.0)
	assert_string_contains((material as ShaderMaterial).shader.code, "blend_add", "the image page's rate")

func test_shadow_splits_across_grid_lines_and_hides_off_the_grid() -> void:
	var view := FrogShadowView.new()
	add_child_autofree(view)
	view.configure(_scene(), _grid(), PackedStringArray(["im_frog_shadow0"]))
	var split: Array[FrogShadowView.Request] = [_request(Vector3i(384, -64, 272))]
	assert_eq(view.draw_shadows(split), 1)
	var vertices: PackedVector3Array = _vertices(view)
	assert_eq(vertices.size(), 12, "two quads")
	assert_eq(vertices[2], GameSpace.position(288, -128, 256), "split edge on the square under corner 0")
	assert_eq(vertices[8], GameSpace.position(288, -64, 176), "far corner on its own square")
	var outside: Array[FrogShadowView.Request] = [_request(Vector3i(-512, -64, 128))]
	assert_eq(view.draw_shadows(outside), 0)
	assert_false(view.visible, "a failed height query hides the shadow")

func test_trail_draws_two_additive_triangles_per_section() -> void:
	var trail := HopTrailState.new()
	trail.start(false)
	for tick: int in 4:
		trail.step(PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 128, -64, 128 + tick * 42]))
	var view := HopTrailView.new()
	add_child_autofree(view)
	assert_eq(view.draw_trail(trail), trail.display_sections)
	assert_eq(_vertices(view).size(), trail.display_sections * 6)
	var colours: PackedColorArray = _colours(view)
	var head: Vector3i = HopTrailState.bytes(trail.rgb)
	assert_eq(colours[0], EffectSpriteMaterial.colour(head))
	assert_eq(colours[2], EffectSpriteMaterial.colour(HopTrailState.bytes(trail.rgb - HopTrailState.SECTION_FALL)))
	var material: ShaderMaterial = view.mesh.surface_get_material(0) as ShaderMaterial
	assert_string_contains(material.shader.code, "blend_add")
	assert_eq(_bias(material), 0.0)
	trail.collapse()
	assert_eq(view.draw_trail(trail), 0)
	assert_false(view.visible)

func test_particles_draw_screen_aligned_quads_with_source_sizes() -> void:
	var view := ParticleSpriteView.new()
	add_child_autofree(view)
	assert_eq(view.configure(_scene(), PackedStringArray(["PGIN_frog_slip_effect", "PGIN_frog_on_fire"])), "")
	var field := ParticleField.new(ParticleField.Kind.FROG_SLIDE, ExeParticleGenerators.c_constants().find("PGIN_frog_slip_effect"), 0, 3)
	var frame := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 1024])
	for _tick: int in 8:
		field.step(frame, true)
	var fields: Array[ParticleField] = [field]
	var camera := GameplayCameraSnapshot.new()
	var drawn: int = view.draw_fields(fields, camera, 1.0)
	assert_eq(drawn, field.live_indices().size())
	assert_gt(drawn, 0)
	assert_eq(_vertices(view).size(), drawn * 6)
	var first: int = field.live_indices()[0]
	assert_eq(_colours(view)[0], EffectSpriteMaterial.colour(field.colour(first)))
	assert_eq(_bias(view.mesh.surface_get_material(0)), 32.0)
	assert_eq(ParticleSpriteView.half_extents(16 * (96 << 10), 8 * (96 << 10), 512.0), Vector2(25.0, 12 * 512.0 / 480.0))
	assert_eq(ParticleSpriteView.half_extents(16 * (96 << 10), 8 * (96 << 10), 20.0), Vector2(-1, -1), "outside the ordering table")
	assert_eq(ParticleSpriteView.half_extents(16 * (96 << 10), 8 * (96 << 10), 160.0), Vector2(-1, -1), "half width from 0x60 is culled")

func test_pop_ring_draws_eight_front_quads() -> void:
	var view := PopRingView.new()
	add_child_autofree(view)
	var ring := PopRingGeometry.new(0x000400)
	ring.step()
	var rings: Array[PopRingGeometry] = [ring]
	assert_eq(view.draw_rings(rings, Vector3(0, 0, 384), GameplayCameraSnapshot.new(), 7), 1)
	assert_eq(_vertices(view).size(), 8 * 6)
	var shape: PopRingGeometry.Frame = ring.frame(7)
	assert_eq(_colours(view)[0], EffectSpriteMaterial.colour(shape.outer_rgb))
	assert_eq(_colours(view)[2], EffectSpriteMaterial.colour(shape.inner_rgb))
	assert_almost_eq(_vertices(view)[0], EffectSpriteMaterial.world(Vector3(shape.outer[0].x * 2.0, shape.outer[0].y * 2.0, 384)), Vector3.ONE * 0.0001)
	var material: ShaderMaterial = view.mesh.surface_get_material(0) as ShaderMaterial
	assert_string_contains(material.shader.code, "depth_test_disabled")
	assert_string_contains(material.shader.code, "blend_add")
	assert_eq(material.render_priority, EffectSpriteMaterial.FRONT_PRIORITY)
	for _tick: int in 29:
		ring.step()
	assert_eq(view.draw_rings(rings, Vector3(0, 0, 384), GameplayCameraSnapshot.new(), 7), 0)

func test_splash_lies_in_the_xz_plane_at_eight_times_scale() -> void:
	var view := SplashView.new()
	add_child_autofree(view)
	assert_eq(view.configure(_scene()), "")
	var splash := SplashView.Splash.new(Vector3i(0, -10, 0))
	var splashes: Array[SplashView.Splash] = [splash]
	for _tick: int in 4:
		splash.timeline.update()
	assert_eq(view.draw_splashes(splashes), 0, "the list opens with four NOPs")
	splash.timeline.update()
	assert_eq(view.draw_splashes(splashes), 1)
	var vertices: PackedVector3Array = _vertices(view)
	assert_eq(vertices[0], GameSpace.position(-64, -10, 32))
	assert_eq(vertices[5], GameSpace.position(64, -10, -32))
	assert_eq(_colours(view)[0], Color(128 / 255.0, 128 / 255.0, 128 / 255.0))
	assert_eq(_bias(view.mesh.surface_get_material(0)), 32.0)
	var lighting := MapLighting.new()
	lighting.ambient = Vector3(2048, 2048, 2048)
	view.set_lighting(lighting)
	view.draw_splashes(splashes)
	assert_eq(_colours(view)[0], Color(64 / 255.0, 64 / 255.0, 64 / 255.0), "lit by the map ambient")

func test_score_popups_rise_fade_and_expire() -> void:
	var view := ScorePopupView.new()
	add_child_autofree(view)
	view.add_image(1, ImageTexture.create_from_image(Image.create(16, 8, false, Image.FORMAT_RGBA8)), Rect2(0, 0, 16, 8), ModelShaders.Blend.ADD)
	assert_true(view.spawn(1, Vector2i(100, 100)))
	assert_false(view.spawn(0, Vector2i(100, 100)), "SCORE_5 has no image")
	view.step()
	assert_eq(view.popups().size(), 1)
	assert_eq(view.popups()[0].screen(), Vector2i(100, 99))
	assert_eq(view.popups()[0].grey, 0x20)
	for _tick: int in 44:
		view.step()
	assert_eq(view.popups().size(), 0)

func test_hud_score_slots_follow_add_frog_score_callers() -> void:
	var before := GameplayState.new()
	before.entity_environment = EntityEnvironmentState.new()
	var after: GameplayState = before.copy()
	after.entity_environment.collected = 0b101
	after.flow.gold_collected = true
	var events: Array[TickEvent] = [TickEvent.reward(5), TickEvent.make(TickEvent.Kind.SUPER_HOP), TickEvent.make(TickEvent.Kind.ROLL), TickEvent.make(TickEvent.Kind.HOP)]
	assert_eq(GameplayHud.score_slots(before, after, events), PackedInt32Array([5, 1, 3, 9, 9, 10]))
	var camera := GameplayCameraSnapshot.new()
	assert_eq(GameplayWorldView.canvas_point(camera, Vector3i(0, 0, 512)), Vector2i(320, 240))
	assert_eq(GameplayWorldView.canvas_point(camera, Vector3i(256, 128, 512)), Vector2i(576, 360))
	assert_false(GameplayWorldView.in_front_of(camera, Vector3i(0, 0, -5)))
