extends AssetTest
## Every imported texture, WAV and Ogg under assets/ uses the import policy in
## project.godot's [code]importer_defaults[/code]: the importer and each policy
## key in its sidecar's [code][params][/code] equal the project default, except
## the keys an upscaled texture folder overrides (its textures carry mipmaps).

## Importer name and project default section by source extension.
const POLICIES: Dictionary[String, Array] = {
	".png": ["texture", "texture"],
	".wav": ["wav", "wav"],
	".ogg": ["oggvorbisstr", "oggvorbisstr"],
}
## Policy keys a folder (by path prefix) sets differently from the project default.
const FOLDER_POLICIES: Dictionary[String, Dictionary] = {
	"res://assets/textures/images_x4/": {"mipmaps/generate": true},
	"res://assets/textures/pages_x4/": {"mipmaps/generate": true},
}


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
		var policy: Dictionary = project.get_value("importer_defaults", section_key, {})
		assert_false(policy.is_empty(), "project.godot has an import policy for %s" % extension)
		var mismatches := PackedStringArray()
		var sources: PackedStringArray = files_under(ASSETS, extension)
		for source: String in sources:
			var sidecar := ConfigFile.new()
			if sidecar.load(source + ".import") != OK:
				mismatches.append("%s has no .import sidecar" % source)
				continue
			if sidecar.get_value("remap", "importer", "") != importer:
				mismatches.append("%s is imported by %s" % [source, sidecar.get_value("remap", "importer", "")])
			var expected_policy: Dictionary = policy_for(source, policy)
			for key: String in expected_policy:
				var got: Variant = sidecar.get_value("params", key, null)
				if got != expected_policy[key]:
					mismatches.append("%s: %s is %s, the policy says %s" % [source, key, got, expected_policy[key]])
			checked += 1
		for mismatch: String in mismatches.slice(0, 10):
			fail_test(mismatch)
		assert_eq(mismatches.size(), 0, "%d %s files follow the policy" % [sources.size(), extension])
	assert_gt(checked, 0)
