extends AssetTest
## Every audio track of the disc is an Ogg Vorbis file under assets/audio/music
## without a baked loop, one per track asset_census.txt counts, and every
## track the executable's music list plays is present. The archive suite's
## test_retail_disc_tracks.gd checks their lengths against the importer's
## disc_tracks.tsv.

## The first audio track; track 1 is the data track.
const FIRST_TRACK: int = 2


## The committed Ogg of disc track [param track].
static func ogg_path(track: int) -> String:
	return "%s/audio/music/track_%02d.ogg" % [ASSETS, track]


func test_every_disc_track_is_an_unlooped_ogg() -> void:
	var count: int = int(fact_values("asset_census.txt")["disc_audio_tracks"])
	assert_eq(count, 31)
	var failures := PackedStringArray()
	for track: int in range(FIRST_TRACK, FIRST_TRACK + count):
		var path: String = ogg_path(track)
		var stream: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis if ResourceLoader.exists(path) else null
		if stream == null:
			failures.append("%s does not load" % path.trim_prefix("res://"))
		elif stream.loop:
			failures.append("%s has a baked loop" % path.trim_prefix("res://"))
	assert_eq(failures, PackedStringArray())
	assert_eq(files_under(ASSETS.path_join("audio/music"), ".ogg").size(), count, "one Ogg per track")


func test_every_music_list_track_is_present() -> void:
	var missing := PackedStringArray()
	for row: PackedStringArray in fact_rows("exe_music.tsv"):
		if not ResourceLoader.exists(ogg_path(int(row[2]))):
			missing.append("%s plays track %s" % [row[1], row[2]])
	assert_eq(missing, PackedStringArray())
