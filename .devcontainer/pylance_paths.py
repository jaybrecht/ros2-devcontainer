#!/usr/bin/env python3
"""
Write Pylance's python.analysis.extraPaths for this workspace.

Pylance never sources setup.bash, so it only finds what's in extraPaths. The list
written to src/.vscode/settings.json is, in order:
  - ROS and the merged colcon install (every built interface package).
  - Each ament_python package in src/. symlink-install leaves only an egg-link
    in install/ for those, which Pylance doesn't follow, so their source folders
    are listed instead.
  - Isaac Sim's extension folders, when the install is mounted at /isaac-sim.
Any other entries already in the file are kept. Runs when the container is
created; run `pylance-paths` by hand to pick up packages added since. It only
prints when the list changes.

Isaac Sim ships .vscode/settings.json with every extension folder listed,
relative to the install root. isaacsim and its sub-namespaces are split across
those folders. A few extensions ship an __init__.py at a shared level (e.g.
isaacsim/__init__.py in isaacsim.ros2.control), which makes Pylance treat it as a
regular package and stop resolving every other isaacsim.* import, so those
extensions are left out. For the same reason, import SimulationApp from
isaacsim.simulation_app rather than isaacsim, whose __init__.py (python_packages/)
only creates it at runtime.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys

ROS_PATHS = [
    '/opt/ros/jazzy/lib/python3.12/site-packages/',
    '/ws/install/lib/python3.12/site-packages/',
]

# Kit's stdlib copy would shadow the container's; site-packages is still kept.
ISAAC_SKIP = {'kit/python/lib/python3.12'}


def load_jsonc(path):
    """Parse a VS Code settings file, which may have comments and trailing commas."""
    text = path.read_text()
    text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}


def ament_python_packages(src):
    """Return the folders of the ament_python packages under src, skipping COLCON_IGNORE."""
    found = []
    for dirpath, dirnames, filenames in os.walk(src):
        if 'COLCON_IGNORE' in filenames:
            dirnames.clear()
            continue
        dirnames[:] = sorted(d for d in dirnames if not d.startswith('.'))
        if 'package.xml' in filenames:
            xml = Path(dirpath, 'package.xml').read_text()
            if re.search(r'<build_type>\s*ament_python\s*</build_type>', xml):
                found.append(dirpath)
            dirnames.clear()  # packages don't nest
    return found


def breaks_namespace(ext):
    """Return True if ext has an __init__.py on a shared level such as isaacsim/ros2/."""
    levels = ext.name.split('-')[0].split('.')[:-1]
    if not levels or levels[0] != 'isaacsim':
        return False
    return any(ext.joinpath(*levels[:i], '__init__.py').is_file()
               for i in range(1, len(levels) + 1))


def isaac_paths(root, mount, notes):
    """Return the Isaac Sim extraPaths rewritten to absolute container paths."""
    if not (root / '.vscode' / 'settings.json').is_file():
        return []
    paths = []
    for rel in load_jsonc(root / '.vscode' / 'settings.json')['python.analysis.extraPaths']:
        if rel in ISAAC_SKIP or not (root / rel).is_dir():
            continue
        if breaks_namespace(root / rel):
            notes.append(f'Left out {rel}: it would hide the rest of isaacsim.*')
            continue
        paths.append(f'{mount}/{rel}')
    return paths


def main():
    """Rewrite the generated part of extraPaths, keeping any other entries."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument('--src', default='/ws/src', help='workspace source folder')
    parser.add_argument('--isaac-root', type=Path, default=Path('/isaac-sim'),
                        help='Isaac Sim install as seen from here (default: /isaac-sim)')
    parser.add_argument('--isaac-mount', default='/isaac-sim',
                        help='Isaac Sim path written into the settings (default: /isaac-sim)')
    parser.add_argument('--settings', type=Path,
                        default=Path('/ws/src/.vscode/settings.json'),
                        help='workspace settings file to update')
    args = parser.parse_args()

    src = args.src.rstrip('/')
    mount = args.isaac_mount.rstrip('/')
    notes = []
    packages = ament_python_packages(src)
    isaac = isaac_paths(args.isaac_root, mount, notes)

    settings = load_jsonc(args.settings) if args.settings.is_file() else {}
    existing = settings.get('python.analysis.extraPaths', [])
    generated = (src + '/', mount + '/')
    others = [p for p in existing if p not in ROS_PATHS and not p.startswith(generated)]
    paths = ROS_PATHS + packages + others + isaac
    if paths == existing:
        return

    settings['python.analysis.extraPaths'] = paths
    args.settings.parent.mkdir(parents=True, exist_ok=True)
    args.settings.write_text(json.dumps(settings, indent=4) + '\n')
    for note in notes:
        print(note, file=sys.stderr)
    print(f'Pylance paths: {len(packages)} ament_python packages, {len(isaac)} Isaac Sim, '
          f'{len(others)} other -> {args.settings}')


if __name__ == '__main__':
    main()
