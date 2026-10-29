extends Control

## Renders the trail store UI to a PNG: `res://examples/ui_shot.tscn -- --shot out.png --view menu|upload|error` (tools/screenshot_ui.sh).
## `menu` is the Trails page inside a real DotMenu with a stub store; `upload` has a random image picked; `error` one with bytes after its end.

var _shot := ""
var _view := "menu"
var _frames := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
		elif args[i] == "--view" and i + 1 < args.size():
			_view = args[i + 1]
	_rng.seed = 20261029
	DotMenuKit.fill_parent(self)
	var reg := _registry()
	var stub := DotTrailBackendStub.from_registry(reg, 1250)
	stub.owned["comet"] = true
	if _view == "menu":
		_in_menu(reg, stub)
	else:
		_upload(reg, stub)


func _in_menu(reg: DotTrailRegistry, stub: DotTrailBackendStub) -> void:
	var menu := DotMenu.new()
	menu.manage_pointer = false
	add_child(menu)
	var _set := menu.setup()
	DotTrailMenu.add_to(menu, func(screen: DotTrailScreen) -> void:
		screen.bind(reg, stub)
		screen.worn_fn = func() -> String: return "comet"
		screen.request_fn = func(_id: String) -> DotResult: return DotResult.success(null)
		screen.refresh())
	menu.open(DotTrailMenu.PAGE_ID)


func _upload(reg: DotTrailRegistry, stub: DotTrailBackendStub) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	DotMenuKit.fill_parent(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	DotMenuKit.fill_parent(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var screen := DotTrailScreen.make(margin, reg, stub)
	for child in screen.get_children():
		child.visible = child == screen.upload or child is Label and child.text == "Make your own"
	var png := _streak(256, 64).save_png_to_buffer()
	if _view == "error":
		png.append_array(PackedByteArray([0x3c, 0x3f, 0x70, 0x68, 0x70]))
	screen.upload.title_edit.text = "Northern streak"
	screen.upload.author_edit.text = "Test uploader"
	var _took := screen.upload.take("my_streak.png", png)


func _process(_delta: float) -> void:
	_frames += 1
	if _shot.is_empty() or _frames < 90:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	get_tree().quit()


func _registry() -> DotTrailRegistry:
	var r := DotTrailRegistry.new()
	var defs := [
		{"id": "spark", "title": "Spark", "price": 0, "color": "#ffd060", "blend": "add"},
		{"id": "comet", "title": "Comet", "price": 300, "color": "#60c0ff", "blend": "add"},
		{"id": "royal", "title": "Royal", "price": 5000, "color": "#c060ff"},
		{"id": "ember", "title": "Ember", "price": 800, "color": "#ff7a30", "blend": "add"},
		{"id": "mint", "title": "Mint", "price": 150, "color": "#60ffb0"},
		{"id": "vip", "title": "Velvet", "access": "groups", "groups": ["vip"], "color": "#ff6080"},
	]
	for d: Dictionary in defs:
		d["image"] = d["id"] + ".png"
		var def: DotTrailDef = DotTrailDef.from_dict(d).value
		var _a := r.add(def, _streak(128, 32).save_png_to_buffer())
	return r


## A soft streak with random speckle, so each test image differs.
func _streak(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		for y in h:
			var u := float(x) / (w - 1)
			var v := absf(float(y) / (h - 1) - 0.5) * 2.0
			var a := pow(1.0 - v, 1.5) * (0.3 + 0.7 * u) * _rng.randf_range(0.7, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return img
