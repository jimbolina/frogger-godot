class_name GameplayScreen
extends GameplayWorldView
## Dedicated single-player scene sharing the transactional host and world renderer.
##
## Player 1's saved key bindings drive the nine gameplay actions ([BindingInput]); R restarts a
## direct launch unless a binding claims the key. The saved music and effects volumes are applied
## when the scene opens. The level is read from the imported assets the
## [AssetLocation] resolves ([method asset_location]). A level that follows FrogLord
## ([method froglord_overlay]: a [code]--froglord[/code] launch, or any level but an attract demo
## while FrogLord is on in the setup) reads the overlay the [FrogLordPointer] names over that base
## root instead, shows the level's unmapped support-report rows as a warning, and reopens the level
## from a new catalog whenever an [AssetReloadWatcher] sees the pointer change or F5 is pressed
## ([method reload_assets]); a pointer change while the level-complete page shows waits for the
## next level. With FrogLord on, opening the scene also keeps the [FrogLordWatcher] running.
##
## Escape opens retail's pause page ([PausePage], pause.c:163-527) when the pause is allowed and
## closes it again from its menu; the page ticks at 30 Hz from [method _process] while the game
## holds, the sound effects hold and the music plays on (pause.c:215-221). Continue and Quit show
## at once; the arrow keys move the selection and releasing the bound super-hop key or Enter is
## fire. Quit then Yes croaks, resumes and removes the frog's control
## ([method GameplayHost.quit_game]), so the next tick opens the game-over page as a quit. Space no
## longer pauses, and Escape no longer leaves the level. The sandbox keeps its own Space pause and
## Escape leave ([method _opens_pause_page]). Every letter or Space key-down, play and
## auto-repeat included, sets the shared [member FrontEndSession.pause_cheats] gate, and each menu
## tick checks the cheat phrases against the keys down or tapped since the last tick; fired cheats
## change [member FrontEndSession.cheats], which seeds every run start and reaches the paused run
## when it resumes.
##
## A completed level opens the retail level-complete page ([LevelCompletePage]) over the map
## alone, as LevelEnd leaves it (gamesys.C:872-894, tempopt.c:5792-6067): the HUD, frog and
## entities hide, the page ticks at 30 Hz from [method _process], the bound super-hop key,
## Enter and Space are fire and Escape is triangle. A front-end game leaves through
## [method settle_level_complete]; a direct launch shows the statistics alone and keeps R and
## Escape. The sandbox never opens the page.
##
## The last life lost, or the pause menu's Quit, opens retail PC's game-over page
## ([GameOverPage], GameOverStartup 0x00443630) on the tick the run enters
## [constant LevelFlowState.Phase.GAME_OVER]: the HUD hides, the sound effects hold (retail sets
## the effects volume to 0), disc track 22 plays once and the run keeps ticking under the page, one
## page update per accepted run tick, while [GameOverView] shrinks the game viewport into the
## centre over black ([method GameplayWorldView.set_view_rect]) and brightens GAME OVER. The bound
## super-hop key, Enter or Space is fire; Escape does nothing. A front-end game then follows the
## flow to name entry, as a quit when Quit opened the page; a direct launch stops on the black
## screen with Replay and Return, and R restarts it during or after the page. The sandbox never
## opens the page.
##
## When [member FrontEndSession.attract_level] names a level outside a game, the screen plays
## that level's recorded attract demo instead (tempopt.c:1481-1626): the demo's own commands drive
## the run ([DemoPlaybackSession]), the HUD panels hide while the score sprites stay (tempopt.c:1379
## leaves GAME_FLAG_SCORE_SPRITES set), and the main menu's sprites fly on over the running game
## and stay live through focus ([MainMenuView]). Pause, restart, croak and Escape are ignored. When
## the demo is 30 ticks from its end ([AttractTimer]) the sprites fly off, the LOADING sprite
## brightens and the screen fades to black over 30 ticks while the game keeps running; the main
## menu then returns. Deaths restart at the demo spawn without rewinding the recording.

## Command-line flag that skips creating sound-effect and music players.
const NO_AUDIO_FLAG: String = "--no-audio"
## The scene a direct launch returns to when the player leaves.
const BOOT_SCENE: String = "res://scenes/boot.tscn"

var auto_open: bool = true
## The pointer file a [code]--froglord[/code] launch opens and watches.
var froglord_pointer_path: String = FrogLordPointer.DEFAULT_PATH
## Whether the level follows the pointer whatever base its overlay was imported over, as a
## [code]--froglord[/code] launch does; set from the command line on opening.
var froglord_flag: bool = false
## The launcher settings file [method asset_location] reads.
var launcher_path: String = LauncherStore.DEFAULT_PATH
var level_code: String = "ORG1"
## Whether a level with a map outside the accepted list may open; set when the command line names a level.
var allow_unaccepted_levels: bool = false
var run: GameplayRun
var last_error: String = ""
var _data: AssetCatalog
var _owns_data: bool = false
var _definition: LevelDefinition
var _host := GameplayHost.new()
var _held: int = 0
## Optional owner playthrough recording requested on the command line.
var recorder: InputRecorder = null
var _hud: GameplayHud
var _status: Label
var _actions: HBoxContainer
var _replay: Button
var _back: Button
var _advance_events: PackedInt32Array = PackedInt32Array()
var _next_level: int = -1
var _session_finished: bool = false
var _model_origins: EntityModelOrigins = null
var _complete_view: LevelCompleteView
## The open level-complete page, or null.
var _complete_page: LevelCompletePage = null
var _complete_elapsed: float = 0.0
var _fire_latched: bool = false
var _back_latched: bool = false
var _completion: LevelProgress.Completion = null
var _level_score: int = 0
var _start_score: int = 0
var _text_assets: FrontEndAssets = null
## Problems from the latest map-less entity model resolution, shown to callers instead of failing.
var entity_model_diagnostics := PackedStringArray()
## Player 1's key bindings: the shipped defaults until the saved options are read on opening.
var input: BindingInput = BindingInput.new()
## The attract demo's duration and input cursor while one plays, else null.
var attract_session: DemoPlaybackSession = null
## The attract demo's menu fly and fade clocks while one plays, else null.
var attract_timer: AttractTimer = null
## Whether leaving an attract demo changes the scene; tests turn it off.
var switches_scene: bool = true
## The scene an attract demo last left for, or "".
var left_for: String = ""
var _attract_demo: SourceDemoFile = null
var _attract_done: bool = false
var _attract_layer: Control = null
var _main_menu: MainMenuView = null
var _loading: TextureRect = null
var _fade: ColorRect = null
var _texture_set_name: String = ""
var _reload_watcher: AssetReloadWatcher = null
var _froglord_notice: FrogLordNotice = null
var _pause_view: PauseView
## The open pause page, or null.
var _pause_page: PausePage = null
var _pause_elapsed: float = 0.0
var _pause_buttons := PausePage.Buttons.new()
var _sound_volume: int = ProgressStore.DEFAULT_SOUND_VOLUME
var _keys_down := PackedInt32Array()
var _keys_tapped := PackedInt32Array()
var _game_over_view: GameOverView
## The open game-over page, or null.
var _game_over_page: GameOverPage = null
var _game_over_shown: bool = false
var _quit_requested: bool = false
var _jingle_selected: bool = false
var _level_music_track: int = -1

