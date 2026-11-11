# Cursor Halo for GNOME Shell 46

This extension provides native Wayland cursor highlighting inside GNOME Shell. It supports **GNOME Shell 46**, including Ubuntu 24.04's GNOME desktop. Other Shell versions and other Wayland compositors are not declared compatible. Check your version with `gnome-shell --version`.

## Install and enable

Download `CursorHalo-<version>-gnome-shell-46.zip` from [Releases](https://github.com/jjs-mm/cursor-halo/releases) and compare its SHA-256 checksum with the accompanying file. Install the ZIP as your normal user:

```sh
gnome-extensions install /path/to/CursorHalo-0.4.0-gnome-shell-46.zip
```

Log out and log back in so GNOME discovers the new extension, then enable it in the **Extensions** app or run:

```sh
gnome-extensions enable cursor-halo@jjs-mm.github.io
```

The crosshair icon in the top panel opens controls. **Ctrl–Alt–H** toggles the halo. Open **Settings** for appearance, click feedback, and alternate shortcuts. Preferences can also be opened with:

```sh
gnome-extensions prefs cursor-halo@jjs-mm.github.io
```

If the preferences command is missing its application, install your distribution's GNOME Extensions application (`gnome-shell-extension-prefs` on Ubuntu). No root access or background service is needed for the extension itself.

## Login, updates, and removal

GNOME loads enabled extensions at login. Use the Extensions app to disable Cursor Halo when you do not want it loaded; the in-app highlight switch only pauses highlighting. GNOME may globally disable extensions after a Shell failure or through the Extensions master switch.

For an update, disable the extension first, retain the previous downloaded ZIP for rollback, install the new archive with `gnome-extensions install --force <archive.zip>`, and log out/in before enabling it again. Logging out is necessary to unload the old JavaScript from a Wayland Shell session. To roll back, repeat these steps using the prior ZIP. Appearance settings remain in your user GSettings store.

To remove the extension:

```sh
gnome-extensions disable cursor-halo@jjs-mm.github.io
gnome-extensions uninstall cursor-halo@jjs-mm.github.io
```

## Behavior and limits

- Ring or soft disc, five colors, adjustable size/opacity/outline, contrasting secondary-click feedback, and a global toggle shortcut.
- Nonreactive compositor actors pass clicks to applications and do not take keyboard focus. The extension disables itself in the lock-screen session mode.
- Pointer position uses Mutter's cursor notifications. GNOME 46 consumes application button events before Shell stage signals, so click feedback samples button state every 16 ms while the user is active. Sampling stops after one second of idle time and resumes on activity. A press and release entirely between samples can be missed. There is no continuous idle rendering loop.
- At most eight short-lived click indicators are retained. GNOME's effective animation preference selects a brief static indicator when animations are disabled.
- Only pointer position and button state are read for drawing; events and typed keys are not logged. Settings are local, and the extension makes no network requests.
- Do not run the X11 app and the GNOME extension together. Use this extension on GNOME Wayland; use the native X11 app on supported X11 desktops.

Automated smoke tests run a real headless GNOME 46 Wayland compositor with a native Wayland test client. They cover click-through behavior, focus, virtual pointer/keyboard input, shortcut conflicts, idle recovery, bounded pulse cleanup, lock-screen session-mode cleanup, and the preferences window. Physical displays, actual next-login startup, and individual recording applications still require manual acceptance. Test a short full-display recording before relying on capture.

## Source and testing

MIT licensed; see the included LICENSE. The implementation is original code using public GNOME APIs. API research references: [Mutter CursorTracker](https://mutter.gnome.org/meta/class.CursorTracker.html), [GNOME extension architecture](https://gjs.guide/extensions/overview/architecture.html), and [GNOME Shell testing](https://gjs.guide/extensions/development/debugging.html).

From a repository checkout:

```sh
node --test linux/gnome/tests/model.test.js
bash linux/gnome/tests/smoke.sh .build/gnome-smoke
```

The smoke test requires a disposable Ubuntu 24.04 environment with GNOME Shell 46, a system D-Bus, software rendering, and the packages declared in CI. It creates isolated XDG directories and a fresh session bus. Its `--unsafe-mode` flag applies only to that test compositor to inspect assertions and inject virtual input; it is never used by the installed extension.
