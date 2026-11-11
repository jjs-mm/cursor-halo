# Architecture

Cursor Halo uses native platform implementations with one [behavior contract](behavior.md). A small utility that draws above other applications needs platform-specific windowing, input, and startup APIs; a shared web UI would not remove those integrations.

## macOS

`Sources/CursorHalo/` contains the AppKit application lifecycle, SwiftUI settings surface, validated local preferences, global shortcut registration, Service Management login-item control, and transparent overlay windows.

Pointer events drive position updates. Each click owns a short-lived pulse with a bounded count. Pausing removes observation; quitting removes all owned monitors, windows, registrations, and observers. The app uses the existing `local.personal.CursorHalo` bundle identity so early local installations keep their preferences and login-item identity.

Shortcut replacement is transactional: an unavailable replacement must not remove a working registration. Login registration is read from macOS and is not mirrored into a potentially stale settings Boolean.

## Windows

`windows/CursorHalo.Core/` holds settings validation, persistence, and platform-independent behavior. `windows/CursorHalo/` contains the WinForms settings/tray UI and Win32 integrations. `windows/CursorHalo.Tests/` is a dependency-free core test executable.

A low-level mouse hook forwards bounded/coalesced work to the UI rather than rendering or writing settings inside the callback. Layered windows provide per-pixel alpha and non-activating, click-through feedback. Per-monitor DPI converts logical dimensions to physical pixels while preserving virtual-desktop coordinates. Animation work exists only while click feedback is active.

The startup entry is per user. Registry presence expresses this app's registration intent; the Windows Startup Apps UI can independently disable launching. That external approval state is not inferred from undocumented registry layouts.

## Linux

`linux/src/` contains the C++17/GTK 3 X11 app and validated settings model. It links to distribution-managed GTK, Cairo, X11, XInput2, and Xfixes libraries. Pointer events drive updates, while click feedback uses bounded animations. Empty input regions and non-focusable windows keep input with the underlying application. The application uses XDG per-user directories for preferences and optional desktop autostart, with safeguards for files it does not own.

`linux/gnome/` is a separate GNOME Shell extension for supported Shell versions. Wayland does not expose desktop-wide pointer observation and arbitrary global window positioning to ordinary clients. A compositor extension can draw non-reactive actors without relying on XWayland or privileged input-device access. CursorTracker signals drive pointer positions. Client button events do not reach stage signals, so an idle-aware 16 ms button-state sampler provides best-effort click feedback; it stops after one idle second and when disabled. Compatibility is explicitly limited to GNOME Shell 46, 50, and 51 and checked with each version's real compositor packages in disposable Ubuntu 24.04, 26.04, and 26.10 environments on native x64 and ARM64 runners. Version-specific API adaptation handles cursor tracking and effective reduced-motion state; adding a Shell major requires a passing native runtime gate, not just a metadata change.

Ubuntu 26.04 LTS and 26.10 GNOME sessions use the extension: an XWayland connection cannot make the standalone X11 app observe native Wayland clients. The generic `gnome-shell.zip` archive contains the same extension code and metadata for every declared Shell major and both architectures.

The app and extension have separate settings stores and lifecycle controls. Do not run both simultaneously. KDE Plasma Wayland and other Wayland compositors need their own integration; they are not covered by the X11 or GNOME implementations.

## Distribution

`VERSION` is the release version. Build scripts create portable archives and checksums. CI executes native tests on each supported architecture. Release automation creates a draft prerelease for review; it does not automatically declare a stable release.

No credential, updater service, network endpoint, backend, or embedded browser is required. Signing/notarization credentials are intentionally outside the source tree. Development artifacts and caches are ignored by Git.
