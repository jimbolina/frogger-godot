class_name RunStart
extends RefCounted
## Explicit stationary component start. It does not imply C's level-start bounce.

enum Mode { COMPONENT, FAST_RESET, SINGLE_START }

var spawn_cell: Vector2i = Vector2i(-1, -1)
var spawn_direction: int = -1
## Run-owned camera-relative control mapping; empty selects identity for this component start.
var controller_directions: PackedInt32Array = PackedInt32Array()
## Authored local modifier state.
var powerup_flags: int = 0
var quick_jump_timer: int = 0
var auto_hop_timer: int = 0
var super_tongue_timer: int = 0
## Keyboard play starts with FROG_START_LIVES; demo playback sets DemoSetup.DEMO_LIVES.
var lives: int = 3
## Score, previous score and next extra-life threshold carried from earlier levels of one game.
var score: int = 0
var old_score: int = 0
var life_bonus_score: int = 10000
## Explicit component RNG seed and level-start camera selection.
var seed: int = 1
var camera_startup: bool = false
var start_timer: int = 0
## 0 isolates stationary components; 1 matches fast/play reset wait; 2 single-start bounce.
var start_mode: int = Mode.COMPONENT
## Frozen Game_timer at level start; a demo harness may align it with a native trace.
var game_timer: int = 0
