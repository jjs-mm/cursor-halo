#!/usr/bin/env python3
"""Probe the real application entry point inside the isolated X11 smoke session."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

binary, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
checks = []
log = (output / 'application.log').open('w')
application = None
try:
    application = subprocess.Popen([str(binary)], stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 10
    windows = []
    while time.monotonic() < deadline:
        if application.poll() is not None:
            raise AssertionError('Normal application exited before showing settings; see application.log')
        search = subprocess.run(['xdotool', 'search', '--all', '--onlyvisible', '--pid', str(application.pid), '--name', '^Cursor Halo$'], capture_output=True, text=True, timeout=2)
        windows = search.stdout.split()
        if windows:
            break
        time.sleep(0.05)
    assert len(windows) == 1, f'Expected one visible settings window from the real application, got {windows}'
    checks.append('Normal application launch renders its settings window')
    second = subprocess.run([str(binary)], stdout=log, stderr=subprocess.STDOUT, timeout=5)
    assert second.returncode == 0, 'Second invocation did not hand off successfully'
    assert application.poll() is None, 'Original instance stopped during handoff'
    after = subprocess.run(['xdotool', 'search', '--all', '--onlyvisible', '--name', '^Cursor Halo$'], capture_output=True, text=True, timeout=2)
    assert after.stdout.split() == windows, 'Second launch created an extra settings window'
    checks.append('Second invocation exits and hands off to the original D-Bus application instance')
    rejected_path = output / 'unsupported-wayland.json'
    rejected_path.unlink(missing_ok=True)
    rejected = subprocess.run([str(binary), '--smoke-test', str(rejected_path)], env=dict(os.environ, XDG_SESSION_TYPE='wayland', WAYLAND_DISPLAY='wayland-unsupported-test'), capture_output=True, text=True, timeout=5)
    assert rejected.returncode == 2 and not rejected_path.exists(), 'XWayland must not produce a false passing smoke result'
    assert 'requires an X11 desktop session' in rejected.stderr
    checks.append('Wayland session is rejected explicitly without a partial overlay or false smoke result')
    result = {'success': True, 'checks': checks}
    (output / 'cli-smoke.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    if application is not None:
        application.terminate()
        try:
            application.wait(timeout=5)
        except subprocess.TimeoutExpired:
            application.kill()
            application.wait(timeout=5)
    log.close()
