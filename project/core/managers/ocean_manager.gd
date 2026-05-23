@tool
extends Node3D

@export var water_material: ShaderMaterial
@export var wave_profile: WaveProfile

@export var camera: Camera3D
@export var chunk_size: float = 50.0
@export var grid_radius: int = 7

# Lade deine vorbereiteten Meshes
@export var mesh_high: PlaneMesh
@export var mesh_med: PlaneMesh
@export var mesh_low: PlaneMesh

var chunks = {} # Speichert unsere Chunk-Instanzen

func _ready():
	# WICHTIG FÜR @TOOL: Alte Chunks aus dem Editor löschen,
	# bevor neue generiert werden (verhindert Datenmüll)
	for child in get_children():
		child.queue_free()
	chunks.clear()

	# WaveProfile -> Shader Uniforms. Profile ist die Quelle der Wahrheit.
	if wave_profile and water_material:
		_sync_profile_to_shader()
		if not wave_profile.changed.is_connected(_sync_profile_to_shader):
			wave_profile.changed.connect(_sync_profile_to_shader)

	# Generiere das initiale Gitter
	for x in range(-grid_radius, grid_radius + 1):
		for z in range(-grid_radius, grid_radius + 1):
			var chunk_pos = Vector2(x, z)
			_create_chunk(chunk_pos)


func _sync_profile_to_shader() -> void:
	if not wave_profile or not water_material:
		return
	water_material.set_shader_parameter("wind_direction_degrees", wave_profile.wind_direction_degrees)
	water_material.set_shader_parameter("storm_intensity", wave_profile.storm_intensity)
	water_material.set_shader_parameter("global_wave_scale", wave_profile.global_wave_scale)
	water_material.set_shader_parameter("global_steepness", wave_profile.global_steepness)
	water_material.set_shader_parameter("time_scale", wave_profile.time_scale)
	water_material.set_shader_parameter("wave_iterations", wave_profile.wave_iterations)

func _create_chunk(grid_pos: Vector2):
	var chunk = MeshInstance3D.new()
	add_child(chunk)
	chunk.material_override = water_material
	chunk.global_position = Vector3(grid_pos.x * chunk_size, 0, grid_pos.y * chunk_size)
	
	# LOD Optimization: Default to the lowest polycount mesh for editor stability.
	chunk.mesh = mesh_low 
	
	chunks[grid_pos] = chunk

func _process(_delta):
	if not camera: return
	
	var cam_grid_pos = Vector2(
		round(camera.global_position.x / chunk_size),
		round(camera.global_position.z / chunk_size)
	)
	
	# Temporärer Speicher für anstehende Dictionary-Änderungen
	var pending_moves = {}
	
	# 1. TREADMILL-LOGIK: Evaluierungs-Pass (Nur Lesezugriff auf 'chunks')
	for grid_pos in chunks.keys():
		var rel_x = grid_pos.x - cam_grid_pos.x
		var rel_z = grid_pos.y - cam_grid_pos.y
		
		var new_grid_x = grid_pos.x
		var new_grid_z = grid_pos.y
		var needs_move = false
		
		# Optimierung: Mutually exclusive conditions nutzen 'elif'
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
	
	# 2. DICTIONARY-MUTATION: Ausführungs-Pass
	for old_pos in pending_moves:
		var new_pos = pending_moves[old_pos]
		var chunk = chunks[old_pos]
		
		chunks[new_pos] = chunk
		chunks.erase(old_pos)
		
		# Reale Weltposition des Chunks aktualisieren
		chunk.global_position = Vector3(new_pos.x * chunk_size, 0, new_pos.y * chunk_size)
	
	# 3. LOD-LOGIK: Distanzprüfung (Nachdem alle Verschiebungen abgeschlossen sind)
	for grid_pos in chunks:
		var chunk = chunks[grid_pos]
		var dist_to_cam = grid_pos.distance_to(cam_grid_pos)
		
		if dist_to_cam <= 1.5:
			if chunk.mesh != mesh_high: chunk.mesh = mesh_high
		elif dist_to_cam <= 3.5:
			if chunk.mesh != mesh_med: chunk.mesh = mesh_med
		else:
			if chunk.mesh != mesh_low: chunk.mesh = mesh_low
