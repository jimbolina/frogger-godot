extends GutTest
## Level-select score lines after HighScoreBuildArcadeTimeTable (HSView.c:1662-1773).


func test_score_blanks_leading_zeros_but_the_last() -> void:
	assert_eq(HighScoreText.score_text(0), "       0")
	assert_eq(HighScoreText.score_text(4000), "    4000")
	assert_eq(HighScoreText.score_text(10000001), "10000001")
	assert_eq(HighScoreText.score_text(123456789), "23456789", "Eight digits of the score")


func test_time_is_minutes_and_seconds_capped_at_99_59() -> void:
	assert_eq(HighScoreText.time_text(0), "00:00s")
	assert_eq(HighScoreText.time_text(495), "08:15s")
	assert_eq(HighScoreText.time_text(5999), "99:59s")
	assert_eq(HighScoreText.time_text(6001), "99:59s")


func test_lines_rank_rows_and_keep_initials_verbatim() -> void:
	var rows: Array[HighScoreRow] = [
		HighScoreRow.create("KEV", 4000, PackedInt32Array([60, 60, 60, 60, 60])),
		HighScoreRow.create("M[B", 25000, PackedInt32Array([1, 0, 0, 0, 0])),
		HighScoreRow.create("DAV", 7, PackedInt32Array()),
		HighScoreRow.create("XXX", 1, PackedInt32Array()),
	]
	var lines: PackedStringArray = HighScoreText.lines(rows)
	assert_eq(lines, PackedStringArray([
		"1.KEV     4000 05:00s ",
		"2.M[B    25000 00:01s ",
		"3.DAV        7 00:00s ",
	]), "At most three lines, without the %jc prefix")
	var none: Array[HighScoreRow] = []
	assert_eq(HighScoreText.lines(none), PackedStringArray())
