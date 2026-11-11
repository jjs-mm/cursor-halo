# Changelog

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
