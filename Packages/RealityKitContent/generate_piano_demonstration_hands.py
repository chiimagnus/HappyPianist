"""Generate the two 21-joint piano demonstration hand assets.

The topology starts from Blender Foundation's Human Base Meshes v1.0.0
(CC0) and is reshaped, mirrored, rigged, and shaded here for HappyPianist.
Source: https://download.blender.org/demo/bundles/bundles-3.6/

Run from the repository root:
    rtk python3 ~/.codex/skills/designs/blender/scripts/run_blender.py \
        Packages/RealityKitContent/generate_piano_demonstration_hands.py
"""

from __future__ import annotations

import hashlib
import math
import os
import sys
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass

import bpy
from mathutils import Matrix, Vector


ASSET_DIRECTORY = os.path.join(
    os.path.dirname(__file__),
    "Sources",
    "RealityKitContent",
    "RealityKitContent.rkassets",
)
PREVIEW_PATH = "/tmp/happypianist-demonstration-hands.png"
BLEND_PATH = "/tmp/happypianist-demonstration-hands.blend"
BASE_MESH_URL = (
    "https://download.blender.org/demo/bundles/bundles-3.6/"
    "human-base-meshes-bundle-v1.0.0.zip"
)
BASE_MESH_SHA256 = "46a912c0524072ac3b78c35d5d2471df7b8df102394a050ca8cd7184e3393648"
BASE_MESH_BLEND_NAME = "human_base_meshes_bundle.blend"
BASE_MESH_OBJECT_NAME = "Hand  - Realistic"


@dataclass(frozen=True)
class FingerDefinition:
    name: str
    joints: tuple[tuple[float, float, float], ...]
    width: float


RIGHT_FINGERS = (
    FingerDefinition(
        "thumb",
        ((-0.030, 0.004, -0.004), (-0.044, 0.025, -0.003), (-0.051, 0.047, -0.004), (-0.053, 0.067, -0.005)),
        0.0105,
    ),
    FingerDefinition(
        "index",
        ((-0.016, 0.027, 0.000), (-0.017, 0.061, 0.002), (-0.017, 0.085, 0.001), (-0.017, 0.105, -0.001)),
        0.0086,
    ),
    FingerDefinition(
        "middle",
        ((0.000, 0.031, 0.001), (0.000, 0.070, 0.003), (0.000, 0.097, 0.002), (0.000, 0.120, -0.001)),
        0.0090,
    ),
    FingerDefinition(
        "ring",
        ((0.017, 0.028, 0.000), (0.018, 0.064, 0.002), (0.019, 0.089, 0.001), (0.019, 0.109, -0.001)),
        0.0081,
    ),
    FingerDefinition(
        "little",
        ((0.033, 0.022, -0.001), (0.036, 0.050, 0.001), (0.037, 0.070, 0.000), (0.038, 0.086, -0.002)),
        0.0069,
    ),
)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mirrored_fingers(hand: str) -> tuple[FingerDefinition, ...]:
    if hand == "right":
        return RIGHT_FINGERS
    return tuple(
        FingerDefinition(
            finger.name,
            tuple((-x, y, z) for x, y, z in finger.joints),
            finger.width,
        )
        for finger in RIGHT_FINGERS
    )


def source_blend_path() -> str:
    cache_directory = os.path.join(tempfile.gettempdir(), "happypianist-blender-assets")
    archive_path = os.path.join(cache_directory, os.path.basename(BASE_MESH_URL))
    blend_path = os.path.join(cache_directory, BASE_MESH_BLEND_NAME)
    os.makedirs(cache_directory, exist_ok=True)

    if not os.path.exists(blend_path):
        if not os.path.exists(archive_path):
            urllib.request.urlretrieve(BASE_MESH_URL, archive_path)
        with open(archive_path, "rb") as archive:
            digest = hashlib.sha256(archive.read()).hexdigest()
        if digest != BASE_MESH_SHA256:
            raise RuntimeError(f"Blender base mesh checksum mismatch: {digest}")
        with zipfile.ZipFile(archive_path) as bundle:
            bundle.extract(BASE_MESH_BLEND_NAME, cache_directory)
    return blend_path


