# Changelog

## Unreleased

- Added optional, shortcuts-only keyboard activity on macOS, Windows, and Linux X11, disabled by default. The latest shortcut briefly appears in a click-through display and pauses with highlighting.
- Added explicit macOS Input Monitoring setup and documented the GNOME Wayland limitation. Keyboard events are never saved, logged, or transmitted.

## 0.5.0 — Ubuntu and GNOME compatibility candidate

- Added compatibility paths for GNOME Shell 50 on Ubuntu 26.04 LTS and GNOME Shell 51 on Ubuntu 26.10, while retaining GNOME Shell 46 on Ubuntu 24.04. Publication requires all declared runtime checks to pass.
- Adapted cursor-tracker access and effective reduced-motion handling for the newer Shell APIs.
- Expanded native Wayland validation to the three Ubuntu/Shell combinations on x64 and ARM64, using the actual distribution compositor packages.
- Renamed the shared extension archive to `CursorHalo-0.5.0-gnome-shell.zip` and clarified the GNOME extension installation path for current Ubuntu desktops.
- Kept GNOME 47–49 and other Wayland compositors outside the declared compatibility list; physical-display and recording acceptance remains separate.

## 0.4.0 — Linux preview

- Added a native GTK app for composited Linux X11 sessions on x64 and ARM64, including appearance settings, click feedback, global shortcuts, and per-user login launch.
- Added a separate GNOME Shell 46 extension for native Wayland sessions, with compositor overlays, panel controls, preferences, and a toggle shortcut.
- Added Linux build, native integration, and isolated installation/update checks, plus archives and checksums.
- Documented Linux dependencies, desktop compatibility, and manual acceptance limits. Other Wayland desktops are not supported by this preview.

## 0.3.0 — First public development release

- Added a native Windows tray application with configurable cursor highlighting, click feedback, global shortcuts, local settings, and optional per-user login launch.
- Hardened macOS preference validation and shortcut replacement behavior.
- Added native build/test automation for Apple Silicon, Intel Mac, Windows x64, and Windows ARM64.
- Added portable release packaging, checksums, installation scripts, and explicit signing/validation limits.
- Published the project under MIT with contribution and security-reporting guidance.

## 0.2.0 — Local Mac build

- Added native launch-at-login registration and system-state refresh.
- Added login-item state and failure tests.

## 0.1.0 — Initial local Mac build

- Added menu-bar controls, ring/disc appearance, click feedback, shortcuts, and local preferences.
