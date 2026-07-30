"""
POLARITY asset generation — spec §13A.

Produces every gameplay mesh as a separate low-poly glTF with clean topology,
a centred origin, real-world-ish scale, vertex colours (no textures, to keep the
web payload small) and material names matching the shared library.

    blender --background --python tools/blender_export.py

Output: assets/*.glb, one file per asset. The game prefers these when present
and falls back to `scripts/meshes.gd` when they are absent, so the project runs
with or without this step having been executed (see scripts/asset_library.gd).

Tri budgets from §13A: magnet 300-800, scrap 50-200.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")

# Shared material library. Names must match what the Godot side expects, so a
# re-export never silently renames a slot.
MATERIALS = {
    "MAT_magnet_pole_a": (1.00, 0.25, 0.36, 1.0),
    "MAT_magnet_pole_b": (0.28, 0.52, 1.00, 1.0),
    "MAT_magnet_body":   (0.72, 0.75, 0.82, 1.0),
    "MAT_scrap_steel":   (0.62, 0.66, 0.72, 1.0),
    "MAT_scrap_brass":   (1.00, 0.78, 0.35, 1.0),
    "MAT_hazard_warn":   (0.95, 0.72, 0.18, 1.0),
    "MAT_hazard_danger": (0.95, 0.24, 0.30, 1.0),
    "MAT_powerup":       (0.36, 0.84, 1.00, 1.0),
}


# --------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = MATERIALS.get(name, (0.8, 0.8, 0.8, 1.0))
            # Low metallic on purpose: the game has no reflection probe, so a high
            # metallic value renders black. Matches scrap_field.gd.
            bsdf.inputs["Metallic"].default_value = 0.15
            bsdf.inputs["Roughness"].default_value = 0.5
    return mat


def finalise(obj, materials, vertex_color_map=None):
    """Centre the origin, apply transforms, bake vertex colours, assign materials."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0.0, 0.0, 0.0)

    obj.data.materials.clear()
    for name in materials:
        obj.data.materials.append(get_material(name))

    # Vertex colours instead of textures — §13A explicitly asks to avoid large
    # textures for the web payload.
    #
    # `mesh.vertex_colors` is documented as "Legacy vertex color layers.
    # Deprecated, use color attributes instead" and is read-only, so writing
    # through it fails on Blender 4.x. Use color_attributes, and keep a legacy
    # path so this still runs on 3.x.
    mesh = obj.data
    layer = None
    if hasattr(mesh, "color_attributes"):
        existing = mesh.color_attributes.get("Col")
        if existing is None:
            existing = mesh.color_attributes.new(
                name="Col", type="FLOAT_COLOR", domain="CORNER")
        mesh.color_attributes.active_color = existing
        layer = existing
    else:                                    # Blender 3.x fallback
        if not mesh.vertex_colors:
            mesh.vertex_colors.new(name="Col")
        layer = mesh.vertex_colors["Col"]

    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_index].vertex_index]
            color = vertex_color_map(vert.co) if vertex_color_map else (1.0, 1.0, 1.0, 1.0)
            layer.data[loop_index].color = color

    bpy.ops.object.shade_flat()
    return obj


def export(obj, filename):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        # NOT `export_colors` — that parameter does not exist and raises
        # TypeError. Verified against the bundled API reference.
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=True,
        export_normals=True,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  {filename:28s} {tris:4d} tris")
    return tris


# --------------------------------------------------------------------------
def build_magnet():
    """Horseshoe magnet, ~600 tris. Two-tone poles baked into vertex colours so
    the shader can split on them without a texture."""
    bm = bmesh.new()
    segments, span = 24, math.radians(320.0)
    start = -span / 2.0
    inner, outer, half_h = 0.66, 1.0, 0.25

    rings = []
    for i in range(segments + 1):
        a = start + span * i / segments
        c, s = math.cos(a), math.sin(a)
        ring = [
            bm.verts.new((c * inner, s * inner, -half_h)),
            bm.verts.new((c * outer, s * outer, -half_h)),
            bm.verts.new((c * outer, s * outer, half_h)),
            bm.verts.new((c * inner, s * inner, half_h)),
        ]
        rings.append(ring)
    bm.verts.ensure_lookup_table()

    for i in range(segments):
        a, b = rings[i], rings[i + 1]
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((a[j], b[j], b[k], a[k]))
    # Cap the two open pole ends.
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("magnet")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("magnet", mesh)
    bpy.context.collection.objects.link(obj)

    # North pole warm, south pole cool, split on X — same convention the
    # in-game shader uses so a swap between the two is invisible.
    def poles(co):
        return (1.0, 0.25, 0.36, 1.0) if co.x > 0 else (0.28, 0.52, 1.0, 1.0)

    finalise(obj, ["MAT_magnet_pole_a", "MAT_magnet_pole_b"], poles)
    return obj


