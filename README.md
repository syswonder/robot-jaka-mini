# robot-jaka-mini — JAKA Mini Robonix deployment

Robonix deployment for the fixed-base **JAKA Mini** 6-DOF arm with a
**TG-9801** adaptive gripper (end RS485). The arm is driven by the
[`primitive-jaka-rbnx`](../primitive-jaka-rbnx) package over TCP to the
controller (jkrc SDK).

## Hardware & platform

| item | value |
|---|---|
| arm | JAKA Mini, controller at `10.5.5.100` (config `jaka_arm.ip`) |
| gripper | TG-9801, RS485 via controller end channel |
| camera | Orbbec Gemini 336L (USB `2bc5:0807`), overhead/fixed — RGBD, 1280×720 |
| platform | Jetson Orin, JetPack 6 (aarch64), ROS 2 Humble + `rmw_zenoh_cpp` |
| base | fixed (no mobile base, no navigation) |

## Packages (sibling repos)

| package | role |
|---|---|
| `../primitive-jaka-rbnx` | arm primitive — `robonix/primitive/arm/*` over jkrc TCP |
| `../primitive-orbbec-camera-rbnx` | Orbbec camera primitive — `robonix/primitive/camera/{rgb,depth,camera_info}` (Gemini 336L via `gemini_330_series.launch.py`) |
| `../skill-jaka-rbnx` | grab/release + camera-driven `pick` skill — `robonix/skill/jaka/*` |

## Pick skill (camera-driven grasp)

`jaka_pick` locates a named object and grasps it: resolve `camera/rgb` → grab a
frame → detect → a calibrated **2D hand-eye homography** maps the bbox centre
to arm `base_link` XY → grasp at `(x, y, desktop_height)` with a
vertical-down orientation. It reuses the same grasp segment as `grab`.

Two detection backends (`detect_scheme` in the skill config):

- **`yolo`** (deploy default): in-process yolo11-obb — the fruit model
  (`carrot`/`potato`/`tomato`) reused from the agilex deploy at
  `robot-agilex-robonix/host-services/yolo/weights/best.pt` (set
  `yolo_model_path`; the skill interpreter has CUDA torch + ultralytics).
  Two-frame consistency filters flicker; Chinese phrasing maps to class
  names via `yolo_class_aliases` (胡萝卜→carrot …); the OBB rotation aligns
  the gripper yaw to the object's long edge
  (`rz = grasp_yaw_offset_deg - yaw`, default -90 = AIIT's tuned JAKA
  value — adjust by ±90 if the fingers land off-axis).
- **`vlm`**: open-vocabulary multimodal detection (pixel bbox, no
  rotation → fixed `grasp_rpy`).

**Calibration is required and on-site.** `pick` is unavailable until you set,
in `robonix_manifest.yaml`'s `skill: - name: jaka` config block:
- `homography_matrix` — 3×3 pixel→base_link, calibrated at 1280×720 (same kind
  of matrix as agilex's `grasp_pose`);
- the scheme's detector: `yolo_model_path` (existing weights file) or
  `vlm_base_url` / `vlm_api_key` / `vlm_model` (**multimodal** endpoint);
- `desktop_height` — the table height in `base_link` (grasp z).

Until then `pick` returns a clear error; `grab` / `release` are unaffected.

## URDF

`urdf/robot.urdf` is the JAKA app export of the real JAKA Mini
(with `meshes/`). It is consumed by Soma (`urdf.path` in `soma.yaml`),
which serves the raw XML to `robot_description` via `get_urdf`.

The export was post-processed for this deployment: the 6 arm joints were
renamed `link_002_joint..link_007_joint` → `joint_1..joint_6` so
`robot_state_publisher` matches the `joint_states` names published by the
`jaka_arm` provider. If the URDF is re-exported from the JAKA app, re-apply
this rename (see the note in `soma.yaml`). The two gripper finger joints
(`link_008_joint`/`link_009_joint`) are kept as exported; the provider
publishes a single `gripper_joint` value.

## Prerequisites

- Robonix tooling: `make install` from a cloned `syswonder/robonix` checkout,
  then `rbnx setup <robonix source dir>`.
- `sudo apt install ros-humble-rclpy ros-humble-rmw-zenoh-cpp`
- Primitive package built: `rbnx build -p ../primitive-jaka-rbnx`

## Build

```bash
bash build.sh
```

`build.sh` is the canonical entry: it prepares the deploy venv, then builds
`../primitive-jaka-rbnx`, `../primitive-orbbec-camera-rbnx`,
`../skill-jaka-rbnx`, and both manifests. `robot_description` is fetched from
the package catalog into `rbnx-boot/cache/` at boot.

> **Camera build note (native):** the Orbbec driver
> (`../primitive-orbbec-camera-rbnx`) colcon-builds the vendored
> `OrbbecSDK_ROS2`, which needs ROS 2 C++ deps (`rclcpp`, `image_transport`,
> `cv_bridge`, `camera_info_manager`, `tf2_ros`, …) absent from this Jetson's
> minimal `/opt/ros/humble`. Install them once per machine (needs sudo):
>
> ```bash
> bash ../primitive-orbbec-camera-rbnx/scripts/install_deps.sh
> ```
>
> The camera `build.sh` checks for these and fails fast with this pointer if
> they're missing. The arm-only stack builds fine without them (the camera
> primitive is only needed for `pick`).

## Boot

```bash
# read-only (motion_enabled: false): feedback streams, no motion
bash start.sh

# after estop verification and single-joint tests, enable motion in
# robonix_manifest.yaml: jaka_arm.config.motion_enabled: true
```

Motion commands stay rejected while `motion_enabled: false` (safety gate,
see `../primitive-jaka-rbnx/config.spec`).

## Acceptance record

| stage | command | expected |
|---|---|---|
| static | `rbnx validate ../primitive-jaka-rbnx && rbnx build -f robonix_manifest.yaml` | all packages built |
| unit | `cd ../primitive-jaka-rbnx && .venv/bin/python -m unittest jaka_arm.tests.test_driver` | 8/8 OK |
| read-only arm | `bash start.sh` | joint_states/end_pose stream; gripper state open/unknown sane |
| single joint | motion_enabled: true, `ros2 topic pub /jaka/joint_command` small delta | joints follow, limits hold, estop works |
| gripper | gripper_joint close/open | soma reports open / holding |
| camera | `bash start.sh`, `rbnx caps -v` | orbbec_camera ACTIVE; `camera/rgb` streams 1280×720 |
| pick (dry) | set VLM + homography, `jaka_pick {object}` before enabling motion | detect + geometry resolve; motion times out with `motion_enabled` hint |
| pick (live) | motion_enabled: true, calibrated | arm descends on the detected object, closes, lifts |
| shutdown | Ctrl-C | motion stops, arm powered off, logs clean |

Fill in the robot revision, Robonix commit (`git -C <robonix> rev-parse HEAD`)
and measured gripper open reading here after acceptance.
