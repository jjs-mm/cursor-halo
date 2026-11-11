import AppKit
import Testing
@testable import CursorHalo

@Suite(.serialized)
@MainActor
struct OverlayControllerTests {
    private func makeOverlay(monitoring: PointerEventMonitoring? = nil) throws -> (OverlayController, NSWindow) {
        _ = NSApplication.shared
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        let overlay = monitoring.map { OverlayController(monitoring: $0) } ?? OverlayController()
        let panel = try #require(NSApp.windows.first { !existing.contains(ObjectIdentifier($0)) })
        return (overlay, panel)
    }

    @Test
    func partialMonitoringFailureCleansUpAndDoesNotLeaveAStaleHalo() throws {
        let monitoring = FakePointerMonitoring()
        monitoring.failGlobal = true
        let (overlay, panel) = try makeOverlay(monitoring: monitoring)
        defer { overlay.stop(); panel.close() }
        var error: String?
        overlay.onMonitoringError = { error = $0 }
        overlay.update(configuration: OverlayConfiguration())
        #expect(!panel.isVisible)
        #expect(error != nil)
        #expect(monitoring.removalCount == 1)

        monitoring.failGlobal = false
        overlay.update(configuration: OverlayConfiguration())
        #expect(panel.isVisible)
        #expect(error == nil)
        overlay.stop()
        #expect(!panel.isVisible)
        #expect(monitoring.removalCount == 3)
    }

    @Test
    func invalidConfigurationCannotProduceAnInvalidWindowFrame() throws {
        let (overlay, panel) = try makeOverlay()
        defer { overlay.stop(); panel.close() }
        var configuration = OverlayConfiguration()
        configuration.diameter = .nan
        configuration.opacity = .infinity
        configuration.lineWidth = -.infinity
        overlay.update(configuration: configuration)
        #expect(panel.isVisible)
        #expect(panel.frame.width.isFinite)
        #expect(panel.frame.height.isFinite)
        #expect(panel.frame.width == 72)
        #expect(configuration.validated.opacity == 0.85)
        #expect(configuration.validated.lineWidth == 3)
    }

    @Test
    func testOverlayIsTransparentClickThroughAndCannotTakeFocus() throws {
        let (overlay, panel) = try makeOverlay()
        defer { overlay.stop(); panel.close() }
        let keyWindow = NSApp.keyWindow

        #expect(!panel.isVisible)
        overlay.update(configuration: OverlayConfiguration())

        #expect(panel.isVisible)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.isOpaque)
        #expect(!panel.hasShadow)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.contentView?.hitTest(.zero) == nil)
        #expect(NSApp.keyWindow === keyWindow)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
    }

    @Test
    func testResizingKeepsHaloCenteredOnPointerAndDoesNotConstrainDisplayEdges() throws {
        let (overlay, panel) = try makeOverlay()
        defer { overlay.stop(); panel.close() }
        var configuration = OverlayConfiguration()
        configuration.diameter = 40
        overlay.update(configuration: configuration)
        let firstSize = panel.frame.size

        configuration.diameter = 100
        let pointerBefore = NSEvent.mouseLocation
        overlay.update(configuration: configuration)
        let pointerAfter = NSEvent.mouseLocation
        #expect(panel.frame.width > firstSize.width)
        #expect(panel.frame.width == panel.frame.height)
        // Mouse movement outside the test process must not make this check flaky.
        if pointerBefore == pointerAfter {
            #expect(abs(panel.frame.midX - pointerAfter.x) <= 0.5)
            #expect(abs(panel.frame.midY - pointerAfter.y) <= 0.5)
        }

        let crossesLeftEdge = NSRect(x: -1925, y: -15, width: 100, height: 100)
        #expect(panel.constrainFrameRect(crossesLeftEdge, to: NSScreen.main) == crossesLeftEdge)
        let crossesUpperEdge = NSRect(x: -50, y: 2500, width: 100, height: 100)
        #expect(panel.constrainFrameRect(crossesUpperEdge, to: NSScreen.main) == crossesUpperEdge)
    }

    @Test
    func testDisableReenableAndStopCleanUpVisibility() throws {
        let (overlay, panel) = try makeOverlay()
        defer { overlay.stop(); panel.close() }
        var configuration = OverlayConfiguration()
        overlay.update(configuration: configuration)
        #expect(panel.isVisible)

        configuration.isEnabled = false
        overlay.update(configuration: configuration)
        #expect(!panel.isVisible)

        configuration.isEnabled = true
        overlay.update(configuration: configuration)
        #expect(panel.isVisible)

        overlay.stop()
        #expect(!panel.isVisible)
        overlay.stop() // Termination cleanup is safe even when repeated.
        overlay.update(configuration: configuration)
        #expect(!panel.isVisible, "A stopped controller must not reinstall its overlay.")
    }

    @Test
    func testSessionAndSleepNotificationsSuspendAndRestoreOverlay() throws {
        let (overlay, panel) = try makeOverlay()
        defer { overlay.stop(); panel.close() }
        overlay.update(configuration: OverlayConfiguration())
        let center = NSWorkspace.shared.notificationCenter

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!panel.isVisible)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!panel.isVisible, "Waking must not display the halo in an inactive session.")
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(panel.isVisible)

        overlay.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(!panel.isVisible)
    }
}

private final class FakePointerMonitoring: PointerEventMonitoring {
    var failGlobal = false
    var removalCount = 0
    func addGlobal(handler: @escaping (NSEvent) -> Void) -> Any? { failGlobal ? nil : NSObject() }
    func addLocal(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { NSObject() }
    func remove(_ monitor: Any) { removalCount += 1 }
}
