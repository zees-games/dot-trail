extends Node3D

## Renders a runner with trails to a PNG: `res://examples/trail_shot.tscn -- --shot out.png` (tools/screenshot.sh). The images are drawn in code, so the tool ships no art.

var _shot := ""
var _t := 0.0
var _runner: Node3D
var _emitters: Array[DotTrailEmitter] = []
var _registry := DotTrailRegistry.new()
var _done := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot" and i + 1 < args.size():
			_shot = args[i + 1]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.36, 0.3)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	_runner = _make_runner(Color(0.9, 0.35, 0.2))
	add_child(_runner)
	var specs := [["comet", Color(1, 0.75, 0.3), "add", 0.9], ["ribbon", Color(0.4, 0.8, 1.0), "mix", 0.6]]
	for k in specs.size():
		var png := _streak_png(specs[k][0] == "comet")
		var def: DotTrailDef = DotTrailDef.from_dict({"id": specs[k][0], "image": specs[k][0] + ".png", "width": specs[k][3], "lifetime": 2.0,
			"color": "#" + (specs[k][1] as Color).to_html(false), "blend": specs[k][2]}).value
		var added := _registry.add(def, png)
		if not added.ok:
			push_error("trail not added: " + str(added.error))
		var e := DotTrailEmitter.new()
		e.registry = _registry
		_runner.add_child(e)
		e.set_trail(def)
		e.lift = 1.2 if k == 0 else 0.5
		_emitters.append(e)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.0, 7.5)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	_runner.position = _path(0.0)
	for step in 140:
		_advance(1.0 / 60.0)


func _make_runner(c: Color) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.7
	body.mesh = cap
	body.position.y = 0.85
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	body.material_override = m
	n.add_child(body)
	return n


func _path(t: float) -> Vector3:
	return Vector3(sin(t * 1.1) * 4.0, 0.0, cos(t * 0.7) * 3.0)


func _advance(dt: float) -> void:
	_t += dt
	var prev := _runner.position
	_runner.position = _path(_t)
	var d := _runner.position - prev
	if d.length_squared() > 0.000001:
		_runner.look_at(_runner.position + d, Vector3.UP)
	for e in _emitters:
		e.sample(_runner.global_position, dt)


func _process(delta: float) -> void:
	_advance(delta)
	if _done or _shot.is_empty() or _t < 3.2:
		return
	_done = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	get_tree().quit()


## Soft streak: fades along its length (u) and across it (v); the comet is bright at the head end.
func _streak_png(comet: bool) -> PackedByteArray:
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		for y in h:
			var u := float(x) / (w - 1)
			var v := absf(float(y) / (h - 1) - 0.5) * 2.0
			var a := pow(1.0 - v, 1.5) * (pow(u, 1.5) if comet else 0.4 + 0.6 * u)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return img.save_png_to_buffer()
