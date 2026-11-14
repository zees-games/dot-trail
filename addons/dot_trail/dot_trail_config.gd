class_name DotTrailConfig
extends DotConfig

## The trail cvars. Layered like every DotConfig: defaults, JSON file, environment (DOT_TRAIL_*), command line (--trail-*).

@export var enabled: bool = true
## Metres a wearer must move before a ribbon point is added.
@export var min_step: float = 0.15
## Points kept per ribbon. 0 is unlimited (the ribbon is then bounded by its lifetime alone).
@export var max_points: int = 64
## Seconds between equip changes per player.
@export var equip_cooldown: float = 1.0
@export var entitlement_ttl: float = 60.0
## Trails the registry accepts. 0 is unlimited.
@export var max_trails: int = 256
## Largest uploaded image in bytes. 0 is unlimited.
@export var max_upload_bytes: int = 262144
## Largest image side in pixels. 0 is unlimited.
@export var max_dimension: int = 512
## Widest ribbon a trail may ask for, in metres. 0 is unlimited.
@export var max_width: float = 2.0
## Longest ribbon lifetime a trail may ask for, in seconds. 0 is unlimited.
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
	if min_step <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: min_step must be positive")
	if max_points < 0 or max_points == 1:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: max_points must be 0 (unlimited) or at least 2")
	if max_trails < 0 or max_upload_bytes < 0 or max_dimension < 0 or max_width < 0.0 or max_lifetime < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: max_trails, max_upload_bytes, max_dimension, max_width and max_lifetime must be 0 (unlimited) or more")
	if equip_cooldown < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "trail config: equip_cooldown must not be negative")
	if not pack.strip_edges().is_empty() and pack_parts().is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "trail config: pack must be <content id>@<version>")
	return DotResult.success(null)


func limits() -> Dictionary:
	return {"max_bytes": max_upload_bytes, "max_dimension": max_dimension, "max_width": max_width, "max_lifetime": max_lifetime}


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
