FROM ros:jazzy-ros-base

RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh python3-pip \
 && rm -rf /var/lib/apt/lists/*

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

RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /home/dev/.oh-my-zsh
COPY --chown=dev:dev zshrc /home/dev/.zshrc
COPY --chown=dev:dev colcon-defaults.yaml /home/dev/.colcon/defaults.yaml
