class_name Buoyancy3D
extends Node3D

## Buoyancy component for a RigidBody3D parent. Samples the WaveProfile
## at N hull points and applies buoyancy forces plus water drag.
## Produces natural rocking motion from the physics solver.

@export_group("References")

## Source of truth for the waves. Must be the same profile as on the
## OceanManager, otherwise rendering and physics drift apart.
@export var wave_profile: WaveProfile

## Hull sample points. Add them as children of the RigidBody3D (so they
## rotate with the body), then reference them here. More points = smoother
## buoyancy at a small cost.
@export var sample_points: Array[Marker3D] = []

@export_group("Forces")

## Buoyancy force per meter of submersion. Tune until the body rests at
## the desired waterline (equilibrium: d_avg * buoyancy_force = mass * gravity).
@export var buoyancy_force: float = 100.0

## Linear damping. Scales with the fraction of submerged sample points.
@export var water_drag: float = 4.0

## Angular damping. Scales with the fraction of submerged sample points.
@export var angular_drag: float = 2.0

var _body: RigidBody3D
var _time: float = 0.0


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if not _body:
		push_warning("Buoyancy3D: parent is not a RigidBody3D")


func _physics_process(delta: float) -> void:
	if not _body or not wave_profile or sample_points.is_empty():
		return

	_time += delta

	var submerged_count := 0
	var force_share: float = 1.0 / float(sample_points.size())

	for mp in sample_points:
		if not mp:
			continue
		var p := mp.global_position
		var water_y := wave_profile.sample_height(Vector2(p.x, p.z), _time)
		var submersion: float = water_y - p.y
		if submersion > 0.0:
			submerged_count += 1
			var force: Vector3 = Vector3.UP * submersion * buoyancy_force * force_share
			var lever: Vector3 = p - _body.global_position
			_body.apply_force(force, lever)

	if submerged_count > 0:
		var fraction: float = float(submerged_count) / float(sample_points.size())
		_body.apply_central_force(-_body.linear_velocity * water_drag * fraction)
		_body.apply_torque(-_body.angular_velocity * angular_drag * fraction)
