class_name FrontEndSession
extends RefCounted
## One game across the front-end pages: unlock progress, saved options and the values carried between levels.
##
## The options (volumes, key bindings and language setting) are read from the store with the
## progress and written back by [method save]. The high-score tables come from the port's own
## high-score file, else from the executable's default tables; they are loaded once and kept with
## the run's recorded levels across the game and front-end scenes, and written by
## [method save_scores] after initials are entered and when a game ends (retail saves at GameEnd).

## Whether a game started from the front end is under way; direct level launches leave it false.
static var active: bool = false
## Where progress is read and written.
static var store_path: String = ProgressStore.DEFAULT_PATH
## Page the front-end scene shows when it opens.
static var start_page: int = FrontEndPage.Page.MAIN_MENU
## The level being played, or -1.
static var level: int = -1
## Whether a level was chosen since the game began; the level list can go back only before that.
static var level_chosen: bool = false
## The unlock state, its stack and its saved file, loaded by the front-end screen.
static var progress: LevelProgress = null
static var stack: LevelStack = null
static var store: ProgressStore = null
## Lives, score, previous score and life-bonus threshold at the start of the current level.
static var lives: int = 3
static var score: int = 0
static var old_score: int = 0
static var life_bonus_score: int = 10000
## Music volume step, 0..8.
static var music_volume: int = ProgressStore.DEFAULT_MUSIC_VOLUME
## Sound-effect volume step, 0..8.
static var sound_volume: int = ProgressStore.DEFAULT_SOUND_VOLUME
## The four controller records.
static var bindings: KeyBindings = KeyBindings.create_default()
## Saved [enum GameLanguage.Id] setting, or [constant GameLanguage.AUTO] to follow the locale.
static var language: int = GameLanguage.AUTO
## Problems found while loading, shown in the menu.
static var diagnostics: PackedStringArray = PackedStringArray()
## The high-score tables and the run's recorded levels, or null before loading.
static var board: HighScoreBoard = null
## Where the high-score tables are read and written.
static var scores_store_path: String = HighScoreStore.DEFAULT_PATH
## The score the last game ended on, checked by the name-entry page.
static var final_score: int = 0
## True when the last game was quit from the game rather than played out.
static var game_quit: bool = false


## Builds the stack and the saved progress from the executable's level-select table.
static func load_progress(data: AssetCatalog) -> String:
	var table: LevelSelectTable = data.tables.level_select()
	if not table.error.is_empty():
		return table.error
	stack = LevelProgressSetup.stack_from_table(table)
	store = ProgressStore.load_from(store_path)
	diagnostics = PackedStringArray()
	if not store.error.is_empty():
		diagnostics.append(store.error)
	read_options(store)
	if not bindings.error.is_empty():
		diagnostics.append(bindings.error)
	load_scores(data)
	if store.level_flags.is_empty():
		progress = LevelProgress.create(stack)
	else:
		var words: Array = []
		for value: int in store.level_flags:
			words.append(value)
		progress = LevelProgressSetup.from_dictionary(stack, {
			LevelProgressSetup.ARCADE_FLAGS_KEY: words,
			LevelProgressSetup.GOLD_FROGS_KEY: store.gold_frogs,
		}, diagnostics)
	return ""


## Builds [member board] once: from the high-score file when it is present, else from
## [param data]'s default tables, else empty with a diagnostic. A board already built is kept.
static func load_scores(data: AssetCatalog) -> void:
	if board != null:
		return
	var saved: HighScoreStore = HighScoreStore.load_from(scores_store_path)
	if not saved.error.is_empty():
		diagnostics.append(saved.error)
	if saved.present:
		board = HighScoreBoard.create(rows_of(saved.main_initials, saved.main_scores, saved.main_times),
			rows_of(saved.level_initials, saved.level_scores, saved.level_times))
		return
	var table: HighScoreTable = data.tables.high_scores() if data != null and data.tables != null else null
	if table != null and table.error.is_empty():
		board = HighScoreBoard.create(rows_of(table.main_initials, table.main_scores, table.main_times),
			rows_of(table.level_initials, table.level_scores, table.level_times))
		return
	diagnostics.append("High scores are unavailable (%s); the tables start empty" % (table.error if table != null else "no tables"))
	var none: Array[HighScoreRow] = []
	board = HighScoreBoard.create(none, none)


