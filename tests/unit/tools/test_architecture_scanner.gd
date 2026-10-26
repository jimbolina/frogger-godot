extends GutTest
## Architecture checks use synthetic sources, independent of retail files.

const Scanner = preload("res://tools/support/architecture_scanner.gd")
const LEGACY: String = "res://src/legacy/example.gd"
const GAME: String = "res://src/game/example.gd"


func _check(sources: Dictionary[String, String]) -> Array[Scanner.Violation]:
	return Scanner.new().check(sources)


func _has_rule(violations: Array[Scanner.Violation], rule: String) -> bool:
	for violation: Scanner.Violation in violations:
		if violation.rule == rule:
			return true
	return false


func test_legacy_io_and_unrelated_text_are_allowed() -> void:
	var source: String = "extends RefCounted\n" \
		+ "# Node, get_tree(), Input, preload('res://src/convert/bad.gd')\n" \
		+ "const TEXT = \"Node Time FileAccess get_tree()\"\n" \
		+ "const LONG_TEXT = '''SceneTree\nInput\npreload(\"res://scenes/boot.tscn\")'''\n" \
		+ "func read_file():\n\tvar f = FileAccess.open(\"user://data\", FileAccess.READ)\n" \
		+ "\tvar env = OS.get_environment(\"DATA\")\n\tvar cfg = ConfigFile.new()\n" \
		+ "\tcfg.load(env)\n\treturn f\n"
	assert_eq(_check({LEGACY: source}).size(), 0)


func test_project_class_name_dependencies_are_resolved() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends RefCounted\nvar renderer: RenderBridge\n",
		"res://src/convert/render.gd": "class_name RenderBridge\nextends RefCounted\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_true(_has_rule(violations, "layer"))
	assert_eq(violations[0].path, LEGACY)
	assert_eq(violations[0].line, 2)


func test_plain_data_child_methods_are_not_node_dependencies() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends RefCounted\nvar config: ConfigData\n" \
			+ "func read():\n\tconfig.add_child(config)\n\tconfig.get_parent()\n",
		"res://src/shared/config.gd": "class_name ConfigData\nextends RefCounted\n" \
			+ "func add_child(child):\n\tpass\nfunc get_parent():\n\treturn null\n",
	}
	assert_eq(_check(sources).size(), 0)


func test_literal_relative_preload_is_resolved() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends RefCounted\nconst VIEW = preload(\"../presentation/view.gd\")\n",
		"res://src/presentation/view.gd": "extends RefCounted\n",
	}
	assert_true(_has_rule(_check(sources), "layer"))


func test_literal_global_and_resource_loader_loads_are_resolved() -> void:
	for expression: String in [
		"load(\"res://src/convert/bad.gd\")",
		"ResourceLoader.load(\"res://src/convert/bad.gd\", \"GDScript\")",
	]:
		var sources: Dictionary[String, String] = {
			LEGACY: "extends RefCounted\nvar bad = " + expression + "\n",
			"res://src/convert/bad.gd": "extends RefCounted\n",
		}
		assert_true(_has_rule(_check(sources), "layer"), expression)


func test_named_and_path_inheritance_resolve_to_refcounted() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends DataBase\n",
		"res://src/shared/base.gd": "class_name DataBase\nextends \"middle.gd\"\n",
		"res://src/shared/middle.gd": "extends RefCounted\n",
	}
	assert_eq(_check(sources).size(), 0)


func test_inherited_node_base_is_rejected() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends DataBase\n",
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
		assert_true(_has_rule(_check({LEGACY: source}), "base"), source)


func test_inner_node_class_is_rejected() -> void:
	var source: String = "extends RefCounted\nclass Inner:\n\textends Node\n"
	var violations: Array[Scanner.Violation] = _check({LEGACY: source})
	assert_true(_has_rule(violations, "base"))
	assert_true(_has_rule(violations, "tree"))


func test_indirect_helper_dependency_reports_origin_and_line() -> void:
	var helper: String = "res://src/shared/helper.gd"
	var sources: Dictionary[String, String] = {
		LEGACY: "extends RefCounted\nvar helper: Helper\n",
		helper: "class_name Helper\nextends RefCounted\nvar renderer: Renderer\n",
		"res://src/presentation/renderer.gd": "class_name Renderer\nextends RefCounted\n",
	}
	var violations: Array[Scanner.Violation] = _check(sources)
	assert_eq(violations.size(), 1)
	assert_eq(violations[0].origin, LEGACY)
	assert_eq(violations[0].path, helper)
	assert_eq(violations[0].line, 3)
	assert_true(violations[0].format().contains("required by"))


func test_legacy_cannot_depend_on_gameplay() -> void:
	var sources: Dictionary[String, String] = {
		LEGACY: "extends RefCounted\nconst GAME = preload(\"res://src/game/model.gd\")\n",
		"res://src/game/model.gd": "extends RefCounted\n",
	}
	assert_true(_has_rule(_check(sources), "layer"))


func test_gameplay_cannot_depend_on_outer_layers() -> void:
	for target: String in ["src/legacy", "src/convert", "src/presentation", "scenes"]:
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
		LEGACY: "extends RefCounted\nconst SCENE = preload(\"res://assets/example.tscn\")\n",
	}), "layer"))


func test_tree_calls_and_node_path_syntax_are_rejected() -> void:
	for expression: String in [
		"get_tree()", "Engine.get_main_loop()", "$Child", "%Child", "get_node(\"Child\")",
	]:
		assert_true(_has_rule(_check({
			LEGACY: "extends RefCounted\nfunc f():\n\treturn " + expression + "\n",
		}), "tree"), expression)


func test_remainder_operator_is_not_a_node_dependency() -> void:
	assert_eq(_check({
		LEGACY: "extends RefCounted\nfunc f(value):\n\treturn value % count\n",
	}).size(), 0)


func test_computed_loads_and_dynamic_calls_require_review() -> void:
	for expression: String in [
		"load(path)", "preload(\"res://\" + name)", "ResourceLoader.load(path)",
		"object.call(\"tick\")", "object.callv(method, args)", "Callable(object, method)",
		"ClassDB.instantiate(\"Node\")", "Engine.get_singleton(name)",
	]:
		assert_true(_has_rule(_check({
			LEGACY: "extends RefCounted\nfunc f():\n\treturn " + expression + "\n",
		}), "review"), expression)


func test_unresolved_literal_script_dependency_requires_review() -> void:
	assert_true(_has_rule(_check({
		LEGACY: "extends RefCounted\nconst DATA = preload(\"res://outside/data.gd\")\n",
	}), "review"))


func test_escaped_strings_preserve_next_token_line_numbers() -> void:
	var source: String = "extends RefCounted\nconst TEXT = \"escaped \\\"Node\\\" text\"\n" \
		+ "var forbidden: Node\n"
	var violations: Array[Scanner.Violation] = _check({LEGACY: source})
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
