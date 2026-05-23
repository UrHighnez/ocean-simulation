extends Node3D
@export var profile: WaveProfile
var time := 0.0

func _process(delta):
	if not profile: return
	time += delta
	global_position.y = profile.sample_height(
		Vector2(global_position.x, global_position.z), time)
