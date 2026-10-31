class_name HighScoreTable
extends Resource
## The v3.0e default high-score tables: the ten main-table rows and three rows for each of the 60 levels.
##
## Each record is [code]HIGH_SCORE_ENTRY[/code] from HSView.h: four initial
## bytes (three letters and a zero), a 32-bit score and five 16-bit
## checkpoint times in whole seconds, padded to 20 bytes. Initials keep their bytes
## as read, so the original's [code]'Z'+1[/code] stays [code][[/code]; only a
## zero byte, which Godot strings cannot hold, becomes a space. Level
## rows are indexed [code]level * 3 + rank[/code] with level ids in
## LIBRARY.H order; times are indexed [code]row * 5 + checkpoint[/code].

## In-program address of [code]Game_high_score[/code].
const MAIN_POINTER: int = 0x477400
## In-program address of [code]Level_high_scores[/code].
const LEVEL_POINTER: int = 0x4774c8
## Rows in the main table.
const MAIN_COUNT: int = 10
## Levels in the per-level table.
const LEVEL_COUNT: int = 60
## Rows kept for each level.
const LEVEL_RANKS: int = 3
## Checkpoint times in each row.
const TIMES_PER_ROW: int = 5
## Letters in each row's initials.
const INITIALS_LENGTH: int = 3
## Bytes in each record.
const ENTRY_SIZE: int = 20

## Main-table initials, best first.
@export var main_initials: PackedStringArray = PackedStringArray()
## Main-table scores, best first.
@export var main_scores: PackedInt32Array = PackedInt32Array()
## Main-table checkpoint times, five per row.
@export var main_times: PackedInt32Array = PackedInt32Array()
## Per-level initials, index [code]level * 3 + rank[/code].
@export var level_initials: PackedStringArray = PackedStringArray()
## Per-level scores, index [code]level * 3 + rank[/code].
@export var level_scores: PackedInt32Array = PackedInt32Array()
## Per-level checkpoint times, five per row.
@export var level_times: PackedInt32Array = PackedInt32Array()
## Why the tables could not be read, or "".
@export var error: String = ""
