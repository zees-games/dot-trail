class_name DotTrailScreen
extends VBoxContainer

## The trails screen: every trail of the server's pack as a card with a live ribbon, its price, Buy or Equip, and a form to send your own for review. Prices and purchases go through a [DotTrailBackend]; equipping asks the server through [member request_fn].

const CHANNEL := "trail"
const COLUMNS := 3

signal purchased(id: String)
signal equip_requested(id: String)
signal submitted(id: String)

var registry: DotTrailRegistry = null
var backend: DotTrailBackend = null
## func(id: String) -> DotResult: asks the server (DotTrailClient.request).
var request_fn: Callable = Callable()
## func() -> String: the trail the server says this player wears.
var worn_fn: Callable = Callable()
## The player's groups, for members-only trails.
var groups := PackedStringArray()
var k: DotTrailKit = null

## id -> {card, preview, status, action, off}
var cards: Dictionary = {}
var points: int = -1
var owned: Dictionary = {}
var catalog_rows: Dictionary = {}
var upload: DotTrailUploadPanel = null
var _points_label: Label = null
var _status: Label = null
var _grid: GridContainer = null
var _textures: Dictionary = {}
var _busy := false


## Builds the screen into [param parent] (a DotMenuPage body, or any container). [param kit] is dot-menu's kit or null.
static func make(parent: Control, p_registry: DotTrailRegistry, p_backend: DotTrailBackend, kit: Object = null, heading: bool = true) -> DotTrailScreen:
	var s := DotTrailScreen.new()
	s.name = "Trails"
	s.registry = p_registry
	s.backend = p_backend
	s.k = DotTrailKit.new(kit)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_theme_constant_override(&"separation", 14)
	parent.add_child(s)
	s._build(heading)
	return s


## Sets the trail set and the store after [method make] (a menu page builds first).
func bind(p_registry: DotTrailRegistry, p_backend: DotTrailBackend) -> void:
	registry = p_registry
	backend = p_backend
	if upload != null:
		upload.backend = p_backend
	_rebuild_cards()


func _build(heading: bool) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 12)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading:
		titles.add_child(k.heading("Trails"))
		titles.add_child(k.label("A ribbon that follows you. Buy one with points, or send your own.", true, "muted"))
	top.add_child(titles)
	_points_label = k.label("Points: …", false, "accent")
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_points_label)
	add_child(top)
	_status = k.label("", true, "muted")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	add_child(k.section("Your trails"))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override(&"h_separation", 12)
	_grid.add_theme_constant_override(&"v_separation", 12)
	add_child(_grid)
	add_child(k.section("Make your own"))
	upload = DotTrailUploadPanel.make(self, backend, k)
	upload.submitted.connect(func(id: String) -> void: submitted.emit(id))
	_rebuild_cards()


## Reads prices, points and what is owned from the backend, then redraws. Awaitable.
func refresh() -> DotResult:
	if backend == null:
		_rebuild_cards()
		return DotResult.fail(DotError.CODE_STATE, "no trail store")
	_say("Loading the store…")
	var res: DotResult = await backend.catalog()
	if not is_instance_valid(self):
		return res
	if not res.ok:
		_say("The store is unavailable: %s" % DotTrailBackend.explain(res), true)
		_rebuild_cards()
		return res
	catalog_rows.clear()
	for row: Dictionary in res.value["trails"]:
		catalog_rows[str(row["id"])] = row
		if bool(row.get("owned", false)):
			owned[str(row["id"])] = true
	points = int(res.value.get("points", -1))
	_say("")
	_rebuild_cards()
	return res


## Spends points on [param id]; on success the trail is owned and equipped.
func buy(id: String) -> DotResult:
	if _busy:
		return DotResult.fail(DotError.CODE_STATE, "busy")
	_busy = true
	_say("Buying %s…" % _title(id))
	var res: DotResult = await backend.purchase(id)
	_busy = false
	if not is_instance_valid(self):
		return res
	if not res.ok:
		_say(DotTrailBackend.explain(res), true)
		return res
	for owned_id: Variant in res.value.get("ids", []):
		owned[str(owned_id)] = true
	owned[id] = true
	if int(res.value.get("points", -1)) >= 0:
		points = int(res.value["points"])
	_say("You bought %s." % _title(id))
	purchased.emit(id)
	_rebuild_cards()
	var _eq := equip(id)
	return res


