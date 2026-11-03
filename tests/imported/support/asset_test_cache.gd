class_name AssetTestCache
extends RefCounted
## The local import's catalog, opened once per run and shared by every
## [AssetTest]. The static state lives here rather than in the inherited test
## base: Godot 4.5.1 on Windows crashes at exit when a script with static
## variables is inherited by a loaded script.

## Where the imported assets live.
const ASSETS: String = ImportedAssets.COMMITTED_ROOT

static var _catalog: ImportedAssets


## The local import, opened on first use.
static func catalog() -> ImportedAssets:
	if _catalog == null:
		_catalog = ImportedAssets.open(ASSETS)
	return _catalog
