extends GutTest
## Visual overlay receives detached state and stays optional.

func test_path_inspection_configures_and_positions_marker() -> void:
	var inspection := PathInspection.new()
	add_child_autofree(inspection)
	assert_false(inspection.visible)
	var definition := PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 160
	segment.start = Vector3i.ZERO
	segment.end = Vector3i(10, 0, 0)
	definition.segments.append(segment)
	inspection.configure(definition)
	assert_not_null(inspection._curve.mesh)
	var snapshot := PathSnapshot.new()
	snapshot.position = Vector3i(256, -256, 512)
	snapshot.tangent = Vector3i(4096, 0, 0)
	inspection.set_snapshot(snapshot)
	assert_eq(inspection._marker.position, Vector3(1, 1, -2))
	assert_not_null(inspection._tangent.mesh)
	inspection.set_snapshot(null)
	assert_false(inspection._marker.visible)
