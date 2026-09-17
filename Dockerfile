FROM ros:jazzy-ros-base

RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Dependencies are resolved from each package's package.xml (ROS/apt) and
# requirements.txt (pip) at build time. Ubuntu 24.04 blocks system-wide pip
# installs unless --break-system-packages is passed.
COPY src /tmp/src
RUN apt-get update \
 && rosdep install --from-paths /tmp/src --ignore-src -y \
 && find /tmp/src -name requirements.txt -print0 \
  | xargs -0 -r -n1 pip install --break-system-packages --no-cache-dir -r \
 && rm -rf /tmp/src /var/lib/apt/lists/*

# Run as a user matching the host UID/GID so files created in the container
# belong to you on the host instead of root. /ws must be owned by that user or
# colcon can't write build/ install/ log/.
RUN groupadd -g 36700 dev \
 && useradd -m -u 67851 -g 36700 -s /bin/zsh dev \
 && mkdir -p /ws \
 && chown dev:dev /ws

USER dev
WORKDIR /ws

RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /home/dev/.oh-my-zsh
COPY --chown=dev:dev zshrc /home/dev/.zshrc
