class_name FrontEndSession
extends RefCounted
## One game across the front-end pages: unlock progress, saved options and the values carried between levels.

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
## Problems found while loading, shown in the menu.
static var diagnostics: PackedStringArray = PackedStringArray()


## Builds the stack and the saved progress from the executable's level-select table.
static func load_progress(data: GameData) -> String:
	var table: LevelSelectTable = data.tables.level_select()
	if not table.error.is_empty():
		return table.error
	stack = LevelProgressSetup.stack_from_table(table)
	store = ProgressStore.load_from(store_path)
	diagnostics = PackedStringArray()
	if not store.error.is_empty():
		diagnostics.append(store.error)
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


## Starts a game: forgets the current game's gold frogs and resets lives and score (GameInitialise).
static func begin_game() -> void:
	active = true
	progress.start_game()
	lives = 3
	score = 0
	old_score = 0
	life_bonus_score = 10000
	level = -1


## Ends the game and returns to the main menu on the next front-end scene.
static func end_game() -> void:
	active = false
	level = -1
	start_page = FrontEndPage.Page.MAIN_MENU


## Writes the progress; returns the problem or "".
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
