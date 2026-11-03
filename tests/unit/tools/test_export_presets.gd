extends GutTest
## The committed export presets ship no retail-derived file: nothing under
## res://assets, the local import, and of res://content only the port's own
## shippable files (the angular font, the emissive table, the lettering
## images and the lettering tile masks), never their sources; the tests,
## tools, documentation and GUT are excluded too, and the archive's import
## facts and FrogLord's configuration with its licence are included as plain
## files. Filters are matched the way Godot's exporter matches them, against
## the path with and without res://.

const PRESETS: String = "res://export_presets.cfg"
const CONTENT: String = "res://content"
## The files under res://content a packaged build carries besides the lettering.
const SHIPPABLE: PackedStringArray = [
	"res://content/fonts/angular/frogger_angular.ttf",
	"res://content/rendering/emissive_images.tres",
]
## The folder of lettering images and tile masks, every one of which a
## packaged build carries.
const LETTERING: String = "res://content/lettering"
const LETTERING_IMAGES: int = 270
const LETTERING_MASKS: int = 49
## Paths of the local import, present or not, that every preset excludes.
const IMPORTED_SAMPLES: PackedStringArray = [
	"res://assets/catalog.tres", "res://assets/textures/images/t0310.png", "res://assets/maps/ORG1.res",
	"res://assets/audio/music/track_02.ogg", "res://assets/fonts/retail/newfont.fnt",
	"res://assets/rendering/emissive_images.tres",
]
## Folders no build carries.
const EXCLUDED_FOLDERS: PackedStringArray = [
	"res://tests", "res://tools", "res://addons", "res://docs", "res://archive/tests", "res://archive/docs",
]
## Plain files the shipped importer reads.
const INCLUDED_FILES: PackedStringArray = [
	"res://archive/import/disc_tracks.tsv",
	"res://archive/third_party/froglord_cfg/LICENSE.md",
]
const FROGLORD_CONFIG: String = "res://archive/third_party/froglord_cfg"
const PLATFORMS: Dictionary[String, String] = {
	"macOS": "macOS", "Windows": "Windows Desktop", "Linux": "Linux",
}


func _presets() -> Array[Dictionary]:
	var config := ConfigFile.new()
	assert_eq(config.load(PRESETS), OK, "export_presets.cfg loads")
	var presets: Array[Dictionary] = []
	for section: String in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			var preset: Dictionary = {"section": section}
			for key: String in config.get_section_keys(section):
				preset[key] = config.get_value(section, key)
			presets.append(preset)
	return presets


func _filters(preset: Dictionary, key: String) -> PackedStringArray:
	var text: String = preset[key]
	var filters := PackedStringArray()
	for part: String in text.split(","):
		if not part.strip_edges().is_empty():
			filters.append(part.strip_edges())
	return filters


func _matches(path: String, filters: PackedStringArray) -> bool:
	var bare: String = path.trim_prefix("res://")
	for filter: String in filters:
		if path.matchn(filter) or bare.matchn(filter):
			return true
	return false


func _files(folder: String, into: PackedStringArray) -> PackedStringArray:
	for child: String in DirAccess.get_directories_at(folder):
		_files(folder.path_join(child), into)
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() != "import":
			into.append(folder.path_join(file))
	return into


func test_the_three_platforms_export_everything_but_the_filters_to_build() -> void:
	var presets: Array[Dictionary] = _presets()
	var names := PackedStringArray()
	for preset: Dictionary in presets:
		var name: String = preset["name"]
		names.append(name)
		assert_true(PLATFORMS.has(name), "preset %s" % name)
		var platform: String = preset["platform"]
		var export_filter: String = preset["export_filter"]
		var expected_platform: String = PLATFORMS.get(name, "")
		assert_eq(platform, expected_platform, "%s platform" % name)
		assert_eq(export_filter, "all_resources", "%s exports all resources except the filters" % name)
		var export_path: String = preset["export_path"]
		assert_true(export_path.begins_with("build/"), "%s exports under build/" % name)
	names.sort()
	assert_eq(names, PackedStringArray(["Linux", "Windows", "macOS"]))


func test_the_local_import_is_excluded() -> void:
	for preset: Dictionary in _presets():
		var excluded: PackedStringArray = _filters(preset, "exclude_filter")
		for path: String in IMPORTED_SAMPLES:
			assert_true(_matches(path, excluded), "%s would ship %s" % [preset["name"], path])


func test_only_the_shippable_content_ships() -> void:
	var lettering: PackedStringArray = _files(LETTERING, PackedStringArray())
	var images: int = 0
	var masks: int = 0
	for path: String in lettering:
		if path.get_base_dir().get_base_dir().get_file() == "masks":
			masks += 1
		elif path.get_base_dir() == LETTERING and path.get_extension() == "png":
			images += 1
	assert_eq(images, LETTERING_IMAGES, "lettering images")
	assert_eq(masks, LETTERING_MASKS, "lettering tile masks")
	assert_eq(lettering.size(), LETTERING_IMAGES + LETTERING_MASKS, "nothing else under the lettering")
	var shippable: PackedStringArray = SHIPPABLE.duplicate()
	shippable.append_array(lettering)
	var content: PackedStringArray = _files(CONTENT, PackedStringArray())
	for preset: Dictionary in _presets():
		var excluded: PackedStringArray = _filters(preset, "exclude_filter")
		var leaked := PackedStringArray()
		for path: String in content:
			if not shippable.has(path) and not _matches(path, excluded) and path.get_extension() != "uid":
				leaked.append(path)
		assert_eq(leaked, PackedStringArray(), "%s would ship: %s" % [preset["name"], ", ".join(leaked.slice(0, 10))])
		var missing := PackedStringArray()
		for path: String in shippable:
			if not FileAccess.file_exists(path) or _matches(path, excluded):
				missing.append(path)
		assert_eq(missing, PackedStringArray(), "%s does not ship: %s" % [preset["name"], ", ".join(missing.slice(0, 10))])


func test_tests_tools_documentation_and_gut_are_excluded() -> void:
	for preset: Dictionary in _presets():
		var excluded: PackedStringArray = _filters(preset, "exclude_filter")
		for folder: String in EXCLUDED_FOLDERS:
			var files: PackedStringArray = _files(folder, PackedStringArray())
			assert_gt(files.size(), 0, folder)
			for path: String in files:
				if not _matches(path, excluded):
					fail_test("%s would ship %s" % [preset["name"], path])
					break


func test_the_importer_facts_and_froglord_configuration_are_included() -> void:
	var config: PackedStringArray = _files(FROGLORD_CONFIG, PackedStringArray())
	for preset: Dictionary in _presets():
		var included: PackedStringArray = _filters(preset, "include_filter")
		var excluded: PackedStringArray = _filters(preset, "exclude_filter")
		for path: String in INCLUDED_FILES:
			assert_true(FileAccess.file_exists(path), path)
			assert_true(_matches(path, included) and not _matches(path, excluded), "%s ships %s" % [preset["name"], path])
		for path: String in config:
			if path.get_extension() == "cfg" and not (_matches(path, included) and not _matches(path, excluded)):
				fail_test("%s would not ship %s" % [preset["name"], path])
				break
