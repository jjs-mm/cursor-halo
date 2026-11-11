#!/usr/bin/env python3
"""Install a verified Cursor Halo package for the current user; no elevation."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import tempfile
import time

APP_ID = 'io.github.jjs_mm.CursorHalo'
MARKER = '.cursor-halo-install.json'
LAUNCHER_MARKER = '# Managed by Cursor Halo installer'
DESKTOP_MARKER = 'X-CursorHalo-Managed=true'


def ensure_safe(path: Path) -> None:
    if any(ord(character) < 32 for character in str(path)):
        raise ValueError('Control characters are not supported in installation paths.')
    if not path.is_absolute():
        raise ValueError(f'An absolute path is required: {path}')
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError(f'Refusing symbolic link: {part}')


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def read_marker(directory: Path, verify_binary: bool = False) -> dict:
    ensure_safe(directory)
    marker = directory / MARKER
    ensure_safe(marker)
    if not marker.is_file() or marker.stat().st_size > 4096:
        raise ValueError(f'Not an identified Cursor Halo installation: {directory}')
    data = json.loads(marker.read_text())
    if not isinstance(data, dict) or data.get('appId') != APP_ID or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', str(data.get('version', ''))):
        raise ValueError(f'Unrecognized application marker: {directory}')
    binary = directory / 'cursor-halo'
    ensure_safe(binary)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError(f'Missing executable: {binary}')
    if verify_binary and (not re.fullmatch(r'[0-9a-f]{64}', str(data.get('executableSha256', ''))) or file_digest(binary) != data['executableSha256']):
        raise ValueError('Executable checksum does not match the package manifest.')
    return data


def paths() -> tuple[Path, Path, Path, Path]:
    home = Path.home()
    data = Path(os.environ.get('XDG_DATA_HOME') or home / '.local/share')
    config = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    if not data.is_absolute() or not config.is_absolute():
        raise ValueError('XDG_DATA_HOME and XDG_CONFIG_HOME must be absolute when set.')
    result = (data / 'cursor-halo', home / '.local/bin/cursor-halo', data / 'applications/cursor-halo.desktop', config / 'autostart' / f'{APP_ID}.desktop')
    for item in result:
        ensure_safe(item)
    return result


def verify_managed_file(path: Path, marker: str) -> None:
    ensure_safe(path)
    if path.exists() and (not path.is_file() or path.stat().st_size > 16384 or marker not in path.read_text().splitlines()):
        raise ValueError(f'Refusing to replace an unrelated file: {path}')


def require_not_running(destination: Path) -> None:
    binary = destination / 'cursor-halo'
    proc = Path('/proc')
    if not proc.exists():
        return
    for process in proc.iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid == os.getuid() and os.readlink(process / 'exe') == str(binary):
                raise ValueError('Quit Cursor Halo before installing, updating, or uninstalling it.')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass


def atomic_write(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp = tempfile.mkstemp(prefix='.cursor-halo-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def desktop_quote(value: str) -> str:
    # Quote for Exec, then escape its backslashes for the Desktop Entry string layer.
    if '=' in value or any(ord(character) < 32 for character in value):
        raise ValueError('Equals signs and control characters are not supported in executable paths.')
    quoted = '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%') + '"'
    return quoted.replace('\\', '\\\\')


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def install(source: Path) -> Path:
    source = source.absolute()
    ensure_safe(source)
    app = source / 'app'
    metadata = read_marker(app, verify_binary=True)
    architecture = {'x86_64': 'x64', 'aarch64': 'arm64', 'arm64': 'arm64'}.get(platform.machine())
    if not architecture or metadata.get('architecture') != architecture:
        raise ValueError('This package does not match your processor architecture. Download the x64 or ARM64 archive for this machine.')
    if not (app / 'LICENSE').is_file() or (app / 'LICENSE').is_symlink():
        raise ValueError('The application license is missing.')
    for entry in app.rglob('*'):
        if entry.is_symlink() or (not entry.is_dir() and not entry.is_file()):
            raise ValueError(f'Refusing special package entry: {entry}')
    destination, launcher, desktop, _ = paths()
    if destination.exists():
        read_marker(destination)
    verify_managed_file(launcher, LAUNCHER_MARKER)
    verify_managed_file(desktop, DESKTOP_MARKER)
    require_not_running(destination)
    executable = destination / 'cursor-halo'
    launcher_content = f'#!/bin/sh\n{LAUNCHER_MARKER}\nexec {shell_quote(str(executable))} "$@"\n'.encode()
    desktop_content = f'[Desktop Entry]\nType=Application\nName=Cursor Halo\nComment=Make your pointer easy to follow\nExec=/usr/bin/env -- {desktop_quote(str(executable))}\nIcon=input-mouse\nTerminal=false\nCategories=Utility;Accessibility;\nStartupNotify=false\n{DESKTOP_MARKER}\n'.encode()
    original_files = {path: (path.read_bytes(), path.stat().st_mode & 0o777) if path.exists() else None for path in (launcher, desktop)}
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.cursor-halo-stage-', dir=destination.parent))
    backup = None
    installed = False
    changed_files = []
    try:
        shutil.copytree(app, staging, dirs_exist_ok=True)
        read_marker(staging, verify_binary=True)
        if destination.exists():
            backup = destination.with_name(f'cursor-halo.backup-{time.time_ns()}')
            if backup.exists() or backup.is_symlink():
                raise ValueError('Backup destination unexpectedly exists.')
            os.replace(destination, backup)
        os.replace(staging, destination)
        installed = True
        atomic_write(launcher, launcher_content, 0o755)
        changed_files.append(launcher)
        atomic_write(desktop, desktop_content, 0o644)
        changed_files.append(desktop)
    except Exception as error:
        rollback_errors = []
        # Recover the application before touching launcher files. A persistent
        # desktop-entry write failure must not strand the new application.
        try:
            if installed and destination.is_dir():
                shutil.rmtree(destination)
            if backup is not None and backup.exists():
                os.replace(backup, destination)
        except Exception as rollback_error:
            rollback_errors.append(f'application: {rollback_error}')
        for path in reversed(changed_files):
            original = original_files[path]
            try:
                if original is None:
                    if path.is_file() and not path.is_symlink():
                        path.unlink()
                else:
                    atomic_write(path, original[0], original[1])
            except Exception as rollback_error:
                rollback_errors.append(f'{path}: {rollback_error}')
        if rollback_errors:
            retained = f' Retained backup: {backup}.' if backup is not None and backup.exists() else ''
            raise ValueError(f'{error}; rollback needs attention: {"; ".join(rollback_errors)}.{retained}') from error
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"Installed Cursor Halo {metadata['version']} to {destination}")
    print(f'Launch it from your application menu or {launcher}')
    if backup is not None:
        print(f'Previous version retained at {backup}')
    return destination


def uninstall() -> None:
    destination, launcher, desktop, startup = paths()
    read_marker(destination)
    verify_managed_file(launcher, LAUNCHER_MARKER)
    verify_managed_file(desktop, DESKTOP_MARKER)
    if startup.exists():
        raise ValueError('Disable launch at login in Cursor Halo before uninstalling it.')
    require_not_running(destination)
    for item in (launcher, desktop):
        if item.exists():
            item.unlink()
    shutil.rmtree(destination)
    print('Uninstalled Cursor Halo. Preferences and retained backups were preserved.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', nargs='?', type=Path, default=Path(__file__).absolute().parent)
    parser.add_argument('--uninstall', action='store_true')
    args = parser.parse_args()
    try:
        if args.uninstall:
            uninstall()
        else:
            install(args.source)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(1, f'Cursor Halo installation failed: {error}\n')


if __name__ == '__main__':
    main()
