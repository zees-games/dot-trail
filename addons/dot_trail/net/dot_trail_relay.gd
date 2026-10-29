class_name DotTrailRelay
extends RefCounted

## The server half of player trails: runs a client's equip request through dot-trail's DotTrailEquip (access rule, cooldown) and tells every peer the id now worn. A refused request is answered with the id still worn, so the client's view reverts. The server's record is the only truth.

const CHANNEL := "trail"
const NET_META := &"dot_trail_relay"

## The server-side record of who wears what.
var equip: DotTrailEquip
## func(peer_id: int) -> PackedStringArray: the groups the player is in (from the session or the backbone).
var groups_fn: Callable = Callable()
## func(peer_id: int) -> PackedStringArray: trail ids the backend says the player bought.
var entitlements_fn: Callable = Callable()

## func(actor: int, id: String, to_peer: int) -> void: replaces the net, so a host can carry trails on another channel (see DotTrailEnvelope). to_peer 0 is everyone.
var send_fn: Callable = Callable()
var _net: DotNetManager = null
var _peers: Dictionary = {}


## Registers the type on [param net], answers requests and stores itself as [constant NET_META]. [param roster] (a DotGameRoster) calls add_peer and remove_peer as players come and go.
static func serve(net: DotNetManager, p_equip: DotTrailEquip, p_groups_fn: Callable = Callable(),
		p_entitlements_fn: Callable = Callable(), roster: Object = null) -> DotResult:
	var made := DotTrailMessage.register(net)
	if not made.ok:
		return made
	var relay := DotTrailRelay.new()
	relay._net = net
	relay.equip = p_equip
	relay.groups_fn = p_groups_fn
	relay.entitlements_fn = p_entitlements_fn
	var _on := net.messages.on(DotTrailMessage.NAME, relay._on_message)
	if roster != null and roster.has_method(&"follow"):
		roster.call(&"follow", relay)
	net.set_meta(NET_META, relay)
	return DotResult.success(relay)


## A relay with no net: set [member send_fn] (DotTrailEnvelope does) and feed it [method receive].
static func create(p_equip: DotTrailEquip, p_groups_fn: Callable = Callable(), p_entitlements_fn: Callable = Callable()) -> DotTrailRelay:
	var relay := DotTrailRelay.new()
	relay.equip = p_equip
	relay.groups_fn = p_groups_fn
	relay.entitlements_fn = p_entitlements_fn
	return relay


static func of(net: DotNetManager) -> DotTrailRelay:
	var relay: Variant = net.get_meta(NET_META, null) if net != null else null
	return relay as DotTrailRelay


## A player joined: tell them who wears what.
func add_peer(peer_id: int) -> void:
	_peers[peer_id] = true
	for other: int in _peers:
		var worn := String(equip.call(&"worn", other))
		if other != peer_id and not worn.is_empty():
			_send(other, worn, peer_id)


## A player left: forget their choice and tell everyone to drop the ribbon.
func remove_peer(peer_id: int) -> void:
	_peers.erase(peer_id)
	equip.call(&"forget", peer_id)
	_send(peer_id, "", 0)


## Re-checks a player's trail after their groups or entitlements changed; true when it was taken off.
func revalidate(peer_id: int) -> bool:
	var dropped: bool = equip.call(&"revalidate", peer_id, _groups(peer_id), _entitlements(peer_id))
	if dropped:
		_send(peer_id, "", 0)
	return dropped


## The peers the relay knows, for a transport that broadcasts by sending to each.
func peers() -> Array:
	return _peers.keys()


## Whether [param peer] may wear [param id] on what the relay knows now; a refusal may be a purchase not yet seen.
func allows(peer: int, id: String) -> bool:
	if id.is_empty():
		return true
	var reg: Variant = equip.get(&"registry")
	return reg != null and (reg as DotTrailRegistry).may_equip(id, _groups(peer), _entitlements(peer)).ok


## A client asked to wear [param id]; the answer goes out through the net or [member send_fn]. Returns the refusal, if any.
func receive(peer: int, id: String) -> DotResult:
	if peer <= 0 or not DotTrailMessage.valid_wire_id(id):
		return DotResult.fail(DotError.CODE_INVALID, "bad trail request")
	var res: DotResult = equip.call(&"equip", peer, id, _groups(peer), _entitlements(peer))
	if res.ok:
		_send(peer, id, 0)
	else:
		DotLog.debug(CHANNEL, "equip refused", {"peer": peer, "id": id, "code": res.code()})
		_send(peer, String(equip.call(&"worn", peer)), peer)
	return res


func _on_message(message: DotNetMessage) -> void:
	var request := message as DotTrailMessage
	if request == null or request.sender_peer_id <= 0:
		return
	var _res := receive(request.sender_peer_id, request.id)


func _groups(peer_id: int) -> PackedStringArray:
	return groups_fn.call(peer_id) if groups_fn.is_valid() else PackedStringArray()


func _entitlements(peer_id: int) -> PackedStringArray:
	return entitlements_fn.call(peer_id) if entitlements_fn.is_valid() else PackedStringArray()


func _send(actor: int, id: String, to_peer: int) -> void:
	if send_fn.is_valid():
		send_fn.call(actor, id, to_peer)
		return
	if _net == null:
		return
	var m := DotTrailMessage.new()
	m.actor = actor
	m.id = id
	var sent := _net.send(m, to_peer)
	if not sent.ok:
		DotLog.debug(CHANNEL, "trail not sent", {"to": to_peer, "why": sent.error.message})
