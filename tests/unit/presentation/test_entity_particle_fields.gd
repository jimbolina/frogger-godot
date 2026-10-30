extends GutTest
## Entity hilite particle fields follow live generations, end on release and draw with per-kind images and depth.

const SMOKE_ID: int = 60
const TONGUE_ID: int = 61
const BISON_FIRST_ID: int = 70

var _at := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 1024])

func _effects() -> EffectResources:
	var effects := EffectResources.new()
	effects.generators = ExeParticleGenerators.c_constants()
	return effects

func _hilites() -> Array[ParticleHilite]:
	var result: Array[ParticleHilite] = []
	for kind: ParticleHilite.Kind in [ParticleHilite.Kind.EXHAUST, ParticleHilite.Kind.DUST, ParticleHilite.Kind.FIRE]:
		var hilite := ParticleHilite.new()
		hilite.kind = kind
		result.append(hilite)
	return result

func _fields(seed: int = 5) -> EntityParticleFields:
	var fields := EntityParticleFields.new()
	fields.configure(_effects(), seed)
	return fields

func _step_all(fields: EntityParticleFields, slot: int, ticks: int) -> void:
	for _tick: int in ticks:
		for index: int in 3:
			fields.step(slot, index, _at, true, Vector3i(128, 128, 128))

func _positions(field: ParticleField) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for index: int in field.live_indices():
		result.append(field.particles[index].position_16)
	return result

func test_ensure_creates_one_field_per_hilite_from_its_record() -> void:
	var fields: EntityParticleFields = _fields()
	fields.ensure(4, 1, _hilites())
	var created: Array[ParticleField] = fields.fields()
	assert_eq(created.size(), 3)
	assert_eq(created[0].kind, ParticleField.Kind.HILITE_EXHAUST)
	assert_eq(created[0].generator_name, "PGIN_hilite_exhaust")
	assert_eq(created[1].kind, ParticleField.Kind.HILITE_DUST)
	assert_eq(created[1].generator_name, "PGIN_hilite_dust")
	assert_eq(created[2].kind, ParticleField.Kind.HILITE_FIRE)
	assert_eq(created[2].generator_name, "PGIN_hilite_fire")
	fields.ensure(4, 1, _hilites())
	assert_same(fields.fields()[2], created[2], "an unchanged generation keeps its fields")

func test_step_drives_one_hilite_and_ignores_unknown_targets() -> void:
	var fields: EntityParticleFields = _fields()
	fields.ensure(4, 1, _hilites())
	fields.step(4, 2, _at, false, Vector3i.ZERO)
	fields.step(4, 3, _at, false, Vector3i.ZERO)
	fields.step(9, 0, _at, false, Vector3i.ZERO)
	var ticks := PackedInt32Array()
	for field: ParticleField in fields.fields():
		ticks.append(field.ticks)
	assert_eq(ticks, PackedInt32Array([0, 0, 1]))
	fields.step(4, 0, _at, false, Vector3i(10, 20, 30))
	assert_eq(fields.fields()[0].colour_scale, Vector3i(10, 20, 30))

func test_a_new_generation_replaces_the_fields() -> void:
	var fields: EntityParticleFields = _fields()
	fields.ensure(4, 1, _hilites())
	_step_all(fields, 4, 6)
	var old: ParticleField = fields.fields()[2]
	fields.ensure(4, 2, _hilites())
	var replaced: Array[ParticleField] = fields.fields()
	assert_eq(replaced.size(), 3)
	assert_ne(replaced[2], old)
	assert_eq(replaced[2].ticks, 0)
	assert_eq(replaced[2].live_indices().size(), 0)

func test_release_and_collapse_end_the_fields() -> void:
	var fields: EntityParticleFields = _fields()
	fields.ensure(4, 1, _hilites())
	fields.ensure(7, 3, _hilites())
	_step_all(fields, 4, 4)
	fields.release(4)
	assert_eq(fields.fields().size(), 3, "only the other slot's fields remain")
	fields.step(4, 2, _at, false, Vector3i.ZERO)
	assert_eq(fields.fields().size(), 3)
	fields.collapse()
	assert_eq(fields.fields().size(), 0)

func test_fields_draw_in_slot_order() -> void:
	var fields: EntityParticleFields = _fields()
	var exhaust: Array[ParticleHilite] = [_hilites()[0]]
	var fire: Array[ParticleHilite] = [_hilites()[2]]
	fields.ensure(9, 1, exhaust)
	fields.ensure(2, 1, fire)
	var ordered: Array[ParticleField] = fields.fields()
	assert_eq(ordered[0].kind, ParticleField.Kind.HILITE_FIRE)
	assert_eq(ordered[1].kind, ParticleField.Kind.HILITE_EXHAUST)

func test_seeds_follow_seed_slot_generation_and_hilite() -> void:
	var first: EntityParticleFields = _fields(5)
	var second: EntityParticleFields = _fields(5)
	first.ensure(4, 1, _hilites())
	second.ensure(4, 1, _hilites())
	second.ensure(8, 1, _hilites())
	_step_all(first, 4, 10)
	_step_all(second, 4, 10)
	_step_all(second, 8, 10)
	var reference := ParticleField.new(ParticleField.Kind.HILITE_FIRE, ExeParticleGenerators.c_constants().find("PGIN_hilite_fire"), 0, hash([5, 4, 1, 2]))
	for _tick: int in 10:
		reference.step(_at, true)
	assert_eq(_positions(first.fields()[2]), _positions(reference))
	assert_eq(_positions(first.fields()[2]), _positions(second.fields()[2]))
	assert_ne(_positions(second.fields()[2]), _positions(second.fields()[5]), "another slot draws another stream")

