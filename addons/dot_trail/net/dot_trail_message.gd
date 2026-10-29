class_name DotTrailMessage
extends DotNetMessage

## A player's equipped trail id. A client asks (id, "" to take it off); the server checks and tells everyone (actor, id). Only the id travels: the image comes in the server's trail pack.

const NAME := &"trail.equip"
const MAX_ID := 32

## The peer wearing it; the server writes it, a client's request leaves it 0.
var actor: int = 0
var id: String = ""


func _type_name() -> StringName:
	return NAME


func _write(w: DotNetWriter) -> void:
	w.write_varint(actor)
	w.write_string(id, MAX_ID)


func _read(r: DotNetReader) -> void:
	actor = r.read_varint()
	id = r.read_string(MAX_ID)


func _validate() -> DotResult:
	if not valid_wire_id(id):
		return DotResult.fail(DotError.CODE_INVALID, "trail id out of range or has a character outside a-z, 0-9, _")
	return DotResult.success(true)


## An id as it may travel: empty (take it off) or up to [constant MAX_ID] of a-z, 0-9, _.
static func valid_wire_id(p_id: String) -> bool:
	if p_id.length() > MAX_ID:
		return false
	for i in p_id.length():
		var c := p_id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true


## Registers the type on [param net]'s manager: call on both ends, before the schema is sealed. Idempotent.
static func register(net: DotNetManager) -> DotResult:
	if net.messages.type_names().has(String(NAME)):
		return DotResult.success(true)
	return net.messages.register(NAME, DotTrailMessage, DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.BOTH, false)
