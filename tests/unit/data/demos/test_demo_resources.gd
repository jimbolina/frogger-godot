extends GutTest
## SourceDemoFile survives a resource save and load with its input stream.

const PATH: String = "user://test_demo_resources.tres"


func after_all() -> void:
	DirAccess.remove_absolute(PATH)


func test_demo_round_trip() -> void:
	var demo := SourceDemoFile.new()
	demo.duration = 900
	demo.start_grid_x = 4
	demo.start_grid_z = 2
	demo.input_bytes = PackedByteArray([1, 0, 128])
	assert_eq(ResourceSaver.save(demo, PATH), OK)
	var loaded := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SourceDemoFile
	assert_not_null(loaded)
	assert_eq([loaded.duration, loaded.start_grid_x, loaded.start_grid_z], [900, 4, 2])
	assert_eq(loaded.input_at(2), 128)
	assert_true(loaded.is_valid())
