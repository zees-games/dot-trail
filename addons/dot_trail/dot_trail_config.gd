class_name DotTrailConfig
extends DotConfig

## The trail cvars. Layered like every DotConfig: defaults, JSON file, environment (DOT_TRAIL_*), command line (--trail-*).

@export var enabled: bool = true
## Metres a wearer must move before a ribbon point is added.
@export var min_step: float = 0.15
@export var max_points: int = 64
## Seconds between equip changes per player.
@export var equip_cooldown: float = 1.0
@export var entitlement_ttl: float = 60.0
@export var max_trails: int = 256
@export var max_upload_bytes: int = 262144
@export var max_dimension: int = 512
@export var max_width: float = 2.0
@export var max_lifetime: float = 5.0
## Emitters farther than this from the camera stop building a mesh. 0 is never.
@export var cull_distance: float = 60.0
## The pack this server advertises as `sv_trail_pack`, "<content id>@<version>" (see [method DotTrailClient.advertise]). Empty advertises none.
@export var pack: String = ""


func env_prefix() -> String:
	return "DOT_TRAIL_"


func cli_prefix() -> String:
	return "--trail-"


func validate() -> DotResult:
	if min_step <= 0.0 or max_points < 2 or max_trails < 1 or max_upload_bytes < 1 or max_dimension < 1:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: min_step, max_points, max_trails, max_upload_bytes and max_dimension must be positive")
	if equip_cooldown < 0.0 or max_width <= 0.0 or max_lifetime <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: equip_cooldown must not be negative; max_width and max_lifetime must be positive")
	if not pack.strip_edges().is_empty() and pack_parts().is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "trail config: pack must be <content id>@<version>")
	return DotResult.success(null)


func limits() -> Dictionary:
	return {"max_bytes": max_upload_bytes, "max_dimension": max_dimension}


## [member pack] as [id, version], or empty when unset or malformed.
func pack_parts() -> PackedStringArray:
	return parse_pack(pack)


## "<id>@<version>" as [id, version]; empty for anything else. The id is dot-cloud's (one slug or `<owner>/<name>`); dot-cloud checks both in full when it fetches.
static func parse_pack(text: String) -> PackedStringArray:
	var parts := text.strip_edges().split("@")
	if parts.size() != 2 or parts[0].contains(".."):
		return PackedStringArray()
	var id := RegEx.create_from_string("^[A-Za-z0-9._-]{1,128}(/[A-Za-z0-9._-]{1,128})?$")
	var version := RegEx.create_from_string("^[A-Za-z0-9._+-]{1,64}$")
	if id.search(parts[0]) == null or version.search(parts[1]) == null:
		return PackedStringArray()
	return parts
