extends AssetTest
## Every imported texture, WAV and Ogg under assets/ uses the import policy in
## project.godot's [code]importer_defaults[/code]: the importer and each policy
## key in its sidecar's [code][params][/code] equal the project default.

## Importer name and project default section by source extension.
const POLICIES: Dictionary[String, Array] = {
	".png": ["texture", "texture"],
	".wav": ["wav", "wav"],
	".ogg": ["oggvorbisstr", "oggvorbisstr"],
}


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
			for key: String in policy:
				var got: Variant = sidecar.get_value("params", key, null)
				if got != policy[key]:
					mismatches.append("%s: %s is %s, the policy says %s" % [source, key, got, policy[key]])
			checked += 1
		for mismatch: String in mismatches.slice(0, 10):
			fail_test(mismatch)
		assert_eq(mismatches.size(), 0, "%d %s files follow the policy" % [sources.size(), extension])
	assert_gt(checked, 0)
