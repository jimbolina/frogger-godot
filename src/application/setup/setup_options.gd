class_name SetupOptions
extends SetupPage
## The settings page: the language, the window, the volumes and the texture pack.
##
## [method read] takes the saved values from the progress, graphics and
## launcher records; the setters keep every value valid; [method write_progress],
## [method write_graphics] and [method write_launcher] put the choices back
## into those records, leaving every other field as it was. The installed
## texture packs are offered after "none", which draws the original textures.

## The windowed sizes offered, smallest first; [constant Vector2i.ZERO] keeps the project's size.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(640, 480), Vector2i(960, 720), Vector2i(1280, 960),
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
]

## The chosen [enum GameLanguage.Id], or [constant GameLanguage.AUTO].
var language: int = GameLanguage.AUTO
## The chosen [enum GraphicsSettings.WindowMode].
var window_mode: GraphicsSettings.WindowMode = GraphicsSettings.WindowMode.WINDOWED
## The windowed size, or [constant Vector2i.ZERO] for the project's.
var window_size: Vector2i = Vector2i.ZERO
## The chosen [enum GraphicsSettings.Vsync].
var vsync: GraphicsSettings.Vsync = GraphicsSettings.Vsync.ENABLED
## The music volume step, 0 to [constant ProgressStore.MAX_VOLUME].
var music_volume: int = ProgressStore.DEFAULT_MUSIC_VOLUME
## The sound-effect volume step, 0 to [constant ProgressStore.MAX_VOLUME].
var sound_volume: int = ProgressStore.DEFAULT_SOUND_VOLUME
## The chosen texture pack's folder name, one of [member texture_packs], or "" for none.
var texture_pack: String = ""
## The installed texture packs offered, sorted by folder name.
var texture_packs: Array[TexturePack] = []


func title() -> String:
	return "Settings"


## Takes the saved choices from [param progress], [param graphics] and
## [param launcher], offering the texture packs [param installed_packs].
func read(progress: ProgressStore, graphics: GraphicsSettings, launcher: LauncherSettings,
		installed_packs: Array[TexturePack]) -> void:
	set_language(progress.language)
	set_music_volume(progress.music_volume)
	set_sound_volume(progress.sound_volume)
	window_mode = graphics.window_mode
	window_size = graphics.window_size
	vsync = graphics.vsync
	offer_texture_packs(installed_packs)
	set_texture_pack(launcher.texture_pack)


## Offers [param installed_packs] and keeps the chosen pack when it is still
## installed, otherwise chooses none.
func offer_texture_packs(installed_packs: Array[TexturePack]) -> void:
	texture_packs = installed_packs.duplicate()
	set_texture_pack(texture_pack)


## The offered pack called [param name], or null.
func offered_pack(name: String) -> TexturePack:
	for pack: TexturePack in texture_packs:
		if pack.pack_name == name:
			return pack
	return null


## The line naming [param pack] in the list: its name, with its author when
## it gives one; "None (original textures)" for null.
static func pack_label(pack: TexturePack) -> String:
	if pack == null:
		return "None (original textures)"
	if pack.author.is_empty():
		return pack.display_name()
	return "%s, by %s" % [pack.display_name(), pack.author]


## Chooses [param value] when it is a language or [constant GameLanguage.AUTO].
func set_language(value: int) -> void:
	language = value if GameLanguage.is_setting(value) else GameLanguage.AUTO


## Sets the music volume step, clamped to the 0 to 8 scale.
func set_music_volume(value: int) -> void:
	music_volume = clampi(value, 0, ProgressStore.MAX_VOLUME)


## Sets the sound-effect volume step, clamped to the 0 to 8 scale.
func set_sound_volume(value: int) -> void:
	sound_volume = clampi(value, 0, ProgressStore.MAX_VOLUME)


## Whether the window fills the screen (either fullscreen mode).
func is_fullscreen() -> bool:
	return window_mode != GraphicsSettings.WindowMode.WINDOWED


## Chooses windowed or fullscreen; a fullscreen mode already chosen is kept.
func set_fullscreen(fullscreen: bool) -> void:
	if not fullscreen:
		window_mode = GraphicsSettings.WindowMode.WINDOWED
	elif not is_fullscreen():
		window_mode = GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN


## Chooses the windowed size [param size]: zero, or positive on both axes.
func set_window_size(size: Vector2i) -> void:
	window_size = size if size == Vector2i.ZERO or (size.x > 0 and size.y > 0) else Vector2i.ZERO


## Whether vsync is on (any mode but disabled).
func is_vsync() -> bool:
	return vsync != GraphicsSettings.Vsync.DISABLED


## Turns vsync on or off; a vsync mode already chosen is kept when on.
func set_vsync(enabled: bool) -> void:
	if not enabled:
		vsync = GraphicsSettings.Vsync.DISABLED
	elif not is_vsync():
		vsync = GraphicsSettings.Vsync.ENABLED


## Chooses the texture pack [param name] when it is offered, matching its
## folder name exactly or else ignoring case; otherwise none.
func set_texture_pack(name: String) -> void:
	var wanted: String = name.strip_edges()
	texture_pack = ""
	if wanted.is_empty():
		return
	if offered_pack(wanted) != null:
		texture_pack = wanted
		return
	for pack: TexturePack in texture_packs:
		if pack.pack_name.to_lower() == wanted.to_lower():
			texture_pack = pack.pack_name
			return


## The sizes offered, with [member window_size] among them.
func window_sizes() -> Array[Vector2i]:
	var sizes: Array[Vector2i] = WINDOW_SIZES.duplicate()
	if not sizes.has(window_size):
		sizes.append(window_size)
	return sizes


## Puts the language and volumes into [param progress].
func write_progress(progress: ProgressStore) -> void:
	progress.language = language
	progress.music_volume = music_volume
	progress.sound_volume = sound_volume


## Puts the window mode, size and vsync into [param graphics].
func write_graphics(graphics: GraphicsSettings) -> void:
	graphics.window_mode = window_mode
	graphics.window_size = window_size
	graphics.vsync = vsync


## Puts the texture pack into [param launcher].
func write_launcher(launcher: LauncherSettings) -> void:
	launcher.texture_pack = texture_pack
