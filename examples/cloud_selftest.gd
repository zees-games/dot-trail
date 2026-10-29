extends Node

## The trail pack flow end to end with the real addons: a store is built into one signed dot-cloud pack, a dot-server console advertises it as `sv_trail_pack`, and a started DotCloudClient fetches, verifies and mounts it before join (through DotGamePrejoin.extra_steps). No network: the CDN is a local directory, read through dot-cloud's local source.

const SECTIONS := 4
const CHECKS := 17
const CONSOLE_SCRIPT := "res://addons/dot_server/console/dot_console_registry.gd"
const PACK_ID := "trails-e2e"
const VERSION := "1.0.0"

var _passed := 0
var _failed := 0
var _section_count := 0
var _work := ""
var _cdn := ""
var _keys := {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_line("dot-trail cloud self-test")
	_work = OS.get_temp_dir().path_join("dot_trail_cloud_%d" % Time.get_ticks_usec())
	_cdn = _work.path_join("cdn")
	_test_build()
	var rules := _test_advertise()
	await _test_fetch(rules)
	await _test_refusals(rules)
	DotPaths.remove_tree(_work)
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		_line("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _png(w: int, h: int, color: Color) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


func _test_build() -> void:
	_section("build and sign")
	var store := DotTrailStore.new(null, _work.path_join("store"))
	var base := {"licence": "CC0-1.0", "author": "Test", "url": "https://example.com/t"}
	var spark := base.merged({"id": "spark", "title": "Spark"})
	var gold := base.merged({"id": "gold", "title": "Gold", "access": "groups", "groups": ["donator"]})
	_check(store.submit(spark, _png(16, 16, Color.ORANGE)).ok and store.submit(gold, _png(32, 16, Color.GOLD)).ok, "two uploads land in the store")
	_keys = DotCloudSignature.generate_keypair(2048).value
	var out := _cdn.path_join(PACK_ID).path_join(VERSION)
	var built := DotTrailPack.build(store, PACK_ID, out, {"version": VERSION, "signing_key_pem": str(_keys.get("private", ""))})
	_check(built.ok and FileAccess.file_exists(out.path_join("manifest.json")), "the store publishes as one pack at <cdn>/<id>/<version>/")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("manifest.json"))) if built.ok else {}
	_check(not str(manifest.get("signature", "")).is_empty(), "the manifest is signed")


func _test_advertise() -> Dictionary:
	_section("advertise")
	var config := DotTrailConfig.new()
	config.pack = DotTrailClient.pack_rule(PACK_ID, VERSION)
	_check(DotTrailClient.NOTIFY_FLAG == DotConVar.FLAG_NOTIFY, "the copied notify flag is dot-server's")
	var console: Node = (load(CONSOLE_SCRIPT) as GDScript).new()
	var made := DotTrailClient.advertise(console, config)
	var cv := made.value as DotConVar if made.ok else null
	_check(cv != null and cv.name == DotTrailClient.PACK_CVAR and cv.has_flag(DotConVar.FLAG_NOTIFY), "the server registers sv_trail_pack as a notify cvar")
	# What dot-server-query publishes: every notify (or replicated) cvar that is not protected or hidden.
	var rules := {}
	for name in console.call(&"cvar_names"):
		var c: DotConVar = console.call(&"find_cvar", name)
		if c.has_flag(DotConVar.FLAG_NOTIFY) and not c.has_flag(DotConVar.FLAG_PROTECTED | DotConVar.FLAG_HIDDEN):
			rules[c.name] = c.get_string()
	_check(DotTrailClient.pack_from_rules(rules) == PackedStringArray([PACK_ID, VERSION]), "the query rules carry the pack to a client")
	config.pack = ""
	var none := DotTrailClient.advertise(console, config)
	_check(none.ok and none.value == null, "an empty pack advertises nothing")
	config.pack = "../x@1"
	_check(not DotTrailClient.advertise(console, config).ok, "a malformed pack is refused before it reaches the console")
	console.free()
	return rules


func _cloud(tag: String) -> DotCloudClient:
	var config := DotCloudConfig.new()
	config.cache_dir = _work.path_join("cache_" + tag)
	config.require_signed_manifests = true
	config.trusted_keys = {"default": str(_keys.get("public", ""))}
	config.verify_before_mount = true
	var client := DotCloudClient.new()
	client.name = "Cloud_" + tag
	client.config = config
	client.config_file = ""
	client.register_service = false
	client.allow_netchan_fallback = false
	client.local_search_dirs = PackedStringArray([_cdn, _cdn.path_join(PACK_ID).path_join(VERSION)])
	add_child(client)
	return client


func _test_fetch(rules: Dictionary) -> void:
	_section("fetch before join")
	var cloud := _cloud("join")
	var started := await cloud.start()
	_check(started.ok, "a DotCloudClient starts with the local CDN and a trusted key")
	var registry := DotTrailRegistry.new()
	var tc := DotTrailClient.new()
	tc.registry = registry
	var pre := DotGamePrejoin.new()
	pre.rules_fn = func(_address: String) -> Dictionary: return rules
	var results := []
	pre.extra_steps.append(func(r: Dictionary) -> DotResult:
		var got: DotResult = await tc.fetch_pack(cloud, r)
		results.append(got)
		return got)
	var joined: DotResult = await pre.prepare(self, "127.0.0.1:27015")
	_check(joined.ok and results.size() == 1, "the prejoin step runs the trail fetch and the join goes ahead")
	var got: DotResult = results[0] if results.size() == 1 else DotResult.fail(DotError.CODE_STATE, "no fetch")
	_check(got.ok and registry.count() == 2, "the verified, mounted pack fills the registry")
	_check(registry.get_def("gold") != null and registry.get_def("gold").groups == PackedStringArray(["donator"]), "access settings survive delivery")
	var tex := registry.texture_for("gold")
	_check(tex != null and tex.get_width() == 32 and tex.get_height() == 16, "an image arrives intact and loads from bytes")
	_check(cloud.is_mounted(StringName(PACK_ID), VERSION), "dot-cloud reports the pack mounted")
	remove_child(cloud)
	cloud.queue_free()


func _test_refusals(rules: Dictionary) -> void:
	_section("refusals")
	var cloud := _cloud("bad")
	var _s := await cloud.start()
	var registry := DotTrailRegistry.new()
	var tc := DotTrailClient.new()
	tc.registry = registry
	var missing: DotResult = await tc.fetch_pack(cloud, {DotTrailClient.PACK_CVAR: DotTrailClient.pack_rule(PACK_ID, "9.9.9")})
	_check(not missing.ok and registry.count() == 0, "a version the CDN does not hold fails and loads nothing")
	var none: DotResult = await tc.fetch_pack(cloud, {})
	_check(none.ok and none.value == 0, "a server with no pack is a successful no-op")
	remove_child(cloud)
	cloud.queue_free()
	# Same key id, different key: the signature does not verify.
	var stranger := _cloud("stranger")
	var other: Dictionary = DotCloudSignature.generate_keypair(2048).value
	stranger.config.trusted_keys = {"default": str(other.get("public", ""))}
	var _t := await stranger.start()
	var untrusted: DotResult = await tc.fetch_pack(stranger, rules)
	_check(not untrusted.ok and registry.count() == 0, "a pack signed by an untrusted key is refused")
	remove_child(stranger)
	stranger.queue_free()


func _section(name: String) -> void:
	_section_count += 1
	_line("")
	_line("== " + name)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		_line("  ok   " + label)
	else:
		_failed += 1
		_line("  FAIL " + label)


func _line(s: String) -> void:
	print(s)
