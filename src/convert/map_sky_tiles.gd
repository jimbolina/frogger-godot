class_name MapSkyTiles
extends RefCounted
## Packs the sky-land tile images into one [Texture2DArray] for the modern sky.
##
## Each layer is one tile image's padded texture from the scene's texture set,
## in the slot order the sky mesh writes to [code]CUSTOM0.x[/code]. Every
## sky-land tile shares one padded size and padding, so the sky shader
## normalises a tile's pixel with [method layer_uv] into whichever layer it
## samples. A missing image, or one whose size differs from the first tile
## with a texture, becomes a magenta layer and a diagnostic.

## Colour of a layer whose image is missing or the wrong size.
const MISSING_COLOUR: Color = Color.MAGENTA


## The tile array of [param images], one layer each in that order, from
## [param library]'s texture set as RGBA8 with mipmaps when [param linear].
## Appends one line to [param diagnostics] per magenta layer; returns null
## with a diagnostic when there are no tiles.
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


## The layer images [method build] packs: each image's texture as RGBA8, or
## a magenta image of the shared size with one line in [param diagnostics]
## when the image is missing or its size or padding differs from the
## [method reference_image]; mipmapped when [param linear].
static func layers(images: Array[VloImage], library: TextureLibrary, linear: bool,
		diagnostics: PackedStringArray) -> Array[Image]:
	var reference: VloImage = reference_image(images, library)
	var size := Vector2i.ONE
	if reference != null:
		size = library.texture_for(reference).get_size()
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
			elif texture.get_size() != Vector2(size) or not _same_layout(image, reference):
				diagnostics.append("Sky tile layer %d (texture %d) is %dx%d padded %dx%d, not %dx%d padded %dx%d; drawn magenta"
					% [layer, image.texture_id, texture.get_width(), texture.get_height(), image.padded_width,
					image.padded_height, size.x, size.y, reference.padded_width, reference.padded_height])
			else:
				pixels = texture.get_image()
				if pixels.is_compressed():
					pixels.decompress()
				pixels.clear_mipmaps()
				pixels.convert(Image.FORMAT_RGBA8)
		if pixels == null:
			pixels = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			pixels.fill(MISSING_COLOUR)
		if linear:
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


static func _same_layout(image: VloImage, reference: VloImage) -> bool:
	return (image.padded_width == reference.padded_width and image.padded_height == reference.padded_height
		and image.left_padding() == reference.left_padding() and image.top_padding() == reference.top_padding())
