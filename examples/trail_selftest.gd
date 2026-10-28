extends Node

## Exercises dot-trail headless: defs, upload validation, registry and index, equip rules, ribbon maths, the emitter and config.
##
## [codeblock]
## godot --headless --path . res://examples/trail_selftest.tscn
## [/codeblock]

const SECTIONS := 7
const CHECKS := 76

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_line("dot-trail self-test")
	_test_def()
	_test_upload()
	_test_registry()
	_test_equip()
	_test_ribbon()
	await _test_emitter()
	_test_config()
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		_line("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.5, 0, 1))
	return img.save_png_to_buffer()


func _webp(w: int, h: int, lossy: bool) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0.5, 1, 1))
	return img.save_webp_to_buffer(lossy, 0.8)


func _def(id: String, access: String = "public", groups: Array = [], price: int = 0) -> DotTrailDef:
	return DotTrailDef.from_dict({"id": id, "image": id + ".png", "access": access, "groups": groups, "price": price}).value


func _registry() -> DotTrailRegistry:
	var r := DotTrailRegistry.new()
	r.add(_def("spark"), _png(16, 16))
	r.add(_def("gold", "groups", ["donator"]), _png(16, 16))
	r.add(_def("paid", "public", [], 50), _png(16, 16))
	return r


func _test_def() -> void:
	_section("def")
	_check(DotTrailDef.from_dict({"id": "ok_1", "image": "a.png"}).ok, "minimal def is valid")
	_code(DotTrailDef.from_dict({"id": "Bad", "image": "a.png"}), "invalid", "uppercase id refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "../a.png"}), "invalid", "path in image refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.gd"}), "invalid", "script extension refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.png", "width": 50}), "invalid", "huge width refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.png", "blend": "burn"}), "invalid", "unknown blend refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.png", "access": "groups"}), "invalid", "groups access needs groups")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.png", "price": -1}), "invalid", "negative price refused")
	_code(DotTrailDef.from_dict({"id": "a", "image": "a.png", "color": "zzz"}), "invalid", "bad colour refused")
	var d := _def("rt", "groups", ["vip"], 5)
	var back := DotTrailDef.from_dict(d.to_dict()).value as DotTrailDef
	_check(back.id == "rt" and back.groups == d.groups and back.price == 5, "to_dict and from_dict round trip")
	_check(d.describe().contains("rt"), "describe names the id")


func _test_upload() -> void:
	_section("upload")
	var lim := {"max_bytes": 4096, "max_dimension": 64}
	var ok := DotTrailUpload.validate(_png(32, 16), "a.png", lim)
	_check(ok.ok and ok.value["width"] == 32 and ok.value["height"] == 16, "png dimensions read from header")
	var wl := DotTrailUpload.validate(_webp(20, 10, false), "a.webp", lim)
	_check(wl.ok and wl.value["width"] == 20 and wl.value["height"] == 10, "lossless webp dimensions")
	var wy := DotTrailUpload.validate(_webp(24, 12, true), "a.webp", lim)
	_check(wy.ok and wy.value["width"] == 24 and wy.value["height"] == 12, "lossy webp dimensions")
	_code(DotTrailUpload.validate(_png(65, 8), "a.png", lim), "invalid", "too wide refused")
	_code(DotTrailUpload.validate(_png(64, 64), "a.png", {"max_bytes": 20, "max_dimension": 64}), "quota", "too many bytes refused")
	_code(DotTrailUpload.validate("extends Node".to_utf8_buffer(), "a.png", lim), "invalid", "script renamed png refused")
	_code(DotTrailUpload.validate(_png(8, 8), "a.gd", lim), "invalid", "gd extension refused")
	_code(DotTrailUpload.validate(_png(8, 8), "a.svg", lim), "invalid", "svg refused")
	_code(DotTrailUpload.validate(_png(8, 8), "../a.png", lim), "invalid", "path in name refused")
	_code(DotTrailUpload.validate(_png(8, 8), "a.webp", lim), "invalid", "png bytes named webp refused")
	var trailing := _png(8, 8)
	trailing.append_array("extends Node".to_utf8_buffer())
	_code(DotTrailUpload.validate(trailing, "a.png", lim), "invalid", "data after IEND refused")
	var cut := _png(8, 8).slice(0, 40)
	_code(DotTrailUpload.validate(cut, "a.png", lim), "invalid", "truncated png refused")
	var wt := _webp(8, 8, false)
	wt.append(0)
	_code(DotTrailUpload.validate(wt, "a.webp", lim), "invalid", "data after webp refused")
	_code(DotTrailUpload.validate(PackedByteArray(), "a.png", lim), "invalid", "empty refused")


