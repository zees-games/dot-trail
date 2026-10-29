extends Node

## The trails screen, its stub store, the upload form with random good and bad images, and the envelope transport, all headless. Needs dot-menu linked into addons/ for the kit (it falls back to plain controls without).

const SECTIONS := 6
const CHECKS := 61

var _passed := 0
var _failed := 0
var _section_count := 0
var _rng := RandomNumberGenerator.new()
var _host: Control = null


class FakeEnvelope:
	extends RefCounted
	var handlers: Dictionary = {}

	func register(kind: StringName, handler: Callable = Callable(), _required: bool = false) -> void:
		handlers[kind] = handler


class FakeServer:
	extends RefCounted
	var envelope := FakeEnvelope.new()
	var sent: Array = []

	func send_kind(peer: int, kind: StringName, payload: Dictionary, lane: int) -> bool:
		sent.append({"peer": peer, "kind": kind, "payload": payload, "lane": lane})
		return true


class FakeLink:
	extends RefCounted
	var envelope := FakeEnvelope.new()
	var sent: Array = []

	func send_kind(kind: StringName, payload: Dictionary, lane: int) -> bool:
		sent.append({"kind": kind, "payload": payload, "lane": lane})
		return true


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_rng.seed = 20261029
	_host = Control.new()
	add_child(_host)
	_run.call_deferred()


