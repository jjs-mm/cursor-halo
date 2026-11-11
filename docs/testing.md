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

## Manual acceptance

Record the OS version, architecture, display arrangement/scaling, app build, and result for each check.

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
