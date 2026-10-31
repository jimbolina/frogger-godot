extends GutTest
## Failure injection for the no-skip result policy and machine/log/process agreement.

const Policy := preload("res://tests/support/result_policy.gd")
const UNIT_ID: String = "res://tests/unit/example.gd::test_example"
const ARCHIVE_ID: String = "res://archive/tests/golden/test_retail_example.gd::test_example"


func _record(identity: String = UNIT_ID, status: String = "pass", reason: String = "") -> Dictionary:
	return {"id": identity, "status": status, "reason": reason}


func _count(report: Dictionary, key: String) -> int:
	var count: int = report[key]
	return count


func _log(report: Dictionary) -> String:
	var lines := PackedStringArray()
	for record: Dictionary in report["records"]:
		if record["status"] in ["skip", "pending"]:
			lines.append("SKIPPED %s (%s)" % [record["id"], record["reason"]])
	lines.append(Policy.summary(report))
	return "\n".join(lines) + "\n"


func _has_problem(report: Dictionary, text: String) -> bool:
	for problem: Variant in report["problems"]:
		if str(problem).contains(text):
			return true
	return false


func test_passing_report_agrees_with_log_and_process() -> void:
	for suite: String in Policy.SUITES:
		var report: Dictionary = Policy.make_report([_record()], suite)
		assert_eq(_count(report, "exit"), 0)
		assert_eq(Policy.validate_report(report, _log(report), 0, suite).size(), 0)


func test_a_skip_is_a_failure() -> void:
	var report: Dictionary = Policy.make_report([_record(),
		_record(ARCHIVE_ID, "skip", "SKIP: FROGGER_DATA_DIR is not set")], "game")
	assert_eq(_count(report, "pass"), 1)
	assert_eq(_count(report, "skip"), 1)
	assert_eq(_count(report, "exit"), 1)
	assert_true(_has_problem(report, "unapproved skip: " + ARCHIVE_ID))
	var errors: PackedStringArray = Policy.validate_report(report, _log(report), 1, "game")
	assert_eq(Array(errors), ["unapproved skip: %s (SKIP: FROGGER_DATA_DIR is not set)" % ARCHIVE_ID])


func test_a_pending_test_is_a_failure() -> void:
	var report: Dictionary = Policy.make_report([_record(),
		_record(UNIT_ID + "_later", "pending", "not implemented")], "archive")
	assert_eq(_count(report, "skip"), 1)
	assert_eq(_count(report, "exit"), 1)
	assert_true(_has_problem(report, "unapproved pending: " + UNIT_ID + "_later"))


func test_empty_records_fail() -> void:
	var empty: Dictionary = Policy.make_report([], "game")
	assert_eq(_count(empty, "exit"), 1)
	assert_gt(Policy.validate_report(empty, _log(empty), 0, "game").size(), 0)


func test_unrun_or_no_assert_tests_fail() -> void:
	assert_eq(_count(Policy.make_report([_record(UNIT_ID, "not_run")], "game"), "exit"), 1)
	assert_eq(_count(Policy.make_report(
		[_record(UNIT_ID, "fail", "asserted nothing")], "game"), "exit"), 1)


func test_fixture_and_runner_errors_fail_even_if_tests_pass() -> void:
	var report: Dictionary = Policy.make_report([_record()], "game", ["fixture failed"])
	assert_eq(_count(report, "pass"), 1)
	assert_eq(_count(report, "exit"), 1)
	assert_eq(Policy.validate_report(report, _log(report), 1, "game").size(), 0)


func test_archive_input_needs_both_retail_files() -> void:
	assert_ne(Policy.input_error(""), "")
	assert_ne(Policy.input_error("res://does_not_exist"), "")
	assert_ne(Policy.input_error("res://tests/unit"), "")


func test_missing_and_malformed_reports_are_rejected() -> void:
	assert_gt(Policy.validate_report(null, "", 0, "game").size(), 0)
	assert_gt(Policy.validate_report({}, "", 0, "game").size(), 0)


func test_missing_duplicate_or_different_summary_is_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], "game")
	for text: String in ["", _log(report) + _log(report),
		"SUMMARY: PASS=2 FAIL=0 SKIP=0 EXIT=0\n",
		"SUMMARY: PASS=1 FAIL=0 SKIP=0 EXIT=1\n"]:
		assert_gt(Policy.validate_report(report, text, 0, "game").size(), 0)


func test_wrong_process_exit_or_suite_is_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], "game")
	for code: int in [1, 2, 3]:
		assert_gt(Policy.validate_report(report, _log(report), code, "game").size(), 0)
	assert_gt(Policy.validate_report(report, _log(report), 0, "archive").size(), 0)
	var unknown: Dictionary = Policy.make_report([_record()], "other")
	assert_gt(Policy.validate_report(unknown, _log(unknown), 0, "other").size(), 0)


func test_inconsistent_counts_and_duplicate_records_are_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], "game")
	report["pass"] = 2
	assert_gt(Policy.validate_report(report, _log(report), 0, "game").size(), 0)
	assert_eq(_count(Policy.make_report([_record(), _record()], "game"), "exit"), 1)
	assert_eq(_count(Policy.make_report([{"id": 4}], "game"), "exit"), 1)


func test_missing_or_extra_named_skips_are_rejected() -> void:
	var report: Dictionary = Policy.make_report([
		_record(UNIT_ID, "skip", "reason")], "game")
	assert_gt(Policy.validate_report(report, Policy.summary(report), 1, "game").size(), 0)
	assert_gt(Policy.validate_report(report, _log(report) + "SKIPPED invented (reason)\n",
		1, "game").size(), 0)


func test_suites_save_distinct_reports() -> void:
	assert_ne(Policy.report_path("game"), Policy.report_path("archive"))
