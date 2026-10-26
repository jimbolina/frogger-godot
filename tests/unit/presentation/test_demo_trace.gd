extends GutTest
## Ensures reference CSV layout preserves source identities and actual live-list order.

func test_projection_uses_committed_frog_and_live_walk_order() -> void:
	var trace := DemoTrace.new()
	trace.form_ids = {4: 32770, 7: 18}
	trace.entity_types = {4: 6, 7: 9}
	var state := GameplayState.new()
	state.frog.flags = 3
	state.frog.cell = Vector2i(3, 8)
	state.frog.matrix12[9] = 123
	state.frog.matrix12[10] = -456
	state.frog.matrix12[11] = 789
	state.entities = EntityRunSnapshot.new()
	for id: int in [4, 7]:
		var entity := EntitySnapshot.new()
		entity.entity_index = id
		entity.unique_id = id + 100
		entity.matrix12[9] = id * 10
		state.entities.entities.append(entity)
	state.entities.live_order = PackedInt32Array([7, 4])
	trace.append(state, 128, 24)
	assert_eq(trace.frog_rows[0], "call,page,map,frog,grid_x,grid_z,x,y,z,mode,flags,input")
	assert_eq(trace.frog_rows[1], "0,7,24,0,3,8,123,-456,789,0,3,128")
	assert_eq(trace.entity_rows[1], "0,24,0,107,18,9,70,0,0")
	assert_eq(trace.entity_rows[2], "0,24,1,104,32770,6,40,0,0")
	state.entities.entities[0].live = false
	trace.append(state, -1, 24)
	assert_eq(trace.entity_rows[3], "1,24,0,107,18,9,70,0,0")
	assert_eq(trace.entity_rows.size(), 4)

func test_external_evidence_rejects_checkout_destination() -> void:
	var trace := DemoTrace.new()
	assert_false(trace.save(ProjectSettings.globalize_path("res://"), {}).is_empty())