def make_hand_surface(hand: str, _: tuple[FingerDefinition, ...]) -> bpy.types.Object:
    # Blender Foundation Human Base Meshes v1.0.0, CC0. We retain its animation-ready
    # quad topology, then replace the material and skeleton for this product-specific rig.
    with bpy.data.libraries.load(source_blend_path(), link=False) as (source, target):
        if BASE_MESH_OBJECT_NAME not in source.objects:
            raise RuntimeError(f"Missing Blender base mesh: {BASE_MESH_OBJECT_NAME}")
        target.objects = [BASE_MESH_OBJECT_NAME]
    surface = target.objects[0]
    bpy.context.collection.objects.link(surface)
    surface.name = f"PianoHandMesh.{hand}"
    surface.asset_clear()
    surface.location = (0, 0, 0)
    surface.rotation_euler = (0, 0, 0)
    surface.scale = (1, 1, 1)

    bpy.ops.object.select_all(action="DESELECT")
    surface.select_set(True)
    bpy.context.view_layer.objects.active = surface
    for modifier in tuple(surface.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)

    # Source mesh is Z-long/Y-thick. RealityKit hand space is X-wide/Y-up/-Z-forward,
    # so author X-wide/Y-forward/Z-up here and let USD perform the standard up-axis conversion.
    mirror_x = -1 if hand == "right" else 1
    transform = Matrix.Diagonal((mirror_x * 0.64, 0.64, 0.64, 1)) @ Matrix.Rotation(
        math.radians(90), 4, "X"
    )
    surface.data.transform(transform)
    surface.data.update()
    for polygon in surface.data.polygons:
        polygon.use_smooth = True

    surface.data.materials.clear()
    surface.data.materials.append(make_material("SilkBody", (0.025, 0.31, 0.68, 0.62), emission=0.08))
    return surface


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    emission: float = 0.35,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.surface_render_method = "DITHERED"
    material.use_transparency_overlap = False
    bsdf = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    for socket in bsdf.inputs:
        if socket.identifier == "Base Color":
            socket.default_value = color
        elif socket.identifier == "Roughness":
            socket.default_value = 0.22
        elif socket.identifier == "Metallic":
            socket.default_value = 0.06
        elif socket.identifier == "Alpha":
            socket.default_value = color[3]
        elif socket.identifier == "Transmission Weight":
            socket.default_value = 0.18
        elif socket.identifier == "Sheen Weight":
            socket.default_value = 0.42
        elif socket.identifier == "Emission Color":
            socket.default_value = (*color[:3], 1)
        elif socket.identifier == "Emission Strength":
            socket.default_value = emission
    return material


