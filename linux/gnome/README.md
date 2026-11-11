# Cursor Halo for GNOME Shell

This extension provides native Wayland cursor highlighting inside GNOME Shell. The 0.5.0 compatibility candidate targets **GNOME Shell 46, 50, and 51**: Ubuntu 24.04 LTS, Ubuntu 26.04 LTS, and Ubuntu 26.10 respectively. The same extension ZIP is used on x64 and ARM64. Check `gnome-shell --version` and the published release's runtime results before installing; GNOME 47–49 and other unlisted versions are not declared compatible. Other Wayland compositors require a different implementation.

On Ubuntu 26.04 LTS and 26.10 GNOME desktops, install this extension. Those desktop sessions use Wayland; the separate native Cursor Halo X11 archive is for a composited X11 desktop session. See [Ubuntu's desktop session notes](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/#wayland-session).

## Install and enable

Download `CursorHalo-<version>-gnome-shell.zip` from [Releases](https://github.com/jjs-mm/cursor-halo/releases) and compare its SHA-256 checksum with the accompanying file. Install the ZIP as your normal user:

```sh
gnome-extensions install /path/to/CursorHalo-0.5.0-gnome-shell.zip
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
- Pointer position uses Mutter's cursor notifications. GNOME consumes application button events before Shell stage signals, so click feedback samples button state every 16 ms while the user is active. Sampling stops after one second of idle time and resumes on activity. A press and release entirely between samples can be missed. There is no continuous idle rendering loop.
- At most eight short-lived click indicators are retained. GNOME's effective animation and Reduced Motion settings select a brief static indicator when motion is reduced or animations are disabled.
- Only pointer position and button state are read for drawing; events and typed keys are not logged. Settings are local, and the extension makes no network requests.
- Do not run the X11 app and the GNOME extension together. Use this extension on GNOME Wayland; use the native X11 app on supported X11 desktops.

The native test matrix requires real headless Wayland compositors on x64 and ARM64. GNOME 46 runs directly on native Ubuntu 24.04 runners; GNOME 50 and 51 use Ubuntu 26.04 and 26.10 containers on runners of the same architecture. Software rendering and a native Wayland test client exercise the actual compositor APIs. Container artifacts record the OS, Shell/package versions, and architecture. The checks cover click-through behavior, focus, virtual pointer/keyboard input, shortcut conflicts, idle recovery, bounded pulse cleanup, lock-screen session-mode cleanup, and the preferences window. Physical displays, actual next-login startup, and individual recording applications still require manual acceptance. Test a short full-display recording before relying on capture.

## Source and testing

MIT licensed; see the included LICENSE. The implementation is original code using public GNOME APIs. API research references: [Mutter CursorTracker](https://mutter.gnome.org/meta/class.CursorTracker.html), [GNOME extension architecture](https://gjs.guide/extensions/overview/architecture.html), and [GNOME Shell testing](https://gjs.guide/extensions/development/debugging.html).

From a repository checkout:

```sh
node --test linux/gnome/tests/model.test.js
bash linux/gnome/tests/smoke.sh .build/gnome-smoke
```

Run the smoke test in each declared Ubuntu/GNOME environment with a system D-Bus, software rendering, and the packages declared in CI. The test must reject an unexpected Shell major rather than silently treating a different runtime as covered. It creates isolated XDG directories and a fresh session bus. Its `--unsafe-mode` flag applies only to that test compositor to inspect assertions and inject virtual input; it is never used by the installed extension.
