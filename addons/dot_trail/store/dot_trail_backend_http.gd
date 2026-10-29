class_name DotTrailBackendHttp
extends DotTrailBackend

## The TMC site's trail store over [DotHttp] (HTTPRequest, so it runs in a browser). A player's calls use /api/app/v1 with their token; the game server's use /api/integration/v1 with its integration key. Paths and field names are settable (see [method apply_config]).

## Player routes: GET lists, PUT sets what is worn, POST purchase buys with points.
var catalog_path := "/api/app/v1/trails"
var equipped_path := "/api/app/v1/trails"
var purchase_path := "/api/app/v1/trails/purchase"
var uploads_path := "/api/app/v1/trails/uploads"
## Server routes, authorised by [member api_key].
var server_catalog_path := "/api/integration/v1/trails/catalog"
var entitlements_path := "/api/integration/v1/trails/entitlements"
## Query parameter naming the player on the entitlements route.
var player_param := "player"

var http: DotHttp = null
## func() -> String: the signed-in player's bearer token, "" for a guest.
var token_fn: Callable = Callable()
## The server's integration token; never set on a client, never logged.
var api_key: String = ""
var _skus: Dictionary = {}


## [param host] keeps the HTTPRequest node; it is freed with it.
static func make(host: Node, base_url: String, p_token_fn: Callable = Callable()) -> DotTrailBackendHttp:
	var b := DotTrailBackendHttp.new()
	b.http = DotHttp.new()
	b.http.name = "TrailStoreHttp"
	b.http.base_url = base_url
	host.add_child(b.http)
	b.token_fn = p_token_fn
	return b


## Takes the `trail_*_path` keys of trail.yml (catalog, equipped, purchase, uploads, server_catalog, entitlements) and `trail_player_param`.
func apply_config(cfg: Dictionary) -> void:
	for key: String in ["catalog", "equipped", "purchase", "uploads", "server_catalog", "entitlements"]:
		var v := str(cfg.get("trail_%s_path" % key, ""))
		if v.begins_with("/"):
			set(key + "_path", v)
	var param := str(cfg.get("trail_player_param", ""))
	if not param.is_empty():
		player_param = param


func catalog() -> DotResult:
	var res: DotResult = await http.get_json(catalog_path, _player_headers())
	if not res.ok:
		return res
	var body: Variant = res.value
	if not (body is Dictionary) or not (body.get("trails") is Array):
		return DotResult.fail(DotError.CODE_PARSE, "trail list is not {trails: [...]}")
	var rows: Array = []
	for row: Variant in body["trails"]:
		if row is Dictionary and DotTrailDef.valid_id(str(row.get("id", ""))):
			rows.append(_row(row))
	return DotResult.success({"trails": rows, "points": _int(body.get("points", body.get("balance")), -1),
		"equipped": str(body.get("equipped", ""))})


func purchase(id: String) -> DotResult:
	var headers := _player_headers()
	if not headers.has("Authorization"):
		return DotResult.fail(DotError.CODE_AUTH, "unauthorized")
	var body := {"id": id, "sku": _skus.get(id, "trail:" + id), "purchase_id": _purchase_id(id)}
	var res: DotResult = await http.post_json(purchase_path, body, headers)
	if not res.ok:
		return res
	var v: Variant = res.value
	if not (v is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "purchase answer is not an object")
	return DotResult.success({"ids": _ids(v.get("ids", v.get("owned", v.get("trails", [])))), "points": _int(v.get("points", v.get("balance")), -1)})


func set_equipped(id: String, game: String = "") -> DotResult:
	var headers := _player_headers()
	if not headers.has("Authorization"):
		return DotResult.fail(DotError.CODE_AUTH, "unauthorized")
	var body := {"id": id}
	if not game.is_empty():
		body["game"] = game
	var res: DotResult = await http.put_json(equipped_path, body, headers)
	if not res.ok:
		return res
	return DotResult.success({"equipped": id})


func submit_upload(meta: Dictionary, bytes: PackedByteArray, file_name: String) -> DotResult:
	var checked := DotTrailUpload.validate(bytes, file_name)
	if not checked.ok:
		return checked
	var headers := _player_headers()
	if not headers.has("Authorization"):
		return DotResult.fail(DotError.CODE_AUTH, "unauthorized")
	var body := {"title": str(meta.get("title", "")), "licence": str(meta.get("licence", "")),
		"author": str(meta.get("author", "")), "url": str(meta.get("url", "")),
		"file_name": file_name, "image_base64": Marshalls.raw_to_base64(bytes)}
	return await http.post_json(uploads_path, body, headers)


func entitlements(player: String) -> DotResult:
	var res: DotResult = await _server_get("%s?%s=%s" % [entitlements_path, player_param, player.uri_encode()])
	if not res.ok:
		return res
	var v: Variant = res.value
	if not (v is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "entitlements answer is not an object")
	var ids := _ids(v.get("trails", v.get("ids", [])))
	var equipped: Variant = v.get("equipped", "")
	if equipped is Dictionary:
		equipped = equipped.get("id", "")
	return DotResult.success({"ids": ids, "groups": _ids(v.get("groups", [])), "equipped": str(equipped)})


func server_catalog() -> DotResult:
	var res: DotResult = await _server_get(server_catalog_path)
	if not res.ok:
		return res
	var v: Variant = res.value
	var list: Variant = v.get("trails") if v is Dictionary else v
	if not (list is Array):
		return DotResult.fail(DotError.CODE_PARSE, "trail catalog is not a list")
	var rows: Array = []
	for row: Variant in list:
		if row is Dictionary and DotTrailDef.valid_id(str(row.get("id", ""))):
			rows.append(row)
	return DotResult.success({"trails": rows})


func _server_get(path: String) -> DotResult:
	if api_key.is_empty():
		return DotResult.fail(DotError.CODE_AUTH, "no trail API key")
	return await http.get_json(path, {"Authorization": "Bearer " + api_key})


## A store row in the shape the screen reads; the site's price and image names are accepted too.
func _row(row: Dictionary) -> Dictionary:
	var price := _int(row.get("price_points", row.get("price")), 0)
	var out := row.duplicate()
	out["price_points"] = price
	out["free"] = bool(row.get("free", price == 0))
	out["owned"] = bool(row.get("owned", false))
	out["preview_url"] = str(row.get("preview_url", row.get("image_url", "")))
	if row.has("sku"):
		_skus[str(row["id"])] = str(row["sku"])
	return out


static func _int(v: Variant, fallback: int) -> int:
	return int(v) if v is float or v is int else fallback


## Ids from a list of strings or of {id} rows.
static func _ids(list: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if list is Array:
		for item: Variant in list:
			var id := str(item.get("id", "")) if item is Dictionary else str(item)
			if not id.is_empty():
				out.append(id)
	return out


func _player_headers() -> Dictionary:
	var token: String = str(token_fn.call()) if token_fn.is_valid() else ""
	return {"Authorization": "Bearer " + token} if not token.is_empty() else {}


## One id per press: a retried request is the same purchase, so the site can make it idempotent.
func _purchase_id(id: String) -> String:
	return "%s-%d-%d" % [id, Time.get_unix_time_from_system(), randi()]
