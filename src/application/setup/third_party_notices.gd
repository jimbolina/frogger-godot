class_name ThirdPartyNotices
extends RefCounted
## The credits and licence notices the setup screen shows: what the game is,
## the importer's third-party notice ([method AssetImporter.third_party_notice])
## and the Godot Engine's licence with the third-party components the engine
## is built from, as [Engine] reports them for the running build.


## The notices for game version [param version], with [param importer_notice]
## ("" for none) after the game's own lines.
static func text(version: String, importer_notice: String) -> String:
	var sections := PackedStringArray()
	sections.append("Frogger (1997) in Godot, version %s\n\n" % version
		+ "A rewrite of the 1997 PC game. It contains no part of the original game: "
		+ "the game files are imported from the player's own copy.")
	if not importer_notice.is_empty():
		sections.append(_heading("FrogLord") + importer_notice.strip_edges())
	sections.append(_heading("Godot Engine") + "This game uses Godot Engine (https://godotengine.org), "
		+ "available under the following licence:\n\n" + Engine.get_license_text().strip_edges())
	sections.append(_heading("Godot Engine components") + components(Engine.get_copyright_info()))
	var licences: Dictionary = Engine.get_license_info()
	var names: Array = licences.keys()
	names.sort()
	var texts := PackedStringArray()
	for name: Variant in names:
		texts.append("%s\n\n%s" % [str(name), str(licences[name]).strip_edges()])
	sections.append(_heading("Component licences") + "\n\n".join(texts))
	return "\n\n".join(sections) + "\n"


## One block per component of [param copyright_info] (as
## [method Engine.get_copyright_info] returns it): its name, then for each
## part its copyright lines and licence.
static func components(copyright_info: Array[Dictionary]) -> String:
	var blocks := PackedStringArray()
	for component: Dictionary in copyright_info:
		var lines := PackedStringArray([str(component.get("name", ""))])
		var parts: Array = component.get("parts", [])
		for part: Variant in parts:
			var fields: Dictionary = part
			var holders: PackedStringArray = fields.get("copyright", PackedStringArray())
			for holder: String in holders:
				lines.append("  (c) " + holder)
			lines.append("  Licence: " + str(fields.get("license", "")))
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


static func _heading(title: String) -> String:
	return "%s\n%s\n\n" % [title, "=".repeat(title.length())]
