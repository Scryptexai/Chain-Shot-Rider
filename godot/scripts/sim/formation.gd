class_name Formation
extends RefCounted
## Crowd layouts for a wave.
##
## Shape matters more than it looks: the squad fires straight up, so a crowd
## scattered evenly across eighteen units can never be engaged. Measured
## headlessly, random placement produced twelve kills in sixty seconds and
## lost every stage in wave one. A formation concentrates the crowd into
## columns the squad can meet, and turns "where do I stand" into a decision.
##
## Pure functions of their arguments, so the same wave index always lays out
## the same way and a replay stays honest.


static func rect(count: int, columns: int, spacing: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	var half := float(columns - 1) * spacing * 0.5
	for i in range(count):
		slots.append(Vector2(float(i % columns) * spacing - half, float(i / columns) * spacing))

	return slots


static func vshape(count: int, spacing: float, half_w: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	var row := 0
	while slots.size() < count and row < 400:
		var x := minf(float(row) * spacing * 0.6, half_w)
		var z := float(row) * spacing * 0.8
		slots.append(Vector2(-x, z))
		if x > 0.01 and slots.size() < count:
			slots.append(Vector2(x, z))
		row += 1

	return slots


static func diamond(count: int, spacing: float, half_w: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	var widest := int(sqrt(float(count)))
	var total := widest * 2
	var row := 0
	while slots.size() < count and row <= total:
		var n := maxi(1, (row + 1) if row <= widest else (total - row + 1))
		var half := minf(float(n - 1) * spacing * 0.5, half_w)
		for c in range(n):
			if slots.size() >= count:
				break
			var x := 0.0 if n == 1 else -half + 2.0 * half * float(c) / float(n - 1)
			slots.append(Vector2(x, float(row) * spacing * 0.9))
		row += 1
	while slots.size() < count:
		var c := slots.size() % 6
		slots.append(Vector2((float(c) - 2.5) * spacing, float(row) * spacing * 0.9))

	return slots


static func circle(count: int, spacing: float, half_w: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	var ring := 1
	while slots.size() < count and ring <= 60:
		var r := minf(float(ring) * spacing * 1.1, half_w)
		var per := maxi(6, int(TAU * r / spacing))
		for i in range(per):
			if slots.size() >= count:
				break
			var a := float(i) / float(per) * TAU
			slots.append(Vector2(cos(a) * r, sin(a) * r + r))
		ring += 1

	return slots
