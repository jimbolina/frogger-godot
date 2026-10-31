class_name HighScoreBoard
extends RefCounted
## The main and per-level arcade high-score tables with player 0's run data (hsinput.c, gamesys.C).
##
## [member main] is Game_high_score, best first. [member levels] is Level_high_scores flattened:
## row [code]level * 3 + rank[/code] with level ids in LIBRARY.H order. The run data is
## Frog_score_data[level][0]: [member recorded] stands for its 'Z' initial, [member run_scores]
## holds the level score and [member run_times] five checkpoint seconds per level at
## [code]level * 5 + checkpoint[/code]. Every comparison is the source's strict [code]<[/code],
## so a score equal to a row goes below it. JUNGLE2 shares JUNGLE1's table. Race tables
## (HighScoreCheckAllRaceScores, HighScoreAddAllRaceScores) are not ported.

## What HighScoreInputStartup decides (hsinput.c:178-226).
enum Startup {
	## Some score qualifies: the name-entry page opens.
	ENTRY,
	## Nothing qualifies: MAIN_OPTIONS at once (hsinput.c:222-226).
	NO_HIGH_SCORE,
	## The game was quit from the pause menu: MAIN_OPTIONS without checks (hsinput.c:189-193).
	GAME_QUIT,
}

const MAIN_COUNT: int = 10
const LEVEL_COUNT: int = 60
const LEVEL_RANKS: int = 3
const CHECKPOINT_COUNT: int = HighScoreRow.CHECKPOINT_COUNT
const LEVEL_JUNGLE1: int = 18
const LEVEL_JUNGLE2: int = 19
const TICKS_PER_SECOND: int = 30
const SECONDS_LIMIT_TICKS: int = 2971
const SECONDS_LIMIT: int = 99
const EMPTY_INITIALS: String = "   "

## Game_high_score's ten rows, best first.
var main: Array[HighScoreRow] = []
## Level_high_scores' 180 rows, index [code]level * 3 + rank[/code].
var levels: Array[HighScoreRow] = []
## 1 where this run has recorded the level (the 'Z' initial of Frog_score_data).
var recorded: PackedByteArray = PackedByteArray()
## The recorded level scores, one per level.
var run_scores: PackedInt32Array = PackedInt32Array()
## The recorded checkpoint seconds, index [code]level * 5 + checkpoint[/code].
var run_times: PackedInt32Array = PackedInt32Array()
## New_high_score: a main-table row was entered since the name-entry page opened.
var new_main: bool = false
## New_high_scores: 1 for each level table given a row since the name-entry page opened.
var new_levels: PackedByteArray = PackedByteArray()


## A board holding copies of [param main_rows] and [param table_rows], padded with empty rows or
## cut to 10 and 180; the run data starts reset.
static func create(main_rows: Array[HighScoreRow], table_rows: Array[HighScoreRow]) -> HighScoreBoard:
	var board := HighScoreBoard.new()
	board.main = _copies(main_rows, MAIN_COUNT)
	board.levels = _copies(table_rows, LEVEL_COUNT * LEVEL_RANKS)
	board.new_levels.resize(LEVEL_COUNT)
	board.reset_run()
	return board


## JUNGLE1 for JUNGLE2, otherwise [param level]: the table a level's scores live in.
static func redirect_level(level: int) -> int:
	return LEVEL_JUNGLE1 if level == LEVEL_JUNGLE2 else level


## Whole checkpoint seconds for [param ticks] of 30 Hz level time (FROG.C:2833-2842): rounded up to
## a whole second, 99 from 2971 ticks.
static func checkpoint_seconds(ticks: int) -> int:
	var value: int = ticks
	while value != 0 and value != PlatformMath.divide(value, TICKS_PER_SECOND) * TICKS_PER_SECOND:
		value += 1
	if value >= SECONDS_LIMIT_TICKS:
		return SECONDS_LIMIT
	return PlatformMath.divide(value, TICKS_PER_SECOND)


## Forgets the run's recorded levels (HighScoreInitialiseData, hsinput.c:129-156).
func reset_run() -> void:
	recorded = PackedByteArray()
	recorded.resize(LEVEL_COUNT)
	run_scores = PackedInt32Array()
	run_scores.resize(LEVEL_COUNT)
	run_times = PackedInt32Array()
	run_times.resize(LEVEL_COUNT * CHECKPOINT_COUNT)


## Records a completed [param level] (gamesys.C:2733-2766): the first completion this run stores
## [param level_score] and the checkpoint seconds of [param checkpoint_ticks]; a later one only
## when it scores higher. Levels outside 0..59 are ignored.
func record_level(level: int, level_score: int, checkpoint_ticks: PackedInt32Array) -> void:
	var seconds := PackedInt32Array()
	for index: int in CHECKPOINT_COUNT:
		seconds.append(checkpoint_seconds(checkpoint_ticks[index]) if index < checkpoint_ticks.size() else 0)
	_record(level, level_score, seconds)


