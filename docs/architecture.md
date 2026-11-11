# Architecture

Cursor Halo uses two native applications with one [behavior contract](behavior.md). A small utility that draws above other applications needs platform-specific windowing, input, and startup APIs; a shared web UI would not remove those integrations.

## macOS

`Sources/CursorHalo/` contains the AppKit application lifecycle, SwiftUI settings surface, validated local preferences, global shortcut registration, Service Management login-item control, and transparent overlay windows.

Pointer events drive position updates. Each click owns a short-lived pulse with a bounded count. Pausing removes observation; quitting removes all owned monitors, windows, registrations, and observers. The app uses the existing `local.personal.CursorHalo` bundle identity so early local installations keep their preferences and login-item identity.

Shortcut replacement is transactional: an unavailable replacement must not remove a working registration. Login registration is read from macOS and is not mirrored into a potentially stale settings Boolean.

## Windows

`windows/CursorHalo.Core/` holds settings validation, persistence, and platform-independent behavior. `windows/CursorHalo/` contains the WinForms settings/tray UI and Win32 integrations. `windows/CursorHalo.Tests/` is a dependency-free core test executable.

A low-level mouse hook forwards bounded/coalesced work to the UI rather than rendering or writing settings inside the callback. Layered windows provide per-pixel alpha and non-activating, click-through feedback. Per-monitor DPI converts logical dimensions to physical pixels while preserving virtual-desktop coordinates. Animation work exists only while click feedback is active.

The startup entry is per user. Registry presence expresses this app's registration intent; the Windows Startup Apps UI can independently disable launching. That external approval state is not inferred from undocumented registry layouts.

## Distribution

`VERSION` is the release version. Build scripts create portable archives and checksums. CI executes native tests on each supported architecture. Release automation creates a draft prerelease for review; it does not automatically declare a stable release.

No credential, updater service, network endpoint, backend, or embedded browser is required. Signing/notarization credentials are intentionally outside the source tree. Development artifacts and caches are ignored by Git.