func _ready() -> void:
	audio_enabled = not ViewerArguments.has_flag(OS.get_cmdline_user_args(), NO_AUDIO_FLAG)
	build_world()
	_frog.hide()
	smoothing = true
	_build_interface()
	if auto_open:
		var settings: ProgressStore = FrontEndSession.settings()
		input = BindingInput.from_array(settings.key_bindings)
		_sound_volume = settings.sound_volume
		if audio_enabled:
			AudioLevels.apply(settings.music_volume, settings.sound_volume, voice_view())
		var arguments: PackedStringArray = OS.get_cmdline_user_args()
		var attract: bool = FrontEndSession.attract_level >= 0 and not FrontEndSession.active
		if attract:
			level_code = FroggerIds.level_code(FrontEndSession.attract_level)
		else:
			recorder = InputRecorder.from_arguments(arguments)
			allow_unaccepted_levels = not ViewerArguments.value(arguments, "--level=").is_empty()
			level_code = FrontEndSession.selected_level if not FrontEndSession.selected_level.is_empty() else ViewerArguments.value(arguments, "--level=")
			if level_code.is_empty():
				level_code = "ORG1"
		FrontEndSession.selected_level = ""
		_texture_set_name = ViewerArguments.texture_set(arguments)
		froglord_flag = ViewerArguments.froglord(arguments)
		var location: AssetLocation = asset_location()
		if location.is_usable():
			FrogLordWatcher.follow(get_tree(), LauncherStore.load_from(launcher_path).settings, location.base_root)
		var choice: FrogLordOverlay = froglord_overlay(attract)
		var data: ImportedAssets = open_overlay_assets(choice)
		if choice.follows:
			watch_froglord()
		data.note_renderer(RenderingServer.get_current_rendering_method())
		for warning: String in data.warnings:
			push_warning(warning)
		if attract:
			open_attract(data)
		elif data.is_valid():
			if open_data(data, level_code, true).is_empty() and choice.follows:
				support_warnings(data)
		else:
			_show_error("The imported assets cannot be opened: %s" % data.error)

func _exit_tree() -> void:
	close_data()

## Where this launch reads its assets: the [AssetLocation] resolved from the command line and
## the launcher settings at [member launcher_path].
func asset_location() -> AssetLocation:
	return AssetLocation.resolve(OS.get_cmdline_user_args(), LauncherStore.load_from(launcher_path))

## How this launch follows FrogLord ([FrogLordOverlay.choose]): from [member froglord_flag] or the
## command line's [code]--froglord[/code], the launcher settings at [member launcher_path], the pointer at
## [member froglord_pointer_path] and the base root; [param attract] for an attract demo.
func froglord_overlay(attract: bool = false) -> FrogLordOverlay:
	var location: AssetLocation = asset_location()
	return FrogLordOverlay.choose(froglord_flag or ViewerArguments.froglord(OS.get_cmdline_user_args()),
		LauncherStore.load_from(launcher_path).settings, attract,
		location.resolve_overlay(froglord_pointer_path), location.base_root)

## Opens the catalog [param choice] names: the base root with the overlay's index, or the base root
## alone with the choice's note, or with the reason in its warnings when the overlay does not open.
func open_overlay_assets(choice: FrogLordOverlay) -> ImportedAssets:
	var location: AssetLocation = asset_location()
	if not choice.index_root.is_empty():
		var overlay: ImportedAssets = location.open(_texture_set_name, choice.index_root)
		if overlay.is_valid():
			return overlay
		overlay.close()
		var base: ImportedAssets = location.open(_texture_set_name)
		base.warnings.append("The FrogLord overlay %s cannot be opened (%s); playing %s" % [choice.index_root, overlay.error, location.base_root])
		return base
	var data: ImportedAssets = location.open(_texture_set_name)
	if not choice.note.is_empty():
		data.warnings.append(choice.note)
	return data

## Opens the catalog a [code]--froglord[/code] launch plays: the overlay the [FrogLordPointer] at
## [member froglord_pointer_path] names, or the base root alone with a line in its warnings when
## there is no pointer.
func open_froglord_assets() -> ImportedAssets:
	var location: AssetLocation = asset_location()
	return open_overlay_assets(FrogLordOverlay.choose(true, null, false,
		location.resolve_overlay(froglord_pointer_path), location.base_root))

## Adds the [AssetReloadWatcher] on [member froglord_pointer_path] that reopens the level when the
## pointer changes and lets F5 call [method reload_assets]. Does nothing when already watching.
func watch_froglord() -> void:
	if _reload_watcher != null:
		return
	_reload_watcher = AssetReloadWatcher.new()
	_reload_watcher.pointer_path = froglord_pointer_path
	_reload_watcher.pointer_changed.connect(_on_pointer_changed)
	add_child(_reload_watcher)

## True when the level follows FrogLord's pointer.
func follows_froglord() -> bool:
	return _reload_watcher != null

## Reopens the current level from a new catalog over the overlay the pointer names, releasing the
## previous catalog. A pointer that names no overlay this level may follow, or an overlay that does
## not open, shows the error and keeps the current level. Returns the error or "".
func reload_assets() -> String:
	var choice: FrogLordOverlay = froglord_overlay()
	if choice.index_root.is_empty():
		return _show_error("No FrogLord overlay to reload: %s" % (choice.note if not choice.note.is_empty() else "FrogLord is off"))
	var data: ImportedAssets = asset_location().open(_texture_set_name, choice.index_root)
	if not data.is_valid():
		return _show_error("The FrogLord overlay cannot be opened: %s" % data.error)
	for warning: String in data.warnings:
		push_warning(warning)
	var issue: String = open_data(data, level_code, true)
	if not issue.is_empty():
		return issue
	print("froglord: reloaded %s from %s" % [level_code, data.source_summary()])
	support_warnings(data)
	return ""

