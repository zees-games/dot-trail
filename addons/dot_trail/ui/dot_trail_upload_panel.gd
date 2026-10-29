class_name DotTrailUploadPanel
extends PanelContainer

## Send your own trail: pick an image, see it checked by [DotTrailUpload.validate] and drawn as a ribbon, fill in the rights, submit it for review.

signal submitted(id: String)

var backend: DotTrailBackend = null
var limits: Dictionary = DotTrailConfig.new().limits()
var picker: DotTrailFilePick = null
var file_name := ""
var bytes := PackedByteArray()
var valid := false

var preview: DotTrailPreview = null
var info: Label = null
var error_label: Label = null
## What the form still needs before Submit turns on.
var hint_label: Label = null
var title_edit: LineEdit = null
var licence: OptionButton = null
var author_edit: LineEdit = null
var url_edit: LineEdit = null
var submit_button: Button = null
var choose_button: Button = null
var k: DotTrailKit = null


static func make(parent: Control, p_backend: DotTrailBackend, kit: DotTrailKit) -> DotTrailUploadPanel:
	var p := DotTrailUploadPanel.new()
	p.name = "Upload"
	p.backend = p_backend
	p.k = kit
	var style: Variant = kit.card().get_theme_stylebox(&"panel")
	if style is StyleBox:
		p.add_theme_stylebox_override(&"panel", style)
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	picker = DotTrailFilePick.new()
	picker.name = "Picker"
	picker.picked.connect(take)
	picker.failed.connect(func(message: String) -> void: _error(message))
	add_child(picker)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	row.add_child(left)
	preview = DotTrailPreview.new()
	preview.custom_minimum_size = Vector2(240, 130)
	preview.dim = true
	left.add_child(preview)
	choose_button = k.secondary("Choose image…")
	choose_button.pressed.connect(picker.open)
	left.add_child(choose_button)
	info = k.label("PNG or WebP, up to %d KB and %d px." % [int(limits["max_bytes"]) / 1024, int(limits["max_dimension"])], true, "muted")
	left.add_child(info)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override(&"separation", 8)
	row.add_child(form)
	title_edit = _field(form, "Name", "Comet tail")
	licence = OptionButton.new()
	for l: String in DotTrailStore.LICENCES:
		licence.add_item(l)
	form.add_child(k.label("Licence", true, "muted"))
	form.add_child(licence)
	author_edit = _field(form, "Author", "Who made the image")
	url_edit = _field(form, "Source", "https://…")
	error_label = k.label("", true, "danger")
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(error_label)
	submit_button = k.primary("Submit for review")
	submit_button.disabled = true
	submit_button.pressed.connect(func() -> void: await submit())
	form.add_child(submit_button)
	hint_label = k.label("Choose an image to start.", true, "muted")
	form.add_child(hint_label)


func _field(form: Control, label: String, hint: String) -> LineEdit:
	form.add_child(k.label(label, true, "muted"))
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.text_changed.connect(func(_t: String) -> void: _update_submit())
	form.add_child(e)
	return e


## A picked file: checked, then previewed. Returns the check.
func take(p_name: String, p_bytes: PackedByteArray) -> DotResult:
	file_name = p_name
	bytes = p_bytes
	var checked := DotTrailUpload.validate(p_bytes, p_name, limits)
	valid = checked.ok
	if not checked.ok:
		_error(_explain(checked))
		preview.texture = null
		preview.dim = true
		info.text = p_name
		_update_submit()
		return checked
	_error("")
	var v: Dictionary = checked.value
	info.text = "%s · %s · %d×%d · %d KB" % [p_name, str(v["type"]).to_upper(), int(v["width"]), int(v["height"]), maxi(1, int(v["bytes"]) / 1024)]
	preview.dim = false
	preview.texture = _texture(p_bytes, str(v["type"]))
	preview.color = Color.WHITE
	if title_edit.text.strip_edges().is_empty():
		title_edit.text = p_name.get_basename().replace("_", " ").capitalize()
	_update_submit()
	return checked


## Sends the image and the rights for review. Awaitable.
func submit() -> DotResult:
	if not valid:
		return DotResult.fail(DotError.CODE_INVALID, "no valid image")
	var missing := _missing()
	if not missing.is_empty():
		_error(missing)
		return DotResult.fail(DotError.CODE_INVALID, missing)
	if backend == null:
		_error("The trail store is not available.")
		return DotResult.fail(DotError.CODE_STATE, "no trail store")
	submit_button.disabled = true
	submit_button.text = "Sending…"
	var meta := {"title": title_edit.text.strip_edges(), "licence": licence.get_item_text(licence.selected),
		"author": author_edit.text.strip_edges(), "url": url_edit.text.strip_edges()}
	var res: DotResult = await backend.submit_upload(meta, bytes, file_name)
	if not is_instance_valid(self):
		return res
	submit_button.text = "Submit for review"
	if not res.ok:
		_error(DotTrailBackend.explain(res))
		_update_submit()
		return res
	_error("")
	info.text = "Sent. A moderator reviews it before it can be worn."
	valid = false
	_update_submit()
	submitted.emit(str(res.value.get("id", "")) if res.value is Dictionary else "")
	return res


func error_text() -> String:
	return error_label.text


func _missing() -> String:
	if title_edit.text.strip_edges().is_empty():
		return "Give the trail a name."
	if author_edit.text.strip_edges().is_empty():
		return "Say who made the image."
	var url := url_edit.text.strip_edges()
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return "Give the image's source as an http(s) link."
	return ""


func _update_submit() -> void:
	var missing := _missing() if valid else ""
	submit_button.disabled = not valid or not missing.is_empty()
	hint_label.text = missing if valid else ("" if error_label.visible else "Choose an image to start.")


func _error(text: String) -> void:
	error_label.text = text
	error_label.visible = not text.is_empty()


## The validator's sentence, made a player's.
func _explain(res: DotResult) -> String:
	match res.code():
		DotError.CODE_QUOTA:
			return "That file is too large: %s." % res.error.message
	return "That image cannot be used: %s." % res.error.message


func _texture(p_bytes: PackedByteArray, type: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(p_bytes) if type == "png" else img.load_webp_from_buffer(p_bytes)
	return ImageTexture.create_from_image(img) if err == OK else null
