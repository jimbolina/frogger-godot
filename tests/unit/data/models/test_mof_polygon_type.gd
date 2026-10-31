extends GutTest
## The sixteen model polygon kinds and what each stores.


func test_polygon_kinds() -> void:
	assert_eq(MofPolygonType.type_name(MofPolygonType.GT4), "GT4")
	assert_eq(MofPolygonType.vertex_count(MofPolygonType.F3), 3)
	assert_eq(MofPolygonType.normal_count(MofPolygonType.G4), 4)
	assert_true(MofPolygonType.is_textured(MofPolygonType.FT3))
	assert_false(MofPolygonType.is_textured(MofPolygonType.G3))
	assert_false(MofPolygonType.is_valid(16))
	assert_eq(MofPolygonType.vertex_count(99), 0)
