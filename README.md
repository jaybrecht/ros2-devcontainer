# ROS 2 Jazzy dev container

A ROS 2 Jazzy container with `src/` mounted from the host, so you edit on the host
and build/test in the container without rebuilding the image.

## Prerequisites

- Docker Engine and the Compose plugin (`docker compose version`)

## Quick start

```bash
docker compose build          # installs the dependencies of everything in src/
docker compose up -d          # start the container in the background
docker compose exec ros bash  # get a shell
```

Inside the container:

```bash
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

Stop with `docker compose down`.

## Layout

| Path                 | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| `src/`               | Your packages. Mounted to `/ws/src` in the container. |
| `Dockerfile`         | Base image + `rosdep install`.                     |
| `docker-compose.yml` | Mount, networking, keeps the container alive.      |

## Adding a package

```bash
docker compose exec ros bash
source /opt/ros/jazzy/setup.bash
cd /ws/src
ros2 pkg create --build-type ament_python my_pkg
```

**Rebuild the image whenever a `package.xml` changes**, so its new dependencies get
installed:

```bash
docker compose build
docker compose up -d --force-recreate
```

Editing source code needs no rebuild — `src/` is a live mount.

## Adding a dependency

Add it to the package's `package.xml` (a ROS package or a rosdep key like
`nlohmann-json-dev`), then `docker compose build`. For anything rosdep can't express,
add it to the `Dockerfile` instead.

Don't `apt install` inside a running container — it's lost when the container is
recreated, and the image drifts from what a rebuild produces.

## Building and testing

```bash
docker compose exec ros bash -c '
  source /opt/ros/jazzy/setup.bash &&
  colcon build &&
  colcon test &&
  colcon test-result --verbose'
```

## Things to know

**ROS is not sourced automatically.** Every shell needs
`source /opt/ros/jazzy/setup.bash` (and `source /ws/install/setup.bash` once you've
built). This is deliberate — add it to your own `.bashrc` or shell setup if you want it.

**Build artifacts live inside the container.** Only `src/` is mounted, so `build/`,
`install/`, and `log/` are lost when the container is removed (`docker compose down`)
and need a fresh `colcon build`. Restarts are fine. To persist them on the host,
change the volume to `.:/ws`.

**The container user is hardcoded to UID 67851 / GID 36700** to match the host user,
so files created in the container aren't owned by root. On a different machine or
user account, update those numbers in the `Dockerfile` (`id -u`, `id -g`) and rebuild.

**Networking is `host` mode**, so DDS discovery reaches other ROS 2 nodes on the
machine and the LAN with no extra setup. Set `ROS_DOMAIN_ID` to isolate yourself from
others on the same network.

## VS Code

Install the **Dev Containers** extension, open this folder, and click
**Reopen in Container** when prompted (or run **Dev Containers: Reopen in Container**
from the command palette). VS Code builds and starts the container, opens `/ws/src`,
and installs the Python and Pylance extensions inside it.

Editor settings live in `.devcontainer/devcontainer.json`. Pylance never sources
`setup.bash`, so every Python path it should resolve must be listed in
`python.analysis.extraPaths`. When you add an interface package, add its install path
(after a `colcon build`):

```
/ws/install/<package>/lib/python3.12/site-packages/
```

After changing `devcontainer.json`, run **Dev Containers: Rebuild Container**.
