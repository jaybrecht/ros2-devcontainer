#!/usr/bin/env python3
"""
Point Pylance at the Isaac Sim install mounted at /isaac-sim.

Isaac Sim ships .vscode/settings.json with every extension folder listed in
python.analysis.extraPaths, relative to the install root. This script prefixes
those paths with the container mount point and merges them into the workspace
settings, keeping any non-Isaac entries (ROS, ament_python packages) as they are.
Re-run it after upgrading Isaac Sim.

isaacsim and its sub-namespaces are split across hundreds of extension folders.
A few extensions ship an __init__.py at a shared level (e.g. isaacsim/__init__.py
in isaacsim.ros2.control), which makes Pylance treat it as a regular package and
stop resolving every other isaacsim.* import, so those extensions are left out.
For the same reason, import SimulationApp from isaacsim.simulation_app rather
than isaacsim, whose __init__.py (python_packages/) only creates it at runtime.
"""

import argparse
import json
from pathlib import Path
import re
import sys

ROS_DEFAULTS = [
    '/opt/ros/jazzy/lib/python3.12/site-packages/',
    '/ws/install/lib/python3.12/site-packages/',
]

# Kit's stdlib copy would shadow the container's; site-packages is still kept.
SKIP = {'kit/python/lib/python3.12'}


def load_jsonc(path):
    """Parse a VS Code settings file, which may have comments and trailing commas."""
    text = path.read_text()
    text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
    text = re.sub(r',(\s*[}\]])', r'\1', text)
    return json.loads(text) if text.strip() else {}


def breaks_namespace(ext):
    """Return True if ext has an __init__.py on a shared level such as isaacsim/ros2/."""
    levels = ext.name.split('-')[0].split('.')[:-1]
    if not levels or levels[0] != 'isaacsim':
        return False
    return any(ext.joinpath(*levels[:i], '__init__.py').is_file()
               for i in range(1, len(levels) + 1))


def isaac_paths(root, mount):
    """Return the Isaac Sim extraPaths rewritten to absolute container paths."""
    paths = []
    for rel in load_jsonc(root / '.vscode' / 'settings.json')['python.analysis.extraPaths']:
        if rel in SKIP or not (root / rel).is_dir():
            continue
        if breaks_namespace(root / rel):
            print(f'Leaving out {rel}: it would hide the rest of isaacsim.*', file=sys.stderr)
            continue
        paths.append(f'{mount}/{rel}')
    return paths


def main():
    """Merge the Isaac Sim paths into the workspace settings."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument('--root', type=Path, default=Path('/isaac-sim'),
                        help='Isaac Sim install as seen from here (default: /isaac-sim)')
    parser.add_argument('--mount', default='/isaac-sim',
                        help='path written into the settings (default: /isaac-sim)')
    parser.add_argument('--settings', type=Path,
                        default=Path('/ws/src/.vscode/settings.json'),
                        help='workspace settings file to update')
    args = parser.parse_args()

    if not (args.root / '.vscode' / 'settings.json').is_file():
        print(f'{args.root} is not an Isaac Sim install, skipping', file=sys.stderr)
        return

    settings = load_jsonc(args.settings) if args.settings.is_file() else {}
    existing = settings.get('python.analysis.extraPaths', ROS_DEFAULTS)
    mount = args.mount.rstrip('/')
    kept = [p for p in existing if not p.startswith(mount + '/')]
    isaac = isaac_paths(args.root, mount)
    settings['python.analysis.extraPaths'] = kept + isaac

    args.settings.parent.mkdir(parents=True, exist_ok=True)
    args.settings.write_text(json.dumps(settings, indent=4) + '\n')
    print(f'Wrote {len(kept)} existing + {len(isaac)} Isaac Sim paths to {args.settings}')


if __name__ == '__main__':
    main()
