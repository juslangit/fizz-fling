class_name Drinks
extends RefCounted
## The drinks you can shake. Each is the same Blender bottle with its own label, soda colour
## and cap, and its own fizz: how much pressure the same shaking builds (`gain`), how hard the
## cap leaves (`cap`), how fast and how long the soda sprays (`spray`, `spray_time`).
## They are balanced so a perfect throw totals about the same with every drink
## (tools/checks/physics_check.gd holds them to within 10%); they differ in *how* they score.

const LIST := [
	{"id": "orange", "name": "FIZZ ORANGE", "trait": "The all-rounder",
		"label": "res://assets/textures/label_orange.png", "liquid": Color(1.0, 0.5, 0.06),
		"glow": Color(0.45, 0.16, 0.0), "plastic": Color(0.75, 0.95, 0.8, 0.3), "cap": Color(0.9, 0.12, 0.14),
		"drop": Color(0.95, 0.32, 0.02), "drop2": Color(1.0, 0.5, 0.1), "splat": Color(1.0, 0.62, 0.25),
		"gain": 1.0, "cap_speed": 1.0, "spray": 1.0, "spray_time": 1.0},
	{"id": "cola", "name": "COLA", "trait": "Foams up fast, big spray",
		"label": "res://assets/textures/label_cola.png", "liquid": Color(0.28, 0.08, 0.03),
		"glow": Color(0.08, 0.02, 0.0), "plastic": Color(0.85, 0.9, 0.88, 0.25), "cap": Color(0.85, 0.08, 0.1),
		"drop": Color(0.35, 0.12, 0.04), "drop2": Color(0.55, 0.25, 0.1), "splat": Color(0.75, 0.55, 0.4),
		"gain": 1.25, "cap_speed": 0.94, "spray": 1.18, "spray_time": 1.3},
	{"id": "bandung", "name": "SIRAP BANDUNG", "trait": "Creamy, the longest spray",
		"label": "res://assets/textures/label_bandung.png", "liquid": Color(1.0, 0.58, 0.72),
		"glow": Color(0.4, 0.12, 0.2), "plastic": Color(0.95, 0.9, 0.95, 0.28), "cap": Color(0.98, 0.98, 0.98),
		"drop": Color(1.0, 0.55, 0.7), "drop2": Color(1.0, 0.75, 0.85), "splat": Color(1.0, 0.8, 0.88),
		"gain": 0.9, "cap_speed": 0.9, "spray": 1.32, "spray_time": 1.5},
	{"id": "sparkling", "name": "SPARKLING WATER", "trait": "Hard to shake, the cap rockets",
		"label": "res://assets/textures/label_sparkling.png", "liquid": Color(0.78, 0.92, 1.0),
		"glow": Color(0.1, 0.2, 0.3), "plastic": Color(0.8, 0.92, 1.0, 0.25), "cap": Color(0.15, 0.45, 0.95),
		"drop": Color(0.75, 0.9, 1.0), "drop2": Color(1.0, 1.0, 1.0), "splat": Color(0.85, 0.95, 1.0),
		"gain": 0.8, "cap_speed": 1.1, "spray": 0.72, "spray_time": 0.7},
]


static func get_drink(id: String) -> Dictionary:
	for d in LIST:
		if d.id == id:
			return d
	return LIST[0]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i].id == id:
			return i
	return 0
