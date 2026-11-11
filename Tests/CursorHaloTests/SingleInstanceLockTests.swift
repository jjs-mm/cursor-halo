import Foundation
import Testing
@testable import CursorHalo

@Suite
struct SingleInstanceLockTests {
    @Test
    func onlyOneInstanceCanClaimTheLockAndItIsReleasedOnExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorHalo-LockTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")

        var first = try SingleInstanceLock.acquire(at: url)
        #expect(first != nil)
        #expect(try SingleInstanceLock.acquire(at: url) == nil)
        #expect(try SingleInstanceLock.acquire(at: url, waitingUpTo: 0.05) == nil)

        first = nil
        #expect(try SingleInstanceLock.acquire(at: url) != nil)
    }

    @Test
    func rapidReopenCanClaimTheLockAfterTheOldInstanceExits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorHalo-LockRetryTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        let holder = LockHolder(lock: try #require(try SingleInstanceLock.acquire(at: url)))
        defer { holder.release() }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { holder.release() }
        #expect(try SingleInstanceLock.acquire(at: url, waitingUpTo: 3) != nil)
    }
}

private final class LockHolder: @unchecked Sendable {
    private let mutex = NSLock()
    private var lock: SingleInstanceLock?

    init(lock: SingleInstanceLock) { self.lock = lock }

    func release() {
        mutex.lock()
        lock = nil
        mutex.unlock()
    }
}