## The rows of [param data]'s [LevelSupportReport] for the open level that the port cannot play,
## shown as a warning when [param data] reads an overlay index; empty for the base root alone.
func support_warnings(data: AssetCatalog) -> PackedStringArray:
	var rows := PackedStringArray()
	var imported: ImportedAssets = data as ImportedAssets
	if imported == null or imported.index_root == imported.root:
		return rows
	var report: LevelSupportReport = LevelSupportReport.from_catalog(data, PackedStringArray([level_code]))
	for row: LevelSupportReport.Row in report.unmapped():
		rows.append("%s %s%s" % [row.kind, row.key, (" (%s)" % row.reason) if not row.reason.is_empty() else ""])
	if not rows.is_empty():
		_show_froglord_notice("FrogLord: %s uses %d things the port cannot play: %s." % [level_code, rows.size(), "; ".join(rows)])
	return rows

func _on_pointer_changed() -> void:
	if _complete_page != null or _game_over_page != null or _session_finished or is_attract():
		return
	var choice: FrogLordOverlay = froglord_overlay()
	if choice.index_root.is_empty():
		print("froglord: the pointer changed but names no overlay this level follows")
		return
	reload_assets()

func _show_froglord_notice(text: String) -> void:
	print(text)
	if _froglord_notice == null:
		_froglord_notice = FrogLordNotice.new()
		add_child(_froglord_notice)
	_froglord_notice.show_text(text, true)

## Opens an explicitly selected level, borrowing the data unless ownership is transferred.
func open_data(data: AssetCatalog, code: String, take_ownership: bool = false) -> String:
	_finish_pending()
	if data != _data:
		close_data()
		_owns_data = take_ownership
	else:
		_detach_game()
		if take_ownership:
			_owns_data = true
	_data = data
	level_code = code
	apply_shadow_arguments(OS.get_cmdline_user_args())
	var level_number: int = FroggerIds.level_from_code(code)
	if data == null or not data.is_valid():
		return _show_error("Valid imported assets are required")
	if not data.is_playable_level(level_number):
		if not allow_unaccepted_levels or not data.has_level_map(level_number):
			return _show_error(_level_choice_message(data))
		print("%s is not an accepted level and may play incompletely" % code)
	var scene_data: MapSceneData = MapSceneData.load_level(data, level_number)
	if not scene_data.error.is_empty():
		return _show_error(scene_data.error)
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(data)
	if not assets.error.is_empty():
		return _show_error(assets.error)
	var setup: GameplaySetup = GameplaySetup.from_data(data, level_number, scene_data.map, assets.model, assets.action_lengths)
	if not setup.error.is_empty():
		return _show_error(setup.error)
	var hud_error: String = _hud.configure(data)
	if not hud_error.is_empty():
		return _show_error(hud_error)
	_definition = setup.definition
	_host.close()
	_clear_entity_visuals()
	if _frog_model != null:
		remove_child(_frog_model)
		_frog_model.queue_free()
		_frog_model = null
	build_map(scene_data)
	var effect_issue: String = _hud.configure_effects(scene_data.effects)
	if not effect_issue.is_empty():
		scene_data.diagnostics.append(effect_issue)
	build_frog(assets)
	_configure_level_audio(data, level_number)
	var issue: String = restart()
	if not issue.is_empty():
		return issue
	build_entities(_definition.entity_collision, scene_data, data)
	draw_state(1.0)
	return ""

## Joins pending work and releases owned source data after detaching its consumers.
func close_data() -> void:
	_detach_game()
	if _owns_data and _data != null:
		_data.close()
	_data = null
	_owns_data = false
	_text_assets = null
	configure_audio(null)
	configure_music(-1)

func _configure_level_audio(data: AssetCatalog, level_number: int) -> void:
	if voice_view() == null:
		return
	var ids := PackedInt32Array()
	for sound: LogicalSoundDefinition in _definition.sounds:
		ids.append(sound.sound_id)
	configure_audio(AudioResources.from_data(data, _definition.sounds), ids)
	configure_music(data.tables.music().track_for_level(level_number), MusicPlayer.folder_of(data))

func _detach_game() -> void:
	_close_level_complete()
	_close_pause_page()
	_close_game_over()
	_quit_requested = false
	_host.close()
	_host.run = null
	run = null
	_definition = null
	_model_origins = null
	entity_model_diagnostics = PackedStringArray()
	_current = null
	_previous = null
	playing = false
	_clear_entity_visuals()
	collapse_effects()
	if _frog_model != null:
		remove_child(_frog_model)
		_frog_model.queue_free()
		_frog_model = null
	frog_assets = null
	_map_instance = null
	if _ground != null:
		for child: Node in _ground.get_children():
			_ground.remove_child(child)
			child.queue_free()
	if _hud != null:
		_hud.clear()
	if _status != null:
		_status.text = ""
	if _actions != null:
		_actions.hide()

## Opens [member FrontEndSession.attract_level]'s recorded demo (high detail) from [param data],
## taking ownership of it. A demo that cannot be resolved or opened is noted in
## [member FrontEndSession.diagnostics] and the main menu returns at once.
func open_attract(data: AssetCatalog) -> void:
	var setup: DemoSetup = DemoSetup.resolve(data, FrontEndSession.attract_level)
	if not setup.error.is_empty():
		if data != null:
			data.close()
		_finish_attract("Attract demo %s: %s" % [level_code, setup.error])
		return
	_attract_demo = setup.demo
	var issue: String = open_data(data, level_code, true)
	if not issue.is_empty():
		_finish_attract("Attract demo %s: %s" % [level_code, issue])

## Plays [param demo] on [param definition] as an attract demo timed by [param timer]: the run
## starts from the demo's spawn ([method DemoSetup.start_for]), the session counts the demo's
## ticks and input, the HUD panels hide and the main menu's sprites start their fly-on. Returns
## the problem, or "".
func open_attract_run(definition: LevelDefinition, demo: SourceDemoFile, timer: AttractTimer) -> String:
	_attract_demo = demo
	_attract_done = false
	attract_timer = timer
	attract_session = DemoPlaybackSession.new()
	recorder = null
	definition.demo_playback = true
	var issue: String = attract_session.configure(demo.duration, demo.input_bytes, -1)
	if issue.is_empty():
		var demo_start: RunStart = DemoSetup.start_for(demo)
		demo_start.cheats = FrontEndSession.cheats.copy()
		issue = open_run(definition, demo_start, _model_origins)
	if not issue.is_empty():
		return issue
	_hud.visible = false
	_build_attract_overlay()
	attract_timer.start_demo()
	_present_attract()
	_update_interface()
	return ""

