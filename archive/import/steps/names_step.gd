extends ImportStep
## Saves FrogLord's name lists for the build as [code]tables/names.tres[/code].


func step_name() -> String:
	return "names"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	var names: GameNameLists = context.data.names
	if names == null:
		context.report("names: the build has no name lists")
		return
	if not names.errors.is_empty():
		context.report("names: %s" % "; ".join(names.errors))
	names.resource_name = "%s names" % context.data.version_name
	ImportContext.number_sub_resources(names)
	context.save_resource(names, context.table_path("names"))


## Gives every embedded sub-resource of [param root] a scene-unique id
## [code]<class>_<n>[/code], numbered in property traversal order. Resources
## saved in files of their own are skipped.
