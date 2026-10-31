class_name ViewerArguments
extends RefCounted
## Shared tool arguments. Callers supply user arguments, keeping tests independent of OS state.

## The launch argument naming the texture set to draw.
const TEXTURE_SET_ARGUMENT: String = "--texture-set="
## The project setting holding the default texture set name.
const TEXTURE_SET_SETTING: String = "frogger/textures/default_set"
## The launch argument naming the rendering profile.
const RENDERING_ARGUMENT: String = "--rendering="
## The project setting holding the default rendering profile name.
const RENDERING_SETTING: String = "frogger/rendering/default_profile"


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


## The name of the rendering profile a launch asked for:
## [code]--rendering=[/code] in [param arguments], else the project setting
## [code]frogger/rendering/default_profile[/code], else the retail profile.
static func rendering_profile(arguments: PackedStringArray) -> String:
	var requested: String = value(arguments, RENDERING_ARGUMENT).strip_edges().to_lower()
	if not requested.is_empty():
		return requested
	return str(ProjectSettings.get_setting(RENDERING_SETTING, RenderingProfile.RETAIL))


## Whether a scenario run attaches the imported assets: a map selected with
## [code]--level=[/code], or the rendered frog of a synthetic scenario selected
## with [code]--frog-assets[/code]. Other runs stay synthetic.
static func uses_assets(arguments: PackedStringArray) -> bool:
	return not value(arguments, "--level=").is_empty() or has_flag(arguments, "--frog-assets")
