class_name DotTrailUpload
extends RefCounted

## Upload validation as a pure function: bytes and a file name in, a DotResult out. The workbench form and the server call the same one.

const PNG_SIG := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


## Value on success: {type, width, height, bytes}. limits: max_bytes, max_dimension.
static func validate(bytes: PackedByteArray, file_name: String, limits: Dictionary = {}) -> DotResult:
	var max_bytes: int = int(limits.get("max_bytes", 262144))
	var max_dim: int = int(limits.get("max_dimension", 512))
	if file_name != file_name.get_file() or file_name.is_empty() or file_name.begins_with("."):
		return DotResult.fail(DotError.CODE_INVALID, "upload name must be a plain file name", file_name)
	var ext := file_name.get_extension().to_lower()
	if ext != "png" and ext != "webp":
		return DotResult.fail(DotError.CODE_INVALID, "only png and webp trails are accepted", file_name)
	if bytes.size() > max_bytes:
		return DotResult.fail(DotError.CODE_QUOTA, "upload is %d bytes, the limit is %d" % [bytes.size(), max_bytes], file_name)
	var dims: DotResult = _png(bytes) if ext == "png" else _webp(bytes)
	if not dims.ok:
		return dims
	var wh: Vector2i = dims.value
	if wh.x < 1 or wh.y < 1 or wh.x > max_dim or wh.y > max_dim:
		return DotResult.fail(DotError.CODE_INVALID, "image is %dx%d, the limit is %d" % [wh.x, wh.y, max_dim], file_name)
	return DotResult.success({"type": ext, "width": wh.x, "height": wh.y, "bytes": bytes.size()})


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func _png(b: PackedByteArray) -> DotResult:
	if b.size() < 33:
		return DotResult.fail(DotError.CODE_INVALID, "not a png: too short")
	for i in 8:
		if b[i] != PNG_SIG[i]:
			return DotResult.fail(DotError.CODE_INVALID, "content is not a png (wrong magic bytes)")
	if b.slice(12, 16).get_string_from_ascii() != "IHDR" or _be32(b, 8) != 13:
		return DotResult.fail(DotError.CODE_INVALID, "png has no IHDR first")
	var wh := Vector2i(_be32(b, 16), _be32(b, 20))
	# Walk the chunks: the file must end exactly at IEND, so nothing rides along after the image.
	var at := 8
	while at + 12 <= b.size():
		var clen := _be32(b, at)
		var kind := b.slice(at + 4, at + 8).get_string_from_ascii()
		var next := at + 12 + clen
		if clen < 0 or next > b.size():
			return DotResult.fail(DotError.CODE_INVALID, "png chunk runs past the end of the file")
		if kind == "IEND":
			if next != b.size():
				return DotResult.fail(DotError.CODE_INVALID, "png has data after IEND")
			return DotResult.success(wh)
		at = next
	return DotResult.fail(DotError.CODE_INVALID, "png has no IEND chunk")


static func _le24(b: PackedByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16)


static func _webp(b: PackedByteArray) -> DotResult:
	if b.size() < 30 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WEBP":
		return DotResult.fail(DotError.CODE_INVALID, "content is not a webp (wrong magic bytes)")
	if (b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24)) + 8 != b.size():
		return DotResult.fail(DotError.CODE_INVALID, "webp size field does not match the file (data after the image)")
	var kind := b.slice(12, 16).get_string_from_ascii()
	if kind == "VP8X":
		return DotResult.success(Vector2i(_le24(b, 24) + 1, _le24(b, 27) + 1))
	if kind == "VP8L":
		if b[20] != 0x2F:
			return DotResult.fail(DotError.CODE_INVALID, "webp lossless signature missing")
		var bits := b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
		return DotResult.success(Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1))
	if kind == "VP8 ":
		if b[23] != 0x9D or b[24] != 0x01 or b[25] != 0x2A:
			return DotResult.fail(DotError.CODE_INVALID, "webp lossy start code missing")
		return DotResult.success(Vector2i((b[26] | (b[27] << 8)) & 0x3FFF, (b[28] | (b[29] << 8)) & 0x3FFF))
	return DotResult.fail(DotError.CODE_INVALID, "unknown webp chunk", kind)
