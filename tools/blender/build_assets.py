"""Builds every 3D model in Fizz Fling and exports each one to assets/models/<name>.glb.

Run inside Blender (through the Blender MCP, or `blender -b -P tools/blender/build_assets.py`).
Everything is made from code, so the whole art set can be rebuilt after a tweak.

Style: cartoon low-poly, flat shaded, plain colours. Blender is Z-up; the glTF exporter
turns it into Godot's Y-up. Sizes are in metres, and the bottle is a slightly chunky
1.5 L soda bottle (32 cm tall) so it reads on a phone screen.
"""
import bpy, bmesh, math, os, random
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__) if "__file__" in dir() else "", "..", ".."))
if not os.path.isdir(os.path.join(ROOT, "assets")):
    ROOT = os.path.expanduser("~/Desktop/project/game/fizz-fling")
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


# ---------------------------------------------------------------- helpers
def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for b in list(coll):
            if b.users == 0:
                coll.remove(b)


def mat(name, rgb, rough=0.7, metal=0.0, alpha=1.0, image=None):
    """rgb is a screen colour (sRGB, as picked in a colour picker); Blender wants linear."""
    rgb = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1:
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image, check_existing=True)
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    m.diffuse_color = (*rgb, alpha)
    return m


def obj_from_bm(name, bm, material=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if material:
        me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = False
    return o


def lathe(name, profile, seg=16, material=None, radial=None, cap_bottom=True, cap_top=True, uv=False):
    """Revolve a list of (radius, z) points round Z. radial(r, z, angle) may reshape a ring."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap") if uv else None
    rings = []
    for r, z in profile:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = radial(r, z, a) if radial else r
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
        rings.append(ring)
    zs = [p[1] for p in profile]
    z0, z1 = min(zs), max(zs)
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            if uvl:
                for loop, (u, v) in zip(f.loops, ((i, k), (i + 1, k), (i + 1, k + 1), (i, k + 1))):
                    loop[uvl].uv = (u / seg, (profile[v][1] - z0) / (z1 - z0))
    if cap_bottom and profile[0][0] > 0:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 0:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, material)


def blob(name, center, radius, material, squash=(1, 1, 1), jitter=0.12, subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in bm.verts:
        v.co *= 1 + random.uniform(-jitter, jitter)
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2])) + Vector(center)
    return obj_from_bm(name, bm, material)


def box(name, size, loc, material, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    o = obj_from_bm(name, bm, material)
    o.location = loc
    o.rotation_euler = rot
    return o


def cyl(name, r, h, loc, material, seg=8, rot=(0, 0, 0)):
    o = lathe(name, [(r, 0), (r, h)], seg=seg, material=material)
    o.location = loc
    o.rotation_euler = rot
    return o


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # pivot at the world origin (the ground), not at the first part — the game places
    # repeated props by their pivot and would otherwise sink them into the grass
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def export(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_apply=True, export_yup=True)
    return path


# ---------------------------------------------------------------- materials
M = {}
def materials():
    M["plastic"] = mat("BottlePlastic", (0.55, 0.85, 0.62), rough=0.08, alpha=0.35)
    M["soda"] = mat("Soda", (1.0, 0.45, 0.05), rough=0.15)
    M["label"] = mat("Label", (1, 1, 1), rough=0.5,
                     image=os.path.join(ROOT, "assets", "textures", "label.png"))
    M["cap"] = mat("CapRed", (0.9, 0.12, 0.14), rough=0.45)
    M["wood"] = mat("Wood", (0.62, 0.38, 0.2), rough=0.9)
    M["wood_dark"] = mat("WoodDark", (0.42, 0.25, 0.13), rough=0.9)
    M["leaf"] = mat("Leaf", (0.27, 0.62, 0.22), rough=0.9)
    M["leaf2"] = mat("LeafDark", (0.16, 0.45, 0.2), rough=0.9)
    M["bark"] = mat("Bark", (0.4, 0.26, 0.16), rough=1.0)
    M["cloud"] = mat("Cloud", (1, 1, 1), rough=1.0)
    M["white"] = mat("SignWhite", (0.97, 0.96, 0.9), rough=0.8)
    M["gold"] = mat("Gold", (1.0, 0.76, 0.12), rough=0.35, metal=0.6)
    M["pole"] = mat("Pole", (0.85, 0.85, 0.88), rough=0.4, metal=0.5)
    M["rock"] = mat("Rock", (0.58, 0.58, 0.6), rough=1.0)
    M["flower_y"] = mat("FlowerYellow", (1.0, 0.85, 0.2))
    M["flower_p"] = mat("FlowerPink", (1.0, 0.45, 0.7))
    M["cloth"] = mat("Cloth", (0.95, 0.3, 0.3), rough=0.9)


# ---------------------------------------------------------------- the bottle
BOTTLE_PROFILE = [  # (radius, z) of the outer wall, bottom to lip
    (0.000, 0.000), (0.030, 0.000), (0.042, 0.008), (0.046, 0.025), (0.045, 0.045),
    (0.046, 0.060), (0.043, 0.066), (0.046, 0.072), (0.046, 0.185), (0.043, 0.191),
    (0.046, 0.197), (0.046, 0.215), (0.043, 0.235), (0.034, 0.258), (0.022, 0.276),
    (0.016, 0.286), (0.016, 0.289), (0.021, 0.290), (0.021, 0.293), (0.015, 0.294),
    (0.015, 0.318),
]


def petaloid(r, z, a):
    """The five 'feet' moulded into the base of a real soda bottle."""
    if z < 0.03 and r > 0:
        k = 1 - z / 0.03
        return r * (1 - 0.13 * k * (0.5 - 0.5 * math.cos(5 * a)))
    return r


def build_bottle():
    body = lathe("Bottle", BOTTLE_PROFILE, seg=20, material=M["plastic"], radial=petaloid, cap_top=False)
    # the soda inside: origin at the base so the game can scale it down as the bottle empties
    liquid_prof = [(0.0, 0.004), (0.038, 0.004), (0.041, 0.02), (0.041, 0.235), (0.037, 0.24)]
    liquid = lathe("Liquid", liquid_prof, seg=20, material=M["soda"], radial=petaloid)
    label = lathe("Label", [(0.0475, 0.074), (0.0475, 0.183)], seg=20, material=M["label"],
                  cap_bottom=False, cap_top=False, uv=True)
    # the bottle reads as plastic only with smooth shading; the props stay faceted
    for o in (body, liquid, label):
        for p in o.data.polygons:
            p.use_smooth = True
    liquid.parent = body
    label.parent = body
    return body


def build_cap():
    """28 mm-style cap: ridged side, flat top. Origin at its middle so it spins cleanly."""
    seg = 32
    prof = [(0.0, -0.011), (0.0205, -0.011), (0.0205, 0.009), (0.019, 0.011), (0.0, 0.011)]
    cap = lathe("Cap", prof, seg=seg, material=M["cap"])
    # grip ridges: push every other vertical edge outwards
    for v in cap.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if rr > 0.0195 and -0.0105 < v.co.z < 0.0085:
            a = math.atan2(v.co.y, v.co.x)
            idx = round(a / (2 * math.pi / seg))
            if idx % 2 == 0:
                s = 1.07
                v.co.x *= s; v.co.y *= s
    return cap


# ---------------------------------------------------------------- park props
def build_table():
    top = box("Top", (1.6, 0.72, 0.05), (0, 0, 0.76), M["wood"])
    parts = [top]
    for y in (-0.62, 0.62):
        parts.append(box("Seat", (1.6, 0.26, 0.045), (0, y, 0.45), M["wood"]))
    for x in (-0.62, 0.62):
        for side in (-1, 1):
            leg = box("Leg", (0.07, 0.07, 1.05), (x, side * 0.33, 0.39), M["wood_dark"],
                      rot=(side * math.radians(38), 0, 0))
            parts.append(leg)
        parts.append(box("Brace", (0.06, 1.46, 0.06), (x, 0, 0.41), M["wood_dark"]))
    # a folded red cloth under the bottle so the launch spot reads from far away
    parts.append(box("Cloth", (0.34, 0.34, 0.006), (0, 0, 0.788), M["cloth"]))
    return join("PicnicTable", parts)


def build_tree(kind):
    parts = []
    if kind == "round":
        parts.append(cyl("Trunk", 0.16, 1.6, (0, 0, 0), M["bark"], seg=7))
        for c, r in (((0, 0, 2.2), 1.05), ((0.55, 0.2, 1.9), 0.75), ((-0.45, -0.3, 2.0), 0.7), ((0.1, -0.1, 2.85), 0.65)):
            parts.append(blob("Leaves", c, r, M["leaf"]))
    elif kind == "pine":
        parts.append(cyl("Trunk", 0.14, 0.9, (0, 0, 0), M["bark"], seg=6))
        for i, (r, z) in enumerate(((1.0, 0.7), (0.78, 1.45), (0.55, 2.15))):
            cone = lathe("Cone", [(0.0, z), (r, z), (0.0, z + 1.15)], seg=8, material=M["leaf2"])
            for v in cone.data.vertices:
                v.co.x *= 1 + random.uniform(-0.08, 0.08); v.co.y *= 1 + random.uniform(-0.08, 0.08)
            parts.append(cone)
    return join("Tree_" + kind, parts)


def build_bush():
    parts = [blob("B", (0, 0, 0.3), 0.45, M["leaf"], squash=(1.2, 1, 0.8)),
             blob("B", (0.45, 0.15, 0.25), 0.33, M["leaf2"], squash=(1, 1, 0.85)),
             blob("B", (-0.4, -0.1, 0.22), 0.3, M["leaf"])]
    for i in range(5):
        a = random.uniform(0, 6.28)
        parts.append(blob("F", (0.5 * math.cos(a), 0.4 * math.sin(a), random.uniform(0.35, 0.6)), 0.05,
                          M["flower_y"] if i % 2 else M["flower_p"], subdiv=0, jitter=0))
    return join("Bush", parts)


def build_cloud():
    parts = [blob("C", (0, 0, 0), 1.3, M["cloud"], squash=(1.4, 1, 0.7), jitter=0.05),
             blob("C", (1.4, 0.2, -0.2), 0.95, M["cloud"], squash=(1.3, 1, 0.7), jitter=0.05),
             blob("C", (-1.3, -0.1, -0.25), 0.9, M["cloud"], squash=(1.3, 1, 0.7), jitter=0.05),
             blob("C", (0.4, 0.1, 0.55), 0.8, M["cloud"], squash=(1.2, 1, 0.8), jitter=0.05)]
    return join("Cloud", parts)


def build_sign():
    """Distance board: the number is written on it in Godot (Label3D), so one model serves every sign."""
    parts = [box("Post", (0.1, 0.1, 1.4), (0, 0, 0.7), M["wood_dark"]),
             box("Board", (1.3, 0.08, 0.7), (0, 0, 1.45), M["white"]),
             box("Rim", (1.4, 0.07, 0.8), (0, 0.012, 1.45), M["wood"])]
    return join("DistanceSign", parts)


def build_flag():
    """Best-distance flag, planted where the player's record landed."""
    pole = cyl("Pole", 0.025, 2.0, (0, 0, 0), M["pole"], seg=6)
    bm = bmesh.new()
    a = bm.verts.new((0, 0, 1.95)); b = bm.verts.new((0.75, 0, 1.72)); c = bm.verts.new((0, 0, 1.45))
    bm.faces.new((a, b, c))
    flag = obj_from_bm("Cloth", bm, M["gold"])
    solid = flag.modifiers.new("Solid", "SOLIDIFY"); solid.thickness = 0.02
    knob = blob("Knob", (0, 0, 2.02), 0.05, M["gold"], subdiv=1, jitter=0)
    return join("BestFlag", [pole, flag, knob])


def build_fence():
    parts = []
    for x in (-1.0, 0.0, 1.0):
        parts.append(box("Post", (0.1, 0.1, 0.9), (x, 0, 0.45), M["wood_dark"]))
    for z in (0.35, 0.7):
        parts.append(box("Rail", (2.1, 0.05, 0.1), (0, 0, z), M["wood"]))
    return join("Fence", parts)


def build_rock():
    r = blob("Rock", (0, 0, 0.12), 0.3, M["rock"], squash=(1.3, 1, 0.6), jitter=0.2, subdiv=1)
    return r


# ---------------------------------------------------------------- run
def main():
    reset()
    materials()
    made = {}
    for name, fn in (("bottle", build_bottle), ("cap", build_cap), ("table", build_table),
                     ("tree_round", lambda: build_tree("round")), ("tree_pine", lambda: build_tree("pine")),
                     ("bush", build_bush), ("cloud", build_cloud), ("sign", build_sign),
                     ("flag", build_flag), ("fence", build_fence), ("rock", build_rock)):
        o = fn()
        made[name] = o
        export(name, [o])
    # lay everything out side by side for a look in the viewport
    x = -6.0
    for name, o in made.items():
        o.location.x = x
        x += 1.4 if name in ("bottle", "cap", "rock", "flag") else 3.2
    made["bottle"].scale = made["cap"].scale = (6, 6, 6)
    return {k: [round(v, 3) for v in o.dimensions] for k, o in made.items()}


result = main()
print(result)
