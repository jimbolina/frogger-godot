extends AssetTest
## Every imported texture, WAV, Ogg and bitmap font under assets/ uses the
## import policy in project.godot's [code]importer_defaults[/code]: the
## importer and each policy key in its sidecar's [code][params][/code] equal
## the project default, except the keys an upscaled texture folder overrides
## (its textures carry mipmaps) and the font pages, which the font importer
## marks as not imported. A vector font follows [constant OWN_POLICIES]
## instead: MSDF glyphs, no hinting and no system fallback.

## Importer name and project default section by source extension; an
## empty section takes the policy from [constant OWN_POLICIES].
const POLICIES: Dictionary[String, Array] = {
	".png": ["texture", "texture"],
	".wav": ["wav", "wav"],
	".ogg": ["oggvorbisstr", "oggvorbisstr"],
	".fnt": ["font_data_bmfont", "font_data_bmfont"],
	".ttf": ["font_data_dynamic", ""],
}
## Policy keys by source extension for the importers project.godot sets no default for.
const OWN_POLICIES: Dictionary[String, Dictionary] = {
	".ttf": {
		"multichannel_signed_distance_field": true,
		"msdf_pixel_range": 16,
		"msdf_size": 64,
		"hinting": 0,
		"generate_mipmaps": false,
		"allow_system_fallback": false,
	},
}
## Policy keys a folder (by path prefix) sets differently from the project default.
const FOLDER_POLICIES: Dictionary[String, Dictionary] = {
	"res://assets/textures/images_x4/": {"mipmaps/generate": true},
}

## Importers a folder (by path prefix) uses instead of an extension's: the
## bitmap font importer sets each font's page image to [code]skip[/code].
const FOLDER_IMPORTERS: Dictionary[String, Dictionary] = {
	"res://assets/fonts/": {".png": "skip"},
}


## The importer of [param source], whose extension is [param extension]: its
## folder's from [constant FOLDER_IMPORTERS], else [param importer].
static func importer_for(source: String, extension: String, importer: String) -> String:
	for prefix: String in FOLDER_IMPORTERS:
		if source.begins_with(prefix) and FOLDER_IMPORTERS[prefix].has(extension):
			return FOLDER_IMPORTERS[prefix][extension]
	return importer


## The project policy [param policy] with the overrides of the folder holding [param source].
static func policy_for(source: String, policy: Dictionary) -> Dictionary:
	var chosen: Dictionary = policy.duplicate()
	for prefix: String in FOLDER_POLICIES:
		if source.begins_with(prefix):
			chosen.merge(FOLDER_POLICIES[prefix], true)
	return chosen


func test_sidecars_follow_the_project_policy() -> void:
	var project := ConfigFile.new()
	assert_eq(project.load("res://project.godot"), OK)
	var checked: int = 0
	for extension: String in POLICIES:
		var importer: String = POLICIES[extension][0]
		var section_key: String = POLICIES[extension][1]
		var policy: Dictionary = OWN_POLICIES.get(extension, {}) if section_key.is_empty() \
			else project.get_value("importer_defaults", section_key, {})
		assert_false(policy.is_empty(), "an import policy exists for %s" % extension)
		var mismatches := PackedStringArray()
		var sources: PackedStringArray = files_under(ASSETS, extension)
		for source: String in sources:
			var sidecar := ConfigFile.new()
			if sidecar.load(source + ".import") != OK:
				mismatches.append("%s has no .import sidecar" % source)
				continue
			var wanted: String = importer_for(source, extension, importer)
			var got_importer: String = sidecar.get_value("remap", "importer", "")
			if got_importer != wanted:
				mismatches.append("%s is imported by %s, not %s" % [source, got_importer, wanted])
			checked += 1
			if wanted != importer:
				continue
			var expected_policy: Dictionary = policy_for(source, policy)
			for key: String in expected_policy:
				var got: Variant = sidecar.get_value("params", key, null)
				if got != expected_policy[key]:
					mismatches.append("%s: %s is %s, the policy says %s" % [source, key, got, expected_policy[key]])
		for mismatch: String in mismatches.slice(0, 10):
			fail_test(mismatch)
		assert_eq(mismatches.size(), 0, "%d %s files follow the policy" % [sources.size(), extension])
	assert_gt(checked, 0)
