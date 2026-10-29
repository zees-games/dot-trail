class_name DotTrailBackend
extends RefCounted

## What a trail store talks to: prices, the player's points and owned trails, purchases and uploads. The TMC site is [DotTrailBackendHttp]; [DotTrailBackendStub] stands in for suites and offline. Every method may be awaited and returns a DotResult.

## Error codes the site sends back, mapped to words a player reads.
const REASONS := {
	"insufficient_points": "You do not have enough points.",
	"already_owned": "You already own this trail.",
	"unknown_sku": "This trail is not for sale.",
	"unauthorized": "Sign in to buy trails.",
}


## Value: {trails: [{id, title, price_points, free, owned, preview_url}], points: int (-1 unknown)}.
func catalog() -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "no trail store")


## Value: {ids: [owned], points}. Debits points; the server then lets the player equip it.
func purchase(_id: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "no trail store")


## Sends a player's own trail for moderation. [param meta]: title, licence, author, url. Value: {id, status}.
func submit_upload(_meta: Dictionary, _bytes: PackedByteArray, _file_name: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "no trail store")


## Server to server: what a player owns. Value: {ids, groups}.
func entitlements(_user: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "no trail store")


## A refusal in a player's words.
static func explain(res: DotResult) -> String:
	if res == null or res.ok:
		return ""
	var text := res.error.message
	var said := text + " " + str(res.error.detail)
	for code: String in REASONS:
		if said.contains(code):
			return REASONS[code]
	return text
