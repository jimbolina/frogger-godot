extends GutTest
## Architecture checks use synthetic sources, independent of retail files.

const Scanner = preload("res://tools/support/architecture_scanner.gd")
const SOURCE: String = "res://src/source/example.gd"
const GAME: String = "res://src/game/example.gd"


func _check(sources: Dictionary[String, String]) -> Array[Scanner.Violation]:
	return Scanner.new().check(sources)


func _has_rule(violations: Array[Scanner.Violation], rule: String) -> bool:
	for violation: Scanner.Violation in violations:
		if violation.rule == rule:
			return true
	return false


func test_source_io_and_unrelated_text_are_allowed() -> void:
	var source: String = "extends RefCounted\n" \
		+ "# Node, get_tree(), Input, preload('res://src/convert/bad.gd')\n" \
		+ "const TEXT = \"Node Time FileAccess get_tree()\"\n" \
		+ "const LONG_TEXT = '''SceneTree\nInput\npreload(\"res://scenes/boot.tscn\")'''\n" \
		+ "func read_file():\n\tvar f = FileAccess.open(\"user://data\", FileAccess.READ)\n" \
		+ "\tvar env = OS.get_environment(\"DATA\")\n\tvar cfg = ConfigFile.new()\n" \
		+ "\tcfg.load(env)\n\treturn f\n"
	assert_eq(_check({SOURCE: source}).size(), 0)


func test_project_class_name_dependencies_are_resolved() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends RefCounted\nvar renderer: RenderBridge\n",
		"res://src/convert/render.gd": "class_name RenderBridge\nextends RefCounted\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_true(_has_rule(violations, "layer"))
	assert_eq(violations[0].path, SOURCE)
	assert_eq(violations[0].line, 2)


func test_plain_data_child_methods_are_not_node_dependencies() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends RefCounted\nvar config: ConfigData\n" \
			+ "func read():\n\tconfig.add_child(config)\n\tconfig.get_parent()\n",
		"res://src/shared/config.gd": "class_name ConfigData\nextends RefCounted\n" \
			+ "func add_child(child):\n\tpass\nfunc get_parent():\n\treturn null\n",
	}
	assert_eq(_check(sources).size(), 0)


func test_literal_relative_preload_is_resolved() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends RefCounted\nconst VIEW = preload(\"../presentation/view.gd\")\n",
		"res://src/presentation/view.gd": "extends RefCounted\n",
	}
	assert_true(_has_rule(_check(sources), "layer"))


func test_literal_global_and_resource_loader_loads_are_resolved() -> void:
	for expression: String in [
		"load(\"res://src/convert/bad.gd\")",
		"ResourceLoader.load(\"res://src/convert/bad.gd\", \"GDScript\")",
	]:
		var sources: Dictionary[String, String] = {
			SOURCE: "extends RefCounted\nvar bad = " + expression + "\n",
			"res://src/convert/bad.gd": "extends RefCounted\n",
		}
		assert_true(_has_rule(_check(sources), "layer"), expression)


func test_named_and_path_inheritance_resolve_to_refcounted() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends DataBase\n",
		"res://src/shared/base.gd": "class_name DataBase\nextends \"middle.gd\"\n",
		"res://src/shared/middle.gd": "extends RefCounted\n",
	}
	assert_eq(_check(sources).size(), 0)


func test_inherited_node_base_is_rejected() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends DataBase\n",
		"res://src/shared/base.gd": "class_name DataBase\nextends \"middle.gd\"\n",
		"res://src/shared/middle.gd": "extends Node3D\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_true(_has_rule(violations, "base"))
	assert_true(_has_rule(violations, "tree"))


func test_missing_unknown_resource_and_cyclic_bases_are_rejected() -> void:
	for source: String in [
		"class_name Example\n",
		"extends UnknownBase\n",
		"extends Resource\n",
		"class_name Example\nextends Example\n",
		"extends \"missing.gd\"\n",
	]:
		assert_true(_has_rule(_check({SOURCE: source}), "base"), source)


