class_name DotTrailMenu
extends RefCounted

## Puts a Trails page into a dot-menu DotMenu (duck-typed: add_page), drawn fresh each time it opens. dot-menu is reached by path, so this file parses without it.

const PAGE_ID := &"trails"
const PAGE_SCRIPT := "res://addons/dot_menu/core/dot_menu_page.gd"


## [param setup] is `func(screen: DotTrailScreen) -> void`: the caller calls bind, sets request_fn and worn_fn, and calls refresh. Returns the page, or null without dot-menu.
static func add_to(menu: Object, setup: Callable, before: StringName = &"") -> Object:
	if menu == null or not menu.has_method(&"add_page") or not ResourceLoader.exists(PAGE_SCRIPT):
		return null
	var page: Object = (load(PAGE_SCRIPT) as GDScript).call(&"make", PAGE_ID, "Trails", "Wear a trail, buy one with points, or send your own.")
	page.set(&"build", func(kit: Object, body: Control) -> void:
		var screen := DotTrailScreen.make(body, null, null, kit, false)
		setup.call(screen))
	menu.call(&"add_page", page, before)
	return page
