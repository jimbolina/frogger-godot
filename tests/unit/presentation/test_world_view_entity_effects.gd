extends GutTest
## The world view feeds entity shadows, splashes, pops, glows, hilite particles and the croak throat from committed state.

class RecordingFields extends EntityParticleFields:
	var calls: Array = []

	func ensure(slot: int, generation: int, hilites: Array[ParticleHilite]) -> void:
		calls.append(["ensure", slot, generation, hilites.size()])

	func release(slot: int) -> void:
		calls.append(["release", slot])

	func step(slot: int, hilite_index: int, owner_m12: PackedInt32Array, moving: bool, colour_scale: Vector3i) -> void:
		calls.append(["step", slot, hilite_index, owner_m12, moving, colour_scale])

	func collapse() -> void:
		calls.append(["collapse"])

const TURNED: PackedInt32Array = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 1000, -50, 2000]

var _view: GameplayWorldView

func before_each() -> void:
	_view = GameplayWorldView.new()
	add_child_autofree(_view)
	_view.build_world()
	var scene := MapSceneData.new()
	scene.effects = EffectResources.resolve(null, null, null, null, null)
	_view._configure_effects(scene)

func _definition(kind: EntityBehavior.Kind) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.behavior.kind = kind
	return definition

func _entity(index: int = 7, matrix: PackedInt32Array = TURNED) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = index
	entity.generation = 1
	entity.matrix12 = matrix.duplicate()
	entity.custom_state = EntityCustomState.new()
	return entity

func _state(tick: int, entities: Array[EntitySnapshot], lifecycle: bool = true) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.entity_environment = EntityEnvironmentState.new()
	state.entities = EntityRunSnapshot.new()
	state.entities.lifecycle_enabled = lifecycle
	for entity: EntitySnapshot in entities:
		state.entities.entities.append(entity.copy())
	return state

func test_desert_shadows_follow_the_committed_shadow_state() -> void:
	var rock: EntitySnapshot = _entity()
	assert_null(GameplayWorldView.entity_shadow(_definition(EntityBehavior.Kind.DES_FALLING_ROCK), rock, Vector3i(1, 2, 3)), "off until committed")
	rock.custom_state.shadow_visible = true
	var request: FrogShadowView.Request = GameplayWorldView.entity_shadow(_definition(EntityBehavior.Kind.DES_FALLING_ROCK), rock, Vector3i(1, 2, 3))
	assert_not_null(request)
	assert_eq(request.offsets, [Vector3i(-0x70, 0, 0x70), Vector3i(0x70, 0, 0x70), Vector3i(-0x70, 0, -0x70), Vector3i(0x70, 0, -0x70)])
	assert_eq(request.symbol, "im_gen_shadow")
	assert_true(request.no_rotation, "the rock keeps EFFECT_NO_ROTATION")
	assert_eq(request.translation, Vector3i(1, 2, 3))
	assert_eq(request.matrix12, rock.matrix12)
	var weed: FrogShadowView.Request = GameplayWorldView.entity_shadow(_definition(EntityBehavior.Kind.DES_TUMBLE_WEED), rock, Vector3i.ZERO)
	assert_false(weed.no_rotation, "the shown tumbleweed turns by its quadrant")
	assert_null(GameplayWorldView.entity_shadow(_definition(EntityBehavior.Kind.DES_ROLLING_ROCK), rock, Vector3i.ZERO), "the rolling rock has no shadow")
	rock.live = false
	assert_null(GameplayWorldView.entity_shadow(_definition(EntityBehavior.Kind.DES_FALLING_ROCK), rock, Vector3i.ZERO))

func test_sprite_events_splash_in_the_entity_frame_and_follow_it() -> void:
	var entities: Array[EntitySnapshot] = [_entity(3, EntityTransform.IDENTITY), _entity()]
	_view.accept_state(_state(0, entities))
	var offsets: Array[Vector3i] = SplashOffsets.offsets(SplashOffsets.ORIGINAL_THEME, 20)
	var events: Array[TickEvent] = []
	for offset: Vector3i in offsets:
		events.append(TickEvent.sprite(offset, Vector2i(1, -16)).for_entity(7))
	_view.accept_state(_state(1, entities), events)
	var splashes: Array[SplashView.Splash] = _view.effect_splashes()
	assert_eq(splashes.size(), 2)
	assert_eq(splashes[0].owner, 1)
	assert_eq(splashes[0].origin, Vector3i(1000 - 128, -50 - 64, 2000), "local -Z turns to world -X")
	assert_eq(splashes[1].origin, Vector3i(1000 + 128, -50 - 64, 2000))
	entities[1].matrix12[9] = 1100
	_view.accept_state(_state(2, entities), [])
	assert_eq(_view.effect_splashes()[0].origin, Vector3i(1100 - 128, -50 - 64, 2000), "the frame carries the splash")
	_view.accept_state(_state(3, entities), [TickEvent.sprite(Vector3i.ZERO, Vector2i(1, -16)).for_entity(99)])
	assert_eq(_view.effect_splashes().size(), 2, "an unknown entity makes no splash")

