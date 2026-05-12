extends Node3D

@export var water_material: ShaderMaterial

@export var camera: Camera3D
@export var chunk_size: float = 50.0
@export var grid_radius: int = 4 # Ergibt ein 9x9 Gitter (4 in jede Richtung + Mitte)

# Lade deine vorbereiteten Meshes
@export var mesh_high: PlaneMesh
@export var mesh_med: PlaneMesh
@export var mesh_low: PlaneMesh

var chunks = {} # Speichert unsere Chunk-Instanzen

func _ready():
	# Generiere das initiale Gitter
	for x in range(-grid_radius, grid_radius + 1):
		for z in range(-grid_radius, grid_radius + 1):
			var chunk_pos = Vector2(x, z)
			_create_chunk(chunk_pos)

func _create_chunk(grid_pos: Vector2):
	var chunk = MeshInstance3D.new()
	add_child(chunk)
	chunk.material_override = water_material
	chunks[grid_pos] = chunk

func _process(delta):
	if not camera: return
	
	# Finde heraus, in welchem Chunk (Grid-Koordinate) sich die Kamera aktuell befindet
	var cam_grid_pos = Vector2(
		round(camera.global_position.x / chunk_size),
		round(camera.global_position.z / chunk_size)
	)
	
	# Aktualisiere alle Chunks
	for grid_pos in chunks.keys():
		var chunk = chunks[grid_pos]
		
		# 1. TREADMILL-LOGIK: Snapping und Teleportation
		# Wenn der Chunk zu weit von der Kamera entfernt ist, verschiebe ihn auf die andere Seite
		var rel_x = grid_pos.x - cam_grid_pos.x
		var rel_z = grid_pos.y - cam_grid_pos.y
		
		var new_grid_x = grid_pos.x
		var new_grid_z = grid_pos.y
		var needs_move = false
		
		if rel_x > grid_radius: new_grid_x -= (grid_radius * 2 + 1); needs_move = true
		if rel_x < -grid_radius: new_grid_x += (grid_radius * 2 + 1); needs_move = true
		if rel_z > grid_radius: new_grid_z -= (grid_radius * 2 + 1); needs_move = true
		if rel_z < -grid_radius: new_grid_z += (grid_radius * 2 + 1); needs_move = true
		
		if needs_move:
			# Chunk im Dictionary unter neuer Position speichern
			var new_grid_pos = Vector2(new_grid_x, new_grid_z)
			chunks[new_grid_pos] = chunk
			chunks.erase(grid_pos)
			grid_pos = new_grid_pos
		
		# Setze die reale Weltposition des Chunks
		chunk.global_position = Vector3(grid_pos.x * chunk_size, 0, grid_pos.y * chunk_size)
		
		# 2. LOD-LOGIK: Mesh basierend auf Distanz tauschen
		var dist_to_cam = grid_pos.distance_to(cam_grid_pos)
		
		if dist_to_cam <= 1.5:
			chunk.mesh = mesh_high
		elif dist_to_cam <= 3.5:
			chunk.mesh = mesh_med
		else:
			chunk.mesh = mesh_low