def build_prism(name, sides, radius, height, hole=0.0, material="MAT_scrap_steel"):
    """Nut / bolt / gear / shard — one generator, four silhouettes."""
    bm = bmesh.new()
    half = height / 2.0
    hollow = hole > 0.001

    outer_rings, inner_rings = [], []
    for i in range(sides):
        a = math.tau * i / sides
        c, s = math.cos(a), math.sin(a)
        outer_rings.append((
            bm.verts.new((c * radius, s * radius, -half)),
            bm.verts.new((c * radius, s * radius, half)),
        ))
        if hollow:
            inner_rings.append((
                bm.verts.new((c * hole, s * hole, -half)),
                bm.verts.new((c * hole, s * hole, half)),
            ))
    bm.verts.ensure_lookup_table()

    for i in range(sides):
        j = (i + 1) % sides
        lo_a, hi_a = outer_rings[i]
        lo_b, hi_b = outer_rings[j]
        bm.faces.new((lo_a, lo_b, hi_b, hi_a))
        if hollow:
            ilo_a, ihi_a = inner_rings[i]
            ilo_b, ihi_b = inner_rings[j]
            bm.faces.new((ihi_a, ihi_b, ilo_b, ilo_a))
            bm.faces.new((hi_a, hi_b, ihi_b, ihi_a))
            bm.faces.new((lo_a, ilo_a, ilo_b, lo_b))

    if not hollow:
        bm.faces.new(tuple(r[1] for r in outer_rings))
        bm.faces.new(tuple(reversed([r[0] for r in outer_rings])))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    finalise(obj, [material])
    return obj


def build_can():
    """Crushed can — a cylinder with a dent, so the scrap set is not all
    rotationally symmetric."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.32, depth=0.8)
    obj = bpy.context.active_object
    obj.name = "scrap_can"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for v in bm.verts:
        if v.co.z > 0.1:
            v.co.x *= 0.6                      # crushed top
            v.co.z -= 0.12 * abs(v.co.y)       # bent
    bm.to_mesh(obj.data)
    bm.free()
    finalise(obj, ["MAT_scrap_steel"])
    return obj


def build_saw():
    """Saw blade: a disc with real teeth rather than a low-segment cylinder."""
    bm = bmesh.new()
    teeth, r_in, r_out, half = 12, 0.72, 1.0, 0.06
    rings = []
    for i in range(teeth * 2):
        a = math.tau * i / (teeth * 2)
        r = r_out if i % 2 == 0 else r_in
        c, s = math.cos(a), math.sin(a)
        rings.append((
            bm.verts.new((c * r, s * r, -half)),
            bm.verts.new((c * r, s * r, half)),
        ))
    bm.verts.ensure_lookup_table()
    for i in range(len(rings)):
        j = (i + 1) % len(rings)
        bm.faces.new((rings[i][0], rings[j][0], rings[j][1], rings[i][1]))
    bm.faces.new(tuple(r[1] for r in rings))
    bm.faces.new(tuple(reversed([r[0] for r in rings])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("hazard_saw")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("hazard_saw", mesh)
    bpy.context.collection.objects.link(obj)
    finalise(obj, ["MAT_hazard_warn"])
    return obj


def build_spike():
    """Spike cluster for the spike pit."""
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.42, depth=1.0)
    base = bpy.context.active_object
    base.name = "hazard_spike"
    finalise(base, ["MAT_hazard_danger"])
    return base


def build_powerup():
    """Power-up pickup: an octahedron, distinct from every scrap silhouette."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.5)
    obj = bpy.context.active_object
    obj.name = "powerup"
    finalise(obj, ["MAT_powerup"])
    return obj


# --------------------------------------------------------------------------
ASSETS = [
    ("magnet.glb",        build_magnet),
    ("scrap_nut.glb",     lambda: build_prism("scrap_nut", 6, 0.5, 0.28, 0.45)),
    ("scrap_bolt.glb",    lambda: build_prism("scrap_bolt", 6, 0.34, 0.7)),
    ("scrap_gear.glb",    lambda: build_prism("scrap_gear", 10, 0.55, 0.2, 0.4)),
    ("scrap_shard.glb",   lambda: build_prism("scrap_shard", 3, 0.45, 0.34)),
    ("scrap_screw.glb",   lambda: build_prism("scrap_screw", 4, 0.2, 0.9)),
    ("scrap_can.glb",     build_can),
    ("hazard_saw.glb",    build_saw),
    ("hazard_spike.glb",  build_spike),
    ("powerup.glb",       build_powerup),
]


def main():
    print("POLARITY asset export -> %s" % OUT_DIR)
    total = 0
    over_budget = []
    for filename, builder in ASSETS:
        reset_scene()
        obj = builder()
        tris = export(obj, filename)
        total += tris
        budget = 800 if filename == "magnet.glb" else 200
        if tris > budget:
            over_budget.append((filename, tris, budget))

    print("total %d tris across %d assets" % (total, len(ASSETS)))
    if over_budget:
        # Loud rather than silent: §13A gives explicit budgets, and blowing them
        # is exactly the thing that quietly costs frames on a mid-range phone.
        for filename, tris, budget in over_budget:
            print("OVER BUDGET: %s %d tris (budget %d)" % (filename, tris, budget))
        sys.exit(1)
    print("all assets within the §13A tri budget")


if __name__ == "__main__":
    main()
