class_name ShadowEffectPolicy
extends RefCounted
## Whether the retail blob shadow effects draw beside the scene lights' real
## shadows: the frog's ground shadow and the Desert falling-rock and
## tumbleweed shadow quads. They draw only when the
## [code]frogger/rendering/effect_shadows[/code] setting asks for them.

## Setting value that draws the blob shadow effects.
const RETAIL: String = "retail"
## Setting value that hides the blob shadow effects.
const OFF: String = "off"
## Setting value used when none is configured.
const DEFAULT: String = OFF


## True when [param setting] draws the blob shadow effects; any setting other
## than [constant OFF] keeps them.
static func draws_blob_shadows(setting: String) -> bool:
	return setting.strip_edges().to_lower() != OFF
