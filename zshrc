export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(git)

source $ZSH/oh-my-zsh.sh

# ROS2
function jazzy () {
  export ROS_DOMAIN_ID=8
  source /opt/ros/jazzy/setup.zsh
  eval "$(register-python-argcomplete ros2)"
  eval "$(register-python-argcomplete colcon)"
  PYTHONWARNINGS="ignore:easy_install command is deprecated,ignore:setup.py install is deprecated"
  export PYTHONWARNINGS
  export RCUTILS_COLORIZED_OUTPUT=1
}

function sw () {
  source install/setup.zsh
  eval "$(register-python-argcomplete ros2)"
  eval "$(register-python-argcomplete colcon)"
}

function rosdep_run () {
  rosdep install --from-paths src -y --ignore-src
}

alias venv=". .venv/bin/activate"