func test_pops_and_glows_step_with_committed_entities() -> void:
	var definitions: Array[EntityDefinition] = [_definition(EntityBehavior.Kind.GOLD_FROG)]
	_view._definitions = definitions
	var cel := MofPart.Partcel.new()
	cel.vertices = PackedInt32Array([0, 0, 0, 64, 0, 0, 0, 64, 0])
	var part := MofPart.new()
	part.partcels.append(cel)
	var polygon := MofPolygon.new()
	polygon.type = MofPolygonType.F3
	polygon.vertices = PackedInt32Array([0, 1, 2])
	part.polygons.append(polygon)
	var model := MofStatic.new()
	model.parts.append(part)
	_view._piece_view.set_pieces(0, ModelPolyPieces.build(model, null, null))
	var frog: EntitySnapshot = _entity()
	var entities: Array[EntitySnapshot] = [frog]
	_view.accept_state(_state(0, entities))
	assert_eq(_view._glow_view.glows().size(), 1)
	assert_true(_view._glow_view.glows()[0].shown)
	frog.pop_allocated = true
	frog.pop_remaining = 31
	_view.accept_state(_state(1, entities))
	assert_eq(_view._piece_view.piece_count(), 1)
	assert_false(_view._glow_view.glows()[0].shown, "the pop kills the glow")
	_view.collapse_effects()
	assert_eq(_view._piece_view.piece_count(), 0)
	assert_eq(_view._glow_view.glows().size(), 0)

func test_hilites_are_ensured_stepped_and_released_per_generation() -> void:
	var fields := RecordingFields.new()
	_view._entity_fields = fields
	var hilite := ParticleHilite.new()
	hilite.part = 0
	hilite.vertex = 1
	var definition: EntityDefinition = _definition(EntityBehavior.Kind.PATH_FOLLOWER)
	definition.particle_hilites.append(hilite)
	var definitions: Array[EntityDefinition] = [definition]
	_view._definitions = definitions
	var file := MofFile.new()
	var cel := MofPart.Partcel.new()
	cel.vertices = PackedInt32Array([0, 0, 0, 10, -20, 30])
	var part := MofPart.new()
	part.partcels.append(cel)
	var model := MofStatic.new()
	model.parts.append(part)
	file.static_models.append(model)
	var files: Array[MofFile] = [file]
	_view._entity_files = files
	var car: EntitySnapshot = _entity()
	var entities: Array[EntitySnapshot] = [car]
	var none: Array[EntitySnapshot] = []
	_view.accept_state(_state(0, none))
	fields.calls.clear()
	_view.accept_state(_state(1, entities))
	var at: PackedInt32Array = TURNED.duplicate()
	at[9] = 1000 + 30
	at[10] = -50 - 20
	at[11] = 2000 - 10
	assert_eq(fields.calls, [["ensure", 0, 1, 1], ["step", 0, 0, at, false, Vector3i(128, 128, 128)]], "the hilite vertex turns with the entity")
	fields.calls.clear()
	car.matrix12[11] = 2100
	car.colour_scaled = true
	car.colour_scale = Vector3i(40, 40, 40)
	_view.accept_state(_state(2, entities))
	at[11] = 2100 - 10
	assert_eq(fields.calls, [["step", 0, 0, at, true, Vector3i(40, 40, 40)]], "moving and the committed fade")
	fields.calls.clear()
	car.generation = 2
	_view.accept_state(_state(3, entities))
	var ensured: Array = fields.calls[0]
	var stepped: Array = fields.calls[1]
	var moving: bool = stepped[4]
	assert_eq(ensured, ["ensure", 0, 2, 1], "a new generation recreates the fields")
	assert_false(moving, "a new generation is not moving")
	fields.calls.clear()
	car.live = false
	_view.accept_state(_state(4, entities))
	assert_eq(fields.calls, [["release", 0]])
	fields.calls.clear()
	_view.accept_state(_state(5, entities))
	assert_eq(fields.calls, [], "released once")
	_view.collapse_effects()
	assert_eq(fields.calls, [["collapse"]])

func test_hilite_matrix_composes_the_part_rotation_and_drops_its_translation() -> void:
	var quarter: PackedInt32Array = PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 500, 600, 700])
	var result: PackedInt32Array = GameplayWorldView.hilite_matrix(EntityTransform.IDENTITY, quarter, Vector3i(10, 0, 0))
	assert_eq(result, PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 0, 10, 0]))

func test_the_throat_shows_and_scales_only_while_croaking() -> void:
	var parts: Array[SyntheticMof.Part] = []
	for _index: int in GameplayWorldView.THROAT_PART + 1:
		parts.append(SyntheticMof.square(MofPolygonType.F4))
	var assets := TerrainFrogAssets.new()
	assets.model = SyntheticMof.static_file(parts)
	assets.mesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(assets.model)
	assets.player = ModelAnimationPlayer.new(assets.model)
	assets.hidden_parts = PackedInt64Array([GameplayWorldView.THROAT_PART])
	_view.build_frog(assets)
	var throat: MeshInstance3D = _view._frog_model.part_nodes[GameplayWorldView.THROAT_PART]
	assert_false(throat.visible)
	var croaking := GameplayState.new()
	croaking.tick_index = 1
	croaking.frog.croak_mode = FrogCroak.Mode.INFLATE
	croaking.frog.croak_scale = 0x800
	_view.accept_state(croaking)
	_view.draw_state(1.0)
	assert_true(throat.visible)
	assert_almost_eq(throat.transform.basis.get_scale(), Vector3.ONE * 0.5, Vector3.ONE * 0.0001)
	assert_true(_view._frog_model.part_nodes[0].visible)
	var done := GameplayState.new()
	done.tick_index = 2
	_view.accept_state(done)
	_view.draw_state(1.0)
	assert_false(throat.visible)
