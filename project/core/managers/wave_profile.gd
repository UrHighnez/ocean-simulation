@tool
class_name WaveProfile
extends Resource

## Wave parameters shared between shader uniforms and CPU sampling.
## Identical values guarantee that rendering and physics stay in sync.

## Primary wind direction in degrees (0 = +X axis).
@export_range(0.0, 360.0) var wind_direction_degrees: float = 0.0:
	set(value):
		wind_direction_degrees = value
		emit_changed()

## Storm strength. Scales amplitude and wave speed non-linearly.
@export_range(0.0, 1.0) var storm_intensity: float = 0.2:
	set(value):
		storm_intensity = value
		emit_changed()

## Global multiplier for wavelength and amplitude.
@export var global_wave_scale: float = 1.0:
	set(value):
		global_wave_scale = value
		emit_changed()

## Gerstner steepness. High values produce sharp crests but can cause
## vertex self-intersection ("pinching").
@export_range(0.0, 1.5) var global_steepness: float = 0.8:
	set(value):
		global_steepness = value
		emit_changed()

## Animation speed of the wave motion.
@export var time_scale: float = 0.7:
	set(value):
		time_scale = value
		emit_changed()

## Number of stacked Gerstner waves.
@export_range(1, 8) var wave_iterations: int = 5:
	set(value):
		wave_iterations = value
		emit_changed()


## Samples the water surface at a world position and time.
## Returns a Dictionary with "position" (Vector3) and "normal" (Vector3).
func sample(world_xz: Vector2, time: float) -> Dictionary:
	var tangent := Vector3(1.0, 0.0, 0.0)
	var binormal := Vector3(0.0, 0.0, 1.0)
	var pos := Vector3(world_xz.x, 0.0, world_xz.y)

	var storm_scale: float = lerpf(0.05, 2.5, storm_intensity)
	var storm_multiplier: float = 0.85 * storm_scale

	var frequency: float = 0.2 / global_wave_scale
	var amplitude: float = 1.5 * global_wave_scale * storm_multiplier
	var speed: float = 2.0 * time_scale * lerpf(0.2, 1.8, storm_intensity)

	var wind_dir := Vector2.RIGHT.rotated(deg_to_rad(wind_direction_degrees))

	for i in wave_iterations:
		var dir := wind_dir.rotated(deg_to_rad(float(i) * 27.5))

		var k: float = frequency
		var a: float = amplitude
		var steepness: float = global_steepness / (float(wave_iterations) * a * k)

		var f: float = dir.dot(world_xz) * k - time * speed
		var sin_f := sin(f)
		var cos_f := cos(f)

		pos.x += dir.x * (steepness * a * cos_f)
		pos.z += dir.y * (steepness * a * cos_f)
		pos.y += a * sin_f

		var wa: float = k * a
		tangent.x -= dir.x * dir.x * (steepness * wa * sin_f)
		tangent.y += dir.x * (wa * cos_f)
		tangent.z -= dir.x * dir.y * (steepness * wa * sin_f)

		binormal.x -= dir.x * dir.y * (steepness * wa * sin_f)
		binormal.y += dir.y * (wa * cos_f)
		binormal.z -= dir.y * dir.y * (steepness * wa * sin_f)

		frequency *= 1.8
		amplitude *= 0.45
		speed *= 1.1

	return {
		"position": pos,
		"normal": binormal.cross(tangent).normalized(),
	}


## Convenience wrapper: only the Y coordinate of the water surface.
func sample_height(world_xz: Vector2, time: float) -> float:
	return (sample(world_xz, time)["position"] as Vector3).y


## Convenience wrapper: only the surface normal.
func sample_normal(world_xz: Vector2, time: float) -> Vector3:
	return sample(world_xz, time)["normal"]
