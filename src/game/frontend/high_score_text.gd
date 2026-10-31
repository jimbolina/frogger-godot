class_name HighScoreText
extends RefCounted
## The level-select score lines built by HighScoreBuildArcadeTimeTable (HSView.c:1662-1773).
##
## Each line is the 22 characters after the [code]%jc[/code] prefix of the SELECT.C:138-144
## templates: [code]%jc[/code] is the text area's centre-justification code, not text, so it is
## dropped and the renderer centres the line. Columns: rank and '.', the three initials verbatim
## (a '[' stays '[' and draws as that newfont cell), a space, the score in eight digits with up to
## seven leading zeros blanked, a space, the checkpoint-time sum as MM:SSs, a space.

const MAX_ROWS: int = 3
const SCORE_DIGITS: int = 8
const MINUTES_LIMIT: int = 99
const SECONDS_AT_LIMIT: int = 59


## One line per row of [param rows], at most three, ranked from 1.
static func lines(rows: Array[HighScoreRow]) -> PackedStringArray:
	var result := PackedStringArray()
	for rank: int in mini(rows.size(), MAX_ROWS):
		var row: HighScoreRow = rows[rank]
		result.append("%s.%s %s %s " % [String.chr(0x31 + rank), row.initials, score_text(row.score), time_text(row.total_seconds())])
	return result


## [param score] as eight digits (the low eight of the unsigned value) with leading zeros blanked,
## keeping the last digit.
static func score_text(score: int) -> String:
	var value: int = score & 0xFFFFFFFF
	var digits := PackedStringArray()
	digits.resize(SCORE_DIGITS)
	for index: int in range(SCORE_DIGITS - 1, -1, -1):
		digits[index] = String.chr(0x30 + value % 10)
		value = PlatformMath.divide(value, 10)
	for index: int in SCORE_DIGITS - 1:
		if digits[index] != "0":
			break
		digits[index] = " "
	return "".join(digits)


## [param total_seconds] as MM:SSs, 99:59s once the minutes pass 99.
static func time_text(total_seconds: int) -> String:
	var total: int = total_seconds & 0xFFFFFFFF
	var seconds: int = total % 60
	var minutes: int = PlatformMath.divide(total, 60)
	if minutes > MINUTES_LIMIT:
		minutes = MINUTES_LIMIT
		seconds = SECONDS_AT_LIMIT
	return "%d%d:%d%ds" % [PlatformMath.divide(minutes, 10), minutes % 10, PlatformMath.divide(seconds, 10), seconds % 10]