## Whether an attract demo plays.
func is_attract() -> bool:
	return attract_timer != null

## Creates a fresh session while retaining the selected level and decoded assets.
func restart() -> String:
	if _definition == null:
		return _show_error("Select a level before restarting")
	if _attract_demo != null:
		return open_attract_run(_definition, _attract_demo, AttractTimer.new())
	var start: RunStart
	if FrontEndSession.active:
		start = FrontEndSession.run_start()
	else:
		start = RunStart.new()
		start.start_mode = RunStart.Mode.SINGLE_START
		start.camera_startup = true
		start.start_timer = 120
		start.cheats = FrontEndSession.cheats.copy()
	_session_finished = false
	return open_run(_definition, start, _model_origins)

## Installs a run for normal play or asset-free scene verification.
## Supplied `origins` rebuild entity visuals without a map, borrowing their data; null keeps the current visuals.
func open_run(definition: LevelDefinition, start: RunStart, origins: EntityModelOrigins = null) -> String:
	_host.close()
	var replacement: GameplayRun = GameplayRun.create(definition, start)
	if not replacement.error.is_empty():
		return _show_error(replacement.error)
	_definition = definition
	set_effect_grid(definition.grid)
	_close_level_complete()
	_close_pause_page()
	_close_game_over()
	_quit_requested = false
	_start_score = start.score
	run = replacement
	_host.open(run)
	_held = 0
	if recorder != null:
		recorder.reset(level_code)
	_previous = null
	_current = null
	for slot: int in _entity_models.size():
		if _entity_models[slot] != null:
			remove_child(_entity_models[slot])
			_entity_models[slot].queue_free()
			_entity_models[slot] = null
		_entity_generations[slot] = -1
	_frog_pose_tick = -1
	_entity_pose_tick = -1
	playing = true
	last_error = ""
	accept_state(run.snapshot())
	_model_origins = origins
	if origins != null:
		entity_model_diagnostics = build_mapless_entities(definition.entity_collision, origins)
	reset_interpolation()
	_update_interface()
	return ""

## Executes an explicit command using the same host as keyboard play.
func step_command(command: TickCommand, capture_phases: bool = true) -> TickResult:
	_finish_pending()
	var result: TickResult = _host.step(command, capture_phases)
	_accept(result)
	return result

## Pauses only after joining a pending command and collapses drawing history.
func set_paused(paused: bool) -> void:
	_hold_play(paused)
	pause_audio(paused)

func _hold_play(paused: bool) -> void:
	_finish_pending()
	playing = not paused and run != null and _current != null and not _current.completed and last_error.is_empty()
	_held = 0
	_host.sampled_held = 0
	_host.elapsed = 0.0
	_host.render_elapsed = 0.0
	reset_interpolation()
	_update_interface()

func _process(delta: float) -> void:
	if run == null or _current == null:
		return
	if _complete_page != null:
		_complete_elapsed += delta
		if _complete_elapsed >= GameplayHost.PERIOD:
			_complete_elapsed = 0.0 if _complete_elapsed > GameplayHost.PERIOD * 2.0 else _complete_elapsed - GameplayHost.PERIOD
			var exit_event: int = step_level_complete()
			if exit_event >= 0:
				_leave_level_complete(exit_event)
				return
		draw_state(1.0)
		return
	if _pause_page != null:
		_pause_elapsed += delta
		if _pause_elapsed >= GameplayHost.PERIOD:
			_pause_elapsed = 0.0 if _pause_elapsed > GameplayHost.PERIOD * 2.0 else _pause_elapsed - GameplayHost.PERIOD
			step_pause()
		if run == null or _current == null:
			return
		draw_state(1.0)
		return
	_host.begin_frame(delta)
	var result: TickResult = _host.poll()
	if result != null:
		_accept(result)
		if run == null or _current == null:
			return
	if _host.advance(delta, playing):
		_host.consume_period()
		if is_attract():
			_submit_attract_tick()
		else:
			var command: TickCommand = _host.sample(_current.tick_index, _held)
			if recorder != null:
				recorder.record(command)
			if not _host.submit(command):
				_show_error(_host.error)
		if run == null or _current == null:
			return
	draw_state(_host.render_elapsed / GameplayHost.PERIOD if playing else 1.0)

func _submit_attract_tick() -> void:
	if _attract_done:
		return
	var command: TickCommand = attract_session.command(attract_session.elapsed_ticks)
	if command == null:
		_advance_attract()
	elif not _host.submit(command):
		_finish_attract("Attract demo %s: %s" % [level_code, _host.error])

## One synchronous attract logic tick: the demo's next recorded command through the host, or only
## the menu and fade clocks once the recording has run out. Returns the tick's result, or null.
func step_attract() -> TickResult:
	if not is_attract() or _attract_done:
		return null
	_finish_pending()
	if _attract_done:
		return null
	var command: TickCommand = attract_session.command(attract_session.elapsed_ticks)
	if command == null:
		_advance_attract()
		return null
	return step_command(command, false)

func _accept(result: TickResult) -> void:
	var demo_issue: String = ""
	if is_attract() and not _attract_done:
		demo_issue = attract_session.accept(result)
	if not result.error.is_empty():
		_show_error(result.error)
		reset_interpolation()
		if is_attract():
			_finish_attract("Attract demo %s: %s" % [level_code, result.error])
		return
	accept_state(result.final_snapshot, result.events)
	_host.render_elapsed = 0.0
	if is_attract():
		_update_interface(result.events)
		if not demo_issue.is_empty():
			_finish_attract("Attract demo %s: %s" % [level_code, demo_issue])
		elif _current.completed or _current.flow.phase == LevelFlowState.Phase.GAME_OVER:
			_finish_attract("Attract demo %s ended its game" % level_code)
		else:
			_advance_attract()
		return
	if _current.flow.phase == LevelFlowState.Phase.GAME_OVER:
		_accept_game_over()
		if _current == null:
			return
	elif _current.completed:
		playing = false
		reset_interpolation()
		_finish_front_end_level()
		if recorder != null and _current.flow.phase == LevelFlowState.Phase.COMPLETE:
			var issue: String = recorder.save(_current.tick_index)
			if not issue.is_empty():
				last_error = issue
			elif not recorder.saved_path.is_empty():
				print("Recorded " + recorder.saved_path)
		if _current.flow.phase == LevelFlowState.Phase.COMPLETE and last_error.is_empty() and _opens_level_complete_page():
			_open_level_complete()
	_update_interface(result.events)

