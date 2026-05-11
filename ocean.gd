extends MeshInstance3D

@export var target_node: Node3D # Dein Schiff oder die Kamera

func _process(_delta):
	if target_node:
		var grid_size = 1.0 # Muss zur Subdivision deines Meshes passen
		var new_pos = target_node.global_position
		# Snapping: Das Mesh bewegt sich nur in "Sprüngen" der Grid-Größe
		global_position = Vector3(
			floor(new_pos.x / grid_size) * grid_size,
			0,
			floor(new_pos.z / grid_size) * grid_size
		)
