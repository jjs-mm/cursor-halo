# Cursor Halo for Linux (X11 preview)

These native builds target Ubuntu 24.04 or a compatible Linux distribution with glibc 2.39 or newer. Use the archive for your processor: x64 (Intel/AMD) or ARM64. They require a **composited X11 session**. An XWayland connection inside a Wayland session does not provide desktop-wide cursor tracking; the app detects this and explains the limitation instead of claiming full support.

Install the runtime libraries using your distribution's package manager. On Ubuntu/Debian:

```sh
sudo apt install libgtk-3-0t64 libx11-6 libxi6 libxfixes3 libxtst6 libxext6 librsvg2-common python3
```

Extract the complete archive, then run `./app/cursor-halo`. You can also install it for your account without administrator privileges:

```sh
./Install-CursorHalo.sh
```

The installer verifies the package checksum, installs to `$XDG_DATA_HOME/cursor-halo` (default `~/.local/share/cursor-halo`), creates `~/.local/bin/cursor-halo`, and adds a desktop launcher to `$XDG_DATA_HOME/applications`. It refuses unrelated files, symbolic links, or updates while the installed app is running. Updates retain the previous application in a timestamped `.backup-…` directory beside the installation. It preserves settings and launch-at-login registration.

Open Cursor Halo from your application menu. The default toggle shortcut is **Ctrl–Alt–H**. The settings window remains available on desktops without a legacy tray. Enable launch at login in settings only if you want automatic startup.

To roll back, quit the app, move the current application directory aside, and move the retained backup back to `cursor-halo`. The launcher and startup command continue to reference that stable installation path. To uninstall, first disable launch at login in the app, quit it, then run the included installer with `--uninstall`. Appearance preferences and retained backups are left in place.

Linux does not share a single desktop compositor. Test your actual multi-monitor layout, fullscreen applications, scaling, login, sleep/wake, and recorder before relying on it. Xvfb CI checks verify the native X11 integration and installer, not every desktop. For GNOME Shell 46 on Wayland, use the separate extension archive described in `docs/linux.md`.

The executable links dynamically to system libraries, which remain managed by your distribution. No third-party shared libraries are bundled. Cursor Halo's source and executable are licensed under the included MIT license.
