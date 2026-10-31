class_name TextureSet
extends RefCounted
## Which committed texture images and baked pages the game draws from: the
## retail-resolution set, or an upscaled set stored beside it.
##
## Records and materials keep pointing at the retail files under
## [code]textures/images/[/code] and [code]textures/pages/[/code]; a catalog
## that chose another set maps each retail path through
## [method counterpart_path] where a texture leaves a record. A set whose
## [member scale] is above 1 samples with linear filtering and mipmaps in 3D,
## and 2D draws scale it back to retail pixels.

## The retail set's name.
const RETAIL: String = "retail"
## The four-times upscaled set's name.
const X4: String = "x4"
## The retail images folder under [code]textures/[/code].
const IMAGES_DIR: String = "images"
## The retail pages folder under [code]textures/[/code].
const PAGES_DIR: String = "pages"

## [constant RETAIL] or [constant X4].
var set_name: String = RETAIL
## The set's images folder under [code]textures/[/code].
var images_dir: String = IMAGES_DIR
## The set's baked pages folder under [code]textures/[/code].
var pages_dir: String = PAGES_DIR
## Pixels per retail pixel on each axis.
var scale: int = 1


## The retail-resolution set.
static func retail() -> TextureSet:
	return TextureSet.new()


## The four-times upscaled set under [code]images_x4/[/code] and [code]pages_x4/[/code].
static func x4() -> TextureSet:
	var made := TextureSet.new()
	made.set_name = X4
	made.images_dir = "images_x4"
	made.pages_dir = "pages_x4"
	made.scale = 4
	return made


## The set called [param name] ("" and [constant RETAIL] give the retail set),
## or null for an unknown name.
static func named(name: String) -> TextureSet:
	match name:
		"", RETAIL:
			return retail()
		X4:
			return x4()
	return null


## True for the retail set.
func is_retail() -> bool:
	return scale == 1


## True when the set's textures are sampled with linear filtering and mipmaps.
func linear_filter() -> bool:
	return scale > 1


## [param path] with its retail images or pages folder replaced by this set's;
## unchanged for the retail set or a path outside those folders.
func counterpart_path(path: String) -> String:
	if is_retail():
		return path
	for pair: PackedStringArray in [PackedStringArray([IMAGES_DIR, images_dir]), PackedStringArray([PAGES_DIR, pages_dir])]:
		var retail_folder: String = "/textures/%s/" % pair[0]
		var at: int = path.find(retail_folder)
		if at >= 0:
			return path.substr(0, at) + "/textures/%s/" % pair[1] + path.substr(at + retail_folder.length())
	return path
