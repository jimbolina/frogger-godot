class_name RenderingProfile
extends RefCounted
## How the game lights and shades its 3D world for one launch: the retail
## profile, which keeps the original look on the Compatibility renderer, or
## the modern profile, which is meant for the Forward+ renderer.
##
## The launch wrappers start Godot with the profile's
## [method rendering_method]; a profile running on another renderer still
## draws, and [method renderer_note] says what may differ.

## The retail profile's name.
const RETAIL: String = "retail"
## The modern profile's name.
const MODERN: String = "modern"
## Godot's name for the Forward+ renderer.
const FORWARD_PLUS: String = "forward_plus"
## Godot's name for the Compatibility renderer.
const COMPATIBILITY: String = "gl_compatibility"

## [constant RETAIL] or [constant MODERN].
var profile_name: String = RETAIL


## The retail profile.
static func retail() -> RenderingProfile:
	return RenderingProfile.new()


## The modern profile.
static func modern() -> RenderingProfile:
	var made := RenderingProfile.new()
	made.profile_name = MODERN
	return made


## The profile called [param name] ("" and [constant RETAIL] give the retail
## profile), or null for an unknown name.
static func named(name: String) -> RenderingProfile:
	match name:
		"", RETAIL:
			return retail()
		MODERN:
			return modern()
	return null


## True for the modern profile.
func is_modern() -> bool:
	return profile_name == MODERN


## The Godot renderer the profile is made for: [constant FORWARD_PLUS] for
## the modern profile, [constant COMPATIBILITY] for the retail profile.
func rendering_method() -> String:
	return FORWARD_PLUS if is_modern() else COMPATIBILITY


## "" when the game runs on [param current_method], the profile's own
## renderer; otherwise one warning line naming both renderers.
func renderer_note(current_method: String) -> String:
	if current_method == rendering_method():
		return ""
	return "rendering profile %s runs on %s; shadows and lighting may differ from %s" % [profile_name, current_method, rendering_method()]
