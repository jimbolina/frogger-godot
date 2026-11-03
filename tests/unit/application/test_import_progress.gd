extends GutTest
## The setup import's progress file: the lines ImportProgress writes, and what
## it reads back from whole lines only.


func test_lines_are_tab_separated_records_ending_in_a_newline() -> void:
	assert_eq(ImportProgress.progress_line(0.25, "Converting maps"), "progress\t0.2500\tConverting maps\n")
	assert_eq(ImportProgress.progress_line(1.5, "Done"), "progress\t1.0000\tDone\n", "the fraction is clamped")
	assert_eq(ImportProgress.note_line("no music"), "note\tno music\n")
	assert_eq(ImportProgress.problem_line("bad\tline\nbreak"), "problem\tbad line break\n",
		"tabs and line breaks in a text cannot split a record")
	assert_eq(ImportProgress.done_line(true), "done\tok\n")
	assert_eq(ImportProgress.done_line(false), "done\tfailed\n")


func test_a_finished_run_reads_back() -> void:
	var text: String = ImportProgress.progress_line(0.0, "Starting") + ImportProgress.progress_line(0.5, "Converting maps") \
		+ ImportProgress.note_line("music: no disc image supplied") + ImportProgress.progress_line(1.0, "Done") \
		+ ImportProgress.done_line(true)
	var report: ImportProgress = ImportProgress.parse(text)
	assert_true(report.finished)
	assert_true(report.succeeded)
	assert_almost_eq(report.fraction, 1.0, 0.0001)
	assert_eq(report.label, "Done")
	assert_eq(report.notes, PackedStringArray(["music: no disc image supplied"]))
	assert_eq(report.problems, PackedStringArray())
	assert_eq(report.unknown_lines, 0)


func test_a_failed_run_reads_back_its_problems() -> void:
	var text: String = ImportProgress.progress_line(0.3, "Converting textures") + ImportProgress.problem_line("one") \
		+ ImportProgress.problem_line("two") + ImportProgress.done_line(false)
	var report: ImportProgress = ImportProgress.parse(text)
	assert_true(report.finished)
	assert_false(report.succeeded)
	assert_eq(report.problems, PackedStringArray(["one", "two"]))
	var contradictory: ImportProgress = ImportProgress.parse(ImportProgress.problem_line("one") + ImportProgress.done_line(true))
	assert_false(contradictory.succeeded, "a reported problem fails the run whatever the last line says")


func test_a_line_still_being_written_is_ignored() -> void:
	var text: String = ImportProgress.progress_line(0.4, "Converting maps") + "progress\t0.9"
	var report: ImportProgress = ImportProgress.parse(text)
	assert_almost_eq(report.fraction, 0.4, 0.0001)
	assert_false(report.finished)
	assert_false(ImportProgress.parse("done\tok").finished, "the final record counts only when whole")
	assert_eq(ImportProgress.parse("").fraction, 0.0)


func test_the_fraction_never_goes_back_and_unknown_lines_are_counted() -> void:
	var text: String = ImportProgress.progress_line(0.6, "a") + ImportProgress.progress_line(0.2, "b") \
		+ "progress\tnot-a-number\tc\n" + "later\trecord\n" + "done\tmaybe\n"
	var report: ImportProgress = ImportProgress.parse(text)
	assert_almost_eq(report.fraction, 0.6, 0.0001)
	assert_eq(report.label, "b", "the label follows the last line")
	assert_eq(report.unknown_lines, 3)
	assert_false(report.finished)


func test_windows_line_endings_read_the_same() -> void:
	var report: ImportProgress = ImportProgress.parse("progress\t0.5000\tMaps\r\ndone\tok\r\n")
	assert_eq(report.label, "Maps")
	assert_true(report.succeeded)
