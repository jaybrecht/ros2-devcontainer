# The base is ROS's image, or NVIDIA's Isaac Sim image with ROS added. compose/isaacsim.yml
# selects the second by setting BASE=isaacsim. BuildKit only builds the stage that's
# used, so the Isaac Sim image (~20 GB) is only pulled when it's selected.
ARG BASE=ros
ARG ISAACSIM_VERSION=6.2.0

# apt has no fallback timer like curl's: if the network has a broken IPv6 route, it
# waits 60 s on every connection before trying IPv4. Ubuntu and ROS mirrors all
# serve IPv4, so forcing it costs nothing where IPv6 works.
FROM ros:jazzy-ros-base AS base-ros
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

# Isaac Sim lives in /isaac-sim, owned by its isaac-sim user (uid 1234, mode 750).
FROM nvcr.io/nvidia/isaac-sim:${ISAACSIM_VERSION} AS base-isaacsim
USER root
ENV ROS_DISTRO=jazzy LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
# ROS 2 Jazzy, installed the same way the official ros:jazzy images do it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -L -s -f -o /tmp/ros2-apt-source.deb \
    https://github.com/ros-infrastructure/ros-apt-source/releases/download/1.2.0/ros2-apt-source_1.2.0.noble_all.deb \
 && echo "0804d9b13db770eb87019be414cd78378835228ad5fa801fc88758596dd8f7e5 */tmp/ros2-apt-source.deb" \
  | sha256sum --strict --check \
 && apt-get install -y /tmp/ros2-apt-source.deb \
 && rm /tmp/ros2-apt-source.deb \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ros-jazzy-ros-base build-essential git python3-colcon-common-extensions \
    python3-rosdep \
 && rm -rf /var/lib/apt/lists/* \
 && rosdep init \
 && printf '#!/bin/bash\nset -e\nsource "/opt/ros/$ROS_DISTRO/setup.bash" --\nexec "$@"\n' \
    > /ros_entrypoint.sh \
 && chmod +x /ros_entrypoint.sh
# NVIDIA's entrypoint starts Isaac Sim headless, and its healthcheck waits for that,
# so both are replaced.
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
HEALTHCHECK NONE

FROM base-${BASE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Isaac Sim needs a Vulkan loader and a few X/GL libraries; the GPU driver itself
# comes from the NVIDIA runtime. The runtime doesn't add a Vulkan ICD file, so two
# are written here:
# - libGLX_nvidia (the default) needs an X display, which compose/linux.yml gives.
# - libEGL_nvidia works with no X server, but segfaults when DISPLAY is set, so it
#   lives outside icd.d. Without X, export VK_DRIVER_FILES=$NVIDIA_EGL_ICD.
ENV NVIDIA_EGL_ICD=/usr/share/vulkan/nvidia_egl_icd.json
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libvulkan1 libgl1 libglu1-mesa libx11-xcb1 libxcb-randr0 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /usr/share/vulkan/icd.d \
 && for lib in GLX:/usr/share/vulkan/icd.d/nvidia_icd.json EGL:$NVIDIA_EGL_ICD; do \
      printf '{"file_format_version": "1.0.1", "ICD": {"library_path": "lib%s_nvidia.so.0", "api_version": "1.4.312"}}\n' \
        "${lib%%:*}" > "${lib#*:}"; \
    done

# Dependencies are resolved from each package's package.xml (ROS/apt) and
# requirements.txt (pip) at build time. .dockerignore limits the context to
# those files, so editing source code doesn't invalidate this layer. Ubuntu
# 24.04 blocks system-wide pip installs unless --break-system-packages is passed.
COPY src /tmp/src
RUN apt-get update \
 && rosdep update --rosdistro $ROS_DISTRO \
 && rosdep install --from-paths /tmp/src --ignore-src -y \
 && find /tmp/src -name requirements.txt -print0 \
  | xargs -0 -r -n1 pip install --break-system-packages --no-cache-dir -r \
 && rm -rf /tmp/src /var/lib/apt/lists/*

# Run as a user matching the host UID/GID (set in .env) so files created in the
# container belong to you on the host instead of root. The base image ships an
# `ubuntu` user at 1000:1000, which is removed so it can't collide. /ws must be
# owned by that user or colcon can't write build/ install/ log/.
# With Isaac Sim, the user joins the isaac-sim group to read /isaac-sim, and owns
# the dirs Kit writes to (created here, since Kit only makes them on first run).
ARG USER_UID=1000
ARG USER_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd -g ${USER_GID} dev \
 && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/zsh dev \
 && mkdir -p /ws \
 && chown dev:dev /ws \
 && if getent group isaac-sim >/dev/null; then \
      usermod -aG isaac-sim dev \
      && mkdir -p /isaac-sim/kit/cache /isaac-sim/kit/data /isaac-sim/kit/logs \
      && chown dev:dev /isaac-sim/kit/cache /isaac-sim/kit/data /isaac-sim/kit/logs; \
    fi

USER dev
WORKDIR /ws

# Mount points for the claude-config and Isaac Sim cache volumes. Creating them
# here makes Docker give new volumes dev's ownership instead of root's.
RUN mkdir -p /home/dev/.claude /home/dev/.cache /home/dev/.local/share

RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /home/dev/.oh-my-zsh
COPY --chown=dev:dev zshrc /home/dev/.zshrc
COPY --chown=dev:dev colcon-defaults.yaml /home/dev/.colcon/defaults.yaml

# Writes Pylance's extraPaths (ROS, ament_python packages, Isaac Sim); run by
# postCreateCommand. Last, so editing it doesn't invalidate earlier layers.
COPY --chmod=755 .devcontainer/pylance_paths.py /usr/local/bin/pylance-paths
