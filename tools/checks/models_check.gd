extends SceneTree
## Checks the Blender models as the game actually uses them: repeated props are drawn with
## MultiMesh from the bare mesh (node transforms dropped), so each mesh must stand on its
## own pivot. On 2026-09-30 the signs were sunk 0.7 m because the pivot sat on the post.

var fails := 0


func check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _init() -> void:
	for n in ["sign", "fence", "tree_round", "tree_pine", "bush", "rock", "table", "flag"]:
		var scene: Node = load("res://assets/models/%s.glb" % n).instantiate()
		var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var box: AABB = mi.mesh.get_aabb()
		check("%s stands on the ground at its own pivot" % n, absf(box.position.y) < 0.08
				and absf(box.position.x + box.size.x * 0.5) < 1.2, "bottom %.3f m" % box.position.y)
		scene.free()
	var sign: Node = load("res://assets/models/sign.glb").instantiate()
	var sb: AABB = (sign.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh.get_aabb()
	check("the sign board is where world.gd writes the number (1.47 m)", sb.position.y + sb.size.y > 1.6 and sb.position.y + sb.size.y < 2.0)
	sign.free()
	var b: Node = load("res://assets/models/bottle.glb").instantiate()
	check("the bottle has its soda inside, to drain", b.find_child("Liquid", true, false) != null)
	b.free()
	print("\n%d failed" % fails)
	quit(1 if fails > 0 else 0)
