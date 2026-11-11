# Shared behavior contract

The platform implementations follow this contract, with explicit desktop differences below. Platform APIs and storage formats are intentionally independent.

| Setting | Default | Supported values |
| --- | --- | --- |
| Highlight enabled | On | On / off |
| Style | Ring | Ring / soft disc |
| Color | Amber | Amber, mint, blue, pink, white |
| Diameter | 56 | 28–120 logical points/DIPs |
| Opacity | 85% | 20–100% |
| Stroke width | 3 | 1–8 logical points/DIPs |
| Click feedback | On | On / off |
| Toggle shortcut | Control + Option/Alt + H | Control + Option/Alt + H or C; Control + Shift + H |
| Launch at login | Off | System-managed, explicitly enabled by the user |

The halo surrounds the pointer hotspot and never replaces the system cursor. A thin dark outline keeps the color visible on light backgrounds. A soft disc has a translucent fill so underlying text remains readable. Right/secondary clicks use a contrasting color. Click feedback stays at the click location while the pointer moves on.

Overlays are transparent, click-through, excluded from task switching where supported, and unable to take keyboard focus. Disabling the halo removes pointer observation and visible feedback. There is no continuous idle rendering loop. Animated feedback has a bounded lifetime and count; the system's reduced-animation preference substitutes a brief static indicator.

Settings are local. Invalid, malformed, or nonfinite numeric values must not crash rendering or create unbounded windows. Changing a shortcut must leave a clear, recoverable state if the new combination is unavailable. Startup registration reflects the actual operating-system state, with approval/failure states shown to the user.

## Platform differences

- macOS uses a menu-bar item, AppKit windows, native mouse event monitors, Carbon hotkey registration, and Service Management login registration.
- Windows uses a notification-area icon, Win32 layered windows, a mouse hook, registered hotkeys, and a per-user startup entry.
- Linux X11 uses GTK settings, a tray icon where the desktop provides one, XInput2 pointer events, X11 shortcut grabs, transparent input-shaped windows, and a per-user freedesktop autostart entry. Settings remain reachable without a tray.
- GNOME Wayland support is a separate Shell extension. The compositor owns its overlays and input access. Enable or disable the extension using GNOME's extension controls; this also controls its availability after login.
- GNOME pointer positioning is event-driven, while click feedback samples button state at 16 ms intervals during activity because client button events do not reach extensions. Sampling stops after one idle second and when feedback or highlighting is disabled. Clicks shorter than a sampling interval can be missed.
- Native X11 binaries must not claim desktop-wide support merely because XWayland is available inside a Wayland session. Unsupported sessions show an explanation.
- macOS points and Windows DIPs are logical dimensions; the renderer must adapt to each display's scale factor.
- X11 uses the GTK desktop scale. Mixed fractional scaling and compositor-specific behavior require manual acceptance; do not infer them from the Windows per-monitor DPI implementation.
- Full-display capture can include the overlay. Individual-window capture may omit it; capture behavior is owned by the recording application.
- Secure desktop and operating-system UI restrictions take precedence over an always-on-top request.
