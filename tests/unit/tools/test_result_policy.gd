extends GutTest
## Failure injection for reviewed skips and machine/log/process agreement.

const Policy := preload("res://tests/support/result_policy.gd")
const RETAIL_ID: String = "res://tests/golden/test_retail_detection.gd::test_retail_install_is_recognised"
const UNIT_ID: String = "res://tests/unit/example.gd::test_example"


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


func test_passing_report_agrees_with_log_and_process() -> void:
	var report: Dictionary = Policy.make_report([_record()], false)
	assert_eq(_count(report, "exit"), 0)
	assert_eq(Policy.validate_report(report, _log(report), 0, false).size(), 0)


func test_only_reviewed_retail_script_skips_get_exit_three() -> void:
	var records: Array = [_record(), _record(RETAIL_ID, "skip", Policy.RETAIL_REASON)]
	var report: Dictionary = Policy.make_report(records, false)
	assert_eq(_count(report, "pass"), 1)
	assert_eq(_count(report, "skip"), 1)
	assert_eq(_count(report, "exit"), 3)
	assert_eq(Policy.validate_report(report, _log(report), 3, false).size(), 0)


func test_manifest_is_exact_and_matches_current_retail_tests() -> void:
	var manifest: Dictionary = Policy.approved_skips()
	assert_eq(manifest.size(), 63, "Review each newly allowed retail identity")
	var discovered: Dictionary = {}
	for file: String in DirAccess.get_files_at("res://tests/golden"):
		if not file.begins_with("test_retail") or file.get_extension() != "gd":
			continue
		var path: String = "res://tests/golden".path_join(file)
		var script: GDScript = load(path)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if name.begins_with("test_"):
				discovered[path + "::" + name] = Policy.RETAIL_REASON
	assert_eq_deep(discovered, manifest)


func test_new_retail_identity_cannot_inherit_skip_permission() -> void:
	var report: Dictionary = Policy.make_report([
		_record(RETAIL_ID + "_new", "skip", Policy.RETAIL_REASON)], false)
	assert_eq(_count(report, "exit"), 1)
	var problems: Array = report["problems"]
	assert_gt(problems.size(), 0)


func test_wrong_reason_and_pending_are_never_allowed() -> void:
	for record: Dictionary in [
		_record(RETAIL_ID, "skip", "not implemented"),
		_record(RETAIL_ID, "pending", Policy.RETAIL_REASON),
		_record(UNIT_ID, "skip", Policy.RETAIL_REASON)]:
		var report: Dictionary = Policy.make_report([record], false)
		assert_eq(_count(report, "exit"), 1)


func test_retail_mode_rejects_even_reviewed_asset_free_skips() -> void:
	var report: Dictionary = Policy.make_report([
		_record(RETAIL_ID, "skip", Policy.RETAIL_REASON)], true)
	assert_eq(_count(report, "exit"), 1)


func test_empty_selection_and_unrun_or_no_assert_tests_fail() -> void:
	assert_eq(_count(Policy.make_report([], false), "exit"), 1)
	assert_eq(_count(Policy.make_report([_record(UNIT_ID, "not_run")], false), "exit"), 1)
	assert_eq(_count(Policy.make_report([_record(UNIT_ID, "fail", "asserted nothing")], false), "exit"), 1)


func test_failure_wins_over_approved_skips() -> void:
	var report: Dictionary = Policy.make_report([
		_record(UNIT_ID, "fail"), _record(RETAIL_ID, "skip", Policy.RETAIL_REASON)], false)
	assert_eq(_count(report, "fail"), 1)
	assert_eq(_count(report, "exit"), 1)


func test_fixture_and_runner_errors_fail_even_if_tests_pass() -> void:
	var report: Dictionary = Policy.make_report([_record()], false, ["fixture failed"])
	assert_eq(_count(report, "pass"), 1)
	assert_eq(_count(report, "exit"), 1)
	assert_eq(Policy.validate_report(report, _log(report), 1, false).size(), 0)


func test_supplied_invalid_directory_is_failure_not_asset_free() -> void:
	assert_eq(Policy.input_error(false, ""), "")
	assert_ne(Policy.input_error(true, ""), "")
	assert_ne(Policy.input_error(true, "res://does_not_exist"), "")
	assert_ne(Policy.input_error(true, "res://tests/unit"), "")


func test_missing_malformed_and_zero_reports_are_rejected() -> void:
	assert_gt(Policy.validate_report(null, "", 0, false).size(), 0)
	assert_gt(Policy.validate_report({}, "", 0, false).size(), 0)
	var empty: Dictionary = Policy.make_report([], false)
	assert_gt(Policy.validate_report(empty, _log(empty), 0, false).size(), 0)


func test_missing_duplicate_or_different_summary_is_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], false)
	for text: String in ["", _log(report) + _log(report),
		"SUMMARY: PASS=2 FAIL=0 SKIP=0 EXIT=0\n",
		"SUMMARY: PASS=1 FAIL=0 SKIP=0 EXIT=3\n"]:
		assert_gt(Policy.validate_report(report, text, 0, false).size(), 0)


func test_wrong_process_exit_and_retail_mode_are_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], false)
	assert_gt(Policy.validate_report(report, _log(report), 3, false).size(), 0)
	assert_gt(Policy.validate_report(report, _log(report), 2, false).size(), 0)
	assert_gt(Policy.validate_report(report, _log(report), 0, true).size(), 0)


func test_inconsistent_counts_and_duplicate_records_are_rejected() -> void:
	var report: Dictionary = Policy.make_report([_record()], false)
	report["pass"] = 2
	assert_gt(Policy.validate_report(report, _log(report), 0, false).size(), 0)
	assert_eq(_count(Policy.make_report([_record(), _record()], false), "exit"), 1)
	assert_eq(_count(Policy.make_report([{"id": 4}], false), "exit"), 1)


func test_missing_or_extra_named_skips_are_rejected() -> void:
	var report: Dictionary = Policy.make_report([
		_record(RETAIL_ID, "skip", Policy.RETAIL_REASON)], false)
	assert_gt(Policy.validate_report(report, Policy.summary(report), 3, false).size(), 0)
	assert_gt(Policy.validate_report(report, _log(report) + "SKIPPED invented (reason)\n",
		3, false).size(), 0)
