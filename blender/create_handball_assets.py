"""Generate the first production court assets in Blender 4.x.

Run from Blender's Scripting workspace or headlessly:
blender --background --python blender/create_handball_assets.py
"""
import bpy
from mathutils import Vector


EXPORT_PATH = "//../assets/handball_court.glb"


def material(name, color, roughness=0.8, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def bevelled_cube(name, location, scale, mat, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(scale) * 0.5
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    modifier = obj.modifiers.new("Edge wear", "BEVEL")
    modifier.width = bevel
    modifier.segments = 2
    return obj


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    concrete = material("Weathered concrete", (0.34, 0.35, 0.34), 0.93)
    mortar = material("Mortar", (0.47, 0.47, 0.43), 1.0)
    rubber = material("Royal blue racquetball", (0.008, 0.12, 0.68), 0.58)
    floor_mat = material("Dark court", (0.105, 0.12, 0.125), 0.9)

    bevelled_cube("Mortar backing", (0, 1.9, -10.15), (10.4, 7.0, 0.18), mortar, 0.01)
    for row in range(15):
        offset = -0.49 if row % 2 else 0.0
        for col in range(12):
            x = -5.28 + col * 0.97 + offset
            if -5.08 <= x <= 5.08:
                block = bevelled_cube(
                    f"Block_{row:02d}_{col:02d}",
                    (x, -1.29 + row * 0.47, -10.0),
                    (0.95, 0.45, 0.28), concrete, 0.018
                )
                block["collision"] = "static"

    floor = bevelled_cube("Court floor", (0, -1.64, -3.0), (12, 0.18, 18), floor_mat, 0.01)
    floor["collision"] = "static"

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5, radius=0.18, location=(0, -0.25, -2.25))
    ball = bpy.context.object
    ball.name = "BlueRacquetball"
    ball.data.materials.append(rubber)
    ball["collision"] = "sphere"
    ball["radius_m"] = 0.18

    bpy.ops.wm.save_as_mainfile(filepath="//handball_assets.blend")
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )


if __name__ == "__main__":
    build()
