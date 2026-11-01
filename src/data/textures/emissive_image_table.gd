class_name EmissiveImageTable
extends Resource
## The hand-authored list of glowing texture images ([EmissiveImage]), looked
## up by image name.

## The glowing images, at most one per name.
@export var entries: Array[EmissiveImage] = []


## The entry called [param image_name] (case-insensitive), or null.
func find(image_name: String) -> EmissiveImage:
	var wanted: String = image_name.to_lower()
	for entry: EmissiveImage in entries:
		if entry != null and entry.image_name.to_lower() == wanted:
			return entry
	return null


## One line per problem: a missing entry, an empty or repeated name (any case),
## or a negative strength or light energy. Empty when the table is usable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen: Dictionary[String, bool] = {}
	for index: int in entries.size():
		var entry: EmissiveImage = entries[index]
		if entry == null:
			problems.append("entry %d is empty" % index)
			continue
		var key: String = entry.image_name.to_lower()
		if key.strip_edges().is_empty():
			problems.append("entry %d has no image name" % index)
		elif seen.has(key):
			problems.append("entry %d repeats %s" % [index, entry.image_name])
		seen[key] = true
		if entry.strength < 0.0:
			problems.append("%s has negative strength %s" % [entry.image_name, entry.strength])
		if entry.light_energy < 0.0:
			problems.append("%s has negative light energy %s" % [entry.image_name, entry.light_energy])
	return problems
