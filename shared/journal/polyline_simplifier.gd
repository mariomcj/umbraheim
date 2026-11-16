class_name PolylineSimplifier
extends RefCounted
## Simplificação de polilinha Ramer–Douglas–Peucker (iterativa, sem recursão).
## Mantém sempre o primeiro e o último ponto.


static func simplify(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points.duplicate()
	var keep := PackedByteArray()
	keep.resize(n)
	keep.fill(0)
	keep[0] = 1
	keep[n - 1] = 1
	var stack := PackedInt32Array([0, n - 1])
	while not stack.is_empty():
		var last := stack[stack.size() - 1]
		var first := stack[stack.size() - 2]
		stack.resize(stack.size() - 2)
		var max_dist := 0.0
		var index := -1
		for i in range(first + 1, last):
			var d := _distance_to_segment(points[i], points[first], points[last])
			if d > max_dist:
				max_dist = d
				index = i
		if index != -1 and max_dist > epsilon:
			keep[index] = 1
			stack.append_array([first, index, index, last])
	var result := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			result.append(points[i])
	return result


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
