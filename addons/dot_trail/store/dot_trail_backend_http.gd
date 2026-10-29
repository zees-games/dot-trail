class_name DotTrailBackendHttp
extends DotTrailBackend

## The TMC site's trail store over [DotHttp] (HTTPRequest, so it runs in a browser). The paths are the contract in docs/design.md; a player's calls carry their site token, the server's carry its API key.

## Paths on the site, settable so a deployment follows the site's routes without a code change.
var catalog_path := "/api/trails/catalog"
var purchase_path := "/api/store/purchase"
var uploads_path := "/api/trails/uploads"
var entitlements_path := "/api/trails/entitlements"

var http: DotHttp = null
## func() -> String: the signed-in player's bearer token, "" for a guest.
var token_fn: Callable = Callable()
## Server to server only; never set on a client.
var api_key: String = ""


## [param host] keeps the HTTPRequest node; it is freed with it.
static func make(host: Node, base_url: String, p_token_fn: Callable = Callable()) -> DotTrailBackendHttp:
	var b := DotTrailBackendHttp.new()
	b.http = DotHttp.new()
	b.http.name = "TrailStoreHttp"
	b.http.base_url = base_url
	host.add_child(b.http)
	b.token_fn = p_token_fn
	return b


func catalog() -> DotResult:
	var res: DotResult = await http.get_json(catalog_path, _player_headers())
	if not res.ok:
		return res
	var body: Variant = res.value
	if not (body is Dictionary) or not (body.get("trails") is Array):
		return DotResult.fail(DotError.CODE_PARSE, "trail catalog is not {trails: [...]}")
	var rows: Array = []
	for row: Variant in body["trails"]:
		if row is Dictionary and DotTrailDef.valid_id(str(row.get("id", ""))):
			rows.append(row)
	var points: Variant = body.get("points")
	return DotResult.success({"trails": rows, "points": int(points) if points is float or points is int else -1})


func purchase(id: String) -> DotResult:
	var headers := _player_headers()
	if not headers.has("Authorization"):
		return DotResult.fail(DotError.CODE_AUTH, "unauthorized")
	var body := {"sku": "trail:" + id, "currency": "points", "purchase_id": _purchase_id(id)}
	var res: DotResult = await http.post_json(purchase_path, body, headers)
	if not res.ok:
		return res
	var v: Variant = res.value
	if not (v is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "purchase answer is not an object")
	return DotResult.success({"ids": v.get("ids", []), "points": int(v.get("points", -1))})


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


func entitlements(user: String) -> DotResult:
	if api_key.is_empty():
		return DotResult.fail(DotError.CODE_AUTH, "no trail API key")
	var res: DotResult = await http.get_json("%s?user=%s" % [entitlements_path, user.uri_encode()], {"Authorization": "Bearer " + api_key})
	if not res.ok:
		return res
	var v: Variant = res.value
	if not (v is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "entitlements answer is not an object")
	return DotResult.success({"ids": PackedStringArray(v.get("ids", [])), "groups": PackedStringArray(v.get("groups", []))})


func _player_headers() -> Dictionary:
	var token: String = str(token_fn.call()) if token_fn.is_valid() else ""
	return {"Authorization": "Bearer " + token} if not token.is_empty() else {}


## One id per press: a retried request is the same purchase, so the site can make it idempotent.
func _purchase_id(id: String) -> String:
	return "%s-%d-%d" % [id, Time.get_unix_time_from_system(), randi()]