## Asks the server to wear [param id] ("" takes it off). The card updates when the server answers ([method server_changed]).
func equip(id: String) -> DotResult:
	equip_requested.emit(id)
	if not request_fn.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "not connected")
	var res: DotResult = request_fn.call(id)
	_say("Asking the server…" if res.ok else "Not connected to a server.", not res.ok)
	return res


## The server's word on what this player wears; call from DotTrailClient.changed.
func server_changed() -> void:
	_say("")
	_rebuild_cards()


## Whether this player may wear [param id] now: free, owned, or in its group.
func can_wear(id: String) -> bool:
	return registry != null and registry.may_equip(id, groups, PackedStringArray(owned.keys())).ok


func price_of(id: String) -> int:
	if catalog_rows.has(id):
		return int(catalog_rows[id].get("price_points", 0))
	var def := registry.get_def(id) if registry != null else null
	return def.price if def != null else 0


func status_text() -> String:
	return _status.text if _status != null else ""


func _worn() -> String:
	return str(worn_fn.call()) if worn_fn.is_valid() else ""


func _title(id: String) -> String:
	var def := registry.get_def(id) if registry != null else null
	return def.title if def != null and not def.title.is_empty() else id


func _say(text: String, bad: bool = false) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override(&"font_color", k.colour("danger" if bad else "muted", Color.TOMATO if bad else Color.GRAY))


func _rebuild_cards() -> void:
	if _points_label != null:
		_points_label.text = "Points: %d" % points if points >= 0 else "Points: —"
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	cards.clear()
	var ids := registry.ids() if registry != null else PackedStringArray()
	if ids.is_empty():
		_grid.add_child(k.label("This server has no trails yet.", true, "muted"))
		return
	for id in ids:
		_grid.add_child(_card(id))


func _card(id: String) -> Control:
	var def := registry.get_def(id)
	var card := k.card()
	card.custom_minimum_size = Vector2(230, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	card.add_child(col)
	var preview := DotTrailPreview.new()
	preview.custom_minimum_size = Vector2(200, 110)
	preview.t = float(cards.size()) * 0.9
	if not _textures.has(id):
		_textures[id] = registry.texture_for(id) if DisplayServer.get_name() != "headless" else null
	preview.show_trail(def, _textures[id])
	col.add_child(preview)
	col.add_child(k.label(_title(id)))
	var status := k.label("", true, "muted")
	col.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	col.add_child(row)
	var entry := {"card": card, "preview": preview, "status": status, "action": null, "off": null}
	_fill_actions(id, def, row, entry)
	preview.dim = not can_wear(id)
	cards[id] = entry
	return card


func _fill_actions(id: String, def: DotTrailDef, row: HBoxContainer, entry: Dictionary) -> void:
	var worn := _worn() == id
	var price := price_of(id)
	var action: Button
	if worn:
		entry["status"].text = "Equipped"
		action = k.secondary(" Equipped ")
		action.disabled = true
		var off := k.secondary("Take off")
		off.pressed.connect(func() -> void: var _r := equip(""))
		entry["off"] = off
		row.add_child(action)
		row.add_child(off)
	elif can_wear(id):
		entry["status"].text = "Owned" if price > 0 else "Free"
		action = k.primary("Equip")
		action.pressed.connect(func() -> void: var _r := equip(id))
		row.add_child(action)
	elif def.access == DotTrailDef.ACCESS_GROUPS and price <= 0:
		entry["status"].text = "Members only: " + ", ".join(def.groups)
		action = k.secondary("Locked")
		action.disabled = true
		row.add_child(action)
	else:
		entry["status"].text = "%d points" % price
		action = k.primary("Buy · %d" % price)
		action.disabled = points >= 0 and price > points
		action.tooltip_text = "Not enough points" if action.disabled else ""
		action.pressed.connect(func() -> void: await buy(id))
		row.add_child(action)
	entry["action"] = action
