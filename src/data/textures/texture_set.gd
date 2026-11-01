class_name TextureSet
extends RefCounted
## Which committed texture images the game draws from: the retail-resolution
## set, or an upscaled set stored beside it.
##
## Records and materials keep pointing at the retail files under
## [code]textures/images/[/code]; a catalog that chose another set maps each
## retail path through
## [method counterpart_path] where a texture leaves a record. A set whose
## [member scale] is above 1 samples with linear filtering and mipmaps in 3D,
## and 2D draws scale it back to retail pixels.
##
## Every set draws a lettering image under [code]textures/lettering/[/code]
## in place of the retail image it replaces ([method lettering_path]): a
## high-resolution rendering of the vector font at a whole multiple of the
## retail padded size, sampled with linear filtering and mipmaps.

## The retail set's name.
const RETAIL: String = "retail"
## The four-times upscaled set's name.
const X4: String = "x4"
## The retail images folder under [code]textures/[/code].
const IMAGES_DIR: String = "images"
## The lettering images folder under [code]textures/[/code].
const LETTERING_DIR: String = "lettering"

## [constant RETAIL] or [constant X4].
var set_name: String = RETAIL
## The set's images folder under [code]textures/[/code].
var images_dir: String = IMAGES_DIR
## The set's font folder under [code]fonts/[/code].
var fonts_dir: String = "retail"
## Pixels per retail pixel on each axis.
var scale: int = 1


## The retail-resolution set.
static func retail() -> TextureSet:
	return TextureSet.new()


## The four-times upscaled set under [code]images_x4/[/code].
static func x4() -> TextureSet:
	var made := TextureSet.new()
	made.set_name = X4
	made.images_dir = "images_x4"
	made.fonts_dir = "x4"
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


## [param path] with its retail images folder replaced by this set's;
## unchanged for the retail set or a path outside that folder.
func counterpart_path(path: String) -> String:
	if is_retail():
		return path
	var retail_folder: String = "/textures/%s/" % IMAGES_DIR
	var at: int = path.find(retail_folder)
	if at < 0:
		return path
	return path.substr(0, at) + "/textures/%s/" % images_dir + path.substr(at + retail_folder.length())


## The path under the assets root of the lettering image that replaces the
## retail image at [param retail_path] in every set, or "" for a path outside
## the retail images folder.
static func lettering_path(retail_path: String) -> String:
	if not retail_path.contains("/textures/%s/" % IMAGES_DIR):
		return ""
	return "textures/%s/%s" % [LETTERING_DIR, retail_path.get_file()]


## True when [param path] is a lettering image.
static func is_lettering_path(path: String) -> bool:
	return path.contains("/textures/%s/" % LETTERING_DIR)


## The path under the assets root of the set's bitmap font called [param name].
func font_path(name: String) -> String:
	return "fonts/%s/%s.fnt" % [fonts_dir, name]
