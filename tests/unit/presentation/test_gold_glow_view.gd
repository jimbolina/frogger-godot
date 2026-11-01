extends GutTest
## The gold-frog glow draws one camera-plane quad per shown gold frog with the source pulse, colour and depth bias.

const GLOW_ID: int = 1727

var _view: GoldGlowView

func before_each() -> void:
	_view = GoldGlowView.new()
	add_child_autofree(_view)

func _scene() -> MapSceneData:
	var pixels: Array[int] = []
	for _index: int in 16 * 8:
		pixels.append_array([200, 200, 200])
	var spec: SyntheticVlo.Spec = SyntheticVlo.spec(16, 8, 0, GLOW_ID, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(pixels))
	spec.blend_mode = 1
	var specs: Array[SyntheticVlo.Spec] = [spec]
	var scene := MapSceneData.new()
	scene.library.add_bank(SyntheticVlo.bank(specs), "TEST.VLO")
	scene.effects = EffectResources.new()
	scene.effects.texture_ids[EffectResources.GLOW_SYMBOL] = GLOW_ID
	var libraries: Array[TextureLibrary] = [scene.library]
	scene.effects.attach_images(libraries)
	return scene

func _definition(kind: EntityBehavior.Kind, form_id: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.behavior.kind = kind
	definition.form_id = form_id
	return definition

func _entity(at: Vector3i, generation: int = 1) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.generation = generation
	entity.matrix12[9] = at.x
	entity.matrix12[10] = at.y
	entity.matrix12[11] = at.z
	return entity

func test_gold_frogs_own_glows() -> void:
	assert_true(GoldGlowView.owns_glow(_definition(EntityBehavior.Kind.GOLD_FROG)))
	assert_true(GoldGlowView.owns_glow(_definition(EntityBehavior.Kind.BABY_FROG, GoldGlowView.ORG_GOLD_BABY_FROG_FORM)))
	assert_false(GoldGlowView.owns_glow(_definition(EntityBehavior.Kind.BABY_FROG, 23)), "the pink frog has none")
	var statue: EntityDefinition = _definition(EntityBehavior.Kind.JUN_GOLD_FROG)
	statue.jungle = EntityJungleDefinition.new()
	statue.jungle.op_id = EntityJungleDefinition.GOLD_FROG_STATUE_ID
	assert_true(GoldGlowView.owns_glow(statue))
	var plinth: EntityDefinition = _definition(EntityBehavior.Kind.JUN_GOLD_FROG)
	plinth.jungle = EntityJungleDefinition.new()
	plinth.jungle.op_id = 2
	assert_false(GoldGlowView.owns_glow(plinth), "only the statue frog creates a glow")
	assert_false(GoldGlowView.owns_glow(_definition(EntityBehavior.Kind.CHECKPOINT)))

func test_glow_quad_pulses_at_the_entity_origin_with_colour_and_bias() -> void:
	assert_eq(_view.configure(_scene()), "")
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.GOLD_FROG), _definition(EntityBehavior.Kind.CHECKPOINT)]
	var entities: Array[EntitySnapshot] = [_entity(Vector3i(64, 0, 400)), _entity(Vector3i(0, 0, 400))]
	_view.accept(definitions, entities)
	_view.accept(definitions, entities)
	assert_eq(_view.glows().size(), 1)
	assert_eq(_view.glows()[0].angle(), 0x200, "two moves")
	var camera := GameplayCameraSnapshot.new()
	assert_eq(_view.draw_glows(camera, 1.0), 1)
	var arrays: Array = _view.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(vertices.size(), 6)
	var otz: int = (400 >> 1) + GoldGlowView.OT_OFFSET
	var pixels: Vector2i = GlowPulse.half_size(16, 8, otz, 0x200)
	var half := Vector2(pixels.x * 400.0 / EffectSpriteMaterial.FOCAL_X, pixels.y * 400.0 / EffectSpriteMaterial.FOCAL_Y)
	assert_almost_eq(vertices[0], EffectSpriteMaterial.world(Vector3(64 - half.x, -half.y, 400)), Vector3.ONE * 0.0001)
	assert_almost_eq(vertices[5], EffectSpriteMaterial.world(Vector3(64 + half.x, half.y, 400)), Vector3.ONE * 0.0001)
	assert_eq(colours[0], Color(1.0, 1.0, 16 / 255.0))
	var material: ShaderMaterial = _view.mesh.surface_get_material(0) as ShaderMaterial
	var bias: float = material.get_shader_parameter("depth_bias")
	assert_eq(bias, GoldGlowView.DEPTH_BIAS)
	assert_eq(GoldGlowView.DEPTH_BIAS, EffectSpriteMaterial.slots_bias(GoldGlowView.OT_OFFSET))
	assert_eq(material.shader.resource_path, GlowHaloMaterial.SHADER_PATH, "the halo replaces the retail image")
	assert_string_contains(material.shader.code, "blend_add")
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq([uvs[0], uvs[5]], [Vector2(0, 0), Vector2(1, 1)], "the halo spans the whole quad")
	var points: Array[GlowLightSpec.Point] = _view.glow_points()
	assert_eq(points.size(), 1)
	assert_eq(points[0].position, EffectSpriteMaterial.world(Vector3(64, 0, 400)) + Vector3.UP * GlowLightSpec.LIFT)
	assert_eq(points[0].colour, Color(1.0, 1.0, 32 / 255.0))
	assert_almost_eq(points[0].energy, GlowLightSpec.ENERGY * GlowLightSpec.energy_ratio(GlowPulse.magnitude(0x200)), 0.00001)
	_view.set_halo_strength(4.5)
	var strength: float = material.get_shader_parameter("halo_strength")
	assert_eq(strength, 4.5)

