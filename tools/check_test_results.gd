extends SceneTree
## Checks retail inputs before GUT or verifies its persisted report afterwards.

const Policy := preload("res://tests/support/result_policy.gd")


func _init() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var supplied: bool = OS.has_environment(GameDataLocator.ENV_VAR)
	if arguments.size() == 1 and arguments[0] == "--input":
		var problem: String = Policy.input_error(supplied,
			OS.get_environment(GameDataLocator.ENV_VAR))
		if not problem.is_empty():
			print("RESULT ERROR: " + problem)
			quit(1)
		else:
			print("test_input: valid")
			quit(0)
		return
	if arguments.size() != 2 or not arguments[1].is_valid_int():
		print("RESULT ERROR: expected test log path and process exit")
		quit(1)
		return
	var report: Variant = null
	if FileAccess.file_exists(Policy.REPORT_PATH):
		report = JSON.parse_string(FileAccess.get_file_as_string(Policy.REPORT_PATH))
	var log_text: String = ""
	if FileAccess.file_exists(arguments[0]):
		log_text = FileAccess.get_file_as_string(arguments[0])
	var errors: PackedStringArray = Policy.validate_report(
		report, log_text, arguments[1].to_int(), supplied)
	for problem: String in errors:
		print("RESULT ERROR: " + problem)
	if errors.is_empty():
		print("test_results: valid, exit %d" % arguments[1].to_int())
		quit(0)
	else:
		quit(1)
