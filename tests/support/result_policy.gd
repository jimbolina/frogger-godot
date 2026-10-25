extends RefCounted
## Shared result rules used by the GUT hook and the wrapper's independent check.

const MANIFEST_PATH: String = "res://tests/support/retail_skips.json"
const REPORT_PATH: String = "user://test_results.json"
const RETAIL_REASON: String = "SKIP: FROGGER_DATA_DIR is not set"


## Loads the reviewed exact identities; inheritance never grants a skip.
static func approved_skips() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return value if value is Dictionary else {}


## Checks the supplied folder, including an explicitly empty environment value.
static func input_error(supplied: bool, directory: String) -> String:
	if supplied and (directory.is_empty() or not RetailDirSource.looks_like(directory)):
		return "supplied FROGGER_DATA_DIR lacks FROGGER.EXE + FROGPSX.MWD"
	return ""


## Counts records and accepts only reviewed script skips with no supplied assets.
static func evaluate(records: Array, supplied: bool, initial_problems: Array = []) -> Dictionary:
	var result: Dictionary = {"pass": 0, "fail": 0, "skip": 0, "exit": 0,
		"problems": initial_problems.duplicate()}
	var problems: Array = result["problems"]
	var manifest: Dictionary = approved_skips()
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
				if status != "skip" or supplied or not manifest.has(identity) \
						or manifest.get(identity) != reason or reason != RETAIL_REASON:
					problems.append("unapproved " + status + ": " + identity + " (" + reason + ")")
			_:
				problems.append("unknown test status: " + status)
	if records.is_empty():
		problems.append("no tests ran or were validly skipped")
	var failed: int = result["fail"]
	var skipped: int = result["skip"]
	if failed > 0 or not problems.is_empty():
		result["exit"] = 1
	elif skipped > 0:
		result["exit"] = 3
	return result


## Creates the machine report from independently inspectable result records.
static func make_report(records: Array, supplied: bool, problems: Array = []) -> Dictionary:
	var report: Dictionary = evaluate(records, supplied, problems)
	report["version"] = 1
	report["retail_supplied"] = supplied
	report["records"] = records
	return report


## Returns the exact human summary that must agree with the process and report.
static func summary(result: Dictionary) -> String:
	return "SUMMARY: PASS=%d FAIL=%d SKIP=%d EXIT=%d" % [
		result["pass"], result["fail"], result["skip"], result["exit"]]


## Validates the saved report, log summary, named skips and actual process exit.
static func validate_report(value: Variant, log_text: String, process_exit: int,
		supplied: bool) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray(["missing or malformed machine report"])
	var report: Dictionary = value
	if report.get("version") != 1 or not report.get("records") is Array \
			or not report.get("problems") is Array \
			or not report.get("retail_supplied") is bool:
		return PackedStringArray(["incomplete machine report"])
	if report["retail_supplied"] != supplied:
		errors.append("report retail mode disagrees with wrapper environment")
	var source_problems: Array = report["problems"]
	for problem: Variant in source_problems:
		if not problem is String:
			errors.append("malformed result problem")
	var records: Array = report["records"]
	var expected: Dictionary = evaluate(records, supplied)
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
	if process_exit not in [0, 1, 3]:
		errors.append("unexpected test process exit")
	return errors
