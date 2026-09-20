import CryptoKit
import Foundation

public enum UpdateError: LocalizedError {
    case notAnApplication
    case notWritable
    case badResponse
    case checksumMissing
    case checksumMismatch
    case noApplicationInImage
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAnApplication:
            "Updates are only available to the packaged app."
        case .notWritable:
            "MechKeys cannot write to its own location. Move it to Applications and try again."
        case .badResponse:
            "The download did not complete."
        case .checksumMissing:
            "The release does not list a checksum for its disk image."
        case .checksumMismatch:
            "The download did not match the checksum published with the release."
        case .noApplicationInImage:
            "The disk image does not contain MechKeys."
        case .commandFailed(let what):
            "\(what) failed."
        }
    }
}

/// Downloads a release, checks it against the checksum published with it, and
/// puts it in place of the running copy.
///
/// What can be relied on here is that the disk image came from the release
/// over HTTPS and hashes to the digest published beside it — so that is
/// checked, and an update that does not match is discarded rather than
/// installed.
///
/// The replacement keeps the application's code signature, which is what
/// macOS keys the Accessibility grant to. As long as every release is signed
/// with the same identity, an update does not cost the user their permission.
/// See `TECHNICAL.md` §9 for why that is a release-process requirement rather
/// than something this code can guarantee.
public enum UpdateInstaller {

    /// Where the running copy lives, when it is a real application bundle.
    public static var installedBundle: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return nil }
        return url
    }

    public static func install(
        _ release: AppRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let destination = installedBundle else { throw UpdateError.notAnApplication }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            throw UpdateError.notWritable
        }

        let image = try await download(release.diskImage, progress: progress)
        defer { try? FileManager.default.removeItem(at: image) }

        try await verify(
            image, named: release.diskImage.lastPathComponent, against: release.checksums)

        let staged = try unpack(image, matching: destination.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

        try replace(destination, with: staged)
        relaunch(destination)
    }

    // MARK: - Steps

    /// A download task rather than `URLSession.bytes`, which would mean
    /// iterating the image one byte at a time and holding all of it in memory
    /// to no purpose. This streams straight to a file and reports progress
    /// from the session's own byte counts.
    private static func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dmg")

        let delegate = DownloadProgress(destination: destination, report: progress)
        let session = URLSession(
            configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.attach(continuation)
            session.downloadTask(with: url).resume()
        }
    }

    private static func verify(
        _ image: URL, named name: String, against checksums: URL
    ) async throws {
        let (data, response) = try await URLSession.shared.data(from: checksums)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let text = String(data: data, encoding: .utf8),
            let expected = Checksums.digest(for: name, in: text)
        else { throw UpdateError.checksumMissing }

        let contents = try Data(contentsOf: image, options: .mappedIfSafe)
        let actual = SHA256.hash(data: contents)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actual == expected else { throw UpdateError.checksumMismatch }
        AppLog.update.notice("Update checksum verified")
    }

    /// Mounts the image, copies the application out of it, and unmounts.
    private static func unpack(_ image: URL, matching bundleName: String) throws -> URL {
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("mechkeys-update-\(UUID().uuidString)")

        try run(
            "/usr/bin/hdiutil",
            ["attach", image.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mount, includingPropertiesForKeys: nil)
        guard
            let source = contents.first(where: {
                $0.pathExtension == "app" && $0.lastPathComponent == bundleName
            }) ?? contents.first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.noApplicationInImage }

        // Staged beside the destination so the replacement below is a rename
        // on one volume rather than a copy across two.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: Bundle.main.bundleURL, create: true)
        let staged = staging.appendingPathComponent(bundleName)
        try FileManager.default.copyItem(at: source, to: staged)

        // The image was downloaded, so everything out of it is quarantined.
        // Left in place, the replaced app would be refused on relaunch.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        return staged
    }

    private static func replace(_ destination: URL, with staged: URL) throws {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        AppLog.update.notice("Update installed over the running copy")
    }

    /// Starts the new copy once this one has gone.
    ///
    /// It has to wait: two MechKeys processes would mean two event taps and
    /// two sounds per keypress, and the new copy cannot take the tap while
    /// this one still holds it.
    private static func relaunch(_ bundle: URL) {
        let script = """
            while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
                /bin/sleep 0.2
            done
            /bin/sleep 0.3
            /usr/bin/open -n "\(bundle.path)"
            """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments

        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            AppLog.update.error("\(tool, privacy: .public) failed: \(text, privacy: .public)")
            throw UpdateError.commandFailed((tool as NSString).lastPathComponent)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Bridges `URLSessionDownloadTask`'s delegate callbacks to one `async` call.
///
/// `@unchecked Sendable` because the session calls back on its own queue: the
/// two pieces of mutable state are guarded by `lock`, which the compiler
/// cannot see.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let destination: URL
    private let report: @Sendable (Double) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastReported: Double = 0

    init(destination: URL, report: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.report = report
    }

    func attach(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    /// Resumes the caller exactly once. Both the success callback and the
    /// completion callback can arrive, and a continuation may only be resumed
    /// a single time.
    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        // Reporting every packet would swamp the main actor for no visible
        // gain; a percent at a time is finer than the bar can draw.
        lock.lock()
        let worthReporting = fraction - lastReported > 0.01
        if worthReporting { lastReported = fraction }
        lock.unlock()

        if worthReporting { report(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
            !(200..<300).contains(http.statusCode)
        {
            finish(.failure(UpdateError.badResponse))
            return
        }

        // `location` is only valid for the length of this call, so the move
        // happens here rather than being deferred to the caller.
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            report(1)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        // A success has already resumed the continuation from the callback
        // above; `finish` ignores the second call.
        finish(.failure(error ?? UpdateError.badResponse))
    }
}
