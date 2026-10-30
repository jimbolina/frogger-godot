extends GutTest
## Entity poly-piece pops start from committed snapshots, follow the pop timer and free their pieces.

const VERTICES: Array[int] = [-64, -32, 48, 64, -32, 48, -64, -96, 48, 64, -96, 48, -1, -1, -1, -2, -2, -2, -2, -1, 0]

var _view: PolyPiecePopView

func before_each() -> void:
	_view = PolyPiecePopView.new()
	add_child_autofree(_view)

func _polygon(type: int, vertices: PackedInt32Array, colour: Color) -> MofPolygon:
	var polygon := MofPolygon.new()
	polygon.type = type
	polygon.vertices = vertices
	polygon.red = colour.r8
	polygon.green = colour.g8
	polygon.blue = colour.b8
	return polygon

func _model() -> MofStatic:
	var cel := MofPart.Partcel.new()
	cel.vertices = PackedInt32Array(VERTICES)
	var part := MofPart.new()
	part.partcels.append(cel)
	part.polygons = [_polygon(MofPolygonType.G4, PackedInt32Array([0, 1, 3, 2]), Color8(10, 20, 30)), _polygon(MofPolygonType.F3, PackedInt32Array([4, 5, 6]), Color8(200, 100, 50))]
	var model := MofStatic.new()
	model.parts.append(part)
	return model

func _entity(pop: bool, remaining: int, generation: int = 1, live: bool = true) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.live = live
	entity.generation = generation
	entity.pop_allocated = pop
	entity.pop_remaining = remaining
	entity.matrix12 = PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 512, -64, 768])
	return entity

func _accept(entity: EntitySnapshot) -> void:
	var entities: Array[EntitySnapshot] = [entity]
	_view.accept(entities)

func test_a_pop_starts_on_the_first_allocated_snapshot_and_follows_the_timer() -> void:
	var pieces: ModelPolyPieces = ModelPolyPieces.build(_model(), null, null)
	_view.set_pieces(0, pieces)
	_accept(_entity(false, 0))
	assert_eq(_view.piece_count(), 0)
	var start: EntitySnapshot = _entity(true, 31)
	_accept(start)
	assert_eq(_view.piece_count(), 2, "one instance per drawn polygon")
	var expected := PolyPiecePopState.new()
	expected.start(start.matrix12, pieces.origins())
	expected.advance_to(31)
	var pop: PolyPiecePopView.Pop = _view.pop_for(0)
	assert_eq(pop.state.timer, 31)
	for index: int in 2:
		assert_eq(pop.nodes[index].transform, expected.transform_for(index))
		assert_same(pop.nodes[index].mesh, pieces.pieces[index].mesh)
	var moved: EntitySnapshot = _entity(true, 29)
	moved.matrix12[9] = 4000
	_accept(moved)
	expected.advance_to(29)
	expected.lwtrans = moved.matrix12.duplicate()
	assert_same(_view.pop_for(0), pop, "the running pop continues")
	assert_eq(pop.state.lwtrans, moved.matrix12, "the pieces turn with the live entity matrix")
	assert_eq(pop.nodes[1].transform, expected.transform_for(1))
	assert_eq(pop.state.positions, expected.positions, "the start matrix fixed the piece positions")
	_accept(_entity(true, 0))
	assert_eq(_view.piece_count(), 0, "freed at timer 0")
	assert_true(_view.pop_for(0).finished)
	_accept(_entity(true, 0))
	assert_eq(_view.piece_count(), 0, "a finished pop does not restart while still allocated")
	_accept(_entity(false, 0))
	assert_null(_view.pop_for(0))
	_accept(_entity(true, 32))
	assert_eq(_view.piece_count(), 2, "a new allocation pops again")
	_accept(_entity(true, 31, 2))
	assert_eq(_view.pop_for(0).generation, 2, "a new generation restarts the pop")
	assert_eq(_view.pop_for(0).state.timer, 31)
	_accept(_entity(true, 30, 2, false))
	assert_eq(_view.piece_count(), 0, "a retired entity frees its pieces")
	assert_null(_view.pop_for(0))

func test_pieces_are_built_once_per_model_file_and_drawn_in_front() -> void:
	var file := MofFile.new()
	file.static_models.append(_model())
	_view.set_model(0, file, null, null)
	_view.set_model(1, file, null, null)
	var entities: Array[EntitySnapshot] = [_entity(true, 31), _entity(true, 31)]
	_view.accept(entities)
	assert_eq(_view.piece_count(), 4)
	assert_same(_view.pop_for(0).pieces, _view.pop_for(1).pieces, "cached per model file")
	var material: ShaderMaterial = _view.pop_for(0).nodes[0].material_override as ShaderMaterial
	assert_string_contains(material.shader.code, "depth_test_disabled")
	assert_string_contains(material.shader.code, "ALPHA = 1.0;", "opaque pieces join the translucent pass to draw last")
	assert_string_contains(material.shader.code, "cull_disabled")
	assert_eq(material.render_priority, EffectSpriteMaterial.FRONT_PRIORITY)
	assert_ne(_view.pop_for(0).nodes[0].material_override, _view.pop_for(1).nodes[0].material_override, "each pop owns its materials")
	_view.set_projection_scale(Vector2(2, 3))
	var scale: Vector2 = material.get_shader_parameter("projection_scale")
	assert_eq(scale, Vector2(2, 3))
	_view.collapse()
	assert_eq(_view.piece_count(), 0)

func test_entities_without_pieces_draw_nothing() -> void:
	_accept(_entity(true, 31))
	assert_eq(_view.piece_count(), 0)
	assert_null(_view.pop_for(0))
