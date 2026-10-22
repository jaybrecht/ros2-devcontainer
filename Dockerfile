FROM ros:jazzy-ros-base

RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Isaac Sim (mounted from the host by compose/isaacsim.yml) needs a Vulkan loader
# and a few X/GL libraries; the GPU driver itself comes from the NVIDIA runtime.
# The runtime doesn't add a Vulkan ICD file, so two are written here:
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
 && rosdep install --from-paths /tmp/src --ignore-src -y \
 && find /tmp/src -name requirements.txt -print0 \
  | xargs -0 -r -n1 pip install --break-system-packages --no-cache-dir -r \
 && rm -rf /tmp/src /var/lib/apt/lists/*

# Run as a user matching the host UID/GID (set in .env) so files created in the
# container belong to you on the host instead of root. The base image ships an
# `ubuntu` user at 1000:1000, which is removed so it can't collide. /ws must be
# owned by that user or colcon can't write build/ install/ log/.
ARG USER_UID=1000
ARG USER_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd -g ${USER_GID} dev \
 && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/zsh dev \
 && mkdir -p /ws \
 && chown dev:dev /ws

USER dev
WORKDIR /ws

# Mount point for the claude-config volume. Creating it here makes Docker give
# the new volume dev's ownership instead of root's. The parents of the Isaac Sim
# cache mounts must also exist as dev, or Docker creates them owned by root.
RUN mkdir -p /home/dev/.claude /home/dev/.cache /home/dev/.local/share

RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /home/dev/.oh-my-zsh
COPY --chown=dev:dev zshrc /home/dev/.zshrc
COPY --chown=dev:dev colcon-defaults.yaml /home/dev/.colcon/defaults.yaml

# Points Pylance at the Isaac Sim install; run by postCreateCommand, and by hand
# after upgrading Isaac Sim. Last, so editing it doesn't invalidate earlier layers.
COPY --chmod=755 .devcontainer/isaacsim_vscode_paths.py /usr/local/bin/isaacsim-vscode-paths
