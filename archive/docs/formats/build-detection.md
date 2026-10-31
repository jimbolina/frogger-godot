# Build detection

The current compatibility target is `pc-retail-v3.0e`, including FrogLord-saved
edits based on it. Existing recognition/configuration data for other builds
does not establish verified gameplay compatibility. Retail counts below refer
to v3.0e. See [source locations](../../../docs/reference/sources.md).

File lookup ignores letter case but returns the directory entry's actual spelling,
preferring an exact match when present. Checking only whether a requested spelling
exists is insufficient on case-insensitive filesystems: macOS Godot can accept
that lookup and then report a case mismatch when opening the file.

- A FrogLord-saved executable ends in the eight bytes `FROGLORD`. Before them: the config text in UTF-8, a zero byte, a version byte, and the original executable length as a 32-bit integer. The config text names the build.
- Otherwise the build is found by the CRC-32 of the whole executable, matched against `exeChecksum` in FrogLord's version files. The retail executable gives 378672750.
- FrogLord has two config formats: an older one for version files and name lists, and a newer one for the block in a saved executable and for the texture-bank tree. They parse differently, so there are two parsers.
- The PC version files leave out the form, entity and script name lists. FrogLord falls back to `forms` and `entities` `1997-09-12-psx-build57` and `scripts` `1997-09-18-psx-build63`, and so does this project.

FrogLord may change config keys or its saved-executable trailer. Check upstream format definitions when supporting a new editor version.