## Records the jungle statue hit on JUNGLE2 into JUNGLE1's run slot with zero checkpoint times
## (gamesys.C:3493-3513), with [method record_level]'s keep-the-better rule.
func record_jungle_statue(level_score: int) -> void:
	var zero := PackedInt32Array()
	zero.resize(CHECKPOINT_COUNT)
	_record(LEVEL_JUNGLE1, level_score, zero)


## The checkpoint seconds recorded for [param level].
func run_times_of(level: int) -> PackedInt32Array:
	return run_times.slice(level * CHECKPOINT_COUNT, (level + 1) * CHECKPOINT_COUNT)


## True when [param score] beats a main-table row (HighScoreCheckScore, hsinput.c:626-643).
func qualifies(score: int) -> bool:
	for row: HighScoreRow in main:
		if row.score < score:
			return true
	return false


## True when a recorded level score beats a row of its table (HighScoreCheckAllArcadeTimes,
## hsinput.c:1076-1114, with HighScoreCheckArcadeTime's JUNGLE2 redirect).
func qualifies_arcade() -> bool:
	for level: int in LEVEL_COUNT:
		if recorded[level] != 0 and _level_rank(redirect_level(level), run_scores[level]) >= 0:
			return true
	return false


## True when the game score or any recorded level qualifies (hsinput.c:195-219, arcade mode).
func qualifies_any(score: int) -> bool:
	return qualifies(score) or qualifies_arcade()


## HighScoreInputStartup's decision for a game that ended on [param score]; [param game_quit] is a
## pause-menu quit. Opening the entry clears the new-score flags (hsinput.c:384-390).
func input_startup(score: int, game_quit: bool) -> Startup:
	if game_quit:
		return Startup.GAME_QUIT
	if not qualifies_any(score):
		return Startup.NO_HIGH_SCORE
	new_main = false
	new_levels = PackedByteArray()
	new_levels.resize(LEVEL_COUNT)
	return Startup.ENTRY


## Enters [param initials] with [param score] into the main table (HighScoreEnterScore,
## hsinput.c:792-844) and returns the rank, or -1 when it does not fit. Rows below move down
## with their initials and score only; checkpoint times stay with their rank.
func enter(initials: String, score: int) -> int:
	var rank: int = 0
	while rank < MAIN_COUNT and not main[rank].score < score:
		rank += 1
	if rank == MAIN_COUNT:
		return -1
	if rank != MAIN_COUNT - 1:
		var below: int = MAIN_COUNT - 1
		while true:
			below -= 1
			main[below + 1].initials = main[below].initials
			main[below + 1].score = main[below].score
			if below == rank:
				break
	main[rank].initials = _initials(initials)
	main[rank].score = score
	new_main = true
	return rank


## Enters [param initials] into every level table a recorded level score beats
## (HighScoreAddAllArcadeTimes and HighScoreEnterArcadeTime, hsinput.c:871-955 and 1186-1214).
## Returns the table level of each insertion in level order. A JUNGLE2 score is compared against
## JUNGLE1's table and, as in the source, the new row takes JUNGLE1's run score and times.
func enter_arcade_times(initials: String) -> PackedInt32Array:
	var entered := PackedInt32Array()
	for level: int in LEVEL_COUNT:
		if recorded[level] == 0:
			continue
		var table: int = redirect_level(level)
		var rank: int = _level_rank(table, run_scores[level])
		if rank < 0:
			continue
		var base: int = table * LEVEL_RANKS
		if rank != LEVEL_RANKS - 1:
			var below: int = LEVEL_RANKS - 1
			while true:
				below -= 1
				levels[base + below + 1] = levels[base + below].copy()
				if below == rank:
					break
		levels[base + rank] = HighScoreRow.create(_initials(initials), run_scores[table], run_times_of(table))
		new_levels[table] = 1
		entered.append(table)
	return entered


## Copies of the three rows of [param level]'s table, JUNGLE2 showing JUNGLE1's.
func level_rows(level: int) -> Array[HighScoreRow]:
	var base: int = redirect_level(level) * LEVEL_RANKS
	var result: Array[HighScoreRow] = []
	for rank: int in LEVEL_RANKS:
		result.append(levels[base + rank].copy())
	return result


func _record(level: int, level_score: int, seconds: PackedInt32Array) -> void:
	if level < 0 or level >= LEVEL_COUNT:
		return
	if recorded[level] != 0 and not run_scores[level] < level_score:
		return
	recorded[level] = 1
	run_scores[level] = level_score
	for index: int in CHECKPOINT_COUNT:
		run_times[level * CHECKPOINT_COUNT + index] = seconds[index]


func _level_rank(table: int, score: int) -> int:
	for rank: int in LEVEL_RANKS:
		if levels[table * LEVEL_RANKS + rank].score < score:
			return rank
	return -1


static func _initials(text: String) -> String:
	return text.substr(0, HighScoreRow.INITIALS_LENGTH).rpad(HighScoreRow.INITIALS_LENGTH, " ")


static func _copies(rows: Array[HighScoreRow], count: int) -> Array[HighScoreRow]:
	var result: Array[HighScoreRow] = []
	for index: int in count:
		result.append(rows[index].copy() if index < rows.size() and rows[index] != null else HighScoreRow.create(EMPTY_INITIALS, 0))
	return result
