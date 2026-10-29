extends Node

## DotTrailBackendHttp against a mocked HTTP layer: each route, its headers and body, the error words, and a purchase flow.

const SECTIONS := 5
const CHECKS := 29

var _passed := 0
var _failed := 0
var _section_count := 0


class MockHttp:
	extends DotHttp
	var calls: Array = []
	## path prefix -> {status, body, method (optional)}
	var routes: Dictionary = {}

	func request(method: int, path: String, body: PackedByteArray = PackedByteArray(), headers: Dictionary = {}, _decode_text: bool = true) -> DotResult:
		calls.append({"method": method, "path": path, "body": body.get_string_from_utf8(), "headers": headers})
		var best := ""
		for prefix: String in routes:
			if path.begins_with(prefix) and routes[prefix].get("method", method) == method and prefix.length() > best.length():
				best = prefix
		if best.is_empty():
			return DotResult.failure(DotError.from_http(404, "no route"))
		var r: Dictionary = routes[best]
		if int(r["status"]) >= 300:
			return DotResult.failure(DotError.from_http(int(r["status"]), str(r["body"])))
		return DotResult.success({"status": r["status"], "headers": {}, "body": PackedByteArray(), "body_text": str(r["body"])})


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _backend(mock: MockHttp, token: String, key: String) -> DotTrailBackendHttp:
	var b := DotTrailBackendHttp.new()
	b.http = mock
	b.token_fn = func() -> String: return token
	b.api_key = key
	return b