func _finish_pending() -> void:
	if _host.pending():
		_accept(_host.finish())

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	_track_key(key)
	if key.echo or is_attract():
		return
	if _complete_page != null:
		if key.pressed:
			_press_on_level_complete(key)
		return
	if _game_over_page != null:
		if key.pressed:
			_press_on_game_over(key)
		return
	if _pause_page != null and _pause_page.active():
		_press_on_pause(key)
		return
	var action: int = input.command(key)
	if action != 0:
		if key.pressed and playing:
			_held |= action
		else:
			_held &= ~action
	elif key.pressed:
		match key.physical_keycode:
			KEY_SPACE:
				if not _opens_pause_page():
					set_paused(playing)
			KEY_R:
				if not FrontEndSession.active:
					restart()
			KEY_F5:
				if _reload_watcher != null:
					reload_assets()
			KEY_ESCAPE:
				if _opens_pause_page():
					open_pause()
				else:
					_return_to_menu()

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = GameplayHud.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_complete_view = LevelCompleteView.new()
	_complete_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_complete_view)
	_complete_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_view = PauseView.new()
	layer.add_child(_pause_view)
	_pause_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_view = GameOverView.new()
	layer.add_child(_game_over_view)
	_game_over_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status = Label.new()
	_status.position = Vector2(16, 200)
	_status.size = Vector2(608, 70)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_status)
	_actions = HBoxContainer.new()
	_actions.position = Vector2(0, 280)
	_actions.size = Vector2(640, 40)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(_actions)
	_replay = Button.new()
	_replay.text = "Replay"
	_replay.pressed.connect(restart)
	_actions.add_child(_replay)
	_back = Button.new()
	_back.text = "Return"
	_back.pressed.connect(_return_to_menu)
	_actions.add_child(_back)
	_actions.hide()

func _update_interface(events: Array[TickEvent] = []) -> void:
	if _status == null:
		return
	if _current != null:
		_hud.present(_current, _current.tick_index, events)
	if is_attract():
		_actions.visible = false
		_status.text = ""
		return
	var terminal: bool = _current != null and _current.flow.phase in [LevelFlowState.Phase.COMPLETE, LevelFlowState.Phase.GAME_OVER]
	var on_page: bool = _complete_page != null or _game_over_page != null
	_actions.visible = (terminal and not on_page) or not last_error.is_empty()
	_replay.visible = _definition != null and not FrontEndSession.active
	if not last_error.is_empty():
		_status.text = last_error
	elif on_page or terminal:
		_status.text = ""
	else:
		_status.text = "" if playing or _opens_pause_page() else "Paused — Space to resume"

## Builds the overlay over the world once: the score sprites, the subtractive fade, the main
## menu's sprites and the LOADING sprite centred as the level select draws it.
func _build_attract_overlay() -> void:
	if _attract_layer != null:
		return
	_attract_layer = Control.new()
	_attract_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.get_parent().add_child(_attract_layer)
	_attract_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.score_popups().reparent(_attract_layer, false)
	_fade = ColorRect.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.position = Vector2.ZERO
	_fade.size = Vector2(StackLayout.DISPLAY_WIDTH, StackLayout.DISPLAY_HEIGHT)
	var subtract := CanvasItemMaterial.new()
	subtract.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	_fade.material = subtract
	_fade.visible = false
	_attract_layer.add_child(_fade)
	_ensure_text_assets()
	var assets: FrontEndAssets = _text_assets if _text_assets != null else FrontEndAssets.new()
	_main_menu = MainMenuView.create(assets, OptionsModels.cloud_texture(_data))
	_attract_layer.add_child(_main_menu)
	_main_menu.menu_event.connect(_on_menu_event)
	_main_menu.sound_requested.connect(_play_menu_sound)
	_main_menu.grab_first_focus()
	_main_menu.focus_row(FrontEndSession.attract_option)
	_loading = TextureRect.new()
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_loading.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading.stretch_mode = TextureRect.STRETCH_SCALE
	_loading.texture = assets.texture("sel_loading")
	var loading_size: Vector2 = assets.retail_size("sel_loading")
	_loading.custom_minimum_size = loading_size
	_loading.size = loading_size
	_loading.position = Vector2((StackLayout.DISPLAY_WIDTH >> 1) - (int(loading_size.x) >> 1),
		(StackLayout.DISPLAY_HEIGHT >> 1) - (int(loading_size.y) >> 1))
	_loading.visible = false
	_attract_layer.add_child(_loading)

## Runs one DEMO_MAIN or DEMO_FADE_OUT step of the timer after a logic tick, then redraws the
## overlay; the finished fade returns to the main menu.
func _advance_attract() -> void:
	if _attract_done:
		return
	if attract_timer.phase == AttractTimer.Phase.PLAYING:
		attract_timer.demo_tick(attract_session.duration - attract_session.elapsed_ticks)
	elif attract_timer.phase == AttractTimer.Phase.FADE_OUT:
		attract_timer.fade_tick()
	_present_attract()
	if attract_timer.phase == AttractTimer.Phase.FINISHED:
		_finish_attract()

func _present_attract() -> void:
	if _main_menu == null:
		return
	_main_menu.set_slide(attract_timer.menu_slide())
	_main_menu.fire_allowed = attract_timer.fire_allowed(false, false)
	var fading: bool = attract_timer.phase in [AttractTimer.Phase.FADE_OUT, AttractTimer.Phase.FINISHED]
	_loading.visible = fading and _loading.texture != null
	var brightness: float = minf(float(attract_timer.loading_brightness) / StackPanel.NEUTRAL_COLOUR, 1.0)
	_loading.modulate = Color(brightness, brightness, brightness)
	_fade.visible = fading and attract_timer.fade_grey > 0
	var grey: float = attract_timer.fade_grey / 255.0
	_fade.color = Color(grey, grey, grey)

func _on_menu_event(kind: int) -> void:
	if not is_attract() or _attract_done:
		return
	match kind:
		MainMenuView.Kind.START:
			_end_demo(false)
			FrontEndSession.menu_start()
			_leave_for(FrontEndScreen.SCENE)
		MainMenuView.Kind.OPTIONS:
			_end_demo(false)
			FrontEndSession.start_page = FrontEndPage.Page.OPTIONS
			_leave_for(FrontEndScreen.SCENE)
		MainMenuView.Kind.EXIT:
			_end_demo(false)
			if switches_scene:
				get_tree().quit()

func _play_menu_sound(sound_name: String) -> void:
	var voices: SoundVoiceView = voice_view()
	if voices == null or _data == null or _data.names == null or _data.names.sounds == null:
		return
	var sound_id: int = _data.names.sounds.index_of(sound_name)
	if sound_id >= 0:
		voices.play_page_sound(sound_id)