func test_missing_records_leave_finished_fields() -> void:
	var fields := EntityParticleFields.new()
	fields.configure(EffectResources.new(), 1)
	fields.ensure(4, 1, _hilites())
	fields.step(4, 0, _at, true, Vector3i.ZERO)
	assert_eq(fields.fields().size(), 0)

func _scene() -> MapSceneData:
	var specs: Array[SyntheticVlo.Spec] = []
	var ids: Array[int] = [SMOKE_ID, TONGUE_ID]
	for offset: int in 6:
		ids.append(BISON_FIRST_ID + offset)
	for identity: int in ids:
		var pixels: Array[int] = []
		for _index: int in 16 * 8:
			pixels.append_array([200, 120, 40])
		var spec: SyntheticVlo.Spec = SyntheticVlo.spec(16, 8, 0, identity, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(pixels))
		spec.blend_mode = 0
		specs.append(spec)
	var scene := MapSceneData.new()
	scene.library.add_bank(VloFile.parse(SyntheticVlo.build_vlo(specs)), "TEST.VLO")
	scene.effects = _effects()
	scene.effects.texture_ids["im_frog_smoke1"] = SMOKE_ID
	scene.effects.texture_ids["im_tongue_tip"] = TONGUE_ID
	for offset: int in 6:
		scene.effects.texture_ids[EffectResources.DUST_SYMBOLS[offset]] = BISON_FIRST_ID + offset
	var libraries: Array[TextureLibrary] = [scene.library]
	scene.effects.attach_images(libraries)
	return scene

func _view(scene: MapSceneData) -> ParticleSpriteView:
	var view := ParticleSpriteView.new()
	add_child_autofree(view)
	assert_eq(view.configure(scene, EntityParticleFields.GENERATOR_NAMES), "")
	return view

func _bias(material: Material) -> float:
	var value: float = (material as ShaderMaterial).get_shader_parameter("depth_bias")
	return value

func _draw(view: ParticleSpriteView, field: ParticleField) -> int:
	var fields: Array[ParticleField] = [field]
	return view.draw_fields(fields, GameplayCameraSnapshot.new(), 1.0)

func test_view_resolves_hilite_images_and_sorts_exhaust_further() -> void:
	var scene: MapSceneData = _scene()
	assert_eq(ParticleSpriteView.generator_images(scene.effects, "PGIN_hilite_exhaust").size(), 1)
	assert_eq(ParticleSpriteView.generator_images(scene.effects, "PGIN_hilite_dust").size(), 6)
	var view: ParticleSpriteView = _view(scene)
	var fields: EntityParticleFields = _fields()
	fields.ensure(1, 1, _hilites())
	for _tick: int in 12:
		fields.step(1, 0, _at, true, Vector3i(128, 128, 128))
		fields.step(1, 2, _at, true, Vector3i(128, 128, 128))
	var exhaust: ParticleField = fields.fields()[0]
	assert_gt(exhaust.live_indices().size(), 0)
	assert_eq(_draw(view, exhaust), exhaust.live_indices().size())
	assert_eq(_bias(view.mesh.surface_get_material(0)), -32.0, "0x10 slots further")
	var fire: ParticleField = fields.fields()[2]
	assert_eq(_draw(view, fire), fire.live_indices().size())
	assert_eq(_bias(view.mesh.surface_get_material(0)), 32.0, "0x10 slots nearer")
	assert_eq(ParticleSpriteView.half_extents(16 << 16, 8 << 16, 10.0, ParticleField.OT_OFFSET, true), Vector2(-1, -1), "a clamped entry of 1 still culls a wide particle")
	assert_gt(ParticleSpriteView.half_extents(16 << 8, 8 << 8, 10.0, ParticleField.OT_OFFSET, true).x, 0.0, "the hilite fire holds the entry at 1")
	assert_eq(ParticleSpriteView.half_extents(16 << 8, 8 << 8, 10.0).x, -1.0, "the frog kinds cull in front of the table")

func test_view_draws_each_dust_particle_with_its_list_image_additively() -> void:
	var view: ParticleSpriteView = _view(_scene())
	var fields: EntityParticleFields = _fields()
	var dust: Array[ParticleHilite] = [_hilites()[1]]
	fields.ensure(1, 1, dust)
	for _tick: int in 12:
		fields.step(1, 0, _at, true, Vector3i(128, 128, 128))
	var field: ParticleField = fields.fields()[0]
	var images: Dictionary[int, bool] = {}
	for index: int in field.live_indices():
		images[field.image_index(index)] = true
	assert_gt(images.size(), 1)
	assert_eq(_draw(view, field), field.live_indices().size())
	assert_eq(view.mesh.get_surface_count(), images.size(), "one material per list image")
	for surface: int in view.mesh.get_surface_count():
		var material: ShaderMaterial = view.mesh.surface_get_material(surface) as ShaderMaterial
		assert_string_contains(material.shader.code, "blend_add", "the PC dust display sets ABR 1")
		assert_eq(_bias(material), 32.0)
