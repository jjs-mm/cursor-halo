# Release validation

Candidate: **0.4.0**, Linux preview alongside the macOS/Windows apps. This file records coverage, not a blanket guarantee of compatibility.

## Current evidence

| Gate | Status | Evidence / limits |
| --- | --- | --- |
| macOS prior local runtime | Passed for bounded checks | Native settings, preference persistence across restart, click-through/non-key window properties, physical-keyboard shortcut, and login registration on/off were checked during the initial Mac implementation. |
| macOS 0.3.0 hardening | Passed locally | All 21 Swift Testing checks passed, including invalid settings, shortcut conflicts/stale events, monitor failure/retry, window geometry, lifecycle, and login-item state. Native tests use temporary windows and mock preference/startup stores. |
| Windows core and native baseline | Passed | Six core checks passed. Initial native Windows x64 and ARM64 CI smoke checks passed for overlays, focus, hotkey conflicts/stale IDs, hook cleanup, and isolated settings rendering. See [baseline run](https://github.com/jjs-mm/cursor-halo/actions/runs/42997152227); later candidates must pass their own checks. |
| Native architecture CI and Windows smoke | Required per candidate | Check the exact commit in [Actions](https://github.com/jjs-mm/cursor-halo/actions/workflows/ci.yml). Release notes link the verified run; its artifacts include Windows smoke JSON and isolated settings renders. |
| Linux X11 | Required per candidate | Native Ubuntu 24.04 x64 and ARM64 builds, core behavior checks, real X11 input/overlay smoke tests under Xvfb with Openbox/xcompmgr, and isolated installer tests. A virtual composited X11 display does not certify a physical desktop's scaling or recorder. |
| GNOME Wayland | Required per candidate | A separate extension is tested inside a disposable GNOME Shell 46 Wayland compositor, including input over a native Wayland client, click-through/focus, shortcuts, and cleanup. Other Shell versions and Wayland compositors are outside the declared support scope. |
| Packaging and signatures | Required per candidate | Build scripts verify Mac ad hoc signatures and package architecture, include licenses, and generate checksums. CI exercises fresh installation and replacement in disposable per-user directories, checks backup and preference preservation, and removes its test-created files. Windows and Linux installer tests also compare startup registration. Release preparation verifies each checksum. Developer ID notarization and Windows Authenticode signing are not configured. |
| Open-source source review | Passed locally | MIT license and contributor/security docs are included. Candidate source files contain no generated builds, personal paths, private email, private-key blocks, or GitHub-token patterns in the bounded pre-publication scan. |

## Runtime acceptance still needed

Use [testing.md](testing.md) to record real mixed-DPI multi-monitor transitions, exclusive fullscreen applications, Spaces/desktops, physical sleep/wake, lock/unlock, actual subsequent-login execution, and specific recorder/meeting-app capture modes. CI smoke tests do not establish these outcomes.

The initial Mac runtime was checked on an Apple Silicon host. Native Windows CI rendered the settings UI and exercised Win32 overlay and hotkey APIs. Linux X11 and GNOME use distinct native integration tests. Physical-input and mixed-display acceptance still need hardware evidence; a successful cross-compilation alone does not count as native runtime testing.

## Release policy and recovery

Binary releases remain **prereleases** while the manual platform matrix is incomplete. Source publication and reproducible CI builds can proceed once their gates pass. Do not label the app stable solely because a compiler or a mock-based test is green.

If an update fails, quit it, restore the prior retained application directory, and verify startup registration points at that installed copy. Settings are per user and should be preserved. Disable launch at login before removing an installation. For GNOME, disable the extension and reinstall the retained prior ZIP, then log out/in before enabling it. No database migration or server rollout is involved.
