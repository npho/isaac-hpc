"""Warm up the Kit/RTX shader caches.

Boots Isaac Sim headless with cameras enabled, renders a small lit scene through a
Replicator RGB annotator until a non-black frame arrives, then exits. Kit writes the
compiled shaders to <isaacsim>/kit/cache, which isaac-sim.def moves into
/workspace/baked_kit_cache so runtime jobs can seed their writable scratch cache.

Exit code is non-zero if no rendered frame is produced within the timeout.
"""

import os
import sys
import time

from isaaclab.app import AppLauncher

TIMEOUT_S = float(os.environ.get("WARMUP_TIMEOUT_S", "900"))
MIN_FRAMES = int(os.environ.get("WARMUP_MIN_FRAMES", "30"))

t_start = time.time()
app = AppLauncher(
    headless=True,
    enable_cameras=True,
    # Same RTX feature toggles as the downstream camera pipelines, so the matching
    # shader permutations are compiled.
    kit_args=(
        "--/log/level=warning "
        "--/telemetry/enableAnonymousData=false "
        "--/rtx/ambientOcclusion/enabled=true "
        "--/rtx/ambientOcclusion/raytracing/enabled=true "
        "--/rtx/directLighting/sampledLighting/enabled=true "
        "--/rtx/indirectDiff/enabled=true"
    ),
).app
t_boot = time.time()
print(f"[warmup] Kit booted in {t_boot - t_start:.1f}s", flush=True)

import numpy as np
import omni.kit.commands
import omni.replicator.core as rep
import omni.usd
from pxr import Gf, Sdf, UsdGeom, UsdLux, UsdShade

ctx = omni.usd.get_context()
if ctx.get_stage() is None:
    ctx.new_stage()
stage = ctx.get_stage()
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)

UsdLux.DomeLight.Define(stage, "/World/DomeLight").CreateIntensityAttr(1000.0)
UsdLux.DistantLight.Define(stage, "/World/Sun").CreateIntensityAttr(3000.0)

# Cube A: UsdPreviewSurface material.
cube_a = UsdGeom.Cube.Define(stage, "/World/CubePreview")
cube_a.CreateSizeAttr(0.3)
UsdGeom.XformCommonAPI(cube_a).SetTranslate(Gf.Vec3d(0.0, -0.25, 0.15))
mat = UsdShade.Material.Define(stage, "/World/Looks/Preview")
shader = UsdShade.Shader.Define(stage, "/World/Looks/Preview/Shader")
shader.CreateIdAttr("UsdPreviewSurface")
shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.8, 0.3, 0.2))
shader.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.5)
mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(), "surface")
UsdShade.MaterialBindingAPI.Apply(cube_a.GetPrim()).Bind(mat)

# Cube B: OmniPBR MDL material (the common Isaac Sim asset material).
cube_b = UsdGeom.Cube.Define(stage, "/World/CubeOmniPBR")
cube_b.CreateSizeAttr(0.3)
UsdGeom.XformCommonAPI(cube_b).SetTranslate(Gf.Vec3d(0.0, 0.25, 0.15))
try:
    omni.kit.commands.execute(
        "CreateMdlMaterialPrim", mtl_url="OmniPBR.mdl", mtl_name="OmniPBR", mtl_path="/World/Looks/OmniPBR"
    )
    omni.kit.commands.execute(
        "BindMaterial", prim_path="/World/CubeOmniPBR", material_path="/World/Looks/OmniPBR"
    )
except Exception as e:  # not fatal: the RTX pipelines still compile without it
    print(f"[warmup] WARNING: OmniPBR material setup failed: {e}", flush=True)

# Camera + Replicator RGB annotator (same path as MultiViewCameraManager).
cam = UsdGeom.Camera.Define(stage, "/World/Camera")
cam.CreateFocalLengthAttr().Set(24.0)
cam.CreateClippingRangeAttr().Set(Gf.Vec2f(0.01, 1000.0))
look_at = Gf.Matrix4d(1).SetLookAt(Gf.Vec3d(1.5, 1.5, 1.2), Gf.Vec3d(0, 0, 0.15), Gf.Vec3d(0, 0, 1)).GetInverse()
xform = UsdGeom.Xformable(cam.GetPrim())
xform.ClearXformOpOrder()
xform.AddTransformOp().Set(look_at)

rp = rep.create.render_product("/World/Camera", (256, 256))
annotator = rep.AnnotatorRegistry.get_annotator("rgb")
annotator.attach([rp])

kit = omni.kit.app.get_app()
frames, first_lit = 0, None
while time.time() - t_boot < TIMEOUT_S:
    kit.update()
    frames += 1
    data = annotator.get_data()
    if isinstance(data, dict):
        data = data.get("data")
    arr = np.asarray(data) if data is not None else np.empty(0)
    if first_lit is None and arr.size and float(arr[..., :3].mean()) > 0.0:
        first_lit = frames
        print(
            f"[warmup] First lit frame at update {frames} ({time.time() - t_boot:.1f}s after boot), "
            f"mean={float(arr[..., :3].mean()):.1f}",
            flush=True,
        )
    if first_lit is not None and frames >= first_lit + MIN_FRAMES:
        break

ok = first_lit is not None
print(f"[warmup] {'OK' if ok else 'FAILED: no lit frame'} after {frames} updates, total {time.time() - t_start:.1f}s", flush=True)
if not ok:
    os._exit(1)  # SimulationApp.close() may exit the process itself and mask the status
app.close()  # clean shutdown flushes the shader caches to disk
sys.exit(0)
