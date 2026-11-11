import Darwin
import Foundation

/// The kernel releases this lock if the app exits unexpectedly. Keep the file
/// descriptor open for the lifetime of the running instance.
final class SingleInstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(at url: URL) throws -> SingleInstanceLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError(errno) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { return nil }
            throw posixError(code)
        }
        return SingleInstanceLock(descriptor: descriptor)
    }

    /// A previous instance may release its lock shortly after it stops
    /// accepting reveal requests. Give a rapid reopen time to take over.
    static func acquire(at url: URL, waitingUpTo timeout: TimeInterval) throws -> SingleInstanceLock? {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while true {
            if let lock = try acquire(at: url) { return lock }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return nil }
            Thread.sleep(forTimeInterval: min(0.05, remaining))
        }
    }

    static var applicationLockURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CursorHalo", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    private static func posixError(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