## Ends the demo as retail's GameEnd does, keeping the menu row for the main menu.
func _end_demo(return_to_menu: bool) -> void:
	_attract_done = true
	if _main_menu != null:
		FrontEndSession.attract_option = _main_menu.option_number
	_finish_pending_quietly()
	close_data()
	FrontEndSession.end_attract(return_to_menu)

func _finish_pending_quietly() -> void:
	if _host.pending():
		_host.finish()
	_host.close()

## Advances the attract cycle past the finished demo (tempopt.c:1560-1626) and returns to the
## main menu; [param reason] notes a demo that could not play to its end.
func _finish_attract(reason: String = "") -> void:
	if _attract_done:
		return
	if not reason.is_empty():
		push_warning(reason)
		FrontEndSession.diagnostics.append(reason)
	if FrontEndSession.attract != null and FrontEndSession.progress != null:
		var next: int = FrontEndSession.attract.finish(FrontEndSession.progress)
		FrontEndSession.attract_intro = next == AttractCycle.INTRO
	_end_demo(true)
	_leave_for(FrontEndScreen.SCENE)

func _leave_for(scene: String) -> void:
	left_for = scene
	if switches_scene:
		get_tree().change_scene_to_file(scene)

func _show_error(message: String) -> String:
	last_error = message
	playing = false
	_update_interface()
	return message

func _return_to_menu() -> void:
	var in_game: bool = FrontEndSession.active
	leave_front_end_level()
	close_data()
	_leave_for(FrontEndScreen.SCENE if in_game else BOOT_SCENE)

## Settles the front-end game when the player leaves the level: a completed level returns to the
## level select as the page's triangle does; a game over still reaches name entry, and only
## leaving an unfinished level is a quit that skips it (hsinput.c:189-193). Does nothing outside a
## front-end game.
func leave_front_end_level() -> void:
	if not FrontEndSession.active:
		return
	var completed: bool = _current != null and _current.flow.phase == LevelFlowState.Phase.COMPLETE
	var ending: int = _current.flow.score if _current != null else FrontEndSession.score
	if _session_finished and completed:
		settle_level_complete(FrontEndFlow.Event.BACK)
	else:
		_warn(FrontEndSession.end_game(not _session_finished, ending))

func _warn(issue: String) -> void:
	if not issue.is_empty():
		push_warning(issue)

## Applies the finished level to the front-end progress and saves it.
func _finish_front_end_level() -> void:
	if not FrontEndSession.active or _session_finished or _current == null:
		return
	_session_finished = true
	var flow: LevelFlowState = _current.flow
	var progress: LevelProgress = FrontEndSession.progress
	var number: int = FroggerIds.level_from_code(level_code)
	if flow.gold_collected:
		FrontEndSession.collect_gold_frog(number)
	_advance_events = PackedInt32Array()
	_next_level = -1
	_completion = null
	if flow.phase == LevelFlowState.Phase.COMPLETE:
		_level_score = flow.score - FrontEndSession.score
		FrontEndSession.record_level(number, _level_score, flow.checkpoint_times)
		FrontEndSession.carry(_current)
		if number == LevelProgress.LEVEL_JUNGLE1:
			progress.reach_jungle_statue()
			progress.rewrite_jungle_row()
			_advance_events = PackedInt32Array([FrontEndFlow.Event.GAME_FINISHED, FrontEndFlow.Event.ENDING_DONE])
		else:
			_completion = progress.complete_level(number)
			if _completion.found and _completion.next_level >= 0:
				_next_level = _completion.next_level
				_advance_events = PackedInt32Array([FrontEndFlow.Event.LEVEL_FINISHED, FrontEndFlow.Event.NEXT_LEVEL])
			else:
				_advance_events = PackedInt32Array([FrontEndFlow.Event.LEVEL_FINISHED, FrontEndFlow.Event.ZONE_COMPLETE])
	else:
		_advance_events = PackedInt32Array([FrontEndFlow.Event.ALL_LIVES_LOST, FrontEndFlow.Event.GAME_OVER_DONE, FrontEndFlow.Event.CONTINUE_DONE])
	var issue: String = FrontEndSession.save()
	if not issue.is_empty():
		last_error = issue

func _level_choice_message(data: AssetCatalog) -> String:
	var message: String = "Playable levels are " + ", ".join(data.playable_level_codes())
	if allow_unaccepted_levels:
		message += "; unaccepted levels with a map are " + ", ".join(data.unaccepted_level_codes())
	return message

## Whether a completed level opens the level-complete page; the sandbox restarts instead.
func _opens_level_complete_page() -> bool:
	return true

## Whether the game-over phase opens the game-over page; the sandbox restarts instead.
func _opens_game_over_page() -> bool:
	return true

## Whether Escape opens the pause page; the sandbox pauses with Space and leaves with Escape instead.
func _opens_pause_page() -> bool:
	return true

## Opens the pause page on Escape's press (pause.c:166-200) after joining pending work, when
## [method PausePage.allowed] lets the committed state pause and no other page, error or demo
## holds the screen: play holds with the sound effects, the music plays on, the hop sounds and
## the page shows. Returns whether the page opened.
func open_pause() -> bool:
	if is_attract() or _pause_page != null or _complete_page != null or _game_over_page != null or not playing:
		return false
	_finish_pending()
	if run == null or _current == null or _complete_page != null or not last_error.is_empty() or not PausePage.allowed(_current):
		return false
	_hold_play(true)
	_pause_page = PausePage.create(_sound_volume)
	_pause_page.cheats = FrontEndSession.pause_cheats
	_pause_elapsed = 0.0
	_pause_buttons = PausePage.Buttons.new()
	var voices: SoundVoiceView = voice_view()
	if voices != null:
		voices.hold_voices(true)
	_play_pause_sounds(_pause_page.startup_events())
	_ensure_text_assets()
	_pause_view.present(_pause_page)
	return true

## One 30 Hz update of the open pause page with the keys latched since the last one and the
## scancodes down or tapped since it for the cheats: plays its sounds, applies fired cheats to
## [member FrontEndSession.cheats] and the progress with their HUD help, counts the HUD's paused
## frame and redraws; the page's end hands the session cheats to the run and resumes play or
## leaves. Returns the tick's events.
func step_pause() -> Array[PausePage.Event]:
	if _pause_page == null:
		return []
	var buttons: PausePage.Buttons = _pause_buttons
	_pause_buttons = PausePage.Buttons.new()
	buttons.arcade = true
	buttons.keys_down = _keys_down.duplicate()
	for code: int in _keys_tapped:
		if not buttons.keys_down.has(code):
			buttons.keys_down.append(code)
	_keys_tapped.clear()
	var events: Array[PausePage.Event] = _pause_page.tick(buttons)
	_play_pause_sounds(events)
	_hud.advance_paused()
	for event: PausePage.Event in events:
		_apply_cheat(event)
	_pause_view.present(_pause_page)
	if PausePage.Event.QUIT in events:
		_apply_session_cheats()
		_close_pause_page()
		set_paused(false)
		_quit_requested = true
		_warn(_host.quit_game())
	elif PausePage.Event.RESUMED in events:
		_close_pause_page()
		_apply_session_cheats()
		set_paused(false)
	return events

