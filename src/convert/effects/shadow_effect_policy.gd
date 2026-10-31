class_name ShadowEffectPolicy
extends RefCounted
## Whether the retail blob shadow effects draw: the frog's ground shadow and
## the Desert falling-rock and tumbleweed shadow quads. The retail profile
## always draws them; the modern profile, whose lights cast real shadows,
## draws them only when the [code]frogger/rendering/effect_shadows[/code]
## setting asks for the retail effects.

## Setting value that keeps the blob shadow effects under both profiles.
const RETAIL: String = "retail"
## Setting value that hides the blob shadow effects under the modern profile.
const OFF: String = "off"
## Setting value used when none is configured.
const DEFAULT: String = OFF


## True when [param profile] draws the blob shadow effects under [param setting];
## any setting other than [constant OFF] keeps them.
static func draws_blob_shadows(profile: RenderingProfile, setting: String) -> bool:
	if profile == null or not profile.is_modern():
		return true
	return setting.strip_edges().to_lower() != OFF