func _run() -> void:
	print("dot-trail http self-test")
	await _test_server()
	await _test_player()
	await _test_purchase_flow()
	await _test_errors()
	_test_config()
	print("\n%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _test_server() -> void:
	_section("server routes")
	var m := MockHttp.new()
	m.routes["/api/integration/v1/trails/catalog"] = {"status": 200, "body": JSON.stringify({"trails": [
		{"id": "spark", "title": "Spark", "image": "spark.png", "image_url": "https://cdn/x.png", "sha256": "ab", "sku": "trail:spark"}, {"id": "BAD ID"}]})}
	m.routes["/api/integration/v1/trails/entitlements"] = {"status": 200, "body": JSON.stringify({"trails": [{"id": "spark"}, {"id": "comet"}], "equipped": {"id": "comet"}})}
	var b := _backend(m, "", "SECRETKEY")
	var cat: DotResult = await b.server_catalog()
	_check(cat.ok and cat.value["trails"].size() == 1 and cat.value["trails"][0]["sha256"] == "ab", "catalog keeps valid defs with sha256 and drops a bad id")
	_check(m.calls[0]["headers"].get("Authorization") == "Bearer SECRETKEY", "the server key travels as a bearer header")
	var ent: DotResult = await b.entitlements("p 1")
	_check(ent.ok and ent.value["ids"] == PackedStringArray(["spark", "comet"]) and ent.value["equipped"] == "comet", "entitlements read trails and the worn id")
	_check(m.calls[1]["path"] == "/api/integration/v1/trails/entitlements?player=p%201", "the player key is a query parameter, encoded")
	var refused: DotResult = await _backend(m, "", "").entitlements("p")
	_check(refused.code() == DotError.CODE_AUTH and m.calls.size() == 2, "no key means no request")


func _test_player() -> void:
	_section("player routes")
	var m := MockHttp.new()
	m.routes["/api/app/v1/trails"] = {"status": 200, "method": HTTPClient.METHOD_GET, "body": JSON.stringify({"points": 120, "equipped": "spark", "trails": [
		{"id": "spark", "title": "Spark", "price": 0, "owned": true, "image_url": "https://cdn/s.png", "sku": "trail:spark"},
		{"id": "comet", "title": "Comet", "price": 300, "sku": "sku-comet"}]})}
	var b := _backend(m, "TOK", "")
	var cat: DotResult = await b.catalog()
	var rows: Array = cat.value["trails"] if cat.ok else [{}, {}]
	_check(cat.ok and rows.size() == 2 and int(cat.value["points"]) == 120 and cat.value["equipped"] == "spark", "list gives rows, the balance and the worn trail")
	_check(rows[0].get("free") and rows[0].get("owned") and rows[0].get("preview_url") == "https://cdn/s.png", "a free row is owned and previews from image_url")
	_check(rows[1].get("price_points") == 300 and not rows[1].get("free") and not rows[1].get("owned"), "price becomes price_points")
	_check(m.calls[0]["headers"].get("Authorization") == "Bearer TOK", "the player token authorises the list")
	m.routes["/api/app/v1/trails"] = {"status": 200, "method": HTTPClient.METHOD_PUT, "body": "{}"}
	var eq: DotResult = await b.set_equipped("comet", "arena")
	_check(eq.ok and eq.value["equipped"] == "comet", "set_equipped succeeds")
	var put: Dictionary = m.calls[1]
	_check(put["method"] == HTTPClient.METHOD_PUT and JSON.parse_string(put["body"]) == {"id": "comet", "game": "arena"}, "PUT carries id and game")
	var site: DotResult = await b.set_equipped("")
	_check(site.ok and JSON.parse_string(m.calls[2]["body"]) == {"id": ""}, "taking off sends an empty id and no game")
	var g: DotResult = await _backend(m, "", "").set_equipped("comet")
	_check(g.code() == DotError.CODE_AUTH and m.calls.size() == 3, "a guest cannot equip")


func _test_purchase_flow() -> void:
	_section("purchase flow")
	var m := MockHttp.new()
	m.routes["/api/app/v1/trails/purchase"] = {"status": 200, "body": JSON.stringify({"trails": [{"id": "spark"}, {"id": "comet"}], "balance": 20})}
	m.routes["/api/app/v1/trails"] = {"status": 200, "method": HTTPClient.METHOD_GET, "body": JSON.stringify({"points": 320, "trails": [{"id": "comet", "price": 300, "sku": "sku-comet"}]})}
	var b := _backend(m, "TOK", "")
	await b.catalog()
	var bought: DotResult = await b.purchase("comet")
	var sent: Variant = JSON.parse_string(m.calls[1]["body"])
	_check(bought.ok and int(bought.value["points"]) == 20, "buy answers the new balance")
	_check(bought.ok and bought.value["ids"].has("comet"), "and the owned ids")
	_check(sent is Dictionary and sent["sku"] == "sku-comet" and sent["id"] == "comet", "the catalog's sku is sent")
	_check(str(sent["purchase_id"]).begins_with("comet-"), "a purchase id is sent")
	_check(m.calls[1]["path"] == "/api/app/v1/trails/purchase" and m.calls[1]["method"] == HTTPClient.METHOD_POST, "buy is a POST to purchase")
	_check((await _backend(m, "", "").purchase("comet")).code() == DotError.CODE_AUTH, "a guest cannot buy")


func _test_errors() -> void:
	_section("error words")
	var m := MockHttp.new()
	var b := _backend(m, "TOK", "")
	m.routes["/api/app/v1/trails/purchase"] = {"status": 402, "body": "{\"error\":\"Need 80 more Points\"}"}
	var poor: DotResult = await b.purchase("comet")
	_check(not poor.ok and DotTrailBackend.explain(poor) == "You need 80 more points.", "insufficient balance names the shortfall")
	m.routes["/api/app/v1/trails/purchase"] = {"status": 403, "body": "{\"error\":\"not_entitled\"}"}
	_check(DotTrailBackend.explain(await b.purchase("comet")) == "You do not own this trail.", "not entitled is explained")
	m.routes["/api/app/v1/trails"] = {"status": 403, "method": HTTPClient.METHOD_PUT, "body": "{\"error\":\"not_entitled\"}"}
	var eq: DotResult = await b.set_equipped("comet")
	_check(not eq.ok and DotTrailBackend.explain(eq).contains("own"), "equipping an unowned trail is refused in words")
	m.routes["/api/app/v1/trails/uploads"] = {"status": 409, "body": "{\"error\":\"pending_moderation\"}"}
	var png := Image.create(8, 4, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	var up: DotResult = await b.submit_upload({"title": "t"}, png, "a.png")
	_check(not up.ok and DotTrailBackend.explain(up).contains("moderation"), "a pending upload is explained")
	var before := m.calls.size()
	var bad: DotResult = await b.submit_upload({}, PackedByteArray([1, 2, 3]), "a.png")
	_check(not bad.ok and m.calls.size() == before, "a bad image never reaches the site")
	m.routes["/api/app/v1/trails"] = {"status": 200, "method": HTTPClient.METHOD_GET, "body": "[1]"}
	_check((await b.catalog()).code() == DotError.CODE_PARSE, "a list that is not {trails} is a parse error")
	m.routes["/api/app/v1/trails"] = {"status": 500, "method": HTTPClient.METHOD_GET, "body": "oops"}
	_check(not (await b.catalog()).ok, "a server error is surfaced")


func _test_config() -> void:
	_section("configurable paths")
	var b := DotTrailBackendHttp.new()
	b.apply_config({"trail_catalog_path": "/x/list", "trail_entitlements_path": "relative", "trail_player_param": "user"})
	_check(b.catalog_path == "/x/list", "a path from trail.yml replaces the default")
	_check(b.entitlements_path == "/api/integration/v1/trails/entitlements", "a path without a leading slash is ignored")
	_check(b.player_param == "user", "the player parameter is settable")


func _section(title: String) -> void:
	_section_count += 1
	print("\n== " + title)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   " + label)
	else:
		_failed += 1
		print("  FAIL " + label)