func _play_pause_sounds(events: Array[PausePage.Event]) -> void:
	var voices: SoundVoiceView = voice_view()
	if voices == null:
		return
	for event: PausePage.Event in events:
		if event == PausePage.Event.HOP:
			voices.play_page_sound(PausePage.HOP_SOUND)
		elif event == PausePage.Event.CROAK:
			voices.play_page_sound(PausePage.CROAK_SOUND)

func _press_on_pause(key: InputEventKey) -> void:
	if not key.pressed:
		if bool(input.command(key) & TickCommand.SUPER_HOP) or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_pause_buttons.fire_released = true
		return
	match key.physical_keycode:
		KEY_ESCAPE: _pause_buttons.escape = true
		KEY_UP: _pause_buttons.up = true
		KEY_DOWN: _pause_buttons.down = true
		KEY_LEFT: _pause_buttons.left = true
		KEY_RIGHT: _pause_buttons.right = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_keys_down.clear()
		_keys_tapped.clear()

func _track_key(key: InputEventKey) -> void:
	if key.pressed and (_gates(key.keycode) or _gates(key.physical_keycode)):
		FrontEndSession.pause_cheats.note_key_down()
	if key.echo:
		return
	if key.pressed and (key.keycode == KEY_META or key.physical_keycode == KEY_META):
		_keys_down.clear()
		_keys_tapped.clear()
		return
	var code: int = BindingInput.scancode(key)
	if code == KeyScancodes.UNKNOWN:
		return
	var index: int = _keys_down.find(code)
	if key.pressed:
		if index < 0:
			_keys_down.append(code)
		if not _keys_tapped.has(code):
			_keys_tapped.append(code)
	elif index >= 0:
		_keys_down.remove_at(index)

func _gates(code: Key) -> bool:
	return code == KEY_SPACE or (code >= KEY_A and code <= KEY_Z)

func _apply_cheat(event: PausePage.Event) -> void:
	var cheats: CheatState = FrontEndSession.cheats
	match event:
		PausePage.Event.CHEAT_INFINITE_LIVES:
			cheats.infinite_lives = not cheats.infinite_lives
			_hud.show_help("INFINITE LIVES ON" if cheats.infinite_lives else "INFINITE LIVES OFF", false)
		PausePage.Event.CHEAT_TIMEOUT_DEATHS:
			cheats.no_death_on_timeout = not cheats.no_death_on_timeout
			_hud.show_help("NO DEATH ON TIMEOUT" if cheats.no_death_on_timeout else "DEATH ON TIMEOUT", true)
		PausePage.Event.CHEAT_ALL_ZONES:
			if FrontEndSession.progress != null:
				FrontEndSession.progress.unlock_all_zones()
				_warn(FrontEndSession.save())
			_hud.show_help("ALL ZONES OPEN", true)
		PausePage.Event.CHEAT_ALL_LEVELS:
			if FrontEndSession.progress != null:
				FrontEndSession.progress.unlock_all_levels()
				_warn(FrontEndSession.save())
			_hud.show_help("ALL LEVELS OPEN", true)

func _apply_session_cheats() -> void:
	if run != null:
		_warn(_host.set_cheats(FrontEndSession.cheats))

func _close_pause_page() -> void:
	if _pause_page == null:
		return
	_pause_page = null
	_pause_elapsed = 0.0
	_pause_buttons = PausePage.Buttons.new()
	_pause_view.clear()
	var voices: SoundVoiceView = voice_view()
	if voices != null:
		voices.hold_voices(false)
	_update_interface()

## Opens the page for the completed level (tempopt.c:5792-5964): the next-level or zone-complete
## variant of a front-end game, else the statistics alone; hides the HUD, frog and entities,
## plays the startup sound and pauses the music as retail does.
func _open_level_complete() -> void:
	var flow: LevelFlowState = _current.flow
	var in_game: bool = FrontEndSession.active
	var variant: LevelCompletePage.Kind = LevelCompletePage.Kind.STATISTICS
	if in_game:
		variant = LevelCompletePage.Kind.NEXT_LEVEL if _next_level >= 0 else LevelCompletePage.Kind.ZONE_COMPLETE
	var score: int = _level_score if in_game else flow.score - _start_score
	var number: int = FroggerIds.level_from_code(level_code)
	if in_game and FrontEndSession.board != null:
		var table: int = HighScoreBoard.redirect_level(number)
		if table >= 0 and table < FrontEndSession.board.run_scores.size():
			score = FrontEndSession.board.run_scores[table]
	var gold: bool = _completion.show_gold_frog if _completion != null else flow.gold_collected
	_complete_page = LevelCompletePage.create(variant, _next_level, flow.checkpoint_times, score, gold)
	_complete_elapsed = 0.0
	_fire_latched = false
	_back_latched = false
	_hud.hide()
	set_map_only(true)
	var voices: SoundVoiceView = voice_view()
	if voices != null:
		voices.collapse()
		for sound_id: int in _complete_page.startup_sounds():
			voices.play_page_sound(sound_id)
	if _complete_page.pauses_music() and music_player() != null:
		music_player().pause(true)
	_ensure_text_assets()
	_complete_view.open(_complete_page)

func _close_level_complete() -> void:
	if _complete_view == null:
		return
	_complete_page = null
	_fire_latched = false
	_back_latched = false
	_complete_view.close()
	_hud.visible = true
	set_map_only(false)

func _ensure_text_assets() -> void:
	if _text_assets == null and _data != null and _data.is_valid():
		var text: FrontEndAssets = FrontEndAssets.from_data(_data, FrontEndScreen.session_language(OS.get_cmdline_user_args()))
		if text.error.is_empty():
			_text_assets = text
		else:
			push_warning("Level-complete images are unavailable: " + text.error)
	_complete_view.configure(_hud.assets, _text_assets)
	_pause_view.configure(_text_assets)
	_game_over_view.configure(_text_assets)

