#!/usr/bin/env python3
"""Bounded integration probe inside a disposable supported GNOME Wayland compositor."""
import ast
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time

out = Path(sys.argv[1]).resolve()
checks = []
shell_version = subprocess.check_output(['gnome-shell', '--version'], text=True).strip()
shell_major = int(re.search(r'\b(\d+)(?:\.|$)', shell_version).group(1))
if shell_major not in (46, 50, 51):
    raise RuntimeError(f'Unexpected GNOME version: {shell_version}')
shell_log = (out / 'gnome-shell.log').open('w')
shell = subprocess.Popen(['gnome-shell', '--headless', '--wayland', '--no-x11', '--virtual-monitor', '1280x720', '--unsafe-mode'],
                         stdout=shell_log, stderr=subprocess.STDOUT)
client = None
uuid = 'cursor-halo@jjs-mm.github.io'
extension = f"Main.extensionManager.lookup('{uuid}').stateObj"

def evaluate(code):
    command = ['gdbus', 'call', '--session', '--dest', 'org.gnome.Shell', '--object-path', '/org/gnome/Shell',
               '--method', 'org.gnome.Shell.Eval', code]
    result = subprocess.run(command, text=True, capture_output=True, timeout=5)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    response = ast.literal_eval(result.stdout.replace('(true,', '(True,', 1).replace('(false,', '(False,', 1))
    if not response[0]:
        raise RuntimeError(response[1])
    return json.loads(response[1]) if response[1] else None

def wait_until(predicate, seconds=15):
    deadline = time.monotonic() + seconds
    last_error = None
    while time.monotonic() < deadline:
        if shell.poll() is not None:
            raise RuntimeError(f'GNOME Shell exited with {shell.returncode}; see gnome-shell.log')
        try:
            result = predicate()
            if result:
                return result
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise RuntimeError(f'Timed out waiting for compositor condition: {last_error}')

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    checks.append(message)
    print('PASS:', message, flush=True)

