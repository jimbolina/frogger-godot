extends ImportStep
## Writes one image per distinct texture id and one [VloFile] resource per bank.
##
## The raw phase writes each texture's padded RGBA8 pixels, alpha from the
## black-is-transparent rule, as [code]textures/images/tNNNN.png[/code], or in
## a runtime run as [code]tNNNN.res[/code], a lossless
## [PortableCompressedTexture2D] without mipmaps (see [method runtime_texture]);
## a texture id held by several banks has identical pixels in every
## one, which is checked. The resources phase saves each bank's headers with
## every image's [member VloImage.texture] set to its loaded image and its
## [member VloImage.pixels] left empty, so the pixels live only in the image file.
## Both phases leave the decoded banks, pixels included, in
## [member ImportContext.banks] for later steps.

func step_name() -> String:
	return "textures"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RAW, PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	var digests: Dictionary[int, String] = {}
	var entries: Array[MwiEntry] = context.data.texture_bank_entries()
	for at: int in entries.size():
		if context.is_cancelled():
			return
		context.advance(at, entries.size())
		var entry: MwiEntry = entries[at]
		var bank_name: String = context.entry_name(entry.index)
		var problems := PackedStringArray()
		var bank: VloFile = context.data.read_texture_bank(entry.index, problems)
		if bank == null:
			context.report("texture bank %s: %s" % [bank_name, "; ".join(problems)])
			continue
		context.banks[bank_name] = bank
		if phase == PHASE_RAW:
			_write_images(context, bank_name, bank, digests)
		else:
			_save_bank(context, entry, bank_name, bank)


func _write_images(context: ImportContext, bank_name: String, bank: VloFile, digests: Dictionary[int, String]) -> void:
	for image: VloImage in bank.images:
		if image.padded_width <= 0 or image.padded_height <= 0 \
				or image.pixels.size() != image.padded_width * image.padded_height * 4:
			context.report("texture bank %s: image %d has no pixels" % [bank_name, image.index])
			continue
		var digest: String = _sha256(image.pixels)
		if digests.has(image.texture_id):
			if digests[image.texture_id] != digest:
				context.report("texture %d differs between banks (%s)" % [image.texture_id, bank_name])
			continue
		digests[image.texture_id] = digest
		var pixels: Image = Image.create_from_data(image.padded_width, image.padded_height, false, Image.FORMAT_RGBA8, image.pixels)
		if context.runtime:
			context.save_resource(runtime_texture(pixels), context.texture_image_path(image.texture_id))
		else:
			context.write_if_changed(context.texture_image_path(image.texture_id), pixels.save_png_to_buffer())


## The texture a runtime run saves for [param pixels]: a
## [PortableCompressedTexture2D] holding them losslessly, with no mipmaps, as
## the editor import of the PNG holds them. Unlike an [ImageTexture], it keeps
## its compressed data, so saving it reads nothing back from the
## RenderingServer and does not wait on the main thread.
static func runtime_texture(pixels: Image) -> PortableCompressedTexture2D:
	var texture := PortableCompressedTexture2D.new()
	texture.keep_compressed_buffer = true
	texture.create_from_image(pixels, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return texture


func _save_bank(context: ImportContext, entry: MwiEntry, bank_name: String, bank: VloFile) -> void:
	var problems := PackedStringArray()
	var saved: VloFile = VloFileReader.parse(context.data.read_resource(entry.index, problems), false)
	if not problems.is_empty() or not saved.error.is_empty() or saved.size() != bank.size():
		context.report("texture bank %s: %s" % [bank_name, "; ".join(problems) + saved.error])
		return
	saved.resource_name = bank_name
	for at: int in saved.size():
		var image: VloImage = saved.images[at]
		image.resource_name = "t%04d" % image.texture_id
		image.resource_scene_unique_id = "image_%03d" % at
		var path: String = context.texture_image_path(image.texture_id)
		var texture: Texture2D = context.load_written(path) as Texture2D
		if texture == null:
			context.report("texture bank %s: %s did not import" % [bank_name, path])
			continue
		image.texture = texture
		bank.images[at].texture = texture
	context.save_resource(saved, context.bank_resource_path(bank_name))


func _sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
