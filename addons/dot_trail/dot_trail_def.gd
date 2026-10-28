class_name DotTrailDef
extends Resource

## One trail: an image, how wide and long-lived the ribbon is, and who may wear it.

const BLENDS := ["mix", "add", "mul"]
const ACCESS_PUBLIC := "public"
const ACCESS_GROUPS := "groups"

@export var id: String = ""
@export var title: String = ""
## File name inside the pack, png or webp.
@export var image: String = ""
@export var width: float = 0.4
@export var lifetime: float = 1.5
@export var color: Color = Color.WHITE
@export_enum("mix", "add", "mul") var blend: String = "mix"
@export_enum("public", "groups") var access: String = ACCESS_PUBLIC
@export var groups: PackedStringArray = PackedStringArray()
## Store points; 0 is free.
@export var price: int = 0
@export var credit: String = ""
## Rights record the upload form requires; the pack builder writes them into the pack's licence.json.
@export var licence: String = ""
@export var author: String = ""
@export var url: String = ""


static func valid_id(s: String) -> bool:
	if s.is_empty() or s.length() > 32:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


## Builds a def from a parsed JSON dictionary, with every field checked.
static func from_dict(d: Dictionary, limits: Dictionary = {}) -> DotResult:
	var t := DotTrailDef.new()
	t.id = str(d.get("id", ""))
	if not valid_id(t.id):
		return DotResult.fail(DotError.CODE_INVALID, "trail id must be 1-32 chars of a-z, 0-9, _", t.id)
	t.title = str(d.get("title", t.id)).substr(0, 64)
	t.image = str(d.get("image", ""))
	var ext := t.image.get_extension().to_lower()
	if t.image != t.image.get_file() or t.image.begins_with(".") or not (ext == "png" or ext == "webp"):
		return DotResult.fail(DotError.CODE_INVALID, "trail image must be a plain png or webp file name", t.id)
	t.width = float(d.get("width", t.width))
	t.lifetime = float(d.get("lifetime", t.lifetime))
	var max_w: float = float(limits.get("max_width", 2.0))
	var max_l: float = float(limits.get("max_lifetime", 5.0))
	if t.width <= 0.0 or t.width > max_w or t.lifetime <= 0.0 or t.lifetime > max_l:
		return DotResult.fail(DotError.CODE_INVALID, "trail width or lifetime out of range", t.id)
	var col: Variant = d.get("color", "#ffffff")
	if col is String or col is StringName:
		if not Color.html_is_valid(str(col)):
			return DotResult.fail(DotError.CODE_INVALID, "trail color is not a hex colour", t.id)
		t.color = Color.html(str(col))
	t.blend = str(d.get("blend", "mix"))
	if not BLENDS.has(t.blend):
		return DotResult.fail(DotError.CODE_INVALID, "trail blend must be mix, add or mul", t.id)
	t.access = str(d.get("access", ACCESS_PUBLIC))
	if t.access != ACCESS_PUBLIC and t.access != ACCESS_GROUPS:
		return DotResult.fail(DotError.CODE_INVALID, "trail access must be public or groups", t.id)
	for g in d.get("groups", []):
		t.groups.append(str(g))
	if t.access == ACCESS_GROUPS and t.groups.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "a groups trail needs at least one group", t.id)
	t.price = int(d.get("price", 0))
	if t.price < 0:
		return DotResult.fail(DotError.CODE_INVALID, "trail price must not be negative", t.id)
	t.credit = str(d.get("credit", "")).substr(0, 200)
	t.licence = str(d.get("licence", "")).substr(0, 32)
	t.author = str(d.get("author", "")).substr(0, 100)
	t.url = str(d.get("url", "")).substr(0, 300)
	return DotResult.success(t)


func to_dict() -> Dictionary:
	return {
		"id": id, "title": title, "image": image, "width": width, "lifetime": lifetime,
		"color": "#" + color.to_html(false), "blend": blend, "access": access,
		"groups": Array(groups), "price": price, "credit": credit,
		"licence": licence, "author": author, "url": url,
	}


func describe() -> String:
	return "%s (%s, %.2fm x %.1fs, %s%s, price %d)" % [id, image, width, lifetime, access, "" if groups.is_empty() else ":" + ",".join(groups), price]
