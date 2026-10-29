class_name DotTrailKit
extends RefCounted

## The menu kit's pieces with a plain fallback, so the trail screens use dot-menu's look when it is there and still draw without it.

var kit: Object = null


func _init(p_kit: Object = null) -> void:
	kit = p_kit
	if kit == null and ResourceLoader.exists("res://addons/dot_menu/core/dot_menu_kit.gd"):
		kit = (load("res://addons/dot_menu/core/dot_menu_kit.gd") as GDScript).new()


func primary(text: String) -> Button:
	return kit.primary_button(text) if kit != null else _plain(text)


func secondary(text: String) -> Button:
	return kit.secondary_button(text) if kit != null else _plain(text)


func card() -> PanelContainer:
	return kit.card() if kit != null else PanelContainer.new()


func section(text: String) -> Label:
	return kit.section(text) if kit != null else _label(text.to_upper())


func label(text: String, small: bool = false, colour: String = "") -> Label:
	if kit == null:
		return _label(text)
	var c: Color = Color(0, 0, 0, 0) if colour.is_empty() else kit.palette.get(colour)
	return kit.label(text, kit.size_small if small else 0, c)


func heading(text: String) -> Label:
	return kit.label(text, kit.size_heading, Color(0, 0, 0, 0), true) if kit != null else _label(text)


## A palette colour by name, or [param fallback] without a kit.
func colour(name: String, fallback: Color) -> Color:
	return kit.palette.get(name) if kit != null else fallback


func _plain(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
