extends GutTest
## Viewer overlay lifecycle and one shared clock with independent path controls.

var _viewer: MapViewer

func before_each() -> void:
	var packed: PackedScene = load("res://scenes/tools/map_viewer.tscn")
	_viewer = packed.instantiate() as MapViewer
	_viewer.auto_open = false
	add_child_autofree(_viewer)
	assert_true(_viewer.show_scene(_viewer._synthetic_path_scene()))

func test_overlay_selection_visibility_and_shared_clock() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_eq(_viewer.set_entity_definitions(scenario.definitions), "")
	assert_not_null(_viewer._entity_inspection)
	assert_eq(_viewer._entity_inspection.marker_count(), 4)
	assert_false(_viewer._entity_inspection.visible)
	_viewer.set_entity_visibility(true)
	assert_true(_viewer._entity_inspection.visible)
	assert_string_contains(_viewer._entity_readout.text, "Base-transform inspection")
	assert_string_contains(_viewer._entity_readout.text, "Scripts/callbacks unexecuted")
	_viewer._on_entity_selected(2)
	assert_string_contains(_viewer._entity_readout.text, "no movement")
	_viewer.step_animation()
	assert_eq(_viewer.entity_snapshot().tick_index, 1)
	assert_eq(_viewer.entity_snapshot().entities[1].path.segment_distance, 10)
	assert_eq(_viewer.entity_snapshot().entities[2].path.segment_distance, 0)
	_viewer.seek_tick(0)
	assert_eq(_viewer.entity_snapshot().entities[1].path.segment_distance, 0)
	_viewer.seek_tick(7)
	assert_eq(_viewer.entity_snapshot().tick_index, 7)
	_viewer.set_camera_preset("map-slice")
	assert_false(_viewer._entity_inspection.visible)
	_viewer.set_camera_preset("default")
	assert_true(_viewer._entity_inspection.visible)

func test_path_controls_do_not_change_attached_entity_start() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_eq(_viewer.set_entity_definitions(scenario.definitions), "")
	var path: PathDefinition = PathScenario.builtin("line").definition
	path.path_index = 3
	_viewer._path_setup = PathSetup.new()
	_viewer._path_setup.definitions.append(path)
	_viewer._path_inspection = PathInspection.new()
	_viewer._world.add_child(_viewer._path_inspection)
	assert_true(_viewer.configure_path(3))
	_viewer.step_animation()
	assert_eq(_viewer.path_snapshot().segment_distance, 16)
	assert_eq(_viewer.entity_snapshot().entities[1].path.segment_distance, 10)
	var changed := PathStart.new()
	changed.speed = 100
	assert_true(_viewer.configure_path(3, changed))
	assert_eq(_viewer.entity_snapshot().entities[1].path.segment_distance, 0)
	_viewer.step_animation()
	assert_eq(_viewer.entity_snapshot().entities[1].path.segment_distance, 10)

func test_replacement_releases_run_definitions_and_markers() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_eq(_viewer.set_entity_definitions(scenario.definitions), "")
	var old: WeakRef = weakref(_viewer._entity_inspection)
	assert_true(_viewer.show_scene(_viewer._synthetic_path_scene()))
	await get_tree().process_frame
	var released: EntityInspection = old.get_ref()
	assert_null(released)
	assert_null(_viewer.entity_snapshot())
	assert_null(_viewer._entity_inspection)
	assert_eq(_viewer._entity_definitions.size(), 0)
	assert_false(_viewer._entity_visible)
	assert_eq(_viewer._world.get_child_count(), 3)

func test_diagnostics_are_visible_and_returned_as_detached_values() -> void:
	var scenario: EntityScenario = EntityScenario.builtin("shared-path")
	assert_eq(_viewer.set_entity_definitions(scenario.definitions), "")
	var setup := EntitySetup.new()
	var diagnostic := EntitySetupDiagnostic.new()
	diagnostic.code = "unknown_behavior"
	diagnostic.message = "Unsupported form"
	setup.diagnostics.append(diagnostic)
	_viewer._entity_setup = setup
	_viewer._entity_readout.tooltip_text = "\n".join(_viewer._entity_diagnostic_text())
	_viewer._update_entity_readout()
	assert_string_contains(_viewer._entity_readout.text, "1 diagnostics")
	assert_string_contains(_viewer._entity_readout.tooltip_text, "unknown_behavior")
	var detached: Array[EntitySetupDiagnostic] = _viewer.entity_diagnostics()
	detached[0].code = "changed"
	assert_eq(_viewer._entity_setup.diagnostics[0].code, "unknown_behavior")
