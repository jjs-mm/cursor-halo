#!/usr/bin/env python3
"""Exercise installer identity, rollback, ownership and preference guarantees."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name('install.py').resolve()
spec = importlib.util.spec_from_file_location('cursor_halo_installer', SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cursor-halo-install-test-')
        self.root = Path(self.temp.name).resolve()
        self.user = self.root / 'user with spaces'
        self.user.mkdir()
        self.data = self.user / 'data'
        self.config = self.user / 'config'
        self.env = {'HOME': str(self.user), 'XDG_DATA_HOME': str(self.data), 'XDG_CONFIG_HOME': str(self.config)}
        self.environ = mock.patch.dict(os.environ, self.env)
        self.environ.start()
        self.source = self.root / 'package'
        self.app = self.source / 'app'
        self.app.mkdir(parents=True)
        self.write_package('0.4.0')
        self.destination = self.data / 'cursor-halo'
        self.launcher = self.user / '.local/bin/cursor-halo'
        self.desktop = self.data / 'applications/cursor-halo.desktop'

    def tearDown(self):
        self.environ.stop()
        self.temp.cleanup()

    def write_package(self, version):
        executable = self.app / 'cursor-halo'
        executable.write_text(f'#!/bin/sh\nprintf "Cursor Halo {version}\\n"\n')
        executable.chmod(0o755)
        (self.app / 'LICENSE').write_text('MIT test license\n')
        architecture = {'x86_64': 'x64', 'aarch64': 'arm64', 'arm64': 'arm64'}[installer.platform.machine()]
        (self.app / installer.MARKER).write_text(json.dumps({'appId': installer.APP_ID, 'version': version, 'architecture': architecture, 'executableSha256': hashlib.sha256(executable.read_bytes()).hexdigest()}))

    def test_install_update_rollback_and_preserve_user_state(self):
        preferences = self.config / 'cursor-halo/settings.conf'
        preferences.parent.mkdir(parents=True)
        preferences.write_bytes(b'unchanged preferences\n')
        startup = self.config / 'autostart' / f'{installer.APP_ID}.desktop'
        startup.parent.mkdir(parents=True)
        startup.write_bytes(b'unchanged startup registration\n')
        installer.install(self.source)
        self.assertEqual(subprocess.check_output([str(self.launcher), '--version'], text=True).strip(), 'Cursor Halo 0.4.0')
        self.write_package('0.4.1')
        installer.install(self.source)
        self.assertEqual(subprocess.check_output([str(self.launcher), '--version'], text=True).strip(), 'Cursor Halo 0.4.1')
        backups = list(self.data.glob('cursor-halo.backup-*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(installer.read_marker(backups[0], True)['version'], '0.4.0')
        self.assertEqual(preferences.read_bytes(), b'unchanged preferences\n')
        self.assertEqual(startup.read_bytes(), b'unchanged startup registration\n')
        self.assertEqual((self.destination / 'LICENSE').read_bytes(), (self.app / 'LICENSE').read_bytes())
        with self.assertRaisesRegex(ValueError, 'Disable launch at login'):
            installer.uninstall()
        startup.unlink()
        installer.uninstall()
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.launcher.exists())
        self.assertFalse(self.desktop.exists())
        self.assertTrue(preferences.exists())
        self.assertTrue(backups[0].exists())

    def test_rejects_checksum_mismatch_before_mutation(self):
        (self.app / 'cursor-halo').write_text('tampered')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            installer.install(self.source)
        self.assertFalse(self.data.exists())

    def test_rejects_wrong_processor_before_mutation(self):
        marker_path = self.app / installer.MARKER
        metadata = json.loads(marker_path.read_text())
        metadata['architecture'] = 'arm64' if metadata['architecture'] == 'x64' else 'x64'
        marker_path.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'processor architecture'):
            installer.install(self.source)
        self.assertFalse(self.data.exists())

    def test_rejects_foreign_installation(self):
        self.destination.mkdir(parents=True)
        note = self.destination / 'unrelated'
        note.write_text('keep')
        with self.assertRaises(ValueError):
            installer.install(self.source)
        self.assertEqual(note.read_text(), 'keep')

    def test_rejects_foreign_launcher(self):
        self.launcher.parent.mkdir(parents=True)
        self.launcher.write_text('keep unrelated launcher')
        with self.assertRaisesRegex(ValueError, 'unrelated'):
            installer.install(self.source)
        self.assertEqual(self.launcher.read_text(), 'keep unrelated launcher')
        self.assertFalse(self.destination.exists())

    def test_rejects_symlink_destination_and_source(self):
        self.data.mkdir(parents=True)
        target = self.root / 'foreign'
        target.mkdir()
        self.destination.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symbolic link'):
            installer.install(self.source)
        self.destination.unlink()
        (self.app / 'extra').symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'special package'):
            installer.install(self.source)
        self.assertEqual(list(target.iterdir()), [])

    def test_rolls_back_app_if_launcher_write_fails(self):
        installer.install(self.source)
        previous_launcher = self.launcher.read_bytes()
        previous_desktop = self.desktop.read_bytes()
        self.write_package('0.4.1')
        write = installer.atomic_write
        calls = 0
        def fail_once(path, content, mode):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('simulated desktop write failure')
            return write(path, content, mode)
        with mock.patch.object(installer, 'atomic_write', fail_once):
            with self.assertRaisesRegex(OSError, 'simulated'):
                installer.install(self.source)
        self.assertEqual(installer.read_marker(self.destination, True)['version'], '0.4.0')
        self.assertEqual(self.launcher.read_bytes(), previous_launcher)
        self.assertEqual(self.desktop.read_bytes(), previous_desktop)
        self.assertEqual(list(self.data.glob('cursor-halo.backup-*')), [])

    def test_rejects_relative_xdg_paths(self):
        with mock.patch.dict(os.environ, {'XDG_DATA_HOME': 'relative'}):
            with self.assertRaisesRegex(ValueError, 'absolute'):
                installer.install(self.source)
        self.assertFalse(self.data.exists())

    def test_persistent_desktop_failure_cannot_prevent_app_rollback(self):
        installer.install(self.source)
        previous_launcher = self.launcher.read_bytes()
        previous_desktop = self.desktop.read_bytes()
        self.write_package('0.4.1')
        write = installer.atomic_write
        def persistent_failure(path, content, mode):
            if path == self.desktop:
                raise PermissionError('persistent desktop write failure')
            return write(path, content, mode)
        with mock.patch.object(installer, 'atomic_write', persistent_failure):
            with self.assertRaisesRegex(PermissionError, 'persistent'):
                installer.install(self.source)
        self.assertEqual(installer.read_marker(self.destination, True)['version'], '0.4.0')
        self.assertEqual(self.launcher.read_bytes(), previous_launcher)
        self.assertEqual(self.desktop.read_bytes(), previous_desktop)
        self.assertEqual(list(self.data.glob('cursor-halo.backup-*')), [])

    def test_rejects_unrepresentable_executable_paths(self):
        for value in ('/tmp/equal=sign/cursor-halo', '/tmp/new\nline/cursor-halo'):
            with self.assertRaises(ValueError):
                installer.desktop_quote(value)

    @unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('gio'), 'requires the Linux GIO desktop launcher')
    def test_desktop_and_shell_launch_with_reserved_characters(self):
        unusual = self.root / 'user $cash %percent "quote" `tick` \\backslash'
        unusual.mkdir()
        probe = self.root / 'desktop-launch-result'
        executable = self.app / 'cursor-halo'
        executable.write_text('#!/bin/sh\nprintf "launched" > "$CURSOR_HALO_INSTALL_TEST_PROBE"\n')
        executable.chmod(0o755)
        marker = json.loads((self.app / installer.MARKER).read_text())
        marker['executableSha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
        (self.app / installer.MARKER).write_text(json.dumps(marker))
        env = {'HOME': str(unusual), 'XDG_DATA_HOME': str(unusual / 'data'), 'XDG_CONFIG_HOME': str(unusual / 'config'), 'CURSOR_HALO_INSTALL_TEST_PROBE': str(probe)}
        with mock.patch.dict(os.environ, env):
            installer.install(self.source)
            subprocess.run([str(unusual / '.local/bin/cursor-halo')], check=True)
            self.assertEqual(probe.read_text(), 'launched')
            probe.unlink()
            subprocess.run(['gio', 'launch', str(unusual / 'data/applications/cursor-halo.desktop')], check=True)
            deadline = time.monotonic() + 5
            while not probe.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertEqual(probe.read_text(), 'launched')


def test_real_package(source: Path):
    source = source.resolve()
    with tempfile.TemporaryDirectory(prefix='cursor-halo-package-install-') as temp:
        user = Path(temp).resolve() / 'user'
        user.mkdir()
        env = dict(os.environ, HOME=str(user), XDG_DATA_HOME=str(user / 'data'), XDG_CONFIG_HOME=str(user / 'config'))
        command = [sys.executable, str(source / 'install.py'), str(source)]
        destination = user / 'data/cursor-halo'
        config = user / 'config/cursor-halo'
        config.mkdir(parents=True)
        preferences = config / 'settings.conf'
        preferences.write_text('installer must preserve this file')
        startup = user / 'config/autostart' / f'{installer.APP_ID}.desktop'
        startup.parent.mkdir(parents=True)
        startup.write_text('installer must preserve this startup file')
        subprocess.run(command, env=env, check=True)
        metadata = installer.read_marker(destination, True)
        output = subprocess.check_output([str(destination / 'cursor-halo'), '--version'], env=env, text=True).strip()
        assert output == f"Cursor Halo {metadata['version']}", output
        subprocess.run(command, env=env, check=True)
        backups = list((user / 'data').glob('cursor-halo.backup-*'))
        assert len(backups) == 1
        assert installer.read_marker(backups[0], True) == metadata
        assert (destination / 'LICENSE').read_bytes() == (source / 'LICENSE').read_bytes()
        assert preferences.read_text() == 'installer must preserve this file'
        assert startup.read_text() == 'installer must preserve this startup file'
        print('Verified real package fresh installation, update, backup, version, license and unchanged preferences/startup registration.')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--package':
        test_real_package(Path(sys.argv[2]))
    else:
        unittest.main()
