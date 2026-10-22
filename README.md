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
| + Isaac Sim     | append `:compose/isaacsim.yml` and set `ISAACSIM_ROOT` |

The separator is `:` on Linux and in WSL, and `;` when you run from PowerShell.

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
| `compose/isaacsim.yml`      | Host Isaac Sim mounted at `/isaac-sim`, with caches. |
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
`python.analysis.extraPaths`. The default list covers ROS and every interface
package you build, since merge-install puts them all in
`/ws/install/lib/python3.12/site-packages/`. It doesn't cover `ament_python`
packages, which symlink-install leaves in `src/`.

Add those per project in `src/.vscode/settings.json`. It's on the host, so it
survives rebuilds, and it isn't tracked by this repo. It replaces the whole
list, so keep the two default entries:

```json
{
    "python.analysis.extraPaths": [
        "/opt/ros/jazzy/lib/python3.12/site-packages/",
        "/ws/install/lib/python3.12/site-packages/",
        "/ws/src/<package>/"
    ]
}
```

After changing `devcontainer.json`, run **Dev Containers: Rebuild Container**.

## Isaac Sim

Isaac Sim is installed on the host and mounted into the container at
`/isaac-sim`, where it runs. Set `ISAACSIM_ROOT` in `.env` and add
`compose/gpu.yml` and `compose/isaacsim.yml` to `COMPOSE_FILE`. In the container:

```bash
jazzy
/isaac-sim/python.sh /ws/src/<pkg>/<script>.py
```

Isaac Sim uses the container's ROS Jazzy (it's always sourced), so your own
message packages work once the workspace is sourced. The shader caches
(`~/.cache/ov` and friends) are mounted from the host so they survive rebuilds;
those directories must exist on the host before the container starts.

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

Isaac Sim ships `.vscode/settings.json` listing every extension folder. On
container creation, `isaacsim-vscode-paths` (`.devcontainer/isaacsim_vscode_paths.py`,
copied into the image) rewrites those to `/isaac-sim/...` and merges them into
`src/.vscode/settings.json`, keeping your other entries. It leaves out the few
extensions (e.g. `isaacsim.ros2.control`) that would otherwise break `isaacsim.*`
imports in Pylance. For the same reason, write
`from isaacsim.simulation_app import SimulationApp`, not `from isaacsim import ...`.
Re-run it after upgrading Isaac Sim, then restart the Python language server:

```bash
isaacsim-vscode-paths
```