## Rows from parallel [param initials], [param scores] and five [param times] per row.
static func rows_of(initials: PackedStringArray, scores: PackedInt32Array, times: PackedInt32Array) -> Array[HighScoreRow]:
	var result: Array[HighScoreRow] = []
	for index: int in mini(initials.size(), scores.size()):
		var start: int = index * HighScoreRow.CHECKPOINT_COUNT
		result.append(HighScoreRow.create(initials[index], scores[index], times.slice(start, start + HighScoreRow.CHECKPOINT_COUNT)))
	return result


## Writes [member board]'s tables to the high-score file; returns the problem or "".
static func save_scores() -> String:
	if board == null:
		return ""
	var saved := HighScoreStore.new()
	for row: HighScoreRow in board.main:
		saved.main_initials.append(row.initials)
		saved.main_scores.append(row.score)
		saved.main_times.append_array(row.times)
	for row: HighScoreRow in board.levels:
		saved.level_initials.append(row.initials)
		saved.level_scores.append(row.score)
		saved.level_times.append_array(row.times)
	return saved.save(scores_store_path)


## Records a completed [param level_number] with [param level_score] and the level's
## [param checkpoint_ticks] for the run (gamesys.C:2733-2766).
static func record_level(level_number: int, level_score: int, checkpoint_ticks: PackedInt32Array) -> void:
	if board != null:
		board.record_level(level_number, level_score, checkpoint_ticks)


## Records the jungle statue's [param level_score] with zero times (gamesys.C:3493-3513).
static func record_jungle_statue(level_score: int) -> void:
	if board != null:
		board.record_jungle_statue(level_score)


## Copies the volumes, bindings and language setting from [param from_store].
static func read_options(from_store: ProgressStore) -> void:
	music_volume = from_store.music_volume
	sound_volume = from_store.sound_volume
	bindings = KeyBindings.from_array(from_store.key_bindings)
	language = from_store.language


## The saved options: the loaded store, or the save file read without keeping it when the
## front end has not loaded one (a direct level launch).
static func settings() -> ProgressStore:
	return store if store != null else ProgressStore.load_from(store_path)


## Starts a game: forgets the current game's gold frogs and resets lives and score (GameInitialise).
static func begin_game() -> void:
	active = true
	progress.start_game()
	lives = 3
	score = 0
	old_score = 0
	life_bonus_score = 10000
	level = -1
	final_score = 0
	game_quit = false
	if board != null:
		board.reset_run()


## Ends the game on [param ending_score]: the next front-end scene opens name entry, which leaves
## at once when [param quit] (a quit from the game) or nothing qualifies. Saves the high scores;
## returns the problem or "".
static func end_game(quit: bool, ending_score: int) -> String:
	active = false
	level = -1
	final_score = ending_score
	game_quit = quit
	start_page = FrontEndPage.Page.HIGH_SCORE_INPUT
	return save_scores()


## Clears the name-entry request once the entry page has read [member start_page],
## [member final_score] and [member game_quit], so opening the front end again cannot enter the
## same score twice.
static func consume_entry_request() -> void:
	if start_page == FrontEndPage.Page.HIGH_SCORE_INPUT:
		start_page = FrontEndPage.Page.MAIN_MENU
	final_score = 0
	game_quit = false


## Writes the progress and options; returns the problem or "".
static func save() -> String:
	if progress == null or store == null:
		return ""
	var saved: LevelProgress = progress.copy()
	saved.apply_save_encoding()
	var flags := PackedByteArray()
	for value: int in saved.arcade_flags:
		flags.append(value)
	store.level_flags = flags
	store.gold_frogs = saved.gold_frogs
	store.music_volume = music_volume
	store.sound_volume = sound_volume
	store.key_bindings = bindings.to_array()
	store.language = language
	return store.save(store_path)


## Records the gold frog collected in a level, if any.
static func collect_gold_frog(level_number: int) -> void:
	var index: int = progress.arcade_levels.find(level_number)
	if index >= 0:
		progress.collect_gold_frog(progress.arcade_themes[index])


## Copies the end-of-level values into the carry for the next level.
static func carry(state: GameplayState) -> void:
	lives = state.frog.lives
	score = state.flow.score
	old_score = state.flow.old_score
	life_bonus_score = state.flow.life_bonus_score


## The run start for the current level with the carried values.
static func run_start() -> RunStart:
	var start := RunStart.new()
	start.start_mode = RunStart.Mode.SINGLE_START
	start.camera_startup = true
	start.start_timer = 120
	start.lives = lives
	start.score = score
	start.old_score = old_score
	start.life_bonus_score = life_bonus_score
	return start
