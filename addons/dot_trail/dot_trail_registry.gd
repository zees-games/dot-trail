class_name DotTrailRegistry
extends RefCounted

## The set of trails a server offers, loaded from the pack's trails.json. Registered with DotRegistry, never an autoload.

const CHANNEL := "trail"
const SERVICE := &"trail_registry"
const INDEX_FILE := "trails.json"

var config: DotTrailConfig = DotTrailConfig.new()
var _defs: Dictionary = {}
## image file name -> validated bytes.
var _images: Dictionary = {}


static func current() -> DotTrailRegistry:
	return DotRegistry.get_service(SERVICE) as DotTrailRegistry


func install() -> void:
	DotRegistry.register(SERVICE, self)


func count() -> int:
	return _defs.size()


func ids() -> PackedStringArray:
	var out := PackedStringArray(_defs.keys())
	out.sort()
	return out


func get_def(id: String) -> DotTrailDef:
	return _defs.get(id) as DotTrailDef


## Adds a def and its image bytes. The image goes through DotTrailUpload.validate, so a pack cannot carry anything else.
func add(def: DotTrailDef, image_bytes: PackedByteArray) -> DotResult:
	if _defs.has(def.id):
		return DotResult.fail(DotError.CODE_CONFLICT, "trail id already exists", def.id)
	if _defs.size() >= config.max_trails:
		return DotResult.fail(DotError.CODE_QUOTA, "trail limit reached (%d)" % config.max_trails, def.id)
	var ok := DotTrailUpload.validate(image_bytes, def.image, config.limits())
	if not ok.ok:
		DotLog.warn(CHANNEL, "rejected trail image", {"id": def.id, "code": ok.code()})
		return ok.wrap("trail " + def.id)
	_defs[def.id] = def
	_images[def.image] = image_bytes
	DotLog.debug(CHANNEL, "trail added", {"id": def.id})
	return DotResult.success(def)


func remove(id: String) -> bool:
	var def := get_def(id)
	if def == null:
		return false
	_defs.erase(id)
	var shared := false
	for other: DotTrailDef in _defs.values():
		shared = shared or other.image == def.image
	if not shared:
		_images.erase(def.image)
	return true


## Parses trails.json text and takes the images from [param files] (file name -> bytes). All or nothing.
func load_index(json_text: String, files: Dictionary) -> DotResult:
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(json_text) == OK else null
	if not (parsed is Dictionary) or not (parsed.get("trails") is Array):
		return DotResult.fail(DotError.CODE_PARSE, "trails.json must be an object with a trails array")
	var staged := DotTrailRegistry.new()
	staged.config = config
	staged._defs = _defs.duplicate()
	staged._images = _images.duplicate()
	for entry: Variant in parsed["trails"]:
		if not (entry is Dictionary):
			return DotResult.fail(DotError.CODE_PARSE, "trail entry is not an object")
		var made := DotTrailDef.from_dict(entry, {"max_width": config.max_width, "max_lifetime": config.max_lifetime})
		if not made.ok:
			return made
		var def: DotTrailDef = made.value
		if not files.has(def.image):
			return DotResult.fail(DotError.CODE_INVALID, "index names a missing image " + def.image, def.id)
		var added := staged.add(def, files[def.image])
		if not added.ok:
			return added
	_defs = staged._defs
	_images = staged._images
	return DotResult.success(_defs.size())


func to_index() -> String:
	var list: Array = []
	for id in ids():
		list.append(get_def(id).to_dict())
	return JSON.stringify({"trails": list}, "\t")


## Files a pack for these trails must carry: trails.json plus each image.
func pack_files() -> Dictionary:
	var out := {INDEX_FILE: to_index().to_utf8_buffer()}
	out.merge(_images)
	return out


func image_bytes(id: String) -> PackedByteArray:
	var def := get_def(id)
	return PackedByteArray() if def == null else _images.get(def.image, PackedByteArray())


## Builds a texture from the stored bytes; null when the id is unknown. Not called headless.
func texture_for(id: String) -> Texture2D:
	var def := get_def(id)
	if def == null:
		return null
	var img := Image.new()
	var bytes := image_bytes(id)
	var err := img.load_png_from_buffer(bytes) if def.image.get_extension().to_lower() == "png" else img.load_webp_from_buffer(bytes)
	return null if err != OK else ImageTexture.create_from_image(img)


## The access rule. [param entitlements] are ids the backend says the player owns (purchases).
func may_equip(id: String, groups: PackedStringArray, entitlements: PackedStringArray = PackedStringArray()) -> DotResult:
	var def := get_def(id)
	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "unknown trail", id)
	if def.access == DotTrailDef.ACCESS_PUBLIC and def.price == 0:
		return DotResult.success(def)
	if entitlements.has(id):
		return DotResult.success(def)
	if def.access == DotTrailDef.ACCESS_GROUPS:
		for g in def.groups:
			if groups.has(g):
				return DotResult.success(def)
	return DotResult.fail(DotError.CODE_FORBIDDEN, "trail is not available to this player", id)


func describe() -> String:
	return "DotTrailRegistry: %d trails, %d images" % [_defs.size(), _images.size()]


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray([describe()])
	for id in ids():
		out.append("  " + get_def(id).describe())
	return out
