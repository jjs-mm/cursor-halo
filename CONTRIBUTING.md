# Contributing

Cursor Halo is a small native pointer-highlighting utility for macOS and Windows. Keep changes focused on reliable pointer visibility, accessible controls, and low idle overhead.

## Getting started

See [README.md](README.md) for build commands. The macOS app uses Swift/AppKit/SwiftUI; the Windows app uses C#/.NET and native Windows APIs. Changes to one platform should preserve the [shared behavior contract](docs/behavior.md) or explain a deliberate platform difference.

Before opening a pull request:

1. Describe the problem, expected behavior, and affected operating system.
2. Add a meaningful regression test for a bug or changed state transition. Avoid tests that simply repeat implementation details.
3. Run the affected platform's tests and build. Report unavailable hardware checks honestly.
4. For overlay changes, check clicking and typing through the halo, display scaling and edges, fullscreen applications, pause/resume, and cleanup on exit. Follow [the manual checklist](docs/testing.md).
5. Keep generated builds, local settings, signing credentials, account identifiers, and personal file paths out of commits.

Pull requests run native CI for both operating systems. No third-party runtime dependency should be added without explaining its need, license, update plan, and impact on distribution size.

## Scope

The app must not intercept typed text, send telemetry, require an account, or introduce a network service to perform its core job. Mouse observation is transient and must not be logged. Overlays must never take keyboard focus or consume another app's clicks.

Contributions are provided under the repository's [MIT license](LICENSE). Submit only code and artwork you have the right to contribute. This project uses its own implementation and assets.
