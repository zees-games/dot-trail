class_name DotTrailRibbon
extends RefCounted

## Ribbon geometry as a pure function of points and ages, so the emitter, a test and a store preview agree.


## Returns {vertices, uvs, alphas}: two vertices per point as a triangle strip. Oldest point first.
static func strip(points: PackedVector3Array, ages: PackedFloat32Array, width: float, lifetime: float) -> Dictionary:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var alphas := PackedFloat32Array()
	var n := points.size()
	if n < 2:
		return {"vertices": verts, "uvs": uvs, "alphas": alphas}
	for i in n:
		var dir := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)])
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized() * (width * 0.5)
		var life := clampf(1.0 - ages[i] / maxf(lifetime, 0.001), 0.0, 1.0)
		var u := float(i) / float(n - 1)
		verts.append(points[i] - side)
		verts.append(points[i] + side)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		alphas.append(life)
		alphas.append(life)
	return {"vertices": verts, "uvs": uvs, "alphas": alphas}