def make_armature(hand: str, fingers: tuple[FingerDefinition, ...]) -> bpy.types.Object:
    armature_data = bpy.data.armatures.new(f"PianoHandSkeleton.{hand}")
    armature = bpy.data.objects.new(f"PianoHandRig.{hand}", armature_data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    wrist = armature_data.edit_bones.new("wrist")
    wrist.head = (0, -0.045, 0)
    wrist.tail = (0, 0, 0)
    wrist.use_deform = True

    for finger in fingers:
        points = tuple(Vector(point) for point in finger.joints)
        previous = wrist
        for index, point in enumerate(points):
            bone = armature_data.edit_bones.new(f"{finger.name}_{index}")
            bone.head = point
            if index + 1 < len(points):
                bone.tail = points[index + 1]
            else:
                direction = (points[index] - points[index - 1]).normalized()
                bone.tail = points[index] + direction * max(0.008, finger.width)
            bone.parent = previous
            bone.use_connect = index > 0
            bone.use_deform = True
            previous = bone

    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def bind_surface(surface: bpy.types.Object, armature: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    surface.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def validate_rig(surface: bpy.types.Object, armature: bpy.types.Object) -> None:
    required = {"wrist"}
    for finger in RIGHT_FINGERS:
        required.update(f"{finger.name}_{index}" for index in range(4))
    bone_names = {bone.name for bone in armature.data.bones if bone.use_deform}
    missing_bones = required - bone_names
    missing_groups = required - {group.name for group in surface.vertex_groups}
    if len(bone_names) != 21 or missing_bones or missing_groups:
        raise RuntimeError(
            f"Invalid hand rig: bones={len(bone_names)} missingBones={sorted(missing_bones)} "
            f"missingGroups={sorted(missing_groups)}"
        )


def export_hand(hand: str, surface: bpy.types.Object, armature: bpy.types.Object) -> str:
    os.makedirs(ASSET_DIRECTORY, exist_ok=True)
    filename = f"PianoDemonstrationHand{hand.title()}.usdc"
    path = os.path.join(ASSET_DIRECTORY, filename)
    bpy.ops.object.select_all(action="DESELECT")
    surface.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.wm.usd_export(
        filepath=path,
        selected_objects_only=True,
        export_animation=False,
        export_armatures=True,
        only_deform_bones=True,
        export_materials=True,
        generate_preview_surface=True,
        convert_scene_units="METERS",
        meters_per_unit=1.0,
        relative_paths=True,
    )
    print("EXPORTED:", path)
    return path


def build_hand(hand: str) -> tuple[bpy.types.Object, bpy.types.Object]:
    fingers = mirrored_fingers(hand)
    surface = make_hand_surface(hand, fingers)
    armature = make_armature(hand, fingers)
    bind_surface(surface, armature)
    validate_rig(surface, armature)
    export_hand(hand, surface, armature)
    return surface, armature


def pose_hand_for_preview(armature: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = armature
    for finger in RIGHT_FINGERS:
        for index, angle in enumerate((-1, -6, -10, -4)):
            pose_bone = armature.pose.bones.get(f"{finger.name}_{index}")
            if pose_bone is None:
                continue
            pose_bone.rotation_mode = "XYZ"
            pose_bone.rotation_euler.x = math.radians(angle if finger.name != "thumb" else angle * 0.72)


def add_preview_stage() -> None:
    world = bpy.data.worlds.new("PreviewWorld")
    bpy.context.scene.world = world
    background = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs[0].default_value = (0.012, 0.018, 0.032, 1)
    background.inputs[1].default_value = 0.28

    bpy.ops.mesh.primitive_plane_add(size=1.2, location=(0, 0.02, -0.021))
    plane = bpy.context.object
    plane.data.materials.append(make_material("PreviewGround", (0.015, 0.025, 0.045, 1), emission=0))

    for x, energy, color in (
        (-0.28, 115, (0.12, 0.72, 1.0)),
        (0.28, 95, (0.72, 0.24, 1.0)),
    ):
        light_data = bpy.data.lights.new(f"Rim.{x}", type="AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = 0.22
        light = bpy.data.objects.new(f"Rim.{x}", light_data)
        bpy.context.collection.objects.link(light)
        light.location = (x, -0.10, 0.28)

    camera_data = bpy.data.cameras.new("Camera")
    camera = bpy.data.objects.new("Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0, -0.36, 0.29)
    target = Vector((0, 0.015, 0.015))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 58
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 620
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = PREVIEW_PATH
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED_BLEND:", BLEND_PATH)
    bpy.ops.render.render(write_still=True)
    print("RENDERED:", PREVIEW_PATH)


def main() -> None:
    clear_scene()
    right_surface, right_armature = build_hand("right")
    left_surface, left_armature = build_hand("left")
    pose_hand_for_preview(right_armature)
    pose_hand_for_preview(left_armature)
    right_armature.location.x = 0.075
    left_armature.location.x = -0.075
    right_armature.rotation_euler.z = math.radians(-5)
    left_armature.rotation_euler.z = math.radians(5)
    add_preview_stage()
    print(
        "HAND_STATS:",
        f"rightVertices={len(right_surface.data.vertices)}",
        f"leftVertices={len(left_surface.data.vertices)}",
        "jointsPerHand=21",
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)
