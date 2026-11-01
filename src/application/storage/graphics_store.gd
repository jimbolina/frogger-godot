class_name GraphicsStore
extends RefCounted
## The port's graphics settings file, one section per group of knobs.
##
## A missing file gives the defaults without an error, and a missing key takes
## its default, so new knobs need no version change. An unreadable, malformed
## or other-version file, or any value of the wrong type or out of range,
## gives all the defaults and sets [member error]. An integer is accepted
## where a decimal is expected. Saving writes a temporary file beside the
## target and renames it over the target, so an interrupted save leaves the
## previous file intact.

## Default settings file.
const DEFAULT_PATH: String = "user://graphics.cfg"
## Version written to and expected in the file.
const FORMAT_VERSION: int = 1
## Settings fields by file section.
const LAYOUT: Dictionary[String, Array] = {
	"display": ["window_mode", "window_size", "vsync", "max_fps"],
	"quality": ["render_scale", "scaler", "fsr_sharpness", "msaa", "screen_aa", "taa"],
	"shadows": [
		"real_shadows", "shadow_atlas_size", "soft_shadow_quality", "shadow_splits",
		"shadow_split_1", "shadow_max_distance", "shadow_bias", "shadow_normal_bias",
	],
	"post": ["bloom", "bloom_intensity", "bloom_threshold", "tonemapper", "exposure", "ssao"],
	"effects": [
		"glow_halo_strength", "glow_lights", "glow_lights_in_caves", "glow_light_energy",
		"lava_emission", "lava_lights",
	],
	"look": ["water_reflection", "water_specular", "water_shininess", "vertex_tint", "cave_light_mode"],
}
const _TEMP_SUFFIX: String = ".tmp"
const _META: String = "meta"

## The loaded settings, or the defaults.
var settings: GraphicsSettings = GraphicsSettings.new()
## Why the last load fell back to defaults, or "".
var error: String = ""


## Reads [param path]; any problem yields the defaults (see the class notes).
static func load_from(path: String = DEFAULT_PATH) -> GraphicsStore:
	var store := GraphicsStore.new()
	if not FileAccess.file_exists(path):
		return store
	var file := ConfigFile.new()
	var status: Error = file.load(path)
	if status != OK:
		store.error = "graphics file %s could not be read (%s); using defaults" % [path, error_string(status)]
		return store
	var problem: String = store._read(file)
	if not problem.is_empty():
		var defaults := GraphicsStore.new()
		defaults.error = "graphics file %s %s; using defaults" % [path, problem]
		return defaults
	return store


## Writes [param values] to [param path]; returns "" or why saving failed.
static func save(values: GraphicsSettings, path: String = DEFAULT_PATH) -> String:
	var problem: String = values.validate()
	if not problem.is_empty():
		return "graphics not saved: " + problem
	var directory: String = path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return "graphics folder %s could not be created (%s)" % [directory, error_string(made)]
	var file := ConfigFile.new()
	file.set_value(_META, "format_version", FORMAT_VERSION)
	for section: String in LAYOUT:
		for field: String in LAYOUT[section]:
			file.set_value(section, field, values.get(field))
	var temporary: String = path + _TEMP_SUFFIX
	var written: Error = file.save(temporary)
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return "graphics file %s could not be written (%s)" % [temporary, error_string(written)]
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
		return "graphics file %s could not replace %s (%s)" % [temporary, path, error_string(renamed)]
	return ""


func _read(file: ConfigFile) -> String:
	if not file.has_section_key(_META, "format_version"):
		return "has no format version"
	var version: Variant = file.get_value(_META, "format_version")
	if typeof(version) != TYPE_INT:
		return "has a non-integer format version"
	if version != FORMAT_VERSION:
		return "has format version %d, expected %d" % [version, FORMAT_VERSION]
	for section: String in LAYOUT:
		for field: String in LAYOUT[section]:
			if not file.has_section_key(section, field):
				continue
			var value: Variant = file.get_value(section, field)
			var expected: int = typeof(settings.get(field))
			if expected == TYPE_FLOAT and typeof(value) == TYPE_INT:
				var whole: int = value
				value = float(whole)
			if typeof(value) != expected:
				return "has %s/%s of type %s, expected %s" % [
					section, field, type_string(typeof(value)), type_string(expected)]
			settings.set(field, value)
	var problem: String = settings.validate()
	return "" if problem.is_empty() else "has " + problem
