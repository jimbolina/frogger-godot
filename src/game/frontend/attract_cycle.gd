class_name AttractCycle
extends RefCounted
## The executable's attract demo order and the session's position in it (tempopt.c Num_demo_levels_seen, DEMO_FINISH :1578-1614).
##
## Rows are the demo table's (level, gate) pairs in order; a play-intro row holds [constant INTRO]
## in both. The caller converts the imported demo table, since gameplay code may not read data
## records: a skipped entry becomes an INTRO row and a level of -1 ends the list.

## The play-intro row value, and what [method finish] returns when the intro would play.
const INTRO: int = -2
## The value [method current_level] and [method finish] return when there is nothing to play.
const NONE: int = -1

## Num_demo_levels_seen: the row of the demo playing or about to play. Session-long; row 0 is
## the first demo and, as in the C, is played without checking its gate.
var seen: int = 0

var _levels: PackedInt32Array = PackedInt32Array()
var _gates: PackedInt32Array = PackedInt32Array()


## A cycle over [param levels] and their gate levels [param gates], both in table order.
static func from_rows(levels: PackedInt32Array, gates: PackedInt32Array) -> AttractCycle:
	var result := AttractCycle.new()
	for index: int in mini(levels.size(), gates.size()):
		if levels[index] == NONE:
			break
		result._levels.append(levels[index])
		result._gates.append(gates[index])
	return result


## Number of rows, play-intro rows included.
func row_count() -> int:
	return _levels.size()


## The level of the row at [member seen], or [constant NONE] when the table is empty.
func current_level() -> int:
	return _levels[seen] if seen >= 0 and seen < _levels.size() else NONE


## The level of row [param index], or [constant NONE] when out of range.
func level_at(index: int) -> int:
	return _levels[index] if index >= 0 and index < _levels.size() else NONE


## DEMO_FINISH: steps [member seen] to the next row that is a play-intro row or whose gate level
## is selectable in [param progress], wrapping to row 0 at the end of the list (row 0 is checked
## after a wrap). Returns that row's level, or [constant INTRO] when the search wrapped to row 0
## or landed on a play-intro row. After INTRO [member seen] is already the next demo's row: 0 on
## a wrap, the row after the play-intro row otherwise, which the C plays without checking it.
## Where the C would loop forever (no row qualifies) or step past the end after a final
## play-intro row, the port returns [constant NONE] or wraps to row 0.
func finish(progress: LevelProgress) -> int:
	var count: int = _levels.size()
	if count == 0:
		return NONE
	var row: int = seen
	var found: bool = false
	for _step: int in count:
		row += 1
		if row >= count:
			row = 0
		if _levels[row] == INTRO or progress.is_selectable(_gates[row]):
			found = true
			break
	if not found:
		return NONE
	seen = row
	if seen == 0:
		return INTRO
	if _levels[seen] == INTRO:
		seen += 1
		if seen >= count:
			seen = 0
		return INTRO
	return _levels[seen]
