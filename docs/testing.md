# Testing

Automated checks establish specific properties; they do not replace testing a physical mouse, mixed-DPI displays, or a particular recorder.

## Automated

macOS:

```sh
./scripts/test.sh
./scripts/build.sh
```

Windows core tests, runnable on any .NET 10 host:

```sh
dotnet run --project windows/CursorHalo.Tests -c Release
```

Native Windows smoke check, on Windows only:

```powershell
& .\CursorHalo.exe --smoke-test
```

The native smoke test runs isolated checks without changing real preferences or launch-at-login entries. CI builds and tests on native runners; see the workflow files for the current architecture matrix.

Linux core and installer checks:

```sh
./linux/scripts/test.sh
```

Native Linux integration requires a composited X11 display. CI creates an isolated Xvfb/Openbox/xcompmgr session and uses a temporary HOME/XDG environment. The separate GNOME extension must be tested inside each declared GNOME Shell version, including pointer input over a native Wayland client. The 0.5.0 matrix requires GNOME 46 directly on native Ubuntu 24.04 x64/ARM64 runners, plus Ubuntu 26.04/GNOME 50 and Ubuntu 26.10/GNOME 51 containers on matching native x64/ARM64 runners. Record `/etc/os-release`, `gnome-shell --version`, and the runtime architecture for every job. Run the actual compositor with the distribution packages and software rendering; changing `metadata.json` or passing model tests is insufficient. A GTK app running under XWayland does not establish GNOME Wayland compatibility. See [Linux documentation](linux.md) and the CI job commands.

The GNOME checks include pointer/keyboard input, click-through behavior, focus preservation, shortcut conflict recovery, idle sampling recovery, bounded pulse cleanup, preference rendering, and cleanup when the Shell enters its lock-screen session mode. Also exercise the effective reduced-animation settings supported by each Shell version. Simulating a session-mode transition does not test a real authentication or suspend/resume cycle.

## Manual acceptance

Record the OS version, architecture, display arrangement/scaling, app build, and result for each check. On Linux, also record the distribution, desktop/Shell version, compositor, and X11/Wayland session type.

- On Ubuntu 26.04 LTS/GNOME 50 and Ubuntu 26.10/GNOME 51, install the GNOME extension through the documented user flow. Confirm it is recognized after logout/login; do not substitute the X11 app running under XWayland. Repeat the retained-compatibility check on Ubuntu 24.04/GNOME 46.
- Start once and start a second copy: settings should be discoverable and only one halo should remain.
- Move and drag across every display edge, including monitors above or left of the main screen and mixed scaling. The halo stays centered; pulse positions remain accurate.
- Click, double-click, right-click, drag, and type in another application. Input must reach that application and keyboard focus must stay there.
- Change all appearance controls, use extreme sizes/opacities, quit, and reopen. Preferences persist without clipping the settings UI.
- Toggle with a physical keyboard while another app is active. Try an unavailable shortcut and recover without losing a clear way to toggle the app.
- Pause highlighting and quit. No visible overlay or input observation should remain.
- Lock/unlock, sleep/wake, connect/disconnect a display, and switch desktops/Spaces. Verify the app resumes correctly without appearing on secure/sign-in surfaces.
- Test reduced animation, high-contrast/accessibility preferences, and keyboard navigation of settings.
- Enable login launch, verify the system entry, log out/in, then disable and verify a subsequent login does not launch it. Do not mark the login execution check passed merely because registration succeeded.
- Record a short full-display clip and test the exact meeting/recorder application you use. Check single-window capture separately.
- Install/update into the intended app directory, preserve preferences, and test uninstall/rollback instructions.

## Reporting

Use [GitHub issues](https://github.com/jjs-mm/cursor-halo/issues) for ordinary defects and [SECURITY.md](../SECURITY.md) for sensitive reports. Include the smallest reproducible sequence and whether the result was observed on hardware, a virtual machine, or CI.