try:
    wait_until(lambda: evaluate(f"Boolean({extension}?._halo)"), 30)
    check(evaluate('Boolean(GLib.getenv("WAYLAND_DISPLAY"))'), 'Loaded extension in an actual GNOME Wayland compositor')
    check(evaluate(f"!{extension}._halo.reactive && !{extension}._halo.can_focus"), 'Overlay actor is nonreactive and cannot focus')
    check(evaluate(f"{extension}._action > 0"), 'Global toggle shortcut registered')
    evaluate("Main.overview.hide()")
    evaluate("(async () => { const {default: Clutter} = await import('gi://Clutter'); "
             "const backend = typeof global.stage.get_context === 'function' ? global.stage.get_context().get_backend() : Clutter.get_default_backend(); "
             "global._haloSmokePointer = backend.get_default_seat().create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE); "
             "return true; })()")
    wayland_name = wait_until(lambda: evaluate('GLib.getenv("WAYLAND_DISPLAY")'))
    client_env = dict(os.environ, WAYLAND_DISPLAY=wayland_name, GDK_BACKEND='wayland')
    clicked = out / 'clicked'
    clicked.unlink(missing_ok=True)
    client = subprocess.Popen(['gjs', '-m', str(Path(__file__).with_name('wayland-client.js')), str(clicked)],
                              env=client_env, stdout=shell_log, stderr=subprocess.STDOUT)
    window_expr = "global.get_window_actors().map(a => a.meta_window).find(w => w.get_title() === 'Cursor Halo Wayland smoke client')"
    wait_until(lambda: evaluate(f"Boolean({window_expr})"))
    wait_until(lambda: evaluate(f"({window_expr}).get_compositor_private().is_mapped() && ({window_expr}).get_frame_rect().width > 400"))
    evaluate(f"({window_expr}).activate(global.get_current_time())")
    wait_until(lambda: evaluate("global.display.focus_window?.get_title() === 'Cursor Halo Wayland smoke client'"))
    rect = evaluate(f"(() => {{ const r=({window_expr}).get_frame_rect(); return [r.x,r.y,r.width,r.height]; }})()")
    x, y = rect[0] + rect[2] // 2, rect[1] + rect[3] // 2
    # Exercise ordinary relative mouse motion. Current headless Mutter virtual
    # absolute warps can constrain an axis while a surface is first activated.
    evaluate(f'global._haloSmokePointer.notify_relative_motion(GLib.get_monotonic_time(), {x} - global.get_pointer()[0], 0)')
    wait_until(lambda: evaluate(f'Math.abs(global.get_pointer()[0] - {x}) < 2'))
    evaluate(f'global._haloSmokePointer.notify_relative_motion(GLib.get_monotonic_time(), 0, {y} - global.get_pointer()[1])')
    wait_until(lambda: evaluate(f'Math.abs(global.get_pointer()[1] - {y}) < 2'))
    wait_until(lambda: evaluate(f'Math.abs({extension}._halo.x + {extension}._halo.width / 2 - {x}) < 2 && Math.abs({extension}._halo.y + {extension}._halo.height / 2 - {y}) < 2'))
    check(True, 'Pointer tracking follows input over a native Wayland client')
    focus_before = evaluate('global.display.focus_window?.get_title()')
    evaluate('global._haloSmokePointer.notify_button(GLib.get_monotonic_time(), 1, 1)')
    wait_until(lambda: clicked.exists(), 3)
    wait_until(lambda: evaluate(f'{extension}._pulses.size > 0'), 1)
    check(True, 'Client receives click through overlay and click feedback is rendered')
    evaluate('global._haloSmokePointer.notify_button(GLib.get_monotonic_time(), 1, 0)')
    evaluate("(async () => { const {default: Clutter} = await import('gi://Clutter'); "
             "const backend = typeof global.stage.get_context === 'function' ? global.stage.get_context().get_backend() : Clutter.get_default_backend(); "
             "global._haloSmokeKeyboard = backend.get_default_seat().create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE); "
             "return true; })()")
    def toggle_with_keyboard():
        evaluate('for (const key of [65507,65513,104]) global._haloSmokeKeyboard.notify_keyval(GLib.get_monotonic_time(),key,1)')
        evaluate('for (const key of [104,65513,65507]) global._haloSmokeKeyboard.notify_keyval(GLib.get_monotonic_time(),key,0)')
    toggle_with_keyboard()
    wait_until(lambda: evaluate(f'!{extension}._settings.get_boolean("enabled")'))
    toggle_with_keyboard()
    wait_until(lambda: evaluate(f'{extension}._settings.get_boolean("enabled")'))
    check(True, 'Virtual Ctrl-Alt-H input toggles off and on while a Wayland client has focus')
    check(evaluate('global.display.focus_window?.get_title()') == focus_before, 'Overlay preserves the client keyboard focus')
    wait_until(lambda: evaluate(f'{extension}._pulses.size === 0'))
    check(True, 'Click feedback expires')
    old_action = evaluate(f'{extension}._action')
    evaluate("global._haloSmokeConflict = global.display.grab_accelerator('<Control><Alt>c', Meta.KeyBindingFlags.NONE)")
    evaluate(f'{extension}._settings.set_int("shortcut", 1)')
    check(evaluate(f'{extension}._action') == old_action and evaluate(f'{extension}._settings.get_int("shortcut")') == 0,
          'Shortcut conflict preserves active registration and rolls back saved selection')
    evaluate('global.display.ungrab_accelerator(global._haloSmokeConflict)')
    evaluate(f'{extension}._interface.set_boolean("enable-animations", false)')
    evaluate(f'for (let i=0;i<20;i++) {extension}._pulse({x},{y},1)')
    check(evaluate(f'{extension}._pulses.size <= 8 && {extension}._pulseTimeouts.size <= 8'), 'Reduced-motion actors and expiry sources are bounded')
    wait_until(lambda: evaluate(f'{extension}._pulses.size === 0 && {extension}._pulseTimeouts.size === 0'))
    check(True, 'Reduced-motion feedback expires without stale timer callbacks')
    if shell_major >= 51:
        evaluate("(async () => { global._haloSmokeSt = (await import('gi://St')).default; })()")
        evaluate("global._haloSmokeA11y = new Gio.Settings({schema_id:'org.gnome.desktop.a11y.interface'}); global._haloSmokeA11y.set_enum('reduced-motion', 1)")
        evaluate(f'{extension}._interface.set_boolean("enable-animations", true)')
        wait_until(lambda: evaluate("Boolean(global._haloSmokeSt) && global._haloSmokeSt.Settings.get().reduced_motion === global._haloSmokeSt.ReducedMotion.REDUCE"))
        wait_until(lambda: evaluate(f'!{extension}._usesMotion()'))
        evaluate(f'{extension}._pulse({x},{y},1)')
        check(evaluate(f'{extension}._pulseTimeouts.size === 1'), 'GNOME 51 reduced-motion preference selects static feedback independently of animation enablement')
        wait_until(lambda: evaluate(f'{extension}._pulses.size === 0 && {extension}._pulseTimeouts.size === 0'))
        evaluate('global._haloSmokeA11y.reset("reduced-motion")')
        evaluate(f'{extension}._interface.set_boolean("enable-animations", false)')
    wait_until(lambda: evaluate(f'!{extension}._buttonPollId && Boolean({extension}._userWatchId)'), 3)
    check(True, 'Button sampling stops while idle')
    evaluate('global._haloSmokePointer.notify_button(GLib.get_monotonic_time(), 1, 1)')
    wait_until(lambda: evaluate(f'{extension}._pulses.size > 0 && Boolean({extension}._buttonPollId)'), 1)
    check(True, 'A click after idle resumes observation and feedback')
    evaluate('global._haloSmokePointer.notify_button(GLib.get_monotonic_time(), 1, 0)')
    evaluate(f'{extension}._settings.set_boolean("enabled", false)')
    check(evaluate(f'!{extension}._halo && !{extension}._positionId && !{extension}._buttonPollId && !{extension}._idleWatchId && !{extension}._userWatchId'), 'Pausing removes overlay and pointer observation')
    evaluate(f'{extension}._settings.set_boolean("enabled", true)')
    check(evaluate(f'Boolean({extension}._halo)'), 'Highlighting can resume')
    evaluate(f'global._haloSmokeBeforeLock = {extension}; Main.sessionMode.pushMode("unlock-dialog")')
    wait_until(lambda: evaluate('!global._haloSmokeBeforeLock._halo && !global._haloSmokeBeforeLock._action'))
    check(True, 'Entering the lock-screen session mode disables extension visuals and shortcuts')
    evaluate('Main.sessionMode.popMode("unlock-dialog")')
    wait_until(lambda: evaluate(f'Boolean({extension}._halo)'))
    check(True, 'Returning to the user session restores the extension')
    subprocess.run(['gnome-extensions', 'prefs', uuid], env=client_env, check=True, timeout=10,
                   stdout=shell_log, stderr=subprocess.STDOUT)
    wait_until(lambda: evaluate("global.get_window_actors().some(a => a.meta_window.get_title() === 'Cursor Halo')"), 10)
    wait_until(lambda: evaluate("global.get_window_actors().some(a => a.meta_window.get_title() === 'Cursor Halo' && a.is_mapped() && a.meta_window.get_frame_rect().width > 400)"), 10)
    evaluate("global.get_window_actors().find(a => a.meta_window.get_title() === 'Cursor Halo').meta_window.activate(global.get_current_time())")
    wait_until(lambda: evaluate("global.display.focus_window?.get_title() === 'Cursor Halo'"), 5)
    check(True, 'Native GTK preferences window opens successfully')
    screenshot = json.dumps(str(out / 'settings.png'))
    evaluate(f'(async () => {{ const stream=Gio.File.new_for_path({screenshot}).replace(null,false,Gio.FileCreateFlags.REPLACE_DESTINATION,null); await new Shell.Screenshot().screenshot(false,stream); stream.close(null); global._haloScreenshotSaved = true; }})()')
    wait_until(lambda: evaluate('global._haloScreenshotSaved === true'))
    evaluate(f'global._haloSmokeExtension = {extension}; Main.extensionManager.disableExtension("{uuid}")')
    wait_until(lambda: evaluate('!global._haloSmokeExtension._halo && !global._haloSmokeExtension._action'))
    check(evaluate('!global._haloSmokeExtension._button && global._haloSmokeExtension._pulses.size === 0'), 'Disabling removes all owned actors, hotkeys, and panel controls')
    result = {'success': True, 'shellVersion': shell_version, 'checks': checks}
    (out / 'native-smoke.json').write_text(json.dumps(result, indent=2) + '\n')
finally:
    if client is not None:
        client.terminate()
        try: client.wait(timeout=5)
        except subprocess.TimeoutExpired: client.kill()
    shell.terminate()
    try: shell.wait(timeout=5)
    except subprocess.TimeoutExpired: shell.kill()
    shell_log.close()
