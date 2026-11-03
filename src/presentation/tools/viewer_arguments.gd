class_name ViewerArguments
extends RefCounted
## Shared tool arguments. Callers supply user arguments, keeping tests independent of OS state.

## The launch argument naming the texture set to draw.
const TEXTURE_SET_ARGUMENT: String = "--texture-set="
## The project setting holding the default texture set name.
const TEXTURE_SET_SETTING: String = "frogger/textures/default_set"
## The launch argument choosing whether the retail blob shadow effects draw beside the real shadows.
const EFFECT_SHADOWS_ARGUMENT: String = "--effect-shadows="
## The project setting holding the default shadow-effect choice.
const EFFECT_SHADOWS_SETTING: String = "frogger/rendering/effect_shadows"
## The launch argument switching the scene lights' real shadows.
const SHADOWS_ARGUMENT: String = "--shadows="
## The project setting holding the default real-shadow switch.
const SHADOWS_SETTING: String = "frogger/rendering/shadows"
## The value of [constant SHADOWS_ARGUMENT] and [constant SHADOWS_SETTING] that turns real shadows off.
const SHADOWS_OFF: String = "off"
## The launch flag that starts the main menu's first attract demo right after its fly-on.
const ATTRACT_FLAG: String = "--attract"
## The launch flag that plays the level from the FrogLord watcher's overlay and reloads it when the
## watcher imports a new save.
const FROGLORD_FLAG: String = "--froglord"


## Value following the first argument starting with [param prefix], including an empty value.
static func value(arguments: PackedStringArray, prefix: String) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


## Whether an argument starts with [param prefix], including one with an empty value.
static func has_prefix(arguments: PackedStringArray, prefix: String) -> bool:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return true
	return false


## Whether [param flag] appears exactly, without treating a value argument as a flag.
static func has_flag(arguments: PackedStringArray, flag: String) -> bool:
	return arguments.has(flag)


## The name of the texture set a launch asked for: [code]--texture-set=[/code]
## in [param arguments], else the project setting
## [code]frogger/textures/default_set[/code], else the retail set.
static func texture_set(arguments: PackedStringArray) -> String:
	var requested: String = value(arguments, TEXTURE_SET_ARGUMENT).strip_edges().to_lower()
	if not requested.is_empty():
		return requested
	return str(ProjectSettings.get_setting(TEXTURE_SET_SETTING, TextureSet.RETAIL))


## The imported assets a launch asked for: the base root [AssetLocation] resolves from
## [param arguments] and the launcher settings, drawn in the [method texture_set] the launch names.
## When no root is usable, the catalog's [member AssetCatalog.error] says why.
static func open_assets(arguments: PackedStringArray) -> ImportedAssets:
	return AssetLocation.resolve(arguments, LauncherStore.load_from()).open(texture_set(arguments))


## The shadow-effect choice a launch asked for, for [ShadowEffectPolicy]:
## [code]--effect-shadows=[/code] in [param arguments], else the project setting
## [code]frogger/rendering/effect_shadows[/code], else [constant ShadowEffectPolicy.DEFAULT].
static func effect_shadows(arguments: PackedStringArray) -> String:
	var requested: String = value(arguments, EFFECT_SHADOWS_ARGUMENT).strip_edges().to_lower()
	if not requested.is_empty():
		return requested
	return str(ProjectSettings.get_setting(EFFECT_SHADOWS_SETTING, ShadowEffectPolicy.DEFAULT)).strip_edges().to_lower()


## Whether the scene lights cast real shadows: false when
## [code]--shadows=off[/code] is in [param arguments], or, without the
## argument, when the project setting [code]frogger/rendering/shadows[/code]
## is [code]"off"[/code]; true otherwise.
static func shadows(arguments: PackedStringArray) -> bool:
	var requested: String = value(arguments, SHADOWS_ARGUMENT).strip_edges().to_lower()
	if requested.is_empty():
		requested = str(ProjectSettings.get_setting(SHADOWS_SETTING, "on")).strip_edges().to_lower()
	return requested != SHADOWS_OFF


## Whether a launch asked for [constant ATTRACT_FLAG]: the main menu's first dwell ends at once,
## so the first attract demo loads as soon as the menu has flown on.
static func attract(arguments: PackedStringArray) -> bool:
	return has_flag(arguments, ATTRACT_FLAG)


## Whether a launch asked for [constant FROGLORD_FLAG]: the gameplay scene opens the overlay the
## [FrogLordPointer] names and reloads it when the pointer changes or F5 is pressed.
static func froglord(arguments: PackedStringArray) -> bool:
	return has_flag(arguments, FROGLORD_FLAG)


## Whether a scenario run attaches the imported assets: a map selected with
## [code]--level=[/code], or the rendered frog of a synthetic scenario selected
## with [code]--frog-assets[/code]. Other runs stay synthetic.
static func uses_assets(arguments: PackedStringArray) -> bool:
	return not value(arguments, "--level=").is_empty() or has_flag(arguments, "--frog-assets")
