class_name DotTrailBackendStub
extends DotTrailBackend

## An in-memory store with the site's contract: a points balance, prices, purchases, uploads queued for moderation. Persists to [member save_path] when set (flushing the web filesystem).

var points: int = 1000
## id -> {title, price_points, public}
var prices: Dictionary = {}
var owned: Dictionary = {}
var uploads: Array[Dictionary] = []
var equipped: String = ""
var save_path: String = ""
## Seconds each call waits, to show a busy state in a shot.
var delay_sec: float = 0.0
var _tree: SceneTree = null


## Prices from a registry's defs (their `price`), the rest of the contract in memory.
static func from_registry(registry: DotTrailRegistry, p_points: int = 1000, tree: SceneTree = null) -> DotTrailBackendStub:
	var b := DotTrailBackendStub.new()
	b.points = p_points
	b._tree = tree
	if registry != null:
		for id in registry.ids():
			var def := registry.get_def(id)
			b.prices[id] = {"title": def.title, "price_points": int(def.price), "public": def.access == DotTrailDef.ACCESS_PUBLIC}
	b.load_state()
	return b


func catalog() -> DotResult:
	await _wait()
	var rows: Array = []
	for id: String in prices:
		var p: int = int(prices[id]["price_points"])
		var free: bool = p == 0 and bool(prices[id].get("public", true))
		rows.append({"id": id, "title": str(prices[id]["title"]), "price_points": p, "free": free,
			"owned": owned.has(id) or free, "preview_url": ""})
	return DotResult.success({"trails": rows, "points": points})


func purchase(id: String) -> DotResult:
	await _wait()
	if not prices.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "unknown_sku")
	if owned.has(id):
		return DotResult.fail(DotError.CODE_CONFLICT, "already_owned")
	var price: int = int(prices[id]["price_points"])
	if price > points:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "insufficient_points")
	points -= price
	owned[id] = true
	save_state()
	return DotResult.success({"ids": owned.keys(), "points": points})


func submit_upload(meta: Dictionary, bytes: PackedByteArray, file_name: String) -> DotResult:
	await _wait()
	var checked := DotTrailUpload.validate(bytes, file_name)
	if not checked.ok:
		return checked
	if str(meta.get("title", "")).strip_edges().is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "a title is required")
	var row := {"id": "upload_%d" % (uploads.size() + 1), "status": "pending", "title": str(meta.get("title")),
		"bytes": bytes.size(), "type": checked.value["type"]}
	uploads.append(row)
	save_state()
	return DotResult.success({"id": row["id"], "status": "pending"})


func entitlements(_player: String) -> DotResult:
	return DotResult.success({"ids": PackedStringArray(owned.keys()), "groups": PackedStringArray(), "equipped": equipped})


func set_equipped(id: String, _game: String = "") -> DotResult:
	if not id.is_empty() and not owned.has(id) and int(prices.get(id, {}).get("price_points", 1)) > 0:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "not_entitled")
	equipped = id
	return DotResult.success({"equipped": id})


func save_state() -> void:
	if save_path.is_empty():
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"points": points, "owned": owned.keys(), "uploads": uploads.size()}))
	f.close()
	DotWeb.sync_filesystem()


func load_state() -> void:
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary:
		points = int(data.get("points", points))
		for id: Variant in data.get("owned", []):
			owned[str(id)] = true


func _wait() -> void:
	if delay_sec > 0.0 and _tree != null:
		await _tree.create_timer(delay_sec).timeout
