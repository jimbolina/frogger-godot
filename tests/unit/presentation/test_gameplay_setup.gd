extends GutTest
## Whole-map selection and source boundary defaults remain independent of retail files.

func test_supported_levels_are_limited_to_verified_single_player_scope() -> void:
	var data: ImportedAssets = ImportedAssets.open()
	assert_eq(data.error, "")
	for code: String in ["ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "SUB1", "SUB2", "SUB3", "SUB4", "SUB5", "FOR1", "FOR2", "VOL1", "VOL2", "VOL3", "CAV1", "CAV3", "CAV4", "DES1", "DES2", "DES3", "DES4", "DES5", "JUN1", "SWP1", "SWP2", "SWP3", "SWP4", "SWP5", "SKY1", "SKY2", "SKY3", "SKY4"]:
		assert_true(data.is_playable_level(FroggerIds.level_from_code(code)), code)
	for code: String in ["ORGM", "SUBM", "FOR3", "FOR4", "FOR5", "FORM", "VOL4", "VOL5", "VOLM", "CAV2", "CAV5", "CAVM", "DESM", "JUN2", "SWPM", "SKY5", "SKYM", "ISLAND", "unknown"]:
		assert_false(data.is_playable_level(FroggerIds.level_from_code(code)), code)
	assert_false(data.is_playable_level(-1))
	assert_false(data.is_playable_level(100))

func test_missing_boundary_markers_use_native_map_load_limits() -> void:
	assert_eq(GameplaySetup.bounds_for(null, null), Rect2i(-32767, -32767, 65534, 65534))

func test_each_boundary_marker_overrides_only_its_own_native_corner() -> void:
	var top := EntityDefinition.new()
	top.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -2000, 0, 1000])
	var bottom := EntityDefinition.new()
	bottom.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 2500, 0, -1500])
	assert_eq(GameplaySetup.bounds_for(top, null), Rect2i(-2000, -32767, 34767, 33767))
	assert_eq(GameplaySetup.bounds_for(null, bottom), Rect2i(-32767, -1500, 35267, 34267))
	assert_eq(GameplaySetup.bounds_for(top, bottom), Rect2i(-2000, -1500, 4500, 2500))

func test_invalid_dependencies_fail_without_a_partial_definition() -> void:
	var setup: GameplaySetup = GameplaySetup.from_data(null, FroggerIds.level_from_code("SUB1"), null, null, PackedInt32Array())
	assert_ne(setup.error, "")
	assert_null(setup.definition)

func test_skeletal_action_lengths_preserve_unsafe_action_slots() -> void:
	var model := MofFile.new()
	model.kind = MofFile.Kind.ANIMATED
	model.animated = MofAnimated.new()
	var set := MofAnimated.ModelSet.new()
	var info := MofAnimated.ModelInfo.new()
	info.static_model_index = 0
	set.models.append(info)
	for index: int in 3:
		var action := MofAnimated.Action.new()
		action.frame_count = 10 + index
		if index == 1:
			action.error = "invalid fixture transform"
		set.actions.append(action)
	model.animated.model_sets.append(set)
	assert_eq(GameplaySetup.model_action_lengths(model), PackedInt32Array([10, 0, 12]))