func _test_registry() -> void:
	_section("registry")
	var r := _registry()
	_check(r.count() == 3 and r.ids() == PackedStringArray(["gold", "paid", "spark"]), "three trails, sorted ids")
	_code(r.add(_def("spark"), _png(8, 8)), "conflict", "duplicate id refused")
	_code(r.add(_def("big"), _png(600, 8)), "invalid", "oversized image refused on add")
	_check(r.count() == 3, "failed adds change nothing")
	var files := r.pack_files()
	var idx := (files[DotTrailRegistry.INDEX_FILE] as PackedByteArray).get_string_from_utf8()
	var r2 := DotTrailRegistry.new()
	var loaded := r2.load_index(idx, files)
	_check(loaded.ok and r2.count() == 3, "index round trip loads 3")
	_check(r2.get_def("gold").groups == PackedStringArray(["donator"]), "groups survive the index")
	var missing := files.duplicate()
	missing.erase("spark.png")
	var r3 := DotTrailRegistry.new()
	_code(r3.load_index(idx, missing), "invalid", "index naming a missing image refused")
	_check(r3.count() == 0, "a failed index load is all or nothing")
	_code(r3.load_index("not json", files), "parse", "bad json refused")
	var evil := files.duplicate()
	evil["spark.png"] = "extends Node".to_utf8_buffer()
	_code(DotTrailRegistry.new().load_index(idx, evil), "invalid", "pack with a script as image refused")
	var small := DotTrailRegistry.new()
	small.config.max_trails = 1
	small.add(_def("a"), _png(8, 8))
	_code(small.add(_def("b"), _png(8, 8)), "quota", "trail cap enforced")
	_check(r.remove("paid") and r.count() == 2 and not r.remove("paid"), "remove works once")
	_check(r.texture_for("nope") == null, "texture for unknown id is null")
	r.install()
	_check(DotTrailRegistry.current() == r, "installed through DotRegistry")
	DotRegistry.unregister(DotTrailRegistry.SERVICE)
	_check(DotTrailRegistry.current() == null, "unregistered")
	_check(r.describe_lines().size() == 3, "describe_lines lists header and trails")


func _test_equip() -> void:
	_section("equip")
	var r := _registry()
	var clock := [0]
	var e := DotTrailEquip.new(r)
	e.now_ms = func() -> int: return clock[0]
	var seen: Array = []
	e.changed.connect(func(p: Variant, t: String) -> void: seen.append([p, t]))
	_check(e.equip(1, "spark", PackedStringArray()).ok and e.worn(1) == "spark", "public trail equips")
	clock[0] = 5000
	_code(e.equip(1, "gold", PackedStringArray(["guest"])), "forbidden", "group trail refused without group")
	_check(e.worn(1) == "spark", "refusal keeps the old trail")
	_check(e.equip(1, "gold", PackedStringArray(["donator"])).ok, "group trail equips with group")
	clock[0] = 10000
	_code(e.equip(1, "paid", PackedStringArray(["donator"])), "forbidden", "priced trail refused without entitlement")
	_check(e.equip(1, "paid", PackedStringArray(), PackedStringArray(["paid"])).ok, "priced trail equips with entitlement")
	clock[0] = 10100
	_code(e.equip(1, "spark", PackedStringArray()), "rate_limited", "cooldown enforced")
	clock[0] = 20000
	_code(e.equip(1, "ghost", PackedStringArray()), "invalid", "unknown id refused")
	_check(e.equip(1, "", PackedStringArray()).ok and e.worn(1) == "", "empty id unequips")
	_check(e.equip(2, "spark", PackedStringArray()).ok, "another player is not rate limited by the first")
	clock[0] = 30000
	e.equip(3, "gold", PackedStringArray(["donator"]))
	_check(e.revalidate(3, PackedStringArray()) and e.worn(3) == "", "revalidate drops a lost group")
	_check(not e.revalidate(2, PackedStringArray()), "revalidate keeps a still-allowed trail")
	e.forget(2)
	_check(e.worn(2) == "", "forget clears the player")
	_check(seen.size() >= 6, "changed signal fired per change")
	_check(e.describe().begins_with("DotTrailEquip"), "describe")


