extends SceneTree
const CAT=preload("res://zombie_catalog.gd")
func _initialize():call_deferred("run")
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/zombie_motion"))
	for id in CAT.DEFINITIONS:
		var z=load("res://Zombie.tscn").instantiate()
		CAT.configure(z,id)
		root.add_child(z)
		z.set_physics_process(false)
		var generated:ArrayMesh=z.locomotion._build_mesh()
		var error:=ResourceSaver.save(generated,"res://art/zombie_motion/"+id+"_mesh.res")
		if error!=OK:
			push_error("Could not bake "+id)
			quit(1)
			return
		print("BAKED: ",id)
		z.free()
	quit()
