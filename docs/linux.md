# Linux

Linux support depends on the desktop session. This preview provides two implementations with separate settings and lifecycle controls.

| Session | Package | Scope |
| --- | --- | --- |
| Composited X11 | `linux-x64.tar.gz` or `linux-arm64.tar.gz` | Native GTK app, tray/settings controls, global shortcut, click feedback, optional login launch |
| GNOME Shell 46, including Wayland | GNOME extension ZIP | Compositor-owned halo, click feedback, panel controls, shortcut, preferences |
| Other GNOME Shell versions | Not declared compatible | Test the actual Shell API before expanding the supported version list |
| KDE Plasma Wayland and other Wayland compositors | Unsupported | Requires a compositor-specific implementation |

Check your session with `echo "$XDG_SESSION_TYPE"`; on GNOME, check the Shell version with `gnome-shell --version`. Do not run both Cursor Halo implementations at once. A visible XWayland `DISPLAY` inside a Wayland session does not establish native X11 compatibility.

## Native X11 app

Prebuilt binaries target Ubuntu 24.04 and its glibc 2.39 baseline, on x64 or ARM64. Compatible distributions need the same or newer runtime ABI; older distributions can try a source build with their native toolchain. A compositor is required for transparent overlays. Xvfb and Openbox with xcompmgr are the automated integration environment; other desktop environments need manual acceptance.

Install runtime dependencies on Ubuntu 24.04:

```sh
sudo apt install libgtk-3-0t64 libx11-6 libxi6 libxfixes3 libxext6 libxtst6 librsvg2-common python3
```

Extract the entire archive. Run `./app/cursor-halo` directly, or install for your account:

```sh
./Install-CursorHalo.sh
```

The installer uses `$XDG_DATA_HOME/cursor-halo`, normally `~/.local/share/cursor-halo`, with an application-menu entry and a launcher at `~/.local/bin/cursor-halo`. It retains the previous app on update and preserves preferences and startup registration. See the archive's `INSTALL-LINUX.md` for rollback and uninstall instructions.

The default shortcut is **Ctrl–Alt–H**. Where the desktop has no legacy system tray, keep the settings window available or reopen Cursor Halo from the application menu. Enable **Launch at login** from settings after installation; it uses the freedesktop per-user autostart directory. Test an actual logout/login before relying on automatic startup.

The application uses the existing X11 connection. It does not require root, access to `/dev/input`, membership in an input-device group, or changes to desktop security settings. System libraries remain distribution-managed; the archive does not bundle GTK or other third-party shared libraries.

Build from source on Ubuntu 24.04:

```sh
sudo apt install build-essential cmake pkg-config libgtk-3-dev libxi-dev libxfixes-dev libxtst-dev python3
./linux/scripts/build.sh
./linux/scripts/test.sh
```

## GNOME Wayland extension

The extension runs inside GNOME Shell and draws non-reactive actors. It uses compositor pointer events and GNOME shortcut registration, so it does not need an XWayland workaround or access to input-device files. This preview declares compatibility with **GNOME Shell 46 only**.

GNOME does not forward native application button events to Shell extensions. Click feedback therefore samples button state every 16 ms while the user is active, stops after one second of idle time, and resumes on activity. Very brief clicks completed between samples can be missed. Pointer tracking remains event-driven, and the halo does not continuously redraw while idle. Turning off click feedback removes the button sampler.

Install the extension ZIP from the release using GNOME's extension tooling:

```sh
gnome-extensions install /path/to/CursorHalo-0.4.0-gnome-shell-46.zip
```

After installing, log out and back in so GNOME discovers the extension, then enable it in the Extensions application or run:

```sh
gnome-extensions enable cursor-halo@jjs-mm.github.io
gnome-extensions prefs cursor-halo@jjs-mm.github.io
```

GNOME loads enabled extensions at login. Disabling Cursor Halo in Extensions removes its overlay, pointer observers, and shortcut. There is no separate background process or autostart desktop file for this implementation. The extension is restricted to GNOME's normal user session and is not intended for the lock or sign-in screen.

For updates, disable the extension, retain the previous release ZIP, and install the new ZIP using `gnome-extensions install --force`. Log out/in before enabling the updated copy. To roll back, repeat with the retained ZIP. To uninstall, disable it and use `gnome-extensions uninstall cursor-halo@jjs-mm.github.io`; preferences may remain in GSettings.

## Validation and limits

CI checks the exact release commit. X11 runs under a composited virtual display, while GNOME runs in an isolated headless Wayland session. These environments exercise native APIs; they do not establish every physical display, desktop shell version, compositor effect, or recorder.

Use the [manual checklist](testing.md) for mixed scaling, monitor changes, physical keyboard/mouse input, lock/unlock, sleep/wake, login execution, fullscreen apps, and capture behavior. Record the distribution, desktop/Shell version, session type, and architecture with results. See [validation status](validation.md) and release notes for the checks completed on each published candidate.

Design references: [Wayland pointer protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_pointer), [GTK input regions](https://docs.gtk.org/gdk3/method.Window.input_shape_combine_region.html), [freedesktop autostart](https://specifications.freedesktop.org/autostart/latest/), and [Desktop Entry command quoting](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html).
