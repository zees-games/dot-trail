class_name DotTrailEquip
extends RefCounted

## Server-side record of who wears what. Replicate only the id; a client never decides.

const CHANNEL := "trail"

var registry: DotTrailRegistry
## Milliseconds clock, replaceable so a test does not sleep.
var now_ms: Callable = Time.get_ticks_msec
var _worn: Dictionary = {}
var _last_change: Dictionary = {}

signal changed(player_id: Variant, trail_id: String)


func _init(p_registry: DotTrailRegistry = null) -> void:
	registry = p_registry if p_registry != null else DotTrailRegistry.new()


## Equips [param trail_id] for the player, or unequips on "". Value on success is the id now worn.
func equip(player_id: Variant, trail_id: String, groups: PackedStringArray, entitlements: PackedStringArray = PackedStringArray()) -> DotResult:
	var now: int = now_ms.call()
	var cooldown := int(registry.config.equip_cooldown * 1000.0)
	if _last_change.has(player_id) and now - int(_last_change[player_id]) < cooldown:
		return DotResult.fail(DotError.CODE_RATE_LIMITED, "equipping too fast", str(player_id))
	if not trail_id.is_empty():
		var allowed := registry.may_equip(trail_id, groups, entitlements)
		if not allowed.ok:
			DotLog.info(CHANNEL, "equip refused", {"player": str(player_id), "trail": trail_id, "code": allowed.code()})
			return allowed
	_last_change[player_id] = now
	if trail_id.is_empty():
		_worn.erase(player_id)
	else:
		_worn[player_id] = trail_id
	DotLog.debug(CHANNEL, "equipped", {"player": str(player_id), "trail": trail_id})
	changed.emit(player_id, trail_id)
	return DotResult.success(trail_id)


func worn(player_id: Variant) -> String:
	return _worn.get(player_id, "")


## Call when a player leaves.
func forget(player_id: Variant) -> void:
	_worn.erase(player_id)
	_last_change.erase(player_id)


## Drops a worn trail the player no longer qualifies for (a group removed, an entitlement expired). True if it did.
func revalidate(player_id: Variant, groups: PackedStringArray, entitlements: PackedStringArray = PackedStringArray()) -> bool:
	var id := worn(player_id)
	if id.is_empty() or registry.may_equip(id, groups, entitlements).ok:
		return false
	_worn.erase(player_id)
	changed.emit(player_id, "")
	return true


func describe() -> String:
	return "DotTrailEquip: %d wearing, %d known trails" % [_worn.size(), registry.count()]
