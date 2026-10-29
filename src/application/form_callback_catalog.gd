class_name FormCallbackCatalog
extends RefCounted
## Verified v3.0e code identities resolved once into typed gameplay callbacks.

const NAMES: Dictionary[int, String] = {
	0x41d7e0: "VolColourTriggerEntityCallback",
	0x428390: "GenBlockCollPrimCallback",
	0x4287a0: "GenBlockWaterFallCollPrimCallback",
	0x4287c0: "GenBlockFallCollPrimCallback",
	0x4231d0: "OrgFlyCallBack",
	0x4284e0: "GenButterFlyCallBack",
	0x43d060: "CavFireFlyCallBack",
	0x4241c0: "SwpCrusherCallback",
}
const KINDS: Dictionary[String, FormCallback.Kind] = {
	"VolColourTriggerEntityCallback": FormCallback.Kind.VOL_COLOUR_SWITCH,
	"GenBlockCollPrimCallback": FormCallback.Kind.BLOCK,
	"GenBlockWaterFallCollPrimCallback": FormCallback.Kind.WATERFALL_BLOCK,
	"GenBlockFallCollPrimCallback": FormCallback.Kind.FALL_BLOCK,
	"OrgFlyCallBack": FormCallback.Kind.ORG_FLY_SCORE,
	"GenButterFlyCallBack": FormCallback.Kind.BUTTERFLY_SCORE,
	"CavFireFlyCallBack": FormCallback.Kind.CAV_FIREFLY_SCORE,
	"SwpCrusherCallback": FormCallback.Kind.CRUSHER_BOUNCE_BACK,
}

## Resolves supported repointing without deriving identity from the owning form.
static func resolve(build_id: String, address: int, _bonus: bool = false) -> FormCallback.Kind:
	if address == 0:
		return FormCallback.Kind.NONE
	if build_id != "pc-retail-v3.0e" or not NAMES.has(address):
		return FormCallback.Kind.UNKNOWN
	var kind: FormCallback.Kind = KINDS[NAMES[address]]
	return kind
