extends GutTest
## Rendered scenario-run selections, the synthetic stage and the viewer hooks they use.

var _viewer: MapViewer

func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)

func _outputs() -> PackedStringArray:
	var folder: String = OS.get_user_data_dir().path_join("scenario-run")
	return PackedStringArray(["--screenshot-dir=" + folder, "--trace-jsonl=" + folder.path_join("trace.jsonl")])

func test_parse_reads_shared_selections() -> void:
	var arguments: PackedStringArray = _outputs()
	arguments.append_array(["--tick-limit=12", "--render-rate=144", "--scenario=line"])
	var settings: MapScenarioRun.Settings = MapScenarioRun.parse(arguments, "Path")
	assert_eq(settings.error, "")
	assert_eq(settings.tick_limit, 12)
	assert_eq(settings.render_rate, 144)
	assert_eq(settings.scenario, "line")
	var defaults: MapScenarioRun.Settings = MapScenarioRun.parse(_outputs(), "Entity")
	assert_eq(defaults.error, "")
	assert_eq(defaults.tick_limit, -1)
	assert_eq(defaults.render_rate, 60)

func test_parse_rejects_destinations_limits_rates_and_path_indices() -> void:
	assert_eq(MapScenarioRun.parse(PackedStringArray(["--screenshot-dir=captures"]), "Entity").error, "Entity output requires absolute external destinations")
	var limit: PackedStringArray = _outputs()
	limit.append("--tick-limit=100001")
	assert_eq(MapScenarioRun.parse(limit, "Path").error, "Path tick limit must be in 0..100000")
	var rate: PackedStringArray = _outputs()
	rate.append("--render-rate=50")
	assert_eq(MapScenarioRun.parse(rate, "Entity").error, "Entity render rate must be 30, 60 or 144")
	var level: PackedStringArray = _outputs()
	level.append("--level=ORG1")
	assert_eq(MapScenarioRun.parse(level, "Path").error, "A level path requires --path-index=0 or greater")
	assert_eq(MapScenarioRun.parse(level, "Entity").error, "")
	var index: PackedStringArray = _outputs()
	index.append("--path-index=2")
	assert_eq(MapScenarioRun.parse(index, "Path").error, "--path-index requires --level")

func test_synthetic_path_attaches_and_frames_on_the_synthetic_stage() -> void:
	assert_true(_viewer.show_scene(MapScenarioRun.synthetic_scene()))
	var scenario: PathScenario = PathScenario.builtin("line")
	assert_eq(scenario.error, "")
	assert_true(_viewer.attach_synthetic_path(scenario.definition, scenario.start))
	MapScenarioRun.frame_path(_viewer, scenario.definition)
	assert_true(_viewer._custom_camera)
	assert_eq(_viewer.path_snapshot().tick_index, 0)
	_viewer.set_playing(true)
	_viewer.advance_clock(1.0 / 30.0)
	assert_eq(_viewer.tick, 1)
	assert_eq(_viewer.path_snapshot().tick_index, 1)
	_viewer.set_controls_visible(false)
	assert_false(_viewer._ui.visible)
	assert_false(_viewer.entities_attached())
