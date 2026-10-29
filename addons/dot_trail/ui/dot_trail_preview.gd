class_name DotTrailPreview
extends Control

## A trail drawn live on a looping path: the same [DotTrailRibbon.strip] maths as in the world, flattened to the screen, so a store card shows what a player will wear.

## Pixels per metre of ribbon width.
const PX_PER_M := 46.0
const SAMPLES := 48

var texture: Texture2D = null
var color: Color = Color.WHITE
var width_m: float = 0.4
var lifetime: float = 1.5
var blend: String = "mix"
## Advances the path; a shot sets it and turns [member playing] off for a still.
var t: float = 0.0
var playing: bool = true
## A dimmed card for a trail the player cannot wear yet.
var dim: bool = false


## Takes a def and the texture its pack image makes (null draws the colour only).
func show_trail(def: DotTrailDef, tex: Texture2D) -> void:
	texture = tex
	color = def.color if def != null else Color.WHITE
	width_m = def.width if def != null else 0.4
	lifetime = def.lifetime if def != null else 1.5
	blend = def.blend if def != null else "mix"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = {"add": CanvasItemMaterial.BLEND_MODE_ADD, "mul": CanvasItemMaterial.BLEND_MODE_MUL}.get(blend, CanvasItemMaterial.BLEND_MODE_MIX)
	material = mat
	queue_redraw()


func _process(delta: float) -> void:
	if playing and is_visible_in_tree():
		t += delta
		queue_redraw()


## The path point at time [param at], in this control's pixels.
func path_at(at: float) -> Vector2:
	var c := size * 0.5
	return c + Vector2(sin(at * 1.7) * size.x * 0.36, sin(at * 2.9 + 0.6) * size.y * 0.28)


## The ribbon as screen quads: {vertices: PackedVector2Array, uvs, alphas}; pure enough for a test.
func geometry() -> Dictionary:
	var span := maxf(lifetime, 0.2)
	var pts := PackedVector3Array()
	var ages := PackedFloat32Array()
	for i in SAMPLES:
		var age := span * (1.0 - float(i) / float(SAMPLES - 1))
		var p := path_at(t - age)
		pts.append(Vector3(p.x, p.y, 0.0))
		ages.append(age)
	var eye := Vector3(size.x * 0.5, size.y * 0.5, 100000.0)
	var s: Dictionary = DotTrailRibbon.strip(pts, ages, clampf(width_m, 0.05, 2.0) * PX_PER_M, span, eye)
	var flat := PackedVector2Array()
	for v: Vector3 in s["vertices"]:
		flat.append(Vector2(v.x, v.y))
	return {"vertices": flat, "uvs": s["uvs"], "alphas": s["alphas"]}


func _draw() -> void:
	var g := geometry()
	var v: PackedVector2Array = g["vertices"]
	var uv: PackedVector2Array = g["uvs"]
	var a: PackedFloat32Array = g["alphas"]
	var tint := color * (Color(0.55, 0.55, 0.6, 0.7) if dim else Color.WHITE)
	var cols := PackedColorArray()
	for k in v.size():
		cols.append(Color(tint, tint.a * a[k]))
	# Indexed triangles: a quad folded by a sharp turn makes draw_polygon's triangulation fail.
	var idx := PackedInt32Array()
	for i in range(0, v.size() - 2, 2):
		idx.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, v, cols, uv, PackedInt32Array(), PackedFloat32Array(), texture.get_rid() if texture != null else RID())
	if v.size() >= 2:
		var head := (v[v.size() - 1] + v[v.size() - 2]) * 0.5
		draw_circle(head, 4.0, Color(1, 1, 1, 0.9 if not dim else 0.4))
