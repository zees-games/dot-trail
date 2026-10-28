class_name DotTrailEmitter
extends Node3D

## Follows a node and keeps a ribbon of where it has been. Place it anywhere; the target comes from a DotNodeRef.

const CHANNEL := "trail"

## The node to follow, resolved against this emitter. Default: the parent.
@export var target: DotNodeRef
## Height above the node's origin (the feet) the ribbon is drawn at.
@export var lift := 0.9
var config: DotTrailConfig = DotTrailConfig.new()
var def: DotTrailDef
var registry: DotTrailRegistry

var _points := PackedVector3Array()
var _times := PackedFloat64Array()
var _clock := 0.0
var _target: Node3D
var _mesh_node: MeshInstance3D
var _mesh: ImmediateMesh
var _dirty := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if target == null:
		target = DotNodeRef.new()
		target.mode = DotNodeRef.Mode.PARENT
	var res := target.resolve(self)
	if res.ok and res.value is Node3D:
		_target = res.value
	else:
		DotLog.warn(CHANNEL, "emitter has no 3D target", {"path": str(get_path())})
	if DisplayServer.get_name() != "headless":
		_mesh = ImmediateMesh.new()
		_mesh_node = MeshInstance3D.new()
		_mesh_node.mesh = _mesh
		_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_node)


## Chooses what is drawn. A null def clears the ribbon.
func set_trail(p_def: DotTrailDef) -> void:
	def = p_def
	if def == null:
		clear()
	if _mesh_node != null:
		_mesh_node.material_override = null if def == null else _material()


func clear() -> void:
	_points.clear()
	_times.clear()
	_dirty = true


func point_count() -> int:
	return _points.size()


func _physics_process(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		sample(_target.global_position, delta)
	else:
		sample(Vector3.INF, delta)


## Advances time by [param delta] and records [param pos] when it moved far enough. INF only ages the ribbon. Public so a test or a server without physics can drive it.
func sample(pos: Vector3, delta: float) -> void:
	_clock += delta
	var lifetime := minf(def.lifetime, config.max_lifetime) if def != null else 0.0
	while not _times.is_empty() and _clock - _times[0] > lifetime:
		_points.remove_at(0)
		_times.remove_at(0)
		_dirty = true
	if def == null or not config.enabled or pos == Vector3.INF:
		return
	if _points.is_empty() or _points[_points.size() - 1].distance_to(pos) >= config.min_step:
		_points.append(pos)
		_times.append(_clock)
		if _points.size() > config.max_points:
			_points.remove_at(0)
			_times.remove_at(0)
		_dirty = true
	if _dirty or (_mesh != null and _points.size() > 1):
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	if def == null or _points.size() < 2 or not _in_range():
		return
	var ages := PackedFloat32Array()
	for t in _times:
		ages.append(_clock - t)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var lifted := PackedVector3Array()
	for p in _points:
		lifted.append(p + Vector3.UP * lift)
	var s := DotTrailRibbon.strip(lifted, ages, minf(def.width, config.max_width), def.lifetime, cam.global_position if cam != null else Vector3.INF)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in s["vertices"].size():
		var a: float = s["alphas"][i]
		_mesh.surface_set_color(Color(def.color.r, def.color.g, def.color.b, def.color.a * a))
		_mesh.surface_set_uv(s["uvs"][i])
		_mesh.surface_add_vertex(to_local(s["vertices"][i]))
	_mesh.surface_end()


func _in_range() -> bool:
	if config.cull_distance <= 0.0:
		return true
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam == null or cam.global_position.distance_to(_points[_points.size() - 1]) <= config.cull_distance


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = {"add": BaseMaterial3D.BLEND_MODE_ADD, "mul": BaseMaterial3D.BLEND_MODE_MUL}.get(def.blend, BaseMaterial3D.BLEND_MODE_MIX)
	if registry != null:
		m.albedo_texture = registry.texture_for(def.id)
	return m


func describe() -> String:
	return "DotTrailEmitter: %s, %d points, target %s" % [def.id if def != null else "none", _points.size(), str(_target.get_path()) if _target != null and _target.is_inside_tree() else "none"]
