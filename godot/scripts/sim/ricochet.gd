class_name Ricochet
extends RefCounted
## Manual reflection maths. No physics engine, by design.
##
## Godot's physics server would happily bounce a body off a wall, and the
## result would be unreproducible: solver iteration counts, contact ordering
## and floating-point accumulation inside the engine are not part of our save
## state. A replay has to land on the same pixel, so every bounce here is a
## closed-form reflection the simulation owns end to end.
##
## All functions are static and side-effect free. The simulation passes state
## in and gets numbers back, which keeps them trivially unit-testable.

## Minimum angle away from a surface after a bounce, in degrees. Without this
## a bullet that grazes a wall reflects almost parallel to it and skitters
## along the surface for the rest of its life, which reads as a stuck bullet.
const MIN_EXIT_ANGLE_DEG := 12.0

const EPSILON := 0.0001


## Mirrors a direction about a surface normal. Both vectors are unit length.
static func reflect(direction: Vector2, normal: Vector2) -> Vector2:
	return (direction - 2.0 * direction.dot(normal) * normal).normalized()


## Reflection, then pushed off the surface if it came out too shallow.
static func reflect_safe(direction: Vector2, normal: Vector2) -> Vector2:
	var out := reflect(direction, normal)
	var min_sin := sin(deg_to_rad(MIN_EXIT_ANGLE_DEG))
	var along := out.dot(normal)
	if along >= min_sin:
		return out
	var tangent := Vector2(-normal.y, normal.x)
	if out.dot(tangent) < 0.0:
		tangent = -tangent
	var corrected := normal * min_sin + tangent * sqrt(1.0 - min_sin * min_sin)
	return corrected.normalized()


## Rotates a direction on the XZ plane, used by bullet steering.
static func rotate_xz(direction: Vector2, degrees: float) -> Vector2:
	return direction.rotated(deg_to_rad(degrees)).normalized()


## Time until a moving point crosses the left or right wall.
##
## Returns the travel fraction in [0, 1] and the wall normal, or a miss.
static func sweep_side_walls(
	origin: Vector2, motion: Vector2, radius: float, x_min: float, x_max: float
) -> Dictionary:
	var best_t := 2.0
	var normal := Vector2.ZERO
	if motion.x < -EPSILON:
		var t_left := (x_min + radius - origin.x) / motion.x
		if t_left >= 0.0 and t_left < best_t:
			best_t = t_left
			normal = Vector2(1.0, 0.0)
	elif motion.x > EPSILON:
		var t_right := (x_max - radius - origin.x) / motion.x
		if t_right >= 0.0 and t_right < best_t:
			best_t = t_right
			normal = Vector2(-1.0, 0.0)
	if best_t > 1.0:
		return {"hit": false}
	return {"hit": true, "t": best_t, "normal": normal}


## Time until a moving circle crosses a horizontal line at z, travelling up.
static func sweep_top_wall(
	origin: Vector2, motion: Vector2, radius: float, z_max: float
) -> Dictionary:
	if motion.y <= EPSILON:
		return {"hit": false}
	var t := (z_max - radius - origin.y) / motion.y
	if t < 0.0 or t > 1.0:
		return {"hit": false}
	return {"hit": true, "t": t, "normal": Vector2(0.0, -1.0)}


## Swept circle against a static circle: the standard quadratic, solved for
## the first root inside the step. Discrete distance checks tunnel straight
## through small targets at 25 units per second, so this is not optional.
static func sweep_circle(
	origin: Vector2, motion: Vector2, radius: float, center: Vector2, target_radius: float
) -> Dictionary:
	var to_target := origin - center
	var combined := radius + target_radius
	var a := motion.dot(motion)
	if a < EPSILON:
		return {"hit": false}
	var b := 2.0 * to_target.dot(motion)
	var c := to_target.dot(to_target) - combined * combined
	if c < 0.0:
		var inside_normal := to_target.normalized() if to_target.length() > EPSILON else Vector2.UP
		return {"hit": true, "t": 0.0, "normal": inside_normal}
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return {"hit": false}
	var root := sqrt(disc)
	var t := (-b - root) / (2.0 * a)
	if t < 0.0 or t > 1.0:
		return {"hit": false}
	var contact := origin + motion * t
	return {"hit": true, "t": t, "normal": (contact - center).normalized()}


## Swept circle against an axis-aligned band, used for gates and platforms.
static func sweep_band(
	origin: Vector2, motion: Vector2, radius: float, band_z: float, half_height: float
) -> Dictionary:
	var reach := half_height + radius
	var relative := origin.y - band_z
	if absf(relative) <= reach:
		return {"hit": true, "t": 0.0}
	if absf(motion.y) < EPSILON:
		return {"hit": false}
	var target := band_z + (reach if relative > 0.0 else -reach)
	var t := (target - origin.y) / motion.y
	if t < 0.0 or t > 1.0:
		return {"hit": false}
	return {"hit": true, "t": t}


## Predicts the aim line for the HUD indicator.
##
## This deliberately re-runs the same wall maths the simulation uses. An
## indicator drawn with its own simplified maths is a promise the game then
## breaks, and players read that as the physics being random.
static func predict_path(
	origin: Vector2,
	direction: Vector2,
	radius: float,
	bounces: int,
	x_min: float,
	x_max: float,
	z_max: float,
	top_absorbs: bool
) -> PackedVector2Array:
	var points := PackedVector2Array([origin])
	var position := origin
	var heading := direction.normalized()
	var remaining := bounces
	while remaining >= 0:
		var motion := heading * 200.0
		var side: Dictionary = sweep_side_walls(position, motion, radius, x_min, x_max)
		var top: Dictionary = sweep_top_wall(position, motion, radius, z_max)
		var use_top: bool = (
			top.get("hit", false)
			and (not side.get("hit", false) or float(top["t"]) < float(side["t"]))
		)
		var chosen: Dictionary = top if use_top else side
		if not chosen.get("hit", false):
			points.append(position + heading * 200.0)
			break
		var contact: Vector2 = position + motion * float(chosen["t"])
		points.append(contact)
		if use_top and top_absorbs:
			break
		heading = reflect_safe(heading, chosen["normal"])
		position = contact + heading * 0.02
		remaining -= 1
	return points