func _run() -> void:
	_line("dot-trail ui self-test")
	_test_envelope()
	await _test_store()
	await _test_screen()
	_test_upload_good()
	_test_upload_bad()
	await _test_submit()
	_host.free()
	await get_tree().process_frame
	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		_line("ERROR: %d sections, %d checks ran; expected %d and %d." % [_section_count, _passed + _failed, SECTIONS, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


## Random noise, so the encoder cannot shrink it to nothing.
func _noise(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf_range(0.3, 1.0)))
	return img


func _registry() -> DotTrailRegistry:
	var r := DotTrailRegistry.new()
	r.config.equip_cooldown = 0.0
	var defs := [
		{"id": "spark", "title": "Spark", "price": 0, "color": "#ffd060", "blend": "add"},
		{"id": "comet", "title": "Comet", "price": 300, "color": "#60c0ff"},
		{"id": "royal", "title": "Royal", "price": 5000, "color": "#c060ff"},
		{"id": "vip", "title": "Velvet", "access": "groups", "groups": ["vip"], "color": "#ff6080"},
	]
	for d: Dictionary in defs:
		d["image"] = d["id"] + ".png"
		var def: DotTrailDef = DotTrailDef.from_dict(d).value
		var _a := r.add(def, _noise(16, 4).save_png_to_buffer())
	return r


func _test_envelope() -> void:
	_section("envelope transport")
	var reg := _registry()
	var relay := DotTrailRelay.create(DotTrailEquip.new(reg))
	var server := FakeServer.new()
	_check(DotTrailEnvelope.serve(server, relay).ok, "serve registers on a server")
	_check(server.envelope.handlers.has(DotTrailEnvelope.KIND), "the server handles dot.trail")
	relay.add_peer(1)
	relay.add_peer(2)
	server.envelope.handlers[DotTrailEnvelope.KIND].call(1, {"id": "spark"})
	_check(server.sent.size() == 2, "a free trail is told to both peers (%d sends)" % server.sent.size())
	_check(server.sent.all(func(s: Dictionary) -> bool: return s["payload"] == {"actor": 1, "id": "spark"} and s["lane"] == 2), "each send is {actor 1, spark} on the event lane")
	server.sent.clear()
	server.envelope.handlers[DotTrailEnvelope.KIND].call(2, {"id": "comet"})
	_check(server.sent.size() == 1 and server.sent[0]["peer"] == 2 and server.sent[0]["payload"]["id"] == "", "an unbought trail is refused to the sender only")
	server.sent.clear()
	server.envelope.handlers[DotTrailEnvelope.KIND].call(2, {"id": 7})
	server.envelope.handlers[DotTrailEnvelope.KIND].call(2, {"id": "../../etc"})
	_check(server.sent.is_empty(), "a malformed id is dropped without an answer")
	relay.add_peer(3)
	_check(server.sent.size() == 1 and server.sent[0]["peer"] == 3 and server.sent[0]["payload"]["id"] == "spark", "a joiner hears who wears what")

	var link := FakeLink.new()
	var client := DotTrailClient.new()
	client.registry = reg
	_check(DotTrailEnvelope.attach(link, client).ok, "attach registers on a link")
	_check(client.request("spark").ok and link.sent.size() == 1 and link.sent[0]["payload"] == {"id": "spark"}, "request goes up as dot.trail {id}")
	link.envelope.handlers[DotTrailEnvelope.KIND].call(1, {"actor": 4.0, "id": "comet"})
	_check(client.worn.get(4, "") == "comet", "a JSON number actor is read as a peer id")
	link.envelope.handlers[DotTrailEnvelope.KIND].call(1, {"actor": 4, "id": ""})
	_check(not client.worn.has(4), "an empty id takes the trail off")
	_check(not DotTrailEnvelope.serve(RefCounted.new(), relay).ok, "serve refuses an object without an envelope")
	var figure := Node3D.new()
	_host.add_child(figure)
	client.receive(6, "spark")
	client.node_for = func(actor: int) -> Node: return figure if actor == 6 else null
	_check(client.apply_missing() == 1 and figure.has_meta(DotTrailClient.EMITTER_META), "a figure that spawns late gets its ribbon")
	_check(client.apply_missing() == 0, "and only once")
	figure.free()

	var ents := {}
	var relay2 := DotTrailRelay.create(DotTrailEquip.new(reg), Callable(), func(p: int) -> PackedStringArray: return PackedStringArray(ents.get(p, [])))
	var s2 := FakeServer.new()
	var refreshed: Array = []
	var _s := DotTrailEnvelope.serve(s2, relay2, func(p: int, id: String) -> void:
		refreshed.append(id)
		ents[p] = [id])
	relay2.add_peer(1)
	s2.envelope.handlers[DotTrailEnvelope.KIND].call(1, {"id": "comet"})
	_check(refreshed == ["comet"] and s2.sent.size() == 1 and s2.sent[0]["payload"]["id"] == "comet", "a trail bought a moment ago is fetched, then worn")
	s2.envelope.handlers[DotTrailEnvelope.KIND].call(1, {"id": "spark"})
	_check(refreshed.size() == 1, "a trail already allowed asks the store nothing")


func _test_store() -> void:
	_section("stub store")
	var reg := _registry()
	var b := DotTrailBackendStub.from_registry(reg, 1000)
	var cat: DotResult = await b.catalog()
	var rows: Dictionary = {}
	for r: Dictionary in cat.value["trails"]:
		rows[r["id"]] = r
	_check(cat.ok and rows.size() == 4 and int(cat.value["points"]) == 1000, "catalog lists four trails and the balance")
	_check(rows["spark"]["free"] and rows["spark"]["owned"], "a free public trail is owned")
	_check(not rows["vip"]["owned"], "a free members-only trail is not owned")
	var bought: DotResult = await b.purchase("comet")
	_check(bought.ok and int(bought.value["points"]) == 700, "buying comet costs 300")
	var again: DotResult = await b.purchase("comet")
	_check(again.code() == DotError.CODE_CONFLICT and DotTrailBackend.explain(again).contains("already"), "buying twice is refused as already owned")
	var poor: DotResult = await b.purchase("royal")
	_check(poor.code() == DotError.CODE_FORBIDDEN and DotTrailBackend.explain(poor).contains("points"), "too few points is explained")
	var nope: DotResult = await b.purchase("nope")
	_check(not nope.ok, "an unknown sku is refused")
	b.save_path = "user://trail_stub_selftest.json"
	b.save_state()
	var c := DotTrailBackendStub.from_registry(reg, 1000)
	c.save_path = b.save_path
	c.load_state()
	_check(c.points == 700 and c.owned.has("comet"), "the store survives a reload")
	DirAccess.remove_absolute(b.save_path)


func _test_screen() -> void:
	_section("screen")
	var reg := _registry()
	var b := DotTrailBackendStub.from_registry(reg, 1000)
	var asked: Array = []
	var worn := [""]
	var screen := DotTrailScreen.make(_host, reg, b)
	screen.request_fn = func(id: String) -> DotResult:
		asked.append(id)
		return DotResult.success(id)
	screen.worn_fn = func() -> String: return worn[0]
	_check(screen.cards.size() == 4, "one card per trail before the store answers")
	var res: DotResult = await screen.refresh()
	_check(res.ok and screen.points == 1000, "refresh reads the balance")
	_check(screen._points_label.text == "Points: 1000", "the header shows the balance")
	_check(screen.cards["spark"]["action"].text == "Equip", "a free trail offers Equip")
	_check(screen.cards["comet"]["action"].text.begins_with("Buy") and not screen.cards["comet"]["action"].disabled, "an affordable trail offers Buy")
	_check(screen.cards["royal"]["action"].disabled, "an unaffordable Buy is disabled")
	_check(screen.cards["vip"]["action"].text == "Locked", "a members-only trail is locked")
	_check(screen.cards["vip"]["preview"].dim and not screen.cards["spark"]["preview"].dim, "locked previews are dimmed")
	screen.cards["spark"]["action"].pressed.emit()
	_check(asked == ["spark"], "Equip asks the server")
	var bought: DotResult = await screen.buy("comet")
	_check(bought.ok and screen.points == 700 and screen.owned.has("comet"), "Buy spends points and owns the trail")
	_check(asked.back() == "comet", "a purchase equips the trail")
	_check(screen.cards["comet"]["action"].text == "Equip", "the bought card now offers Equip")
	worn[0] = "comet"
	screen.server_changed()
	_check(screen.cards["comet"]["status"].text == "Equipped" and screen.cards["comet"]["off"] != null, "the worn card says Equipped with Take off")
	screen.cards["comet"]["off"].pressed.emit()
	_check(asked.back() == "", "Take off asks for no trail")
	var poor: DotResult = await screen.buy("royal")
	_check(not poor.ok and screen.status_text().contains("points"), "a refused buy is explained on the screen")
	screen.groups = PackedStringArray(["vip"])
	screen.server_changed()
	_check(screen.cards["vip"]["action"].text == "Equip", "a member may equip the members-only trail")
	screen.free()


func _panel() -> DotTrailUploadPanel:
	var p := DotTrailUploadPanel.make(_host, null, DotTrailKit.new())
	return p


func _test_upload_good() -> void:
	_section("upload: good images")
	var p := _panel()
	var png := _noise(128, 32).save_png_to_buffer()
	var res := p.take("my_comet.png", png)
	_check(res.ok and p.valid, "a random 128x32 png passes")
	_check(p.info.text.contains("128×32") and p.info.text.contains("PNG"), "its size and type are shown")
	_check(p.title_edit.text == "My Comet", "the name is suggested from the file")
	_check(not p.error_label.visible, "no error is shown")
	_check(p.submit_button.disabled, "submit waits for the author and source")
	p.author_edit.text = "Tester"
	p.url_edit.text = "https://example.com/comet"
	p._update_submit()
	_check(not p.submit_button.disabled, "submit opens once the rights are filled in")
	var webp := _noise(64, 64).save_webp_to_buffer(true)
	_check(p.take("swirl.webp", webp).ok, "a random webp passes")
	p.free()


func _test_upload_bad() -> void:
	_section("upload: bad images")
	var p := _panel()
	var script := FileAccess.get_file_as_bytes("res://examples/ui_selftest.gd")
	var r1 := p.take("evil.png", script)
	_check(not r1.ok and p.error_label.visible and p.error_text().contains("cannot be used"), "a script renamed .png is refused: " + p.error_text())
	_check(p.submit_button.disabled and p.preview.dim, "a refused file cannot be submitted and the preview is dimmed")
	var r2 := p.take("photo.jpg", _noise(8, 8).save_jpg_to_buffer())
	_check(not r2.ok, "a jpg is refused")
	var big := _noise(400, 400).save_png_to_buffer()
	var r3 := p.take("huge.png", big)
	_check(r3.code() == DotError.CODE_QUOTA and p.error_text().contains("too large"), "a %d KB png is refused as too large" % (big.size() / 1024))
	var wide := Image.create(600, 4, false, Image.FORMAT_RGBA8)
	var r4 := p.take("wide.png", wide.save_png_to_buffer())
	_check(not r4.ok and p.error_text().contains("600"), "a 600 px wide png is refused for its size")
	var tail := _noise(32, 8).save_png_to_buffer()
	tail.append_array("<?php echo 1; ?>".to_utf8_buffer())
	var r5 := p.take("tail.png", tail)
	_check(not r5.ok, "bytes after IEND are refused: " + p.error_text())
	var r6 := p.take("../x.png", _noise(8, 8).save_png_to_buffer())
	_check(not r6.ok, "a path is refused as a name")
	_check(p.take("ok.png", _noise(8, 8).save_png_to_buffer()).ok and not p.error_label.visible, "a good file after bad ones clears the error")
	p.free()


func _test_submit() -> void:
	_section("upload: submit for review")
	var b := DotTrailBackendStub.from_registry(_registry())
	var p := DotTrailUploadPanel.make(_host, b, DotTrailKit.new())
	var got: Array = []
	p.submitted.connect(func(id: String) -> void: got.append(id))
	var none: DotResult = await p.submit()
	_check(not none.ok, "nothing to submit before an image")
	var _t := p.take("aurora.png", _noise(96, 24).save_png_to_buffer())
	p.url_edit.text = "ftp://nope"
	p.author_edit.text = "Tester"
	var bad_url: DotResult = await p.submit()
	_check(not bad_url.ok and p.error_text().contains("http"), "a non-http source is refused")
	p.url_edit.text = "https://example.com/aurora"
	var sent: DotResult = await p.submit()
	_check(sent.ok and got == ["upload_1"], "the image goes to review as upload_1")
	_check(b.uploads.size() == 1 and b.uploads[0]["status"] == "pending", "the store queues it as pending")
	_check(p.info.text.contains("moderator") and p.submit_button.disabled, "the form says it waits for a moderator")
	_check(p.submit_button.text == "Submit for review", "the button label is restored")
	p.free()


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
