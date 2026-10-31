class_name HighScoreRow
extends RefCounted
## One HIGH_SCORE_ENTRY (HSView.h:73-81): three initials, a score and five checkpoint seconds.
##
## [member initials] holds exactly three characters; retail's default tables use '[' ('Z' + 1)
## where the 3D view shows the dot pad. [member times] are whole seconds per checkpoint.

const INITIALS_LENGTH: int = 3
const CHECKPOINT_COUNT: int = 5

var initials: String = "   "
var score: int = 0
var times: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])


## A row with [param initials], [param score] and [param times] (padded or cut to five).
static func create(row_initials: String, row_score: int, row_times: PackedInt32Array = PackedInt32Array()) -> HighScoreRow:
	var row := HighScoreRow.new()
	row.initials = row_initials.substr(0, INITIALS_LENGTH).rpad(INITIALS_LENGTH, " ")
	row.score = row_score
	for index: int in CHECKPOINT_COUNT:
		row.times[index] = row_times[index] if index < row_times.size() else 0
	return row


## An independent copy with every field as it is.
func copy() -> HighScoreRow:
	var row := HighScoreRow.new()
	row.initials = initials
	row.score = score
	row.times = times.duplicate()
	return row


## The sum of the checkpoint seconds (HighScoreBuildArcadeTimeTable's total).
func total_seconds() -> int:
	var total: int = 0
	for value: int in times:
		total += value
	return total
