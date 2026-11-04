extends SceneTree
## Checks the archive suite's player folder before GUT, or verifies one suite's
## saved report afterwards.
##
##   -s res://tools/check/check_test_results.gd -- --input
##       Exit 0 when FROGGER_DATA_DIR names a folder with FROGGER.EXE and
##       FROGPSX.MWD; exit 1 when it is unset, empty or lacks either file.
##   -s res://tools/check/check_test_results.gd -- <log> <exit> [--suite=<name>]
##       Exit 0 when the suite's report agrees with the GUT log and process
##       exit; the suite is game (the default), imported or archive. With
##       FROGGER_TEST_SELECTION=1 a suite that selected nothing is valid.

const Policy := preload("res://tests/support/result_policy.gd")
const SUITE_OPTION: String = "--suite="


func _init() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() == 1 and arguments[0] == "--input":
		var problem: String = Policy.input_error(OS.get_environment("FROGGER_DATA_DIR"))
		if not problem.is_empty():
			print("RESULT ERROR: " + problem)
			quit(1)
		else:
			print("test_input: valid")
			quit(0)
		return
	var suite: String = "game"
	if arguments.size() == 3 and arguments[2].begins_with(SUITE_OPTION):
		suite = arguments[2].trim_prefix(SUITE_OPTION)
		arguments.resize(2)
	if arguments.size() != 2 or not arguments[1].is_valid_int() or suite not in Policy.SUITES:
		print("RESULT ERROR: expected test log path, process exit and optional --suite=<%s>" % "|".join(Policy.SUITES))
		quit(1)
		return
	var report: Variant = null
	if FileAccess.file_exists(Policy.report_path(suite)):
		report = JSON.parse_string(FileAccess.get_file_as_string(Policy.report_path(suite)))
	var log_text: String = ""
	if FileAccess.file_exists(arguments[0]):
		log_text = FileAccess.get_file_as_string(arguments[0])
	var errors: PackedStringArray = Policy.validate_report(
		report, log_text, arguments[1].to_int(), suite, Policy.selection_requested())
	for problem: String in errors:
		print("RESULT ERROR: " + problem)
	if errors.is_empty():
		print("test_results: valid %s suite, exit %d" % [suite, arguments[1].to_int()])
		quit(0)
	else:
		quit(1)
