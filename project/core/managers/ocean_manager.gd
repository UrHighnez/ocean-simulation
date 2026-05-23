@tool
class_name OceanManager
extends Node3D

## Manages a camera-tracked chunk grid with LOD and pushes the
## WaveProfile into the shader uniforms.

@export_group("Rendering")

## Shader material applied to every ocean chunk. The wave uniforms here
## are overwritten by the WaveProfile.
@export var water_material: ShaderMaterial

## Source of truth for all wave parameters (shader + buoyancy).
@export var wave_profile: WaveProfile

@export_group("World")

## Camera the chunk grid follows.
@export var camera: Camera3D

## Edge length of a single chunk in meters.
@export var chunk_size: float = 50.0

## Grid radius around the camera, in chunks. Total grid = (2r+1)^2.
@export var grid_radius: int = 7

@export_group("LOD Meshes")

## Highest resolution, used for chunks near the camera.
@export var mesh_high: PlaneMesh

## Medium resolution, mid-distance chunks.
@export var mesh_med: PlaneMesh

## Lowest resolution, far chunks.
@export var mesh_low: PlaneMesh

var chunks: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	chunks.clear()

	if wave_profile and water_material:
		_sync_profile_to_shader()
		if not wave_profile.changed.is_connected(_sync_profile_to_shader):
			wave_profile.changed.connect(_sync_profile_to_shader)

	for x in range(-grid_radius, grid_radius + 1):
		for z in range(-grid_radius, grid_radius + 1):
			_create_chunk(Vector2(x, z))


func _process(_delta: float) -> void:
	if not camera:
		return

	var cam_grid_pos := Vector2(
		round(camera.global_position.x / chunk_size),
		round(camera.global_position.z / chunk_size)
	)

	var pending_moves: Dictionary = {}
	for grid_pos in chunks.keys():
		var rel_x: float = grid_pos.x - cam_grid_pos.x
		var rel_z: float = grid_pos.y - cam_grid_pos.y

		var new_grid_x: float = grid_pos.x
		var new_grid_z: float = grid_pos.y
		var needs_move := false

		if rel_x > grid_radius:
			new_grid_x -= (grid_radius * 2 + 1)
			needs_move = true
		elif rel_x < -grid_radius:
			new_grid_x += (grid_radius * 2 + 1)
			needs_move = true

		if rel_z > grid_radius:
			new_grid_z -= (grid_radius * 2 + 1)
			needs_move = true
		elif rel_z < -grid_radius:
			new_grid_z += (grid_radius * 2 + 1)
			needs_move = true

		if needs_move:
			pending_moves[grid_pos] = Vector2(new_grid_x, new_grid_z)

	for old_pos in pending_moves:
		var new_pos: Vector2 = pending_moves[old_pos]
		var chunk: MeshInstance3D = chunks[old_pos]
		chunks[new_pos] = chunk
		chunks.erase(old_pos)
		chunk.global_position = Vector3(new_pos.x * chunk_size, 0, new_pos.y * chunk_size)

	for grid_pos in chunks:
		var chunk: MeshInstance3D = chunks[grid_pos]
		var dist_to_cam: float = grid_pos.distance_to(cam_grid_pos)

		if dist_to_cam <= 1.5:
			if chunk.mesh != mesh_high:
				chunk.mesh = mesh_high
		elif dist_to_cam <= 3.5:
			if chunk.mesh != mesh_med:
				chunk.mesh = mesh_med
		else:
			if chunk.mesh != mesh_low:
				chunk.mesh = mesh_low


func _sync_profile_to_shader() -> void:
	if not wave_profile or not water_material:
		return
	water_material.set_shader_parameter("wind_direction_degrees", wave_profile.wind_direction_degrees)
	water_material.set_shader_parameter("storm_intensity", wave_profile.storm_intensity)
	water_material.set_shader_parameter("global_wave_scale", wave_profile.global_wave_scale)
	water_material.set_shader_parameter("global_steepness", wave_profile.global_steepness)
	water_material.set_shader_parameter("time_scale", wave_profile.time_scale)
	water_material.set_shader_parameter("wave_iterations", wave_profile.wave_iterations)


func _create_chunk(grid_pos: Vector2) -> void:
	var chunk := MeshInstance3D.new()
	add_child(chunk)
	chunk.material_override = water_material
	chunk.global_position = Vector3(grid_pos.x * chunk_size, 0, grid_pos.y * chunk_size)
	chunk.mesh = mesh_low
	chunks[grid_pos] = chunk