func _press_on_level_complete(key: InputEventKey) -> void:
	var fire: bool = bool(input.command(key) & TickCommand.SUPER_HOP) or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if fire:
		_fire_latched = true
	elif key.physical_keycode == KEY_ESCAPE:
		if _complete_page.shows_prompt():
			_back_latched = true
		else:
			_return_to_menu()
	elif key.physical_keycode == KEY_R and not FrontEndSession.active:
		restart()

## One 30 Hz update of the open page with the keys pressed since the last one: plays its sounds,
## keeps the map animating and redraws. Returns the page's exit event, or -1 while it stays open.
func step_level_complete() -> int:
	if _complete_page == null:
		return -1
	var fire: bool = _fire_latched
	var back: bool = _back_latched
	_fire_latched = false
	_back_latched = false
	var exit_event: int = _complete_page.tick(fire, back)
	var voices: SoundVoiceView = voice_view()
	if voices != null:
		for sound_id: int in _complete_page.sounds:
			voices.play_page_sound(sound_id)
	advance_map_tick()
	_complete_view.present(_complete_page)
	return exit_event

## Applies [param exit_event] of the page to the front-end game (tempopt.c:6029-6070): triangle
## opens a closed next level and focuses the stack on it; the count-down's end opens the next
## level outright or returns to the stack; JUN1's fire follows the ending. Returns the page the
## flow reaches.
func settle_level_complete(exit_event: int) -> int:
	var number: int = FroggerIds.level_from_code(level_code)
	var events: PackedInt32Array
	if exit_event == FrontEndFlow.Event.BACK or number != LevelProgress.LEVEL_JUNGLE1:
		events = PackedInt32Array([FrontEndFlow.Event.LEVEL_FINISHED, exit_event])
	else:
		events = _advance_events
	var page: int = _follow_flow(events)
	var progress: LevelProgress = FrontEndSession.progress
	if _next_level >= 0 and progress != null:
		if exit_event == FrontEndFlow.Event.BACK:
			progress.open_level_if_closed(_next_level)
			FrontEndSession.level = _next_level
		elif exit_event == FrontEndFlow.Event.NEXT_LEVEL:
			progress.open_level(_next_level)
			FrontEndSession.level = _next_level
			FrontEndSession.selected_level = FroggerIds.level_code(_next_level)
	var ending: int = _current.flow.score if _current != null else FrontEndSession.score
	if page == FrontEndPage.Page.LEVEL_SELECT:
		FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
		_warn(FrontEndSession.save())
	elif page == FrontEndPage.Page.GAME:
		_warn(FrontEndSession.save())
	else:
		_warn(FrontEndSession.end_game(false, ending))
	return page

func _leave_level_complete(exit_event: int) -> void:
	if not FrontEndSession.active:
		return
	_switch_scene(settle_level_complete(exit_event))

func _follow_flow(events: PackedInt32Array) -> int:
	var page: int = FrontEndPage.Page.GAME
	var problems := PackedStringArray()
	for event: int in events:
		page = FrontEndFlow.next_page(page, event, problems)
	for problem: String in problems:
		push_warning(problem)
	return page

func _switch_scene(page: int) -> void:
	close_data()
	if page == FrontEndPage.Page.GAME and not FrontEndSession.selected_level.is_empty():
		if switches_scene:
			get_tree().reload_current_scene()
	else:
		_leave_for(FrontEndScreen.SCENE)

## Opens the game-over page on the first tick of the game-over phase after settling the
## front-end progress, then ticks it once per accepted run tick (retail's GameOverUpdate runs the
## level under it, OptUpdateGame). The page's croak request is not played: retail's effects volume
## is 0 for the whole page.
func _accept_game_over() -> void:
	if not _game_over_shown:
		_game_over_shown = true
		_finish_front_end_level()
		if _opens_game_over_page():
			_open_game_over()
		return
	if _game_over_page == null:
		return
	var exit_event: int = _game_over_page.tick(_fire_latched)
	_fire_latched = false
	set_view_rect(_game_over_page.view_rect())
	_game_over_view.present(_game_over_page)
	if exit_event >= 0:
		_leave_game_over(exit_event)

## Starts the page as GameOverStartup does: the HUD hides, the sound effects hold, the level
## music gives way to disc track 22 played once, and the run's held keys are released.
func _open_game_over() -> void:
	_game_over_page = GameOverPage.create(_quit_requested)
	_fire_latched = false
	_held = 0
	_host.sampled_held = 0
	if _game_over_page.hides_hud():
		_hud.hide()
	var voices: SoundVoiceView = voice_view()
	if voices != null and _game_over_page.mutes_effects():
		voices.hold_voices(true)
	var music: MusicPlayer = music_player()
	if music != null:
		if not _jingle_selected:
			_level_music_track = music.track
			_jingle_selected = true
		music.select(_game_over_page.startup_track(), false)
		music.restart()
	_ensure_text_assets()
	_game_over_view.open(_game_over_page)

## Ends the page with [param exit_event]: a front-end game follows the flow through CONTINUE to
## name entry, as a quit when Quit opened the page; a direct launch stops on the last frame of the
## shrink with Replay and Return.
func _leave_game_over(exit_event: int) -> void:
	var page: GameOverPage = _game_over_page
	_game_over_page = null
	_release_game_over_effects(page)
	if FrontEndSession.active:
		_game_over_view.close()
		var first: int = FrontEndFlow.Event.QUIT if page.quit else FrontEndFlow.Event.ALL_LIVES_LOST
		var reached: int = _follow_flow(PackedInt32Array([first, exit_event, FrontEndFlow.Event.CONTINUE_DONE]))
		var score: int = _current.flow.score if _current != null else FrontEndSession.score
		_warn(FrontEndSession.end_game(page.quit, score))
		_switch_scene(reached)
		return
	_game_over_view.finish()
	_hold_play(true)

func _release_game_over_effects(page: GameOverPage) -> void:
	var voices: SoundVoiceView = voice_view()
	if voices != null and page != null and page.mutes_effects():
		voices.hold_voices(false)

func _close_game_over() -> void:
	if _game_over_view == null:
		return
	_release_game_over_effects(_game_over_page)
	_game_over_page = null
	_game_over_shown = false
	_fire_latched = false
	_game_over_view.close()
	set_view_rect(Rect2i())
	_hud.visible = true
	var music: MusicPlayer = music_player()
	if _jingle_selected and music != null:
		music.select(_level_music_track)
	_jingle_selected = false
	_level_music_track = -1

func _press_on_game_over(key: InputEventKey) -> void:
	if bool(input.command(key) & TickCommand.SUPER_HOP) or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_fire_latched = true
	elif key.physical_keycode == KEY_R and not FrontEndSession.active:
		restart()
