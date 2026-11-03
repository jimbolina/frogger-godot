class_name MapSkyTiles
extends RefCounted
## Packs the sky-land tile images into one [Texture2DArray] for the map sky.
##
## Each layer is one tile image's padded texture as the scene's catalog draws
## it, in the slot order the sky mesh writes to [code]UV2.x[/code]. Every
## sky-land tile shares one padded size and padding, so the sky shader
## normalises a tile's pixel with [method layer_uv] into whichever layer it
## samples. Layers share the largest scale among the tiles' textures: a tile
## drawn at a smaller scale, such as a retail tile beside a texture pack's,
## is enlarged by repeating pixels. A missing image, or one whose padded
## layout differs from the first tile with a texture or whose texture is not
## a whole multiple of its padded size, becomes a magenta layer and a
## diagnostic.

## Colour of a layer whose image is missing or the wrong size.
const MISSING_COLOUR: Color = Color.MAGENTA


## The tile array of [param images], one layer each in that order, from
## [param library] as RGBA8, with mipmaps when [param linear] or when the
## layers are upscaled. Appends one line to [param diagnostics] per magenta
## layer; returns null with a diagnostic when there are no tiles.
static func build(images: Array[VloImage], library: TextureLibrary, linear: bool,
		diagnostics: PackedStringArray) -> Texture2DArray:
	if images.is_empty():
		diagnostics.append("The sky has no tile images; the sky is not drawn")
		return null
	var tiles := Texture2DArray.new()
	var error: Error = tiles.create_from_images(layers(images, library, linear, diagnostics))
	if error != OK:
		diagnostics.append("The sky tile array could not be created (error %d); the sky is not drawn" % error)
		return null
	return tiles


## The layer images [method build] packs: each image's texture as RGBA8 at
## the shared scale, or a magenta image of the shared size with one line in
## [param diagnostics] when the image is missing, its padded layout differs
## from the [method reference_image] or its texture is not a whole multiple
## of its padded size; mipmapped when [param linear] or the scale is above 1.
static func layers(images: Array[VloImage], library: TextureLibrary, linear: bool,
		diagnostics: PackedStringArray) -> Array[Image]:
	var reference: VloImage = reference_image(images, library)
	var scale: int = 1
	var size := Vector2i.ONE
	if reference != null:
		for image: VloImage in images:
			if image != null and _same_layout(image, reference):
				scale = maxi(scale, _scale_of(image, library.texture_for(image)))
		size = Vector2i(reference.padded_width, reference.padded_height) * scale
	var made: Array[Image] = []
	for layer: int in images.size():
		var image: VloImage = images[layer]
		var pixels: Image = null
		if image == null:
			diagnostics.append("Sky tile layer %d has no image; drawn magenta" % layer)
		else:
			var texture: Texture2D = library.texture_for(image)
			if texture == null:
				diagnostics.append("Sky tile layer %d (texture %d) has no texture; drawn magenta" % [layer, image.texture_id])
			elif not _same_layout(image, reference) or _scale_of(image, texture) == 0:
				diagnostics.append("Sky tile layer %d (texture %d) is %dx%d padded %dx%d, not a multiple of padded %dx%d; drawn magenta"
					% [layer, image.texture_id, texture.get_width(), texture.get_height(), image.padded_width,
					image.padded_height, reference.padded_width, reference.padded_height])
			else:
				pixels = TextureBuilder.source_texture(texture).get_image()
				if pixels.is_compressed():
					pixels.decompress()
				pixels.clear_mipmaps()
				pixels.convert(Image.FORMAT_RGBA8)
				if pixels.get_size() != size:
					pixels.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		if pixels == null:
			pixels = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			pixels.fill(MISSING_COLOUR)
		if linear or scale > 1:
			pixels.generate_mipmaps()
		made.append(pixels)
	return made


## The first tile image that has a texture in [param library]'s set, whose
## size and padding every layer shares; null when none has one.
static func reference_image(images: Array[VloImage], library: TextureLibrary) -> VloImage:
	for image: VloImage in images:
		if image != null and library.texture_for(image) != null:
			return image
	return null


## The normalised coordinate inside the padded layer of [param image] that the
## sky shader gives image-relative [param pixel]: [code](pixel + padding) / padded_size[/code].
static func layer_uv(pixel: Vector2, image: VloImage) -> Vector2:
	return (pixel + Vector2(image.left_padding(), image.top_padding())) / Vector2(image.padded_width, image.padded_height)


static func _scale_of(image: VloImage, texture: Texture2D) -> int:
	if texture == null:
		return 0
	return TextureSet.scale_for(Vector2i(texture.get_size()), Vector2i(image.padded_width, image.padded_height))


static func _same_layout(image: VloImage, reference: VloImage) -> bool:
	return (image.padded_width == reference.padded_width and image.padded_height == reference.padded_height
		and image.left_padding() == reference.left_padding() and image.top_padding() == reference.top_padding())
