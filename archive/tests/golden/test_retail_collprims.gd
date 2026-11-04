extends RetailTest
## Needs the retail files: every model's collision primitives and decoded
## matrices, and the animated primitive parts detached for gameplay, match
## tests/golden/pc-retail-v3.0e/mof_collprims.tsv and
## animation_primitive_poses.tsv from tools/golden/make_golden_collprims.py.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _digest(values: PackedInt32Array) -> String:
	return GoldenFiles.list_digest32(values) if not values.is_empty() else "-"

func _match_golden(label: String, got: Array[PackedStringArray], file_name: String) -> void:
	var differences: PackedStringArray = GoldenFiles.differences(label, got, GoldenFiles.rows(file_name))
	for difference: String in differences:
		fail_test(difference)
	assert_eq(differences.size(), 0, "%s matches" % file_name)

func test_every_primitive_and_matrix_matches() -> void:
	assert_eq(_data.error, "")
	var rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	for entry: MwiEntry in _data.model_entries():
		var model: MofFile = _data.read_model(entry.index, problems)
		if model == null:
			continue
		for static_index: int in model.static_models.size():
			for part: MofPart in model.static_models[static_index].parts:
				var matrices := PackedInt32Array()
				for matrix: PackedInt32Array in part.matrices:
					matrices.append_array(matrix)
				for primitive_index: int in part.collprims.size():
					var primitive: MofPart.Collprim = part.collprims[primitive_index]
					rows.append(PackedStringArray([str(entry.index), entry.display_name(), str(static_index),
						str(part.index), str(int(part.borrows)), str(primitive_index), str(primitive.type),
						str(primitive.flags), "%d,%d,%d" % [primitive.offset.x, primitive.offset.y, primitive.offset.z],
						str(primitive.radius_squared), "%d,%d,%d" % [primitive.size.x, primitive.size.y, primitive.size.z],
						str(primitive.user), str(primitive.matrix_index), str(part.matrices.size()), _digest(matrices)]))
	assert_eq(problems.size(), 0, ", ".join(problems))
	_match_golden("collprims", rows, "mof_collprims.tsv")

func test_animated_primitive_parts_detach_source_poses() -> void:
	assert_eq(_data.error, "")
	var rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	var done: Dictionary[int, bool] = {}
	for golden: PackedStringArray in GoldenFiles.rows("animation_primitive_poses.tsv"):
		var resource_id: int = golden[0].to_int()
		if done.has(resource_id):
			continue
		done[resource_id] = true
		var model: MofFile = _data.read_model(resource_id, problems)
		assert_not_null(model, golden[1])
		if model == null:
			continue
		var setup: EntityPrimitiveSetup = EntityPrimitiveSetup.from_model(model, resource_id)
		assert_eq(setup.error, "", golden[1])
		if not setup.error.is_empty():
			continue
		assert_not_null(setup.part, golden[1])
		assert_eq(setup.primitives.size(), 1, golden[1])
		var primitive: EntityPrimitiveDefinition = setup.primitives[0]
		assert_eq(primitive.part_index, setup.part.part_index, golden[1])
		assert_eq(primitive.model_resource_id, resource_id, golden[1])
		var owner: MofPart = model.static_models[0].parts[primitive.part_index]
		assert_eq(primitive.rotation, owner.matrices[primitive.matrix_index].slice(0, 9) if primitive.matrix_index >= 0 else PackedInt32Array(), golden[1])
		for action_index: int in setup.part.actions.size():
			var action: EntityPrimitivePartDefinition.Action = setup.part.actions[action_index]
			var poses := PackedInt32Array()
			for frame: PackedInt32Array in action.frames:
				poses.append_array(frame)
			rows.append(PackedStringArray([str(resource_id), _data.mwi.get_entry(resource_id).display_name(),
				str(action_index), str(action.frames.size()), str(setup.part.part_index), _digest(action.actual_cels),
				_digest(poses)]))
	assert_eq(problems.size(), 0, ", ".join(problems))
	_match_golden("primitive poses", rows, "animation_primitive_poses.tsv")
