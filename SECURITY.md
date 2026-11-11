# Security

Report a security problem privately through [GitHub's vulnerability reporting form](https://github.com/jjs-mm/cursor-halo/security/advisories/new). Include the operating system, version or commit, reproduction steps, and impact. Do not put credentials, personal recordings, or private screen content into public issues.

This is a community-maintained project without a guaranteed response time. The latest published prerelease or release is the supported development baseline; there are no long-term-support branches yet.

## Boundaries

- Cursor Halo needs no account or network connection to work and sends no telemetry.
- It observes pointer movement and mouse clicks to draw feedback. It does not record them or inspect the contents of other apps.
- The highlight toggle registers a specific shortcut. Optional keyboard activity observes keyboard events only while enabled, filters ordinary typing, and briefly shows the latest shortcut. It never saves, logs, or transmits keyboard events or shortcut labels. macOS requires explicit Input Monitoring permission; secure input suppresses display. The GNOME extension does not offer keyboard activity.
- Settings and optional login startup are per user. Windows and Linux user installation do not require administrator access. Linux system dependencies are installed by the distribution's package manager.
- Linux X11 uses the existing desktop connection, without direct access to `/dev/input` or elevated input permissions. GNOME support runs as a Shell extension and follows GNOME's extension enable/disable lifecycle.
- It does not draw over Windows secure desktops, permission prompts, or the sign-in screen. Do not weaken system protections to change that.

Release archives are accompanied by SHA-256 checksums. Checksums detect changes relative to the published values; they do not replace platform signing or establish independent trust. macOS builds are ad hoc signed unless a release explicitly states otherwise. Windows builds are unsigned unless stated otherwise. Developer ID notarization and Authenticode signing require maintainer-owned credentials and are not configured in this repository.