func _test_ribbon() -> void:
	_section("ribbon")
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var ages := PackedFloat32Array([1.0, 0.5, 0.0])
	var s := DotTrailRibbon.strip(pts, ages, 0.4, 1.0)
	_check(s["vertices"].size() == 6 and s["uvs"].size() == 6, "two vertices per point")
	_check(is_equal_approx(s["vertices"][0].distance_to(s["vertices"][1]), 0.4), "strip is as wide as asked")
	_check(is_equal_approx(s["alphas"][0], 0.0) and is_equal_approx(s["alphas"][4], 1.0), "alpha fades with age")
	_check(is_equal_approx(s["vertices"][0].y, 0.0), "a flat path gives a flat ribbon")
	var up := DotTrailRibbon.strip(PackedVector3Array([Vector3.ZERO, Vector3.UP]), PackedFloat32Array([0, 0]), 1.0, 1.0)
	_check(up["vertices"].size() == 4 and is_finite(up["vertices"][0].x), "a vertical path does not divide by zero")
	_check(DotTrailRibbon.strip(PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([0]), 1.0, 1.0)["vertices"].is_empty(), "one point draws nothing")


func _test_emitter() -> void:
	_section("emitter")
	var player := Node3D.new()
	add_child(player)
	var em := DotTrailEmitter.new()
	player.add_child(em)
	em.set_trail(_def("spark"))
	em.config.min_step = 0.5
	em.config.max_points = 5
	em.sample(Vector3.ZERO, 0.1)
	em.sample(Vector3(0.2, 0, 0), 0.1)
	_check(em.point_count() == 1, "movement under min_step adds no point")
	em.sample(Vector3(1, 0, 0), 0.1)
	_check(em.point_count() == 2, "movement over min_step adds a point")
	for i in 10:
		em.sample(Vector3(2 + i, 0, 0), 0.01)
	_check(em.point_count() == 5, "point count is capped")
	em.sample(Vector3.INF, 5.0)
	_check(em.point_count() == 0, "points expire after the lifetime")
	em.config.enabled = false
	em.sample(Vector3(50, 0, 0), 0.1)
	_check(em.point_count() == 0, "disabled cvar records nothing")
	em.config.enabled = true
	player.global_position = Vector3(0, 0, 0)
	em.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.global_position = Vector3(5, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(em.point_count() >= 2, "physics tick follows the parent through the default DotNodeRef")
	_check(em.describe().contains("spark"), "describe names the trail")
	em.set_trail(null)
	_check(em.point_count() == 0, "clearing the trail empties the ribbon")
	var orphan := DotTrailEmitter.new()
	orphan.target = DotNodeRef.of_path(NodePath("Nope"))
	add_child(orphan)
	orphan.set_trail(_def("spark"))
	orphan.sample(Vector3.ZERO, 0.1)
	_check(orphan.point_count() == 1, "an emitter without a target still accepts samples")
	player.queue_free()
	orphan.queue_free()


func _test_config() -> void:
	_section("config")
	var c := DotTrailConfig.new()
	_check(c.validate().ok, "defaults validate")
	var applied := c.apply_dictionary({"max_points": 10, "min_step": 0.3})
	_check(applied.size() == 2 and c.max_points == 10, "dictionary layer applies")
	c.max_points = 1
	_code(c.validate(), "invalid", "max_points below 2 refused")
	var cli := DotTrailConfig.new()
	_check(cli.cli_prefix() == "--trail-" and cli.env_prefix() == "DOT_TRAIL_", "prefixes")
	_check(cli.limits()["max_dimension"] == 512, "limits feed the upload check")


# --- helpers ---------------------------------------------------------------

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


func _code(res: DotResult, code: String, label: String) -> void:
	_check(not res.ok and res.code() == code, label + " (" + res.code() + ")" if not res.ok else label + " (succeeded)")


func _line(s: String) -> void:
	print(s)
