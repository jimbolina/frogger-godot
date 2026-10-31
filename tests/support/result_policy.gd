extends RefCounted
## Shared result rules used by the GUT hook and the wrapper's independent check.
##
## Two suites exist: [code]game[/code] ([code]tests/[/code], always run, asset-free)
## and [code]archive[/code] ([code]archive/tests/[/code], run only with the player's
## files). In both, every selected test must pass; a skip or pending test fails.
## Valid process exits are 0 (all passed) and 1 (any failure or problem).

const SUITE_VARIABLE: String = "FROGGER_TEST_SUITE"
const SUITES: Array[String] = ["game", "archive"]
const REPORT_VERSION: int = 2


## The suite named by [code]FROGGER_TEST_SUITE[/code]; unset selects the game suite.
static func current_suite() -> String:
	if OS.has_environment(SUITE_VARIABLE):
		return OS.get_environment(SUITE_VARIABLE)
	return "game"


## The machine report saved by one suite's GUT run.
static func report_path(suite: String) -> String:
	return "user://test_results_%s.json" % suite


## Describes why a player folder is unusable for the archive suite, or "".
static func input_error(directory: String) -> String:
	if directory.is_empty() or not RetailDirSource.looks_like(directory):
		return "FROGGER_DATA_DIR lacks FROGGER.EXE + FROGPSX.MWD"
	return ""


## Counts records; any failure, skip, pending test or problem gives exit 1.
static func evaluate(records: Array, initial_problems: Array = []) -> Dictionary:
	var result: Dictionary = {"pass": 0, "fail": 0, "skip": 0, "exit": 0,
		"problems": initial_problems.duplicate()}
	var problems: Array = result["problems"]
	var seen: Dictionary = {}
	for value: Variant in records:
		if not value is Dictionary:
			problems.append("malformed test record")
			continue
		var record: Dictionary = value
		if not record.get("id") is String or not record.get("status") is String \
				or not record.get("reason") is String:
			problems.append("malformed test identity/status/reason")
			continue
		var identity: String = record["id"]
		var status: String = record["status"]
		var reason: String = record["reason"]
		if identity.is_empty() or seen.has(identity):
			problems.append("empty or duplicate test identity: " + identity)
		seen[identity] = true
		match status:
			"pass":
				result["pass"] += 1
			"fail", "not_run":
				result["fail"] += 1
			"skip", "pending":
				result["skip"] += 1
				problems.append("unapproved " + status + ": " + identity + " (" + reason + ")")
			_:
				problems.append("unknown test status: " + status)
	if records.is_empty():
		problems.append("no tests ran")
	var failed: int = result["fail"]
	if failed > 0 or not problems.is_empty():
		result["exit"] = 1
	return result


## Creates one suite's machine report from independently inspectable records.
static func make_report(records: Array, suite: String, problems: Array = []) -> Dictionary:
	var report: Dictionary = evaluate(records, problems)
	report["version"] = REPORT_VERSION
	report["suite"] = suite
	report["records"] = records
	return report


## Returns the exact human summary that must agree with the process and report.
static func summary(result: Dictionary) -> String:
	return "SUMMARY: PASS=%d FAIL=%d SKIP=%d EXIT=%d" % [
		result["pass"], result["fail"], result["skip"], result["exit"]]


## Validates a saved report against its suite, the log summary, named skips and
## the actual process exit.
static func validate_report(value: Variant, log_text: String, process_exit: int,
		suite: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray(["missing or malformed machine report"])
	var report: Dictionary = value
	if report.get("version") != REPORT_VERSION or not report.get("records") is Array \
			or not report.get("problems") is Array \
			or not report.get("suite") is String:
		return PackedStringArray(["incomplete machine report"])
	if report["suite"] != suite or suite not in SUITES:
		errors.append("report suite disagrees with wrapper suite")
	var source_problems: Array = report["problems"]
	for problem: Variant in source_problems:
		if not problem is String:
			errors.append("malformed result problem")
	var records: Array = report["records"]
	var expected: Dictionary = evaluate(records)
	if not source_problems.is_empty():
		expected["exit"] = 1
	for key: String in ["pass", "fail", "skip", "exit"]:
		var count: Variant = report.get(key)
		if (not count is int and not count is float) or count != expected[key]:
			errors.append("report count/code disagrees: " + key)
	var policy_problems: Array = expected["problems"]
	if not policy_problems.is_empty():
		errors.append_array(PackedStringArray(policy_problems))
	var summaries := PackedStringArray()
	var skips := PackedStringArray()
	for line: String in log_text.split("\n"):
		var clean: String = line.strip_edges()
		if clean.begins_with("SUMMARY:"):
			summaries.append(clean)
		if clean.begins_with("SKIPPED "):
			skips.append(clean)
	if summaries.size() != 1 or summaries[0] != summary(expected):
		errors.append("missing, duplicate or inconsistent log summary")
	var expected_skips := PackedStringArray()
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		if record.get("status") in ["skip", "pending"]:
			expected_skips.append("SKIPPED %s (%s)" % [record.get("id"), record.get("reason")])
	expected_skips.sort()
	skips.sort()
	if skips != expected_skips:
		errors.append("named skip log disagrees with machine report")
	var expected_exit: int = expected["exit"]
	if process_exit != expected_exit:
		errors.append("process exit disagrees with result policy")
	if process_exit not in [0, 1]:
		errors.append("unexpected test process exit")
	return errors
