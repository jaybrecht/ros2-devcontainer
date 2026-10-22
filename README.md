# ROS 2 Jazzy dev container

A reusable ROS 2 Jazzy container. This repo holds only the container setup. Your
project repos are cloned into `src/`, which is mounted into the container. You edit
on the host and build and test in the container without rebuilding the image.

## Prerequisites

- **Linux:** Docker Engine and the Compose plugin (`docker compose version`). For a
  GPU, also the NVIDIA driver and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
- **Windows 11:** Docker Desktop with the WSL2 backend. For a GPU, a current NVIDIA
  Windows driver (no toolkit needed). Clone this repo **inside WSL2** (for example
  `~/` in Ubuntu), not on `C:\`. Bind mounts from the Windows filesystem are very
  slow, and `colcon build` suffers most.

## Setting up a project

```bash
git clone <this repo> my_project_ws
cd my_project_ws
git clone <your project repo> src/<project>   # repeat for each repo you need
cp .env.example .env                          # then pick your options, see below
docker compose build
docker compose up -d
docker compose exec ros zsh
```

Each clone of this repo is a separate workspace. Compose names the image and
container after the folder, so several workspaces can run at the same time.

## Options (`.env`)

`.env` is local and not committed. Both `docker compose` and VS Code read it.
Uncomment one `COMPOSE_FILE` line from `.env.example`:

| Option          | Files                                   |
| --------------- | --------------------------------------- |
| Linux           | `docker-compose.yml:compose/linux.yml`  |
| Linux + GPU     | `...:compose/linux.yml:compose/gpu.yml` |
| Windows         | `docker-compose.yml:compose/windows.yml`|
| Windows + GPU   | `...:compose/windows.yml:compose/gpu.yml` |
| + Isaac Sim     | append `:compose/isaacsim.yml` (needs GPU; Linux only) |

The separator is `:` on Linux and in WSL, and `;` when you run from PowerShell.

Set `CLAUDE_CODE=true` to use Claude Code in the container. The container's
`postCreateCommand` then installs the VS Code extension. The login is kept in a
Docker volume shared by every workspace on the machine, so you sign in once. That
volume is mounted either way, but nothing uses it when `CLAUDE_CODE=false`.

On Linux, set `USER_UID`/`USER_GID` to the output of `id -u`/`id -g`. Files
created in the container are then owned by you on the host, not by root. On
Windows, leave them at 1000.

After you change `.env`, run `docker compose build && docker compose up -d --force-recreate`
(or **Dev Containers: Rebuild Container**).

## Layout

| Path                        | Purpose                                              |
| --------------------------- | ---------------------------------------------------- |
| `src/`                      | Your project repos (git-ignored here). Mounted to `/ws/src`. |
| `Dockerfile`                | Base image, `rosdep install`, container user.        |
| `docker-compose.yml`        | Base service: mount, networking, build args.         |
| `compose/linux.yml`         | GUI through the host X server.                       |
| `compose/windows.yml`       | GUI through WSLg.                                    |
| `compose/gpu.yml`           | NVIDIA GPU passthrough.                              |
| `compose/isaacsim.yml`      | Builds on NVIDIA's Isaac Sim image; cache volumes.  |
| `colcon-defaults.yaml`      | Makes `colcon build` use `--merge-install --symlink-install`. |
| `.devcontainer/`            | VS Code Dev Containers config, Pylance path script.  |

## Adding a dependency

Add it to the package's `package.xml` (a ROS package or a rosdep key like
`nlohmann-json-dev`) or `requirements.txt`, then rebuild:

```bash
docker compose build
docker compose up -d --force-recreate
```

The build only sees `package.xml` and `requirements.txt` files (see `.dockerignore`),
so editing source code never triggers a rebuild. For anything rosdep can't express,
add it to the `Dockerfile`.

Don't `apt install` inside a running container. The package is lost when the
container is recreated, and the image drifts from what a rebuild produces.

## Building and testing

Inside the container (the zsh helpers `jazzy` and `sw` source ROS and the workspace):

```bash
jazzy
colcon build
sw
colcon test && colcon test-result --verbose
```

## Things to know

**Build artifacts live inside the container.** Only `src/` is mounted, so `build/`,
`install/`, and `log/` are lost on `docker compose down` and need a fresh
`colcon build`. Restarts are fine.

**Networking is `host` mode**, so DDS discovery reaches other ROS 2 nodes on the
machine and the LAN. On Windows, enable host networking in Docker Desktop
(Settings → Resources → Network). Even then, "host" is the WSL2 VM, not Windows
itself.

**Line endings.** `.gitattributes` forces LF, so the zshrc still works when the repo
is cloned on Windows.

## VS Code

Install the **Dev Containers** extension, open this folder, and run
**Dev Containers: Reopen in Container**. It uses the same `.env` as
`docker compose`, because `dockerComposeFile` is an empty list in
`devcontainer.json`.

Pylance never sources `setup.bash`, so it only finds what's in
`python.analysis.extraPaths`. `pylance-paths` (`.devcontainer/pylance_paths.py`,
copied into the image) writes that list to `src/.vscode/settings.json`:

- ROS, and every interface package you build (merge-install puts them all in
  `/ws/install/lib/python3.12/site-packages/`).
- The source folder of each `ament_python` package in `src/`. symlink-install
  only leaves an egg-link for those in `install/`, which Pylance doesn't follow.
- Isaac Sim, when it's in the image (see below).

It runs when the container is created (or rebuilt). To pick up a package added to
`src/` since then, rebuild or run `pylance-paths`, then **Python: Restart Language
Server**. Other entries you add to the list yourself are kept.

After changing `devcontainer.json`, run **Dev Containers: Rebuild Container**.

## Isaac Sim

Add `compose/gpu.yml` and `compose/isaacsim.yml` to `COMPOSE_FILE`. The image is
then built on NVIDIA's Isaac Sim image (`nvcr.io/nvidia/isaac-sim`, ~20 GB, pulled
once per machine) with ROS Jazzy added, instead of `ros:jazzy-ros-base`. Isaac Sim
is at `/isaac-sim`. Set `ISAACSIM_VERSION` in `.env` to pick another release.
Using it means accepting NVIDIA's Isaac Sim license (`/isaac-sim/LICENSE.txt`).
In the container:

```bash
jazzy
/isaac-sim/python.sh /ws/src/<pkg>/<script>.py
```

With ROS sourced (`jazzy`), Isaac Sim uses the container's ROS Jazzy, so your own
message packages work once the workspace is sourced. Compiled shaders and Python
bytecode are kept in Docker volumes shared by every workspace on the machine, so
only the first launch after a version change is slow (~3 minutes instead of ~20 s).

To check the setup, run the smoke test (add `--gui` for the window):

```bash
/isaac-sim/python.sh /ws/src/aprs_testbed/testbed_sim/scripts/isaacsim_smoke_test.py
```

For the Isaac Sim window, run `/isaac-sim/isaac-sim.sh` for the full editor, or
start your own script with `SimulationApp({'headless': False})`. The smoke test
takes `--gui`. Windows go to the host X server through `compose/linux.yml`.

The NVIDIA runtime doesn't add a Vulkan ICD file, so the image adds one for
`libGLX_nvidia.so.0`, which needs an X display. Without X (for example over SSH,
or without `compose/linux.yml`), use the EGL one instead:
`export VK_DRIVER_FILES=$NVIDIA_EGL_ICD`. If `nvidia-smi` in the container fails with
`Failed to initialize NVML: Unknown Error`, the container lost GPU access after a
systemd reload on the host (a known NVIDIA Container Toolkit issue); recreate it.

Isaac Sim ships `.vscode/settings.json` listing every extension folder.
`pylance-paths` (see [VS Code](#vs-code)) rewrites those to `/isaac-sim/...` for
Pylance. It leaves out the few extensions (e.g. `isaacsim.ros2.control`) that
would otherwise break `isaacsim.*` imports. For the same reason, write
`from isaacsim.simulation_app import SimulationApp`, not `from isaacsim import ...`.
