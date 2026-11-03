class_name TexturePack
extends Resource
## One installed texture pack: a folder of replacement images and its
## [code]pack.cfg[/code].
##
## A plain record filled by [TexturePackReader]. [member pack_name] is the
## folder's name, which [code]--texture-pack=[/code] and the launcher settings
## use; [member title] is the name the pack gives itself. [member files] are
## the folder's PNG file names, each named by texture id ([code]t0310.png[/code])
## or by FrogLord image name ([code]hi_a.png[/code]); which texture each
## replaces is resolved against a catalog's image names.

## The folder's name, which names the pack on the command line and in the launcher settings.
@export var pack_name: String = ""
## The pack's own name from [code]pack.cfg[/code].
@export var title: String = ""
## Who made the pack, or "".
@export var author: String = ""
## The pack's version text, or "".
@export var version: String = ""
## A sentence about the pack, or "".
@export var description: String = ""
## The build the pack was drawn for, such as [code]pc-retail-v3.0e[/code].
@export var base_build: String = ""
## The pack's folder.
@export var folder: String = ""
## The PNG file names in [member folder], sorted.
@export var files: PackedStringArray = PackedStringArray()


## [member title], or [member pack_name] when the pack gives itself no name.
func display_name() -> String:
	return title if not title.is_empty() else pack_name


## The path of the file called [param file_name] in the pack's folder.
func path_of(file_name: String) -> String:
	return folder.path_join(file_name)