func test_inner_node_class_is_rejected() -> void:
	var source: String = "extends RefCounted\nclass Inner:\n\textends Node\n"
	var violations: Array[Scanner.Violation] = _check({SOURCE: source})
	assert_true(_has_rule(violations, "base"))
	assert_true(_has_rule(violations, "tree"))


func test_indirect_helper_dependency_reports_origin_and_line() -> void:
	var helper: String = "res://src/shared/helper.gd"
	var sources: Dictionary[String, String] = {
		SOURCE: "extends RefCounted\nvar helper: Helper\n",
		helper: "class_name Helper\nextends RefCounted\nvar renderer: Renderer\n",
		"res://src/presentation/renderer.gd": "class_name Renderer\nextends RefCounted\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_eq(violations.size(), 1)
	assert_eq(violations[0].origin, SOURCE)
	assert_eq(violations[0].path, helper)
	assert_eq(violations[0].line, 3)
	assert_true(violations[0].format().contains("required by"))


func test_source_cannot_depend_on_gameplay() -> void:
	var sources: Dictionary[String, String] = {
		SOURCE: "extends RefCounted\nconst GAME = preload(\"res://src/game/model.gd\")\n",
		"res://src/game/model.gd": "extends RefCounted\n",
	}
	assert_true(_has_rule(_check(sources), "layer"))


func test_gameplay_cannot_depend_on_outer_layers() -> void:
	for target: String in ["src/source", "src/application", "src/inspection", "src/convert", "src/presentation", "scenes"]:
		var source: String = "extends RefCounted\nconst BAD = preload(\"res://" \
			+ target + "/bad.gd\")\n"
		assert_true(_has_rule(_check({GAME: source}), "layer"), target)


func test_gameplay_environment_calls_are_rejected() -> void:
	for expression: String in [
		"FileAccess.open(\"user://file\", 1)", "DirAccess.open(\"user://\")",
		"ConfigFile.new()", "ZIPReader.new()", "ZIPPacker.new()",
		"Input.is_action_pressed(\"jump\")", "Time.get_ticks_msec()",
		"OS.get_environment(\"NAME\")", "ResourceLoader.load(\"res://texture.png\")",
		"load(\"res://src/game/data.gd\")",
	]:
		var source: String = "extends RefCounted\nfunc tick():\n\treturn " + expression + "\n"
		assert_true(_has_rule(_check({GAME: source}), "environment"), expression)


func test_gameplay_literal_data_script_preload_is_allowed() -> void:
	var sources: Dictionary[String, String] = {
		GAME: "extends RefCounted\nconst DATA = preload(\"res://src/game/data.gd\")\n",
		"res://src/game/data.gd": "extends RefCounted\nvar value: int = 0\n",
	}
	assert_eq(_check(sources).size(), 0)


func test_gameplay_comments_and_unrelated_strings_are_allowed() -> void:
	assert_eq(_check({
		GAME: "extends RefCounted\n# Input Time OS FileAccess call(path)\n" \
			+ "const LABEL = \"Input Time FileAccess ResourceLoader Node\"\n",
	}).size(), 0)


func test_gameplay_indirect_environment_dependency_is_rejected() -> void:
	var helper: String = "res://src/shared/helper.gd"
	var sources: Dictionary[String, String] = {
		GAME: "extends RefCounted\nvar helper: Helper\n",
		helper: "class_name Helper\nextends RefCounted\n" \
			+ "func now():\n\treturn Time.get_ticks_msec()\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_eq(violations.size(), 1)
	assert_eq(violations[0].rule, "environment")
	assert_eq(violations[0].path, helper)
	assert_eq(violations[0].origin, GAME)


func test_scene_resources_are_rejected_outside_scenes_folder() -> void:
	assert_true(_has_rule(_check({
		SOURCE: "extends RefCounted\nconst SCENE = preload(\"res://assets/example.tscn\")\n",
	}), "layer"))


func test_tree_calls_and_node_path_syntax_are_rejected() -> void:
	for expression: String in [
		"get_tree()", "Engine.get_main_loop()", "$Child", "%Child", "get_node(\"Child\")",
	]:
		assert_true(_has_rule(_check({
			SOURCE: "extends RefCounted\nfunc f():\n\treturn " + expression + "\n",
		}), "tree"), expression)


func test_remainder_operator_is_not_a_node_dependency() -> void:
	assert_eq(_check({
		SOURCE: "extends RefCounted\nfunc f(value):\n\treturn value % count\n",
	}).size(), 0)


func test_computed_loads_and_dynamic_calls_require_review() -> void:
	for expression: String in [
		"load(path)", "preload(\"res://\" + name)", "ResourceLoader.load(path)",
		"object.call(\"tick\")", "object.callv(method, args)", "Callable(object, method)",
		"ClassDB.instantiate(\"Node\")", "Engine.get_singleton(name)",
	]:
		assert_true(_has_rule(_check({
			SOURCE: "extends RefCounted\nfunc f():\n\treturn " + expression + "\n",
		}), "review"), expression)


func test_unresolved_literal_script_dependency_requires_review() -> void:
	assert_true(_has_rule(_check({
		SOURCE: "extends RefCounted\nconst DATA = preload(\"res://outside/data.gd\")\n",
	}), "review"))


func test_escaped_strings_preserve_next_token_line_numbers() -> void:
	var source: String = "extends RefCounted\nconst TEXT = \"escaped \\\"Node\\\" text\"\n" \
		+ "var forbidden: Node\n"
	var violations: Array[Scanner.Violation] = _check({SOURCE: source})
	assert_eq(violations.size(), 1)
	assert_eq(violations[0].line, 3)

func test_entity_name_dispatch_is_rejected_but_diagnostics_are_allowed() -> void:
	for expression: String in [
		"if definition.entity_name == \"MOVING\":\n\t\tpass",
		"if \"MOVING\" != definition.entity_name:\n\t\tpass",
		"if definition.entity_name in [\"STATIC\", \"MOVING\"]:\n\t\tpass",
		"match definition.entity_name:\n\t\t_:\n\t\t\tpass",
	]:
		var source: String = "extends RefCounted\nfunc update(definition):\n\t" + expression + "\n"
		assert_true(_has_rule(_check({GAME: source}), "behavior"), expression)
	var diagnostic: String = "extends RefCounted\nfunc describe(definition):\n\treturn \"Unknown behavior %s\" % definition.entity_name\n"
	assert_eq(_check({GAME: diagnostic}).size(), 0)


func test_application_adapters_reject_environment_and_inspection_dependencies() -> void:
	var adapter: String = "res://src/application/adapter.gd"
	assert_true(_has_rule(_check({adapter: "extends RefCounted\nfunc f():\n\treturn OS.get_environment(\"DATA\")\n"}), "environment"))
	assert_true(_has_rule(_check({adapter: "extends RefCounted\nconst Guard = preload(\"res://src/inspection/guard.gd\")\n"}), "layer"))
	assert_eq(_check({adapter: "extends RefCounted\nvar facts: SourceFacts\n", "res://src/source/facts.gd": "class_name SourceFacts\nextends RefCounted\nfunc read():\n\treturn FileAccess.open(\"data\", 1)\n"}).size(), 0)


func _rule_count(violations: Array[Scanner.Violation], rule: String) -> int:
	var count: int = 0
	for violation: Scanner.Violation in violations:
		if violation.rule == rule:
			count += 1
	return count


func test_shipped_script_cannot_load_archive_path() -> void:
	var path: String = "res://scenes/boot.gd"
	var violations: Array[Scanner.Violation] = _check({
		path: "extends Node\nconst OLD = preload(\"res://archive/x.gd\")\n",
		"res://archive/x.gd": "extends RefCounted\n",
	})
	assert_eq(_rule_count(violations, "archive"), 1)
	assert_eq(violations[0].path, path)
	assert_eq(violations[0].line, 2)


func test_shipped_script_cannot_use_archive_class_name() -> void:
	for path: String in ["res://src/convert/view.gd", "res://tests/unit/test_x.gd",
			"res://tools/tool.gd", "res://assets/helper.gd"]:
		var violations: Array[Scanner.Violation] = _check({
			path: "extends Node\nfunc f():\n\treturn RetailReader.new()\n",
			"res://archive/source/reader.gd": "class_name RetailReader\nextends RefCounted\n",
		})
		assert_eq(_rule_count(violations, "archive"), 1, path)


func test_transitive_archive_dependency_reports_origin() -> void:
	var adapter: String = "res://src/application/adapter.gd"
	var scene: String = "res://scenes/level.gd"
	var violations: Array[Scanner.Violation] = _check({
		scene: "extends Node3D\nvar adapter: LevelAdapter\n",
		adapter: "class_name LevelAdapter\nextends RefCounted\nvar reader: RetailReader\n",
		"res://archive/source/reader.gd": "class_name RetailReader\nextends RefCounted\n",
	})
	assert_eq(_rule_count(violations, "archive"), 2)
	for violation: Scanner.Violation in violations:
		assert_eq(violation.rule, "archive")
		assert_eq(violation.path, adapter)
		assert_eq(violation.line, 3)
	var origins: Array[String] = [violations[0].origin, violations[1].origin]
	var expected: Array[String] = [adapter, scene]
	origins.sort()
	expected.sort()
	assert_eq(origins, expected)
	assert_true(violations[0].format().contains("required by") \
		or violations[1].format().contains("required by"))


func test_archive_scripts_may_depend_on_shipped_code() -> void:
	assert_eq(_check({
		"res://archive/tests/test_old.gd": "extends Node\nvar facts: SourceFacts\n" \
			+ "const ARCHIVED = preload(\"res://archive/other.gd\")\n" \
			+ "func f():\n\treturn FileAccess.open(\"data\", 1)\n",
		"res://archive/other.gd": "extends Node\n",
		"res://src/source/facts.gd": "class_name SourceFacts\nextends RefCounted\n",
	}).size(), 0)


func test_archived_source_keeps_the_source_layer_rules() -> void:
	var archived: String = "res://archive/source/reader.gd"
	assert_eq(_check({
		archived: "extends RefCounted\nvar level: LevelData\nfunc read():\n\treturn FileAccess.open(\"data\", 1)\n",
		"res://src/data/level.gd": "class_name LevelData\nextends Resource\n",
	}).size(), 0)
	for target: String in ["src/game", "src/application", "src/convert", "src/presentation",
			"src/inspection", "scenes"]:
		assert_true(_has_rule(_check({
			archived: "extends RefCounted\nconst BAD = preload(\"res://" + target + "/bad.gd\")\n",
		}), "layer"), target)
	var node: Array[Scanner.Violation] = _check({archived: "extends Node\n"})
	assert_true(_has_rule(node, "base"))
	assert_true(_has_rule(node, "tree"))


func test_archived_source_helpers_are_checked_transitively() -> void:
	var archived: String = "res://archive/source/reader.gd"
	var helper: String = "res://archive/source/helper.gd"
	var violations: Array[Scanner.Violation] = _check({
		archived: "extends RefCounted\nvar helper: ReaderHelper\n",
		helper: "class_name ReaderHelper\nextends RefCounted\nvar view: View\n",
		"res://src/presentation/view.gd": "class_name View\nextends RefCounted\n",
	})
	assert_eq(violations.size(), 2)
	for violation: Scanner.Violation in violations:
		assert_eq(violation.rule, "layer")
		assert_eq(violation.path, helper)
		assert_eq(violation.line, 3)


func test_archive_tests_may_use_archived_source_but_shipped_tests_may_not() -> void:
	var reader: String = "res://archive/source/reader.gd"
	var sources: Dictionary[String, String] = {
		"res://archive/tests/unit/test_reader.gd": "extends Node\nfunc f():\n\treturn RetailReader.new()\n",
		reader: "class_name RetailReader\nextends RefCounted\n",
	}
	assert_eq(_check(sources).size(), 0)
	sources["res://tests/unit/test_reader.gd"] = "extends Node\nfunc f():\n\treturn RetailReader.new()\n"
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_eq(_rule_count(violations, "archive"), 1)
	assert_eq(violations[0].origin, "res://tests/unit/test_reader.gd")


func test_scene_and_resource_archive_references_are_rejected() -> void:
	var scene: String = "res://scenes/level.tscn"
	var text: String = "[gd_scene format=3]\n\n" \
		+ "[ext_resource type=\"Script\" path=\"res://archive/old.gd\" id=\"1\"]\n"
	var violations: Array[Scanner.Violation] = _check({scene: text})
	assert_eq(violations.size(), 1)
	assert_eq(violations[0].rule, "archive")
	assert_eq(violations[0].path, scene)
	assert_eq(violations[0].line, 3)
	assert_eq(Scanner.scan_resource("res://assets/level.tres", text).size(), 1)
	assert_eq(Scanner.scan_resource("res://archive/level.tscn", text).size(), 0)
	assert_eq(Scanner.scan_resource(scene,
		"[ext_resource type=\"Script\" path=\"res://src/view.gd\" id=\"1\"]\n").size(), 0)


func test_data_resource_schema_is_allowed() -> void:
	assert_eq(_check({
		"res://src/data/level.gd": "class_name LevelData\nextends Resource\n" \
			+ "@export var texture: Texture2D\n@export var mesh: ArrayMesh\n" \
			+ "@export var scene: PackedScene\n@export var sound: AudioStreamWAV\n" \
			+ "@export var animations: AnimationLibrary\n@export var parts: Array[PartData] = []\n",
		"res://src/data/part.gd": "class_name PartData\nextends Resource\n" \
			+ "class Inner:\n\textends Resource\n",
	}).size(), 0)


func test_data_rejects_nodes_tree_calls_and_environment() -> void:
	var path: String = "res://src/data/bad.gd"
	var node: Array[Scanner.Violation] = _check({path: "extends Node\n"})
	assert_true(_has_rule(node, "base"))
	assert_true(_has_rule(node, "tree"))
	for expression: String in ["get_tree()", "scene.instantiate().get_node(\"X\")"]:
		assert_true(_has_rule(_check({
			path: "extends Resource\nfunc f(scene):\n\treturn " + expression + "\n",
		}), "tree"), expression)
	for expression: String in ["FileAccess.open(\"user://x\", 1)", "load(\"res://x.tres\")"]:
		assert_true(_has_rule(_check({
			path: "extends Resource\nfunc f():\n\treturn " + expression + "\n",
		}), "environment"), expression)
	assert_true(_has_rule(_check({
		path: "extends Resource\nfunc f(o):\n\treturn o.call(\"x\")\n",
	}), "review"))


func test_packed_scene_exemption_is_limited_to_data() -> void:
	assert_true(_has_rule(_check({
		SOURCE: "extends RefCounted\nvar scene: PackedScene\n",
	}), "tree"))


func test_data_layer_dependency_rules() -> void:
	var data: String = "res://src/data/level.gd"
	var schema: String = "class_name LevelData\nextends Resource\n"
	var use: String = "extends RefCounted\nvar level: LevelData\n"
	assert_true(_has_rule(_check({GAME: use, data: schema}), "layer"))
	assert_eq(_check({"res://src/application/adapter.gd": use, data: schema}).size(), 0)
	assert_eq(_check({SOURCE: use, data: schema}).size(), 0)
	for target: String in ["src/game", "src/application", "src/convert", "src/presentation",
			"src/inspection", "scenes"]:
		assert_true(_has_rule(_check({
			data: schema + "const BAD = preload(\"res://" + target + "/bad.gd\")\n",
		}), "layer"), target)
	assert_true(_has_rule(_check({
		data: schema + "const BAD = preload(\"res://assets/level.tscn\")\n",
	}), "layer"))
	assert_true(_has_rule(_check({
		data: schema + "var old: RetailReader\n",
		"res://archive/source/reader.gd": "class_name RetailReader\nextends RefCounted\n",
	}), "archive"))


func test_application_storage_may_use_file_io() -> void:
	var source: String = "extends RefCounted\nfunc f():\n\treturn FileAccess.open(\"user://s\", 1)\n"
	assert_eq(_check({"res://src/application/storage/store.gd": source}).size(), 0)
	assert_eq(_check({"res://src/application/loaders/loader.gd": source}).size(), 0)
	assert_true(_has_rule(_check({"res://src/application/other.gd": source}), "environment"))


func test_application_loaders_may_compute_resource_paths() -> void:
	var source: String = "extends RefCounted\nfunc f(path: String):\n\treturn ResourceLoader.load(path)\n"
	assert_eq(_check({"res://src/application/loaders/loader.gd": source}).size(), 0)
	assert_true(_has_rule(_check({"res://src/application/other.gd": source}), "review"))


func test_lighting_types_belong_to_presentation() -> void:
	for type_name: String in Scanner.LIGHTING_TYPES:
		var source: String = "extends Node\nfunc f():\n\treturn %s.new()\n" % type_name
		for path: String in ["res://src/convert/x.gd", "res://src/inspection/x.gd"]:
			var violations: Array[Scanner.Violation] = _check({path: source})
			assert_eq(violations.size(), 1, path + " " + type_name)
			assert_true(_has_rule(violations, "lighting-ownership"), path + " " + type_name)
			assert_eq(violations[0].line, 3)
		assert_eq(_check({"res://src/presentation/x.gd": source}).size(), 0, type_name)


func test_lighting_names_in_text_and_members_are_allowed() -> void:
	assert_eq(_check({
		"res://src/convert/x.gd": "extends RefCounted\n## Environment normals and Light3D notes.\n" \
			+ "# WorldEnvironment\nconst LABEL = \"DirectionalLight3D Environment\"\n" \
			+ "func f(o):\n\treturn o.Environment\n",
	}).size(), 0)


func test_gameplay_lighting_is_a_tree_and_ownership_violation() -> void:
	var violations: Array[Scanner.Violation] = _check({
		GAME: "extends RefCounted\nvar sun: DirectionalLight3D\n",
	})
	assert_true(_has_rule(violations, "tree"))
	assert_true(_has_rule(violations, "lighting-ownership"))


func test_lighting_outside_src_is_exempt() -> void:
	var source: String = "extends Node3D\nfunc f():\n\tvar sun := DirectionalLight3D.new()\n" \
		+ "\tvar world := WorldEnvironment.new()\n\tworld.environment = Environment.new()\n" \
		+ "\treturn sun\n"
	for path: String in ["res://scenes/level.gd", "res://tests/unit/test_x.gd",
			"res://tools/probe.gd", "res://archive/tools/probe.gd"]:
		assert_eq(_rule_count(_check({path: source}), "lighting-ownership"), 0, path)


func test_every_src_folder_is_classified() -> void:
	var folders: PackedStringArray = DirAccess.get_directories_at("res://src")
	assert_gt(folders.size(), 0)
	var scanner := Scanner.new()
	assert_false(scanner.classifies("res://src/unclassified/example.gd"))
	for folder: String in folders:
		assert_true(scanner.classifies("res://src/%s/example.gd" % folder), folder)
