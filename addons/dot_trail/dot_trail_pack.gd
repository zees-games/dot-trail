class_name DotTrailPack
extends RefCounted

## One dot-cloud pack for all of a server's trails: build it from a store, fetch and mount it before join. dot-cloud is reached by path and duck typing, so this addon does not depend on it.

const CHANNEL := "trail"
const PUBLISHER_SCRIPT := "res://addons/dot_cloud/publish/dot_cloud_publisher.gd"
const PACK_PREFIX := "trails-"


## The pack's content id for a server, e.g. "trails-myserver". Only a-z, 0-9, - and _ survive.
static func content_id_for(server_name: String) -> String:
	var out := ""
	for i in server_name.to_lower().length():
		var c := server_name.to_lower()[i]
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "-"
	return PACK_PREFIX + out.substr(0, 48).strip_edges()


## Saves [param store] to a staging directory and publishes it as ONE pack into [param out_dir] (manifest.json plus content-addressed objects, ready for the CDN). [param opts]: version, signing_key_pem, display_name. Value on success: the publisher's result.
static func build(store: DotTrailStore, content_id: String, out_dir: String, opts: Dictionary = {}) -> DotResult:
	if store.registry.count() == 0:
		return DotResult.fail(DotError.CODE_INVALID, "no trails to publish")
	if not ResourceLoader.exists(PUBLISHER_SCRIPT):
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "dot-cloud is not linked; use tools/publish_pack.sh on the store directory instead")
	var staging := out_dir.path_join("_source")
	var saved := store.save(staging)
	if not saved.ok:
		return saved
	var pub: RefCounted = (load(PUBLISHER_SCRIPT) as GDScript).new()
	pub.set(&"content_id", content_id)
	pub.set(&"version", str(opts.get("version", "1.0.0")))
	pub.set(&"display_name", str(opts.get("display_name", content_id)))
	pub.set(&"signing_key_pem", str(opts.get("signing_key_pem", "")))
	pub.set(&"metadata", {"kind": "trails", "count": store.registry.count()})
	var res: DotResult = pub.call(&"publish", staging, out_dir)
	DotLog.info(CHANNEL, "trail pack built", {"id": content_id, "trails": store.registry.count(), "ok": res.ok})
	return res


## The client side of join: ensures the pack through a DotCloudClient (duck-typed), then loads the mounted trails.json into [param registry]. A failure is a result, so the caller joins without trails.
static func fetch(client: Object, content_id: String, version: String, registry: DotTrailRegistry) -> DotResult:
	if client == null or not client.has_method(&"ensure"):
		return DotResult.fail(DotError.CODE_INVALID, "no dot-cloud client")
	var res: DotResult = await client.call(&"ensure", StringName(content_id), version)
	if not res.ok:
		return res.wrap("fetching the trail pack " + content_id)
	var prefix: String = str(res.value)
	return DotTrailStore.new(registry).load_dir(prefix)
