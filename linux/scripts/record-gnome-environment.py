#!/usr/bin/env python3
"""Assert and record the actual native GNOME test environment."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('expected_major')
parser.add_argument('output', type=Path)
args = parser.parse_args()
if not re.fullmatch(r'[0-9]+', args.expected_major):
    parser.error('Expected GNOME Shell major must be numeric.')
version = subprocess.check_output(['gnome-shell', '--version'], text=True).strip()
architecture = platform.machine()
expected_architecture = os.environ.get('CURSOR_HALO_EXPECTED_ARCH')
if expected_architecture and architecture != expected_architecture:
    raise SystemExit(f'Expected native architecture {expected_architecture}, found {architecture}.')
match = re.match(r'^GNOME Shell ([0-9]+)(?:\.|$)', version)
if not match or match[1] != args.expected_major:
    raise SystemExit(f'Expected GNOME Shell {args.expected_major}, found {version}.')
packages = subprocess.check_output(['dpkg-query', '-W', '-f=${db:Status-Status}\t${Package}\t${Version}\n', 'gnome-shell', 'gjs', 'libmutter-*', 'gsettings-desktop-schemas'], text=True)
installed = [line.split('\t', 1)[1] for line in packages.splitlines() if line.startswith('installed\t')]
data = {'expectedShellMajor': args.expected_major, 'shellVersion': version,
        'architecture': architecture, 'osRelease': Path('/etc/os-release').read_text(),
        'baseImage': os.environ.get('CURSOR_HALO_BASE_IMAGE'), 'packages': installed}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(data, indent=2) + '\n')
print(json.dumps(data, indent=2))
