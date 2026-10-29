class_name DotTrailFilePick
extends Node

## Asks the player for one image file: a FileDialog on the desktop, the browser's own file input on the web (read through FileReader, so nothing touches user://). Call [method open] from a button press: a browser only opens a picker during a user gesture.

signal picked(file_name: String, bytes: PackedByteArray)
signal failed(message: String)

## Refused before reading; [DotTrailUpload.validate] then applies the real limit with a clearer sentence.
var read_cap_bytes: int = 4 * 1024 * 1024
var _dialog: FileDialog = null
var _js_input: Variant = null
var _js_reader: Variant = null
var _js_name := ""


func open() -> void:
	if DotWeb.available():
		_open_web()
	else:
		_open_desktop()


## Hands bytes in as if picked; for suites and the shot tool.
func deliver(file_name: String, bytes: PackedByteArray) -> void:
	if bytes.size() > read_cap_bytes:
		failed.emit("%s is too large to read (%d bytes)." % [file_name, bytes.size()])
		return
	picked.emit(file_name, bytes)


func _open_desktop() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.png, *.webp ; Trail images"])
		_dialog.use_native_dialog = true
		_dialog.title = "Choose a trail image"
		_dialog.file_selected.connect(_on_desktop_file)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _on_desktop_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		failed.emit("Could not open %s." % path.get_file())
		return
	var size := f.get_length()
	if size > read_cap_bytes:
		failed.emit("%s is too large to read (%d bytes)." % [path.get_file(), size])
		return
	var bytes := f.get_buffer(size)
	f.close()
	picked.emit(path.get_file(), bytes)


func _open_web() -> void:
	var doc: Variant = DotWeb.get_global("document")
	if doc == null:
		failed.emit("This browser does not allow choosing a file here.")
		return
	_js_input = doc.createElement("input")
	_js_input.type = "file"
	_js_input.accept = ".png,.webp,image/png,image/webp"
	_js_input.onchange = DotWeb.create_callback("dot_trail_pick_change", _on_web_change)
	_js_input.click()


func _on_web_change(_args: Array) -> void:
	var files: Variant = _js_input.files if _js_input != null else null
	if files == null or int(files.length) < 1:
		return
	var file: Variant = files.item(0)
	_js_name = str(file.name)
	if int(file.size) > read_cap_bytes:
		failed.emit("%s is too large to read (%d bytes)." % [_js_name, int(file.size)])
		return
	_js_reader = DotWeb.bridge().call("create_object", "FileReader")
	_js_reader.onload = DotWeb.create_callback("dot_trail_pick_load", _on_web_load)
	_js_reader.onerror = DotWeb.create_callback("dot_trail_pick_error", func(_a: Array) -> void: failed.emit("The browser could not read %s." % _js_name))
	_js_reader.readAsDataURL(file)


func _on_web_load(_args: Array) -> void:
	var url := str(_js_reader.result)
	var comma := url.find(",")
	var bytes := Marshalls.base64_to_raw(url.substr(comma + 1)) if comma >= 0 else PackedByteArray()
	DotWeb.release_callback("dot_trail_pick_change")
	DotWeb.release_callback("dot_trail_pick_load")
	DotWeb.release_callback("dot_trail_pick_error")
	picked.emit(_js_name, bytes)