func test_glow_points_follow_the_interpolated_origin_and_clear_with_the_glows() -> void:
	assert_eq(_view.configure(_scene()), "")
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.GOLD_FROG)]
	var entities: Array[EntitySnapshot] = [_entity(Vector3i(0, 0, 400))]
	_view.accept(definitions, entities)
	entities = [_entity(Vector3i(128, 0, 400))]
	_view.accept(definitions, entities)
	var camera := GameplayCameraSnapshot.new()
	_view.draw_glows(camera, 0.5)
	assert_eq(_view.glow_points()[0].position, EffectSpriteMaterial.world(Vector3(64, 0, 400)) + Vector3.UP * GlowLightSpec.LIFT)
	_view.draw_glows(null, 1.0)
	assert_true(_view.glow_points().is_empty())
	_view.draw_glows(camera, 1.0)
	_view.collapse()
	assert_true(_view.glow_points().is_empty())

func test_glows_hide_with_their_frog_and_restart_with_a_new_generation() -> void:
	assert_eq(_view.configure(_scene()), "")
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.BABY_FROG, GoldGlowView.ORG_GOLD_BABY_FROG_FORM)]
	var hidden: EntitySnapshot = _entity(Vector3i(0, 0, 400))
	hidden.custom_state = EntityCustomState.new()
	hidden.custom_state.model_hidden = true
	var entities: Array[EntitySnapshot] = [hidden]
	_view.accept(definitions, entities)
	var camera := GameplayCameraSnapshot.new()
	assert_eq(_view.draw_glows(camera, 1.0), 0, "hidden until the baby frog is shown")
	var shown: EntitySnapshot = hidden.copy()
	shown.custom_state.model_hidden = false
	entities = [shown]
	_view.accept(definitions, entities)
	assert_eq(_view.draw_glows(camera, 1.0), 1)
	assert_eq(_view.glows()[0].moves, 2, "the pulse runs while hidden")
	var popped: EntitySnapshot = shown.copy()
	popped.pop_allocated = true
	entities = [popped]
	_view.accept(definitions, entities)
	assert_eq(_view.draw_glows(camera, 1.0), 0, "killed with the pop")
	entities = [_entity(Vector3i(0, 0, 400), 2)]
	_view.accept(definitions, entities)
	assert_eq(_view.glows()[0].moves, 1, "a new generation creates a new glow")
	var behind: EntitySnapshot = _entity(Vector3i(0, 0, -400), 2)
	entities = [behind]
	_view.accept(definitions, entities)
	assert_eq(_view.draw_glows(camera, 1.0), 0, "outside the ordering table")
	var retired: EntitySnapshot = _entity(Vector3i(0, 0, 400), 2)
	retired.live = false
	entities = [retired]
	_view.accept(definitions, entities)
	assert_eq(_view.glows().size(), 0)
