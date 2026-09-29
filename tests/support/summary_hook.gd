extends GutHookScript
## Runs after all tests: prints a PASS / FAIL / SKIP summary and sets the exit code.
##
## Exit codes (documented in README.md):
## [br]0 - every test ran and passed;
## [br]1 - at least one test failed;
## [br]3 - nothing failed, but some tests were skipped (e.g. no retail files).
## A skipped test is never counted as a pass.
##
## The summary is also written to [code]user://test_summary.txt[/code] so a
## wrapper script can read it even where the console output is unreliable.

## Exit code when all tests passed.
const EXIT_ALL_PASSED: int = 0
## Exit code when any test failed.
const EXIT_FAILED: int = 1
## Exit code when nothing failed but something was skipped.
const EXIT_SKIPPED: int = 3


## Collects the results from GUT and reports them.
func run() -> void:
	var runner: Object = gut
	var collector: Object = runner.call("get_test_collector")
	var scripts: Array = collector.get("scripts")
	var passed: int = 0
	var failed: int = 0
	var skipped: int = 0
	var lines := PackedStringArray()
	for script: Object in scripts:
		var path: String = script.get("path")
		var tests: Array = script.get("tests")
		var script_skipped: bool = script.get("was_skipped")
		if script_skipped:
			var reason: String = str(script.get("skip_reason"))
			for test: Object in tests:
				skipped += 1
				lines.append("SKIPPED %s::%s (%s)" % [path, test.get("name"), reason])
			continue
		for test: Object in tests:
			var test_name: String = test.get("name")
			if test.call("is_failing"):
				failed += 1
				lines.append("FAILED  %s::%s" % [path, test_name])
			elif test.call("is_pending"):
				skipped += 1
				var texts: Array = test.get("pending_texts")
				lines.append("SKIPPED %s::%s (%s)" % [path, test_name, ", ".join(PackedStringArray(texts))])
			elif test.call("is_passing"):
				passed += 1
			elif test.get("was_run"):
				failed += 1
				lines.append("FAILED  %s::%s (asserted nothing)" % [path, test_name])
	var code: int = EXIT_ALL_PASSED
	if failed > 0:
		code = EXIT_FAILED
	elif skipped > 0:
		code = EXIT_SKIPPED
	lines.append("SUMMARY: PASS=%d FAIL=%d SKIP=%d EXIT=%d" % [passed, failed, skipped, code])
	var report: String = "\n".join(lines)
	print("\n" + report)
	var file: FileAccess = FileAccess.open("user://test_summary.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(report + "\n")
		file.close()
	set_exit_code(code)
