extends GutHookScript
## Saves exact test outcomes after GUT and fails any skip, pending test or problem.
##
## The suite comes from [code]FROGGER_TEST_SUITE[/code] (unset means the game
## suite) and selects the saved report path.

const Policy := preload("res://tests/support/result_policy.gd")


## Collects test, fixture and logger failures before choosing the process exit.
func run() -> void:
	var runner: Object = gut
	var collector: Object = runner.call("get_test_collector")
	var scripts: Array = collector.get("scripts")
	var records: Array = []
	var problems: Array = []
	var suite: String = Policy.current_suite()
	if suite not in Policy.SUITES:
		problems.append("unknown test suite: " + suite)
	elif suite == "archive":
		var input_problem: String = Policy.input_error(
			OS.get_environment("FROGGER_DATA_DIR"))
		if not input_problem.is_empty():
			problems.append(input_problem)
	var test_filter: String = runner.get("unit_test_name")
	var class_filter: String = runner.get("inner_class_name")
	for script: Object in scripts:
		var skipped: bool = script.get("was_skipped")
		if not skipped and not script.get("was_run"):
			continue
		var inner: String = str(script.get("inner_class_name"))
		if not class_filter.is_empty() and inner.findn(class_filter) == -1:
			continue
		var identity_path: String = script.call("get_full_name")
		var tests: Array = script.get("tests")
		for test: Object in tests:
			var name: String = test.get("name")
			if not test_filter.is_empty() and not name.contains(test_filter):
				continue
			var status: String = "not_run"
			var reason: String = "selected test did not run"
			if skipped:
				status = "skip"
				reason = str(script.get("skip_reason"))
			elif test.call("is_failing"):
				status = "fail"
				reason = ""
			elif test.call("is_pending"):
				status = "pending"
				var texts: Array = test.get("pending_texts")
				reason = ", ".join(PackedStringArray(texts))
			elif test.call("is_passing"):
				status = "pass"
				reason = ""
			elif test.get("was_run"):
				status = "fail"
				reason = "asserted nothing"
			records.append({"id": identity_path + "::" + name, "status": status, "reason": reason})
		var fixtures: Array = script.get("setup_teardown_tests")
		for fixture: Object in fixtures:
			if fixture.call("is_failing") or fixture.call("is_pending"):
				problems.append("fixture failed/pending: %s::%s" % [
					identity_path, fixture.get("name")])
	var logger: Object = runner.call("get_logger")
	var logger_errors: Array = logger.call("get_errors")
	if not logger_errors.is_empty():
		problems.append("GUT reported %d runner errors" % logger_errors.size())
	var report: Dictionary = Policy.make_report(records, suite, problems)
	var file: FileAccess = FileAccess.open(Policy.report_path(suite), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report) + "\n")
		file.close()
	else:
		problems.append("could not save machine report")
		report = Policy.make_report(records, suite, problems)
	var lines := PackedStringArray()
	for record: Dictionary in records:
		if record["status"] in ["skip", "pending"]:
			lines.append("SKIPPED %s (%s)" % [record["id"], record["reason"]])
		elif record["status"] in ["fail", "not_run"]:
			lines.append("FAILED  %s (%s)" % [record["id"], record["reason"]])
	for problem: Variant in report["problems"]:
		lines.append("RESULT ERROR: " + str(problem))
	lines.append(Policy.summary(report))
	print("\n" + "\n".join(lines))
	var code: int = report["exit"]
	set_exit_code(code)
